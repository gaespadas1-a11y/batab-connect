-- =====================================================================
-- BATAB Connect · v9b · Alerta de licencias diaria desde 30 días antes
-- Fecha: 2026-11-03
-- Avisa todos los días desde que faltan 30 días ("Faltan 30 días…", "Faltan 29
-- días…") hasta el vencimiento, y sigue avisando diario mientras esté vencida.
-- Reversa: volver a aplicar la función de v9_alertas_licencias.sql
-- =====================================================================
create or replace function public.mt_alerta_licencias(p_prueba boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_lista jsonb;
  v_to text[];
  v_filas text;
  v_html text;
  v_req bigint;
  v_hoy date := (now() at time zone 'America/Mexico_City')::date;
begin
  select coalesce(jsonb_agg(x order by (x->>'dias')::int), '[]'::jsonb) into v_lista from (
    select jsonb_build_object('nombre', o.nombre, 'codigo', o.codigo, 'numero', p.licencia_numero,
             'tipo', p.licencia_tipo, 'vence', p.licencia_vence, 'dias', p.licencia_vence - v_hoy) x
    from mt_perfiles p join operadores o on o.id = p.operador_id
    where p.licencia_vence is not null and o.activo and not p.es_prueba
      and (p_prueba or (p.licencia_vence - v_hoy) <= 30)
  ) q;

  if jsonb_array_length(v_lista) = 0 then
    return jsonb_build_object('ok', true, 'enviado', false, 'motivo', 'Sin licencias por avisar hoy');
  end if;

  select array_agg(distinct lower(email)) into v_to from mt_avisos_destinos
  where rol = 'licencias' and activo and email is not null and ambito = case when p_prueba then 'prueba' else 'real' end;
  if v_to is null then return jsonb_build_object('ok', false, 'error', 'Sin destinatarios de licencias'); end if;

  select string_agg(format(
    '<tr><td style="padding:6px 8px;border-bottom:1px solid #eee">%s</td><td style="padding:6px 8px;border-bottom:1px solid #eee">%s · núm. %s</td><td style="padding:6px 8px;border-bottom:1px solid #eee;white-space:nowrap">%s</td><td style="padding:6px 8px;border-bottom:1px solid #eee"><b style="color:%s">%s</b></td></tr>',
    x->>'nombre', coalesce(x->>'tipo', '—'), coalesce(x->>'numero', '—'), to_char((x->>'vence')::date, 'DD/MM/YYYY'),
    case when (x->>'dias')::int <= 7 then '#B91C1C' when (x->>'dias')::int <= 30 then '#B45309' else '#15803D' end,
    case when (x->>'dias')::int < -1 then 'LICENCIA VENCIDA hace ' || abs((x->>'dias')::int) || ' días'
         when (x->>'dias')::int = -1 then 'LICENCIA VENCIDA desde ayer'
         when (x->>'dias')::int = 0 then 'SU LICENCIA VENCE HOY'
         when (x->>'dias')::int = 1 then 'Falta 1 día para el vencimiento de su licencia'
         else 'Faltan ' || (x->>'dias') || ' días para el vencimiento de su licencia' end), '' order by (x->>'dias')::int)
  into v_filas from jsonb_array_elements(v_lista) x;

  v_html := '<p style="margin:0 0 12px">Licencias de conducir de choferes que requieren atención. '
    || 'Al vencer, BATAB Connect ya no deja que el chofer arranque la unidad hasta que se registre la renovación.</p>'
    || '<table style="border-collapse:collapse;font-size:14px;width:100%"><tr style="text-align:left;color:#6B7280">'
    || '<th style="padding:6px 8px">Chofer</th><th style="padding:6px 8px">Licencia</th><th style="padding:6px 8px">Vence</th><th style="padding:6px 8px">Estado</th></tr>'
    || v_filas || '</table>'
    || '<p style="margin:16px 0 0;font-size:12px;color:#6B7280">' || case when p_prueba then '<b>PRUEBA</b> · ' else '' end
    || 'Aviso automático de <a href="https://gaespadas1-a11y.github.io/batab-connect/">BATAB Connect</a>.</p>';

  select net.http_post(
    url := 'https://szrcmvlgxxpmvgrfmxak.supabase.co/functions/v1/enviar-correo',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('guard', 'BATAB-CORREO-2026', 'from', 'ceo3@batab.mx', 'to', to_jsonb(v_to),
      'subject', '[BATAB Connect] ' || case when p_prueba then 'PRUEBA · ' else '' end || 'Licencias de conducir por vencer'
        || case when jsonb_array_length(v_lista) = 1 then ' · ' || (v_lista->0->>'nombre') || ': '
             || case when (v_lista->0->>'dias')::int < 0 then 'vencida' when (v_lista->0->>'dias')::int = 0 then 'vence hoy'
                     else 'faltan ' || (v_lista->0->>'dias') || ' días' end else '' end,
      'titulo', 'Licencias de conducir por vencer', 'html', v_html)
  ) into v_req;

  insert into mt_avisos_licencias_log (prueba, destinatarios, licencias, respuesta_id) values (p_prueba, v_to, v_lista, v_req);
  return jsonb_build_object('ok', true, 'enviado', true, 'destinatarios', to_jsonb(v_to), 'licencias', v_lista);
end $$;
