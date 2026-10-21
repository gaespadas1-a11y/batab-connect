// connect-api v0.3.0 · BATAB Connect
// Única puerta de la app hacia la base de datos. El navegador nunca toca las tablas.
// POST { accion, token?, ... }
//   login    { codigo, pin }                     -> { ok, token, operador, perfil, sesion }
//   yo       { token }                           -> { ok, operador, perfil, sesion }
//   ficha    { token, qr }                       -> ficha del equipo (mt_ficha)
//   iniciar  { token, qr, lectura, respuestas, lineas[], observaciones, fotos[] }  (mt_iniciar_uso_v2) + aviso
//   iniciar  { token, qr, lectura, respuestas, linea }   (mt_iniciar_uso, app 0.1.x)
//   cerrar   { token, lectura }                  (mt_cerrar_uso)
//   reportar { token, qr?, tipo, puede_operar, descripcion, fotos[] }  (mt_reportar) + aviso
//   bandeja  { token, estados? }                 (mt_bandeja) con enlaces temporales a fotos
//   estado_reporte { token, reporte_id, estado, nota, liberar, fotos[] }  (mt_reporte_estado) + aviso si se libera
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "https://esm.sh/bcryptjs@2.4.3";

const VERSION = "0.3.0";
// Avisos: correo (función enviar-correo). WhatsApp se agrega como segundo canal.
const CORREO_URL = Deno.env.get("SUPABASE_URL")! + "/functions/v1/enviar-correo";
const CORREO_GUARD = "BATAB-CORREO-2026";
const CORREO_FROM = "ceo3@batab.mx";
const APP_URL = "https://gaespadas1-a11y.github.io/batab-connect/";
const BUCKET = "connect_fotos";
const MAX_FOTOS = 4;
const MAX_FOTO_BYTES = 3_000_000;
const DIAS_ENLACE_CORREO = 30;
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(Deno.env.get("SUPABASE_URL")!, KEY);
const HORAS_TOKEN = 12;

const enc = new TextEncoder();
const b64u = (buf: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const fromB64u = (s: string) => atob(s.replace(/-/g, "+").replace(/_/g, "/"));
let hmacKey: CryptoKey | null = null;
async function hkey() {
  if (!hmacKey) {
    hmacKey = await crypto.subtle.importKey("raw", enc.encode("batab-connect:" + KEY), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  }
  return hmacKey;
}
async function firmar(payload: Record<string, unknown>) {
  const body = b64u(enc.encode(JSON.stringify(payload)));
  const sig = b64u(await crypto.subtle.sign("HMAC", await hkey(), enc.encode(body)));
  return body + "." + sig;
}
async function leerToken(token: string): Promise<{ id: string; nombre: string; rol: string; codigo: string } | null> {
  const [body, sig] = String(token || "").split(".");
  if (!body || !sig) return null;
  const esperado = b64u(await crypto.subtle.sign("HMAC", await hkey(), enc.encode(body)));
  if (esperado !== sig) return null;
  try {
    const p = JSON.parse(fromB64u(body));
    if (!p.exp || Date.now() > p.exp) return null;
    return p;
  } catch { return null; }
}

async function sesionAbierta(operadorId: string) {
  const { data } = await sb.from("mt_sesiones_uso")
    .select("id,inicio,lectura_inicio,linea_atendida,lineas_atendidas,activo:mt_activos(codigo,nombre,qr_token,tipo:mt_tipos_activo(medidor))")
    .eq("operador_id", operadorId).is("fin", null).maybeSingle();
  return data ?? null;
}
async function perfil(operadorId: string) {
  const { data } = await sb.from("mt_perfiles").select("roles,es_prueba").eq("operador_id", operadorId).maybeSingle();
  return data ?? { roles: ["operador"], es_prueba: false };
}

// ---------------- Fotos ----------------
// Recibe fotos como "data:image/jpeg;base64,..." (la app ya las reduce) y las guarda en el bucket privado.
async function guardarFotos(reporteId: string, operadorId: string, fotos: unknown, etapa = "reporte") {
  if (!Array.isArray(fotos) || !fotos.length) return 0;
  let n = 0;
  for (const f of fotos.slice(0, MAX_FOTOS)) {
    const m = /^data:(image\/(jpeg|png|webp));base64,(.+)$/.exec(String(f || ""));
    if (!m) continue;
    const bytes = Uint8Array.from(atob(m[3]), (c) => c.charCodeAt(0));
    if (bytes.length > MAX_FOTO_BYTES) continue;
    const ext = m[2] === "jpeg" ? "jpg" : m[2];
    const ruta = `reportes/${reporteId}/${crypto.randomUUID()}.${ext}`;
    const { error } = await sb.storage.from(BUCKET).upload(ruta, bytes, { contentType: m[1], upsert: false });
    if (error) continue;
    await sb.from("mt_reporte_fotos").insert({ reporte_id: reporteId, ruta, subida_por: operadorId, etapa });
    n++;
  }
  return n;
}
async function enlaces(rutas: string[], segundos: number) {
  if (!rutas?.length) return [];
  const { data } = await sb.storage.from(BUCKET).createSignedUrls(rutas, segundos);
  return (data || []).map((d) => d.signedUrl).filter(Boolean) as string[];
}

// ---------------- Avisos ----------------
const escH = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const LINEAS: Record<string, string> = { "1B": "Besser 1", "2B": "Besser 2", "3C": "Columbia" };
const td = 'style="color:#6B7280;padding:2px 12px 2px 0;vertical-align:top"';

async function destinatarios(lineas: string[], esPrueba: boolean) {
  const { data: dest } = await sb.from("mt_avisos_destinos").select("rol,linea,nombre,email,ambito").eq("activo", true)
    .eq("ambito", esPrueba ? "prueba" : "real");
  const para = (dest || []).filter((d: any) => d.email && (d.rol === "mantenimiento" || d.linea === null || lineas.includes(d.linea)));
  return {
    correos: [...new Set(para.map((d: any) => String(d.email).toLowerCase()))],
    nombres: para.map((d: any) => `${d.nombre} (${d.rol === "mantenimiento" ? "taller" : "área"})`),
  };
}
async function enviarCorreo(to: string[], titulo: string, html: string) {
  if (!to.length) return { ok: false, detalle: "Sin destinatarios configurados" };
  try {
    const r = await fetch(CORREO_URL, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ guard: CORREO_GUARD, from: CORREO_FROM, to, subject: `[BATAB Connect] ${titulo}`, titulo, html }),
    });
    return { ok: r.ok, detalle: (await r.text()).slice(0, 500) };
  } catch (e) { return { ok: false, detalle: (e as Error).message }; }
}
function pie(nombres: string[], esPrueba: boolean) {
  return `<p style="margin:16px 0 0;font-size:12px;color:#6B7280">` +
    (esPrueba ? `<b>PRUEBA</b> · En operación real lo recibirían: ${escH(nombres.join(", ")) || "—"}<br>` : `Enviado a: ${escH(nombres.join(", "))}<br>`) +
    `Aviso automático de <a href="${APP_URL}">BATAB Connect</a>.</p>`;
}

// Un aviso agrupado por los reportes recién creados.
async function avisar(ids: string[]) {
  if (!ids?.length) return;
  const { data: reps } = await sb.from("mt_reportes")
    .select("id,folio,tipo,critico,puede_operar,descripcion,lineas,origen,created_at,operador_id,activo:mt_activos(codigo,nombre,estado),operador:operadores(nombre)")
    .in("id", ids).order("folio");
  if (!reps?.length) return;
  const r0: any = reps[0];
  const esPrueba = (await perfil(r0.operador_id)).es_prueba;
  const lineas = [...new Set(reps.flatMap((r: any) => r.lineas || []))] as string[];
  const { correos, nombres } = await destinatarios(lineas, esPrueba);
  const { data: fotos } = await sb.from("mt_reporte_fotos").select("ruta").in("reporte_id", ids).order("created_at");
  const urls = await enlaces((fotos || []).map((f: any) => f.ruta), DIAS_ENLACE_CORREO * 86400);

  const detenido = reps.some((r: any) => !r.puede_operar) || r0.activo?.estado === "no_apto";
  const fecha = new Date(r0.created_at).toLocaleString("es-MX", { timeZone: "America/Mexico_City", dateStyle: "medium", timeStyle: "short" });
  const titulo = `${esPrueba ? "PRUEBA · " : ""}${detenido ? "EQUIPO DETENIDO" : "Observación"} · ${r0.activo?.codigo}`;
  const filas = reps.map((r: any) =>
    `<tr><td style="padding:6px 8px;border-bottom:1px solid #eee;white-space:nowrap">#${r.folio}</td>` +
    `<td style="padding:6px 8px;border-bottom:1px solid #eee">${r.critico ? '<b style="color:#B91C1C">CRÍTICO</b> · ' : ""}${r.tipo === "falla" ? "Falla" : "Observación"}</td>` +
    `<td style="padding:6px 8px;border-bottom:1px solid #eee">${escH(r.descripcion)}</td></tr>`).join("");
  const galeria = urls.length
    ? `<p style="margin:16px 0 6px"><b>Evidencia (${urls.length} foto${urls.length > 1 ? "s" : ""})</b></p>` +
      urls.map((u, i) => `<a href="${u}"><img src="${u}" alt="Foto ${i + 1}" width="150" style="width:150px;height:150px;object-fit:cover;border-radius:6px;margin:0 6px 6px 0;border:1px solid #ddd"></a>`).join("") +
      `<p style="margin:4px 0 0;font-size:12px;color:#6B7280">Toca una foto para verla completa. Los enlaces vencen en ${DIAS_ENLACE_CORREO} días.</p>`
    : "";
  const html =
    `<p style="margin:0 0 12px">${detenido
      ? '<b style="color:#B91C1C">El equipo quedó NO APTO y no debe operarse hasta que mantenimiento lo libere.</b>'
      : "El equipo sigue operando; revisar en la próxima oportunidad."}</p>` +
    `<table style="border-collapse:collapse;font-size:14px;margin-bottom:12px">` +
    `<tr><td ${td}>Equipo</td><td><b>${escH(r0.activo?.nombre)}</b> (${escH(r0.activo?.codigo)})</td></tr>` +
    `<tr><td ${td}>Reportó</td><td>${escH(r0.operador?.nombre)}</td></tr>` +
    `<tr><td ${td}>Fecha</td><td>${fecha}</td></tr>` +
    `<tr><td ${td}>Líneas</td><td>${lineas.map((l) => LINEAS[l] || l).join(", ") || "—"}</td></tr>` +
    `<tr><td ${td}>Origen</td><td>${r0.origen === "checklist" ? "Check-list diario" : "Durante la operación"}</td></tr></table>` +
    `<table style="border-collapse:collapse;font-size:14px;width:100%">${filas}</table>` + galeria +
    `<p style="margin:16px 0 0"><a href="${APP_URL}" style="background:#f59e0b;color:#1a1204;padding:10px 16px;border-radius:6px;text-decoration:none;font-weight:600">Abrir bandeja de reportes</a></p>` +
    pie(nombres, esPrueba);

  const { ok, detalle } = await enviarCorreo(correos, titulo, html);
  await sb.from("mt_avisos_log").insert(reps.map((r: any) => ({ reporte_id: r.id, canal: "correo", destinatarios: correos, ok, detalle })));
  if (ok) await sb.from("mt_reportes").update({ avisado_en: new Date().toISOString() }).in("id", ids);
}

// Aviso de equipo liberado por el taller.
async function avisarLiberado(reporteId: string, quien: string, nota: string) {
  const { data: r } = await sb.from("mt_reportes")
    .select("id,folio,descripcion,lineas,operador_id,activo:mt_activos(codigo,nombre)").eq("id", reporteId).maybeSingle();
  if (!r) return;
  const rr: any = r;
  const esPrueba = (await perfil(rr.operador_id)).es_prueba;
  const { correos, nombres } = await destinatarios(rr.lineas || [], esPrueba);
  const titulo = `${esPrueba ? "PRUEBA · " : ""}Equipo LIBERADO · ${rr.activo?.codigo}`;
  const html =
    `<p style="margin:0 0 12px"><b style="color:#15803D">El equipo quedó OPERATIVO y se puede volver a usar.</b></p>` +
    `<table style="border-collapse:collapse;font-size:14px">` +
    `<tr><td ${td}>Equipo</td><td><b>${escH(rr.activo?.nombre)}</b> (${escH(rr.activo?.codigo)})</td></tr>` +
    `<tr><td ${td}>Reporte</td><td>#${rr.folio} · ${escH(rr.descripcion)}</td></tr>` +
    `<tr><td ${td}>Liberó</td><td>${escH(quien)}</td></tr>` +
    `<tr><td ${td}>Trabajo realizado</td><td>${escH(nota)}</td></tr></table>` + pie(nombres, esPrueba);
  const { ok, detalle } = await enviarCorreo(correos, titulo, html);
  await sb.from("mt_avisos_log").insert({ reporte_id: rr.id, canal: "correo", destinatarios: correos, ok, detalle: "liberado: " + detalle });
}

function enSegundoPlano(p: Promise<unknown>) {
  // deno-lint-ignore no-explicit-any
  const er = (globalThis as any).EdgeRuntime;
  if (er?.waitUntil) er.waitUntil(p.catch(() => {})); else p.catch(() => {});
}

const num = (v: unknown) => (v === null || v === undefined || v === "" || isNaN(Number(v)) ? null : Number(v));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
  try {
    const b = await req.json().catch(() => ({}));
    const accion = String(b.accion || "");

    if (accion === "version") return J({ ok: true, version: VERSION });

    if (accion === "login") {
      const codigo = String(b.codigo || "").trim().toUpperCase();
      const pin = String(b.pin || "").trim();
      if (!codigo || !pin) return J({ ok: false, error: "Escribe tu código y tu PIN." });
      const { data, error } = await sb.from("operadores").select("id,codigo,nombre,rol,activo,pin_hash").eq("codigo", codigo).maybeSingle();
      if (error) return J({ ok: false, error: "No se pudo consultar. Intenta de nuevo." });
      if (!data || !data.activo) return J({ ok: false, error: "Usuario no encontrado o inactivo." });
      let match = false;
      try { match = bcrypt.compareSync(pin, data.pin_hash); } catch { match = false; }
      if (!match) return J({ ok: false, error: "PIN incorrecto." });
      sb.from("operadores").update({ last_login: new Date().toISOString() }).eq("id", data.id).then(() => {});
      const operador = { id: data.id, codigo: data.codigo, nombre: data.nombre, rol: data.rol };
      const token = await firmar({ ...operador, exp: Date.now() + HORAS_TOKEN * 3600_000 });
      return J({ ok: true, token, operador, perfil: await perfil(data.id), sesion: await sesionAbierta(data.id) });
    }

    const yo = await leerToken(b.token);
    if (!yo) return J({ ok: false, codigo: "sesion_vencida", error: "Tu acceso venció. Entra de nuevo con tu PIN." }, 401);

    if (accion === "yo") {
      return J({ ok: true, operador: { id: yo.id, codigo: yo.codigo, nombre: yo.nombre, rol: yo.rol },
        perfil: await perfil(yo.id), sesion: await sesionAbierta(yo.id) });
    }

    if (accion === "ficha") {
      const { data, error } = await sb.rpc("mt_ficha", { p_operador: yo.id, p_qr: String(b.qr || "").trim() });
      if (error) return J({ ok: false, error: error.message });
      return J(data);
    }

    if (accion === "iniciar" && Array.isArray(b.lineas)) {
      const { data, error } = await sb.rpc("mt_iniciar_uso_v2", {
        p_operador: yo.id,
        p_qr: String(b.qr || "").trim(),
        p_lectura: num(b.lectura),
        p_respuestas: Array.isArray(b.respuestas) ? b.respuestas : [],
        p_lineas: b.lineas.map(String),
        p_observaciones: b.observaciones ? String(b.observaciones).slice(0, 1000) : null,
        p_lat: num(b.lat),
        p_lng: num(b.lng),
        p_dispositivo: String(req.headers.get("user-agent") || "").slice(0, 200),
      });
      if (error) return J({ ok: false, error: error.message });
      if (data?.reportes?.length) {
        // las fotos del arranque se ligan al primer reporte; el correo las muestra todas
        await guardarFotos(data.reportes[0], yo.id, b.fotos);
        enSegundoPlano(avisar(data.reportes));
      }
      return J({ ...data, sesion: data?.ok ? await sesionAbierta(yo.id) : null });
    }

    if (accion === "reportar") {
      const { data, error } = await sb.rpc("mt_reportar", {
        p_operador: yo.id,
        p_qr: b.qr ? String(b.qr).trim() : null,
        p_tipo: b.tipo === "falla" ? "falla" : "observacion",
        p_puede_operar: b.puede_operar !== false,
        p_descripcion: String(b.descripcion || "").slice(0, 1000),
      });
      if (error) return J({ ok: false, error: error.message });
      let fotos = 0;
      if (data?.ok && data.reporte_id) {
        fotos = await guardarFotos(data.reporte_id, yo.id, b.fotos);
        enSegundoPlano(avisar([data.reporte_id]));
      }
      return J({ ...data, fotos, sesion: await sesionAbierta(yo.id) });
    }

    if (accion === "bandeja") {
      const estados = Array.isArray(b.estados) && b.estados.length ? b.estados.map(String) : null;
      const { data, error } = await sb.rpc("mt_bandeja", { p_operador: yo.id, p_estados: estados });
      if (error) return J({ ok: false, error: error.message });
      if (!data?.ok) return J(data);
      for (const r of data.reportes) r.fotos = await enlaces(r.fotos, 3600);
      return J(data);
    }

    if (accion === "estado_reporte") {
      const nota = String(b.nota || "").slice(0, 1000);
      const { data, error } = await sb.rpc("mt_reporte_estado", {
        p_operador: yo.id, p_reporte: String(b.reporte_id || ""), p_estado: String(b.estado || ""),
        p_nota: nota, p_liberar: b.liberar === true,
      });
      if (error) return J({ ok: false, error: error.message });
      if (data?.ok) {
        await guardarFotos(String(b.reporte_id), yo.id, b.fotos, data.estado === "en_revision" ? "revision" : "reparacion");
        if (data.equipo_liberado) enSegundoPlano(avisarLiberado(String(b.reporte_id), yo.nombre, nota));
      }
      return J(data);
    }

    if (accion === "iniciar") {
      const { data, error } = await sb.rpc("mt_iniciar_uso", {
        p_operador: yo.id,
        p_qr: String(b.qr || "").trim(),
        p_lectura: num(b.lectura),
        p_respuestas: Array.isArray(b.respuestas) ? b.respuestas : [],
        p_linea: b.linea ? String(b.linea) : null,
        p_lat: num(b.lat),
        p_lng: num(b.lng),
        p_dispositivo: String(req.headers.get("user-agent") || "").slice(0, 200),
      });
      if (error) return J({ ok: false, error: error.message });
      return J({ ...data, sesion: data?.ok ? await sesionAbierta(yo.id) : null });
    }

    if (accion === "cerrar") {
      const { data, error } = await sb.rpc("mt_cerrar_uso", { p_operador: yo.id, p_lectura: num(b.lectura) });
      if (error) return J({ ok: false, error: error.message });
      return J(data);
    }

    return J({ ok: false, error: "Acción no reconocida." }, 400);
  } catch (e) {
    return J({ ok: false, error: (e as Error).message }, 500);
  }
});
