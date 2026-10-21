// connect-api v0.1.0 · BATAB Connect
// Única puerta de la app hacia la base de datos. El navegador nunca toca las tablas.
// POST { accion, token?, ... }
//   login   { codigo, pin }                    -> { ok, token, operador, sesion }
//   yo      { token }                          -> { ok, operador, sesion }
//   ficha   { token, qr }                      -> ficha del equipo (mt_ficha)
//   iniciar { token, qr, lectura, respuestas, linea, lat, lng }  (mt_iniciar_uso)
//   cerrar  { token, lectura }                 (mt_cerrar_uso)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "https://esm.sh/bcryptjs@2.4.3";

const VERSION = "0.1.0";
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
    .select("id,inicio,lectura_inicio,linea_atendida,activo:mt_activos(codigo,nombre,qr_token,tipo:mt_tipos_activo(medidor))")
    .eq("operador_id", operadorId).is("fin", null).maybeSingle();
  return data ?? null;
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
