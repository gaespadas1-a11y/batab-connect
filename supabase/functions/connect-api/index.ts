// connect-api v0.2.0 · BATAB Connect
// Única puerta de la app hacia la base de datos. El navegador nunca toca las tablas.
// POST { accion, token?, ... }
//   login   { codigo, pin }                    -> { ok, token, operador, sesion }
//   yo      { token }                          -> { ok, operador, sesion }
//   ficha   { token, qr }                      -> ficha del equipo (mt_ficha)
//   iniciar { token, qr, lectura, respuestas, linea, lat, lng }  (mt_iniciar_uso)
//   cerrar  { token, lectura }                 (mt_cerrar_uso)
//   reportar { token, qr?, tipo, puede_operar, descripcion }  (mt_reportar) + aviso
//   iniciar con lineas[] y observaciones usa mt_iniciar_uso_v2 + aviso
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "https://esm.sh/bcryptjs@2.4.3";

const VERSION = "0.2.0";
// Avisos: por ahora correo (función enviar-correo). WhatsApp se agrega como segundo canal.
const CORREO_URL = Deno.env.get("SUPABASE_URL")! + "/functions/v1/enviar-correo";
const CORREO_GUARD = "BATAB-CORREO-2026";
const CORREO_FROM = "ceo3@batab.mx";
const APP_URL = "https://gaespadas1-a11y.github.io/batab-connect/";
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

const escH = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const LINEAS: Record<string, string> = { "1B": "Besser 1", "2B": "Besser 2", "3C": "Columbia" };

// Envía UN aviso agrupado por los reportes recién creados y lo registra en la bitácora.
async function avisar(ids: string[]) {
  if (!ids?.length) return;
  const { data: reps } = await sb.from("mt_reportes")
    .select("id,folio,tipo,critico,puede_operar,descripcion,lineas,origen,created_at,activo:mt_activos(codigo,nombre,estado),operador:operadores(nombre)")
    .in("id", ids).order("folio");
  if (!reps?.length) return;
  const lineas = [...new Set(reps.flatMap((r: any) => r.lineas || []))];
  const { data: dest } = await sb.from("mt_avisos_destinos").select("rol,linea,nombre,email").eq("activo", true);
  const para = (dest || []).filter((d: any) => d.email && (d.rol === "mantenimiento" || d.linea === null || lineas.includes(d.linea)));
  const correos = [...new Set(para.map((d: any) => String(d.email).toLowerCase()))];
  const r0: any = reps[0];
  const detenido = reps.some((r: any) => !r.puede_operar) || r0.activo?.estado === "no_apto";
  const fecha = new Date(r0.created_at).toLocaleString("es-MX", { timeZone: "America/Mexico_City", dateStyle: "medium", timeStyle: "short" });
  const titulo = detenido ? `EQUIPO DETENIDO · ${r0.activo?.codigo}` : `Observación · ${r0.activo?.codigo}`;
  const filas = reps.map((r: any) =>
    `<tr><td style="padding:6px 8px;border-bottom:1px solid #eee;white-space:nowrap">#${r.folio}</td>` +
    `<td style="padding:6px 8px;border-bottom:1px solid #eee">${r.critico ? '<b style="color:#B91C1C">CRÍTICO</b> · ' : ""}${r.tipo === "falla" ? "Falla" : "Observación"}</td>` +
    `<td style="padding:6px 8px;border-bottom:1px solid #eee">${escH(r.descripcion)}</td></tr>`).join("");
  const html =
    `<p style="margin:0 0 12px">${detenido
      ? '<b style="color:#B91C1C">El equipo quedó NO APTO y no debe operarse hasta que mantenimiento lo libere.</b>'
      : "El equipo sigue operando; revisar en la próxima oportunidad."}</p>` +
    `<table style="border-collapse:collapse;font-size:14px;margin-bottom:12px">` +
    `<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Equipo</td><td><b>${escH(r0.activo?.nombre)}</b> (${escH(r0.activo?.codigo)})</td></tr>` +
    `<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Reportó</td><td>${escH(r0.operador?.nombre)}</td></tr>` +
    `<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Fecha</td><td>${fecha}</td></tr>` +
    `<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Líneas</td><td>${lineas.map((l) => LINEAS[l] || l).join(", ") || "—"}</td></tr>` +
    `<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Origen</td><td>${r0.origen === "checklist" ? "Check-list diario" : "Durante la operación"}</td></tr></table>` +
    `<table style="border-collapse:collapse;font-size:14px;width:100%">${filas}</table>` +
    `<p style="margin:16px 0 0;font-size:12px;color:#6B7280">Aviso automático de <a href="${APP_URL}">BATAB Connect</a>.</p>`;

  let ok = false, detalle = "";
  if (!correos.length) {
    detalle = "Sin destinatarios configurados";
  } else {
    try {
      const r = await fetch(CORREO_URL, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ guard: CORREO_GUARD, from: CORREO_FROM, to: correos, subject: `[BATAB Connect] ${titulo}`, titulo, html }),
      });
      const t = await r.text();
      ok = r.ok; detalle = t.slice(0, 500);
    } catch (e) { detalle = (e as Error).message; }
  }
  await sb.from("mt_avisos_log").insert(reps.map((r: any) => ({ reporte_id: r.id, canal: "correo", destinatarios: correos, ok, detalle })));
  if (ok) await sb.from("mt_reportes").update({ avisado_en: new Date().toISOString() }).in("id", ids);
}
function enSegundoPlano(p: Promise<unknown>) {
  // deno-lint-ignore no-explicit-any
  const er = (globalThis as any).EdgeRuntime;
  if (er?.waitUntil) er.waitUntil(p.catch(() => {})); else p.catch(() => {});
}

const num = (v: unknown) =>(v === null || v === undefined || v === "" || isNaN(Number(v)) ? null : Number(v));

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
      return J({ ok: true, token, operador, sesion: await sesionAbierta(data.id) });
    }

    const yo = await leerToken(b.token);
    if (!yo) return J({ ok: false, codigo: "sesion_vencida", error: "Tu acceso venció. Entra de nuevo con tu PIN." }, 401);

    if (accion === "yo") {
      return J({ ok: true, operador: { id: yo.id, codigo: yo.codigo, nombre: yo.nombre, rol: yo.rol }, sesion: await sesionAbierta(yo.id) });
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
      if (data?.reportes?.length) enSegundoPlano(avisar(data.reportes));
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
      if (data?.ok && data.reporte_id) enSegundoPlano(avisar([data.reporte_id]));
      return J({ ...data, sesion: await sesionAbierta(yo.id) });
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
