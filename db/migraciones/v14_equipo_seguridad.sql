-- =====================================================================
-- BATAB Connect · v14 · Equipo de seguridad por unidad (responsable: Seguridad)
-- Fecha: 2026-11-03 · Solicitado por el Director.
-- 1. Catálogo de equipo de seguridad y herramienta por unidad.
-- 2. Seguridad (Ing. Fabiola) hace la revisión inicial y la ENTREGA al chofer;
--    queda un acta y se manda por correo al chofer (formal) y a Seguridad.
-- 3. Si en el check-list diario falta o está dañado algo de seguridad,
--    se avisa a Seguridad para averiguar y reponer.
-- 4. Aviso diario a Seguridad desde 30 días antes de cada caducidad
--    (recarga del extintor, botiquín) para comprar o reemplazar.
-- Reversa: db/reversa/v14_reversa.sql
-- =====================================================================

-- Puesto de Seguridad en Connect
alter table public.mt_perfiles drop constraint if exists mt_perfiles_roles_check;
alter table public.mt_perfiles add constraint mt_perfiles_roles_check
  check (roles <@ array['operador','mantenimiento','supervisor_area','almacen','director','seguridad']::text[]);

alter table public.mt_avisos_destinos drop constraint if exists mt_avisos_destinos_rol_check;
alter table public.mt_avisos_destinos add constraint mt_avisos_destinos_rol_check
  check (rol in ('mantenimiento','area','licencias','seguridad'));

-- Catálogo
create table if not exists public.mt_seguridad_catalogo (
  codigo              text primary key,
  nombre              text not null,
  orden               int not null,
  cantidad_sugerida   int not null default 1,
  requiere_caducidad  boolean not null default false,
  nota_caducidad      text
);
alter table public.mt_seguridad_catalogo enable row level security;
insert into public.mt_seguridad_catalogo (codigo, nombre, orden, cantidad_sugerida, requiere_caducidad, nota_caducidad) values
  ('EXTINTOR',          'Extintor',                               1, 1, true,  'Fecha de la próxima recarga'),
  ('TRIANGULOS',        'Triángulos o reflejantes de emergencia', 2, 2, false, null),
  ('BOTIQUIN',          'Botiquín de primeros auxilios',          3, 1, true,  'Caducidad más próxima del material'),
  ('TRINQUETE_4',       'Trinquete de amarre de 4"',              4, 6, false, null),
  ('LLANTA_REFACCION',  'Llanta de refacción',                    5, 1, false, null),
  ('GATO_LLAVE',        'Gato y llave de birlos (cruceta)',       6, 1, false, null),
  ('HERRAMIENTA',       'Herramienta básica (juego)',             7, 1, false, null)
on conflict (codigo) do nothing;

-- Inventario de seguridad por unidad
create table if not exists public.mt_equipo_seguridad (
  id              bigint generated always as identity primary key,
  activo_id       uuid not null references public.mt_activos(id),
  catalogo        text not null references public.mt_seguridad_catalogo(codigo),
  cantidad        int not null default 0,
  estado          text not null default 'ok' check (estado in ('ok','falta','danado','vencido')),
  vence_en        date,
  num_serie       text,
  notas           text,
  actualizado_por uuid references public.operadores(id),
  actualizado_en  timestamptz not null default now(),
  unique (activo_id, catalogo)
);
alter table public.mt_equipo_seguridad enable row level security;

-- Actas de entrega / revisión de Seguridad
create table if not exists public.mt_seguridad_entregas (
  id            bigint generated always as identity primary key,
  folio         bigint generated always as identity,
  activo_id     uuid not null references public.mt_activos(id),
  entregado_por uuid not null references public.operadores(id),
  recibido_por  uuid references public.operadores(id),
  detalle       jsonb not null,
  notas         text,
  created_at    timestamptz not null default now()
);
alter table public.mt_seguridad_entregas enable row level security;

-- Qué punto del check-list corresponde a qué equipo de seguridad
alter table public.mt_checklist_items add column if not exists seguridad text references public.mt_seguridad_catalogo(codigo);
update public.mt_checklist_items i set seguridad = m.cat
from (values (25,'EXTINTOR'),(26,'TRIANGULOS'),(27,'BOTIQUIN'),(28,'LLANTA_REFACCION'),(29,'GATO_LLAVE'),(30,'HERRAMIENTA')) m(orden, cat)
where i.version = 2 and i.orden = m.orden
  and i.tipo_id in (select id from public.mt_tipos_activo where codigo in ('CAMION','CAMION_RABON','TRACTOCAMION'));
update public.mt_checklist_items set seguridad = 'TRINQUETE_4'
where version = 2 and orden = 5 and tipo_id = (select id from public.mt_tipos_activo where codigo = 'PLATAFORMA');

-- Correo genérico desde la base de datos
create or replace function public.mt_enviar_correo(p_to text[], p_asunto text, p_titulo text, p_html text)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare v bigint;
begin
  if p_to is null or cardinality(p_to) = 0 then return null; end if;
  select net.http_post(
    url := 'https://szrcmvlgxxpmvgrfmxak.supabase.co/functions/v1/enviar-correo',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('guard', 'BATAB-CORREO-2026', 'from', 'ceo3@batab.mx', 'to', to_jsonb(p_to),
      'subject', '[BATAB Connect] ' || p_asunto, 'titulo', p_titulo, 'html', p_html)) into v;
  return v;
end $$;
revoke all on function public.mt_enviar_correo(text[], text, text, text) from public, anon, authenticated;

create or replace function public.mt_destinos_seguridad(p_prueba boolean)
returns text[] language sql stable security definer set search_path = public as $$
  select array_agg(distinct lower(email)) from mt_avisos_destinos
  where rol = 'seguridad' and activo and email is not null and ambito = case when p_prueba then 'prueba' else 'real' end;
$$;

-- Ficha de seguridad de una unidad (para Seguridad o Dirección)
create or replace function public.mt_seguridad_ficha(p_operador uuid, p_qr text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a mt_activos%rowtype; v_roles text[]; v_tipos bigint[];
begin
  select roles into v_roles from mt_perfiles where operador_id = p_operador;
  if v_roles is null or not (v_roles && array['seguridad','director']) then
    return jsonb_build_object('ok', false, 'error', 'Solo Seguridad puede registrar el equipo de seguridad.');
  end if;
  select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr);
  if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
  select array_agg(tipo_id) into v_tipos from mt_activos where id = a.id or padre_id = a.id;
  return jsonb_build_object('ok', true,
    'activo', jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre),
    'items', (select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'sugerida', c.cantidad_sugerida,
                'requiere_caducidad', c.requiere_caducidad, 'nota_caducidad', c.nota_caducidad,
                'cantidad', e.cantidad, 'estado', e.estado, 'vence_en', e.vence_en, 'num_serie', e.num_serie, 'notas', e.notas,
                'actualizado_en', e.actualizado_en) order by c.orden)
              from mt_seguridad_catalogo c left join mt_equipo_seguridad e on e.activo_id = a.id and e.catalogo = c.codigo),
    'choferes', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', o.id, 'nombre', o.nombre)), '[]'::jsonb)
                 from mt_autorizaciones au join operadores o on o.id = au.operador_id
                 left join mt_perfiles pf on pf.operador_id = o.id
                 where au.vigente and o.activo and coalesce(pf.es_prueba, false) = coalesce((select es_prueba from mt_perfiles where operador_id = p_operador), false)
                   and (au.activo_id = a.id or au.tipo_id = a.tipo_id)),
    'ultima_entrega', (select jsonb_build_object('folio', s.folio, 'fecha', s.created_at, 'recibio', o.nombre)
                       from mt_seguridad_entregas s left join operadores o on o.id = s.recibido_por
                       where s.activo_id = a.id order by s.created_at desc limit 1));
end $$;

-- Registrar revisión / entrega
create or replace function public.mt_seguridad_registrar(p_operador uuid, p_qr text, p_items jsonb, p_recibe uuid, p_notas text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a mt_activos%rowtype; v_roles text[]; v_prueba boolean; v_folio bigint; v_rec record; v_ent record;
  v_html text; v_to text[]; it jsonb;
begin
  select roles, es_prueba into v_roles, v_prueba from mt_perfiles where operador_id = p_operador;
  if v_roles is null or not (v_roles && array['seguridad','director']) then
    return jsonb_build_object('ok', false, 'error', 'Solo Seguridad puede registrar el equipo de seguridad.');
  end if;
  select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr);
  if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'No hay equipo que registrar.');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if exists (select 1 from mt_seguridad_catalogo c where c.codigo = it->>'codigo' and c.requiere_caducidad)
       and (it->>'estado') = 'ok' and nullif(it->>'vence_en', '') is null then
      return jsonb_build_object('ok', false, 'error', 'Falta la fecha de caducidad de ' || (select nombre from mt_seguridad_catalogo where codigo = it->>'codigo') || '.');
    end if;
    insert into mt_equipo_seguridad (activo_id, catalogo, cantidad, estado, vence_en, num_serie, notas, actualizado_por, actualizado_en)
    values (a.id, it->>'codigo', coalesce((it->>'cantidad')::int, 0), coalesce(nullif(it->>'estado', ''), 'ok'),
            nullif(it->>'vence_en', '')::date, nullif(it->>'num_serie', ''), nullif(it->>'notas', ''), p_operador, now())
    on conflict (activo_id, catalogo) do update set cantidad = excluded.cantidad, estado = excluded.estado, vence_en = excluded.vence_en,
      num_serie = excluded.num_serie, notas = excluded.notas, actualizado_por = excluded.actualizado_por, actualizado_en = now();
  end loop;

  insert into mt_seguridad_entregas (activo_id, entregado_por, recibido_por, detalle, notas)
  values (a.id, p_operador, p_recibe, p_items, nullif(trim(coalesce(p_notas, '')), '')) returning folio into v_folio;

  select o.nombre as quien, r.nombre as recibe, r.email as recibe_email into v_ent
  from operadores o left join operadores r on r.id = p_recibe where o.id = p_operador;

  select string_agg(format('<tr><td style="padding:5px 8px;border-bottom:1px solid #eee">%s</td><td style="padding:5px 8px;border-bottom:1px solid #eee;text-align:center">%s</td><td style="padding:5px 8px;border-bottom:1px solid #eee">%s</td><td style="padding:5px 8px;border-bottom:1px solid #eee">%s</td></tr>',
           c.nombre, e.cantidad,
           case e.estado when 'ok' then 'Bueno' when 'falta' then '<b style="color:#B91C1C">Falta</b>' when 'danado' then '<b style="color:#B91C1C">Dañado</b>' else '<b style="color:#B91C1C">Vencido</b>' end,
           coalesce(to_char(e.vence_en, 'DD/MM/YYYY'), '—')), '' order by c.orden)
  into v_html from mt_equipo_seguridad e join mt_seguridad_catalogo c on c.codigo = e.catalogo where e.activo_id = a.id;

  v_html := '<p style="margin:0 0 12px">Acta de entrega y revisión de equipo de seguridad <b>#' || v_folio || '</b>.</p>'
    || '<table style="border-collapse:collapse;font-size:14px;margin-bottom:12px">'
    || '<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Unidad</td><td><b>' || a.nombre || '</b> (' || a.codigo || ')</td></tr>'
    || '<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Entregó</td><td>' || v_ent.quien || ' (Seguridad)</td></tr>'
    || '<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Recibió</td><td>' || coalesce(v_ent.recibe, '—') || '</td></tr>'
    || '<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Fecha</td><td>' || to_char(now() at time zone 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') || '</td></tr></table>'
    || '<table style="border-collapse:collapse;font-size:14px;width:100%"><tr style="text-align:left;color:#6B7280"><th style="padding:5px 8px">Equipo</th><th style="padding:5px 8px">Cant.</th><th style="padding:5px 8px">Estado</th><th style="padding:5px 8px">Caducidad</th></tr>'
    || coalesce(v_html, '') || '</table>'
    || case when nullif(trim(coalesce(p_notas, '')), '') is not null then '<p style="margin:12px 0 0"><b>Notas:</b> ' || replace(replace(p_notas, '<', '&lt;'), '>', '&gt;') || '</p>' else '' end
    || '<p style="margin:16px 0 0;font-size:13px">El chofer que recibe es responsable de conservar este equipo en la unidad y de reportar en su check-list diario cualquier faltante o daño.</p>'
    || '<p style="margin:12px 0 0;font-size:12px;color:#6B7280">' || case when v_prueba then '<b>PRUEBA</b> · ' else '' end || 'BATAB Connect.</p>';

  v_to := coalesce(mt_destinos_seguridad(coalesce(v_prueba, false)), '{}');
  if not coalesce(v_prueba, false) and v_ent.recibe_email is not null then v_to := v_to || lower(v_ent.recibe_email); end if;
  perform mt_enviar_correo(v_to, case when v_prueba then 'PRUEBA · ' else '' end || 'Acta de entrega de equipo de seguridad #' || v_folio || ' · ' || a.codigo,
    'Entrega de equipo de seguridad', v_html);

  return jsonb_build_object('ok', true, 'folio', v_folio, 'enviado_a', to_jsonb(v_to));
end $$;

-- Aviso a Seguridad cuando el check-list reporta faltante o daño de equipo de seguridad
create or replace function public.mt_trg_reportes_seguridad()
returns trigger language plpgsql security definer set search_path = public as $$
declare g record; v_html text; v_to text[];
begin
  for g in
    select n.activo_id, n.operador_id, coalesce(pf.es_prueba, false) prueba,
           array_agg(i.seguridad) cats,
           string_agg('<li>' || c.nombre || ' — ' || replace(replace(n.descripcion, '<', '&lt;'), '>', '&gt;') || '</li>', '') lista
    from nuevos n
    join mt_checklist_items i on i.id = n.item_id and i.seguridad is not null
    join mt_seguridad_catalogo c on c.codigo = i.seguridad
    left join mt_perfiles pf on pf.operador_id = n.operador_id
    group by n.activo_id, n.operador_id, pf.es_prueba
  loop
    update mt_equipo_seguridad set estado = 'falta', actualizado_en = now(),
      notas = coalesce(notas || ' · ', '') || 'Reportado en check-list ' || to_char(now() at time zone 'America/Mexico_City', 'DD/MM/YYYY')
    where activo_id = g.activo_id and catalogo = any(g.cats) and estado = 'ok';

    select '<p style="margin:0 0 12px"><b style="color:#B91C1C">Equipo de seguridad faltante o dañado</b> reportado en el check-list diario.</p>'
      || '<table style="border-collapse:collapse;font-size:14px;margin-bottom:12px">'
      || '<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Unidad</td><td><b>' || a.nombre || '</b> (' || a.codigo || ')</td></tr>'
      || '<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Chofer</td><td>' || o.nombre || '</td></tr>'
      || '<tr><td style="color:#6B7280;padding:2px 12px 2px 0">Fecha</td><td>' || to_char(now() at time zone 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') || '</td></tr></table>'
      || '<ul style="font-size:14px">' || g.lista || '</ul>'
      || '<p style="margin:12px 0 0">Favor de averiguar qué pasó y, si procede, solicitar la compra o el reemplazo.</p>'
      || '<p style="margin:12px 0 0;font-size:12px;color:#6B7280">' || case when g.prueba then '<b>PRUEBA</b> · ' else '' end || 'Aviso automático de BATAB Connect.</p>'
    into v_html
    from mt_activos a, operadores o where a.id = g.activo_id and o.id = g.operador_id;

    v_to := mt_destinos_seguridad(g.prueba);
    perform mt_enviar_correo(v_to, case when g.prueba then 'PRUEBA · ' else '' end || 'Equipo de seguridad faltante · ' ||
      (select codigo from mt_activos where id = g.activo_id), 'Equipo de seguridad faltante', v_html);
  end loop;
  return null;
end $$;

drop trigger if exists mt_reportes_seguridad on public.mt_reportes;
create trigger mt_reportes_seguridad after insert on public.mt_reportes
  referencing new table as nuevos for each statement execute function public.mt_trg_reportes_seguridad();

-- Aviso diario de caducidades (desde 30 días antes y mientras siga vencido)
create or replace function public.mt_alerta_caducidad_seguridad(p_prueba boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_hoy date := (now() at time zone 'America/Mexico_City')::date; v_filas text; v_n int; v_to text[];
begin
  select count(*), string_agg(format('<tr><td style="padding:5px 8px;border-bottom:1px solid #eee">%s (%s)</td><td style="padding:5px 8px;border-bottom:1px solid #eee">%s</td><td style="padding:5px 8px;border-bottom:1px solid #eee">%s</td><td style="padding:5px 8px;border-bottom:1px solid #eee"><b style="color:%s">%s</b></td></tr>',
           a.nombre, a.codigo, c.nombre, to_char(e.vence_en, 'DD/MM/YYYY'),
           case when e.vence_en - v_hoy <= 7 then '#B91C1C' else '#B45309' end,
           case when e.vence_en < v_hoy then 'VENCIDO hace ' || (v_hoy - e.vence_en) || ' días'
                when e.vence_en = v_hoy then 'VENCE HOY'
                when e.vence_en - v_hoy = 1 then 'Falta 1 día'
                else 'Faltan ' || (e.vence_en - v_hoy) || ' días' end), '' order by e.vence_en)
  into v_n, v_filas
  from mt_equipo_seguridad e join mt_seguridad_catalogo c on c.codigo = e.catalogo join mt_activos a on a.id = e.activo_id
  where e.vence_en is not null and (p_prueba or e.vence_en - v_hoy <= 30);

  if coalesce(v_n, 0) = 0 then return jsonb_build_object('ok', true, 'enviado', false); end if;
  update mt_equipo_seguridad set estado = 'vencido' where vence_en < v_hoy and estado = 'ok';
  v_to := mt_destinos_seguridad(p_prueba);
  perform mt_enviar_correo(v_to, case when p_prueba then 'PRUEBA · ' else '' end || 'Equipo de seguridad por caducar o vencido',
    'Equipo de seguridad por caducar',
    '<p style="margin:0 0 12px">Equipo de seguridad que requiere compra, recarga o reemplazo:</p>'
    || '<table style="border-collapse:collapse;font-size:14px;width:100%"><tr style="text-align:left;color:#6B7280"><th style="padding:5px 8px">Unidad</th><th style="padding:5px 8px">Equipo</th><th style="padding:5px 8px">Caduca</th><th style="padding:5px 8px">Estado</th></tr>'
    || v_filas || '</table><p style="margin:12px 0 0;font-size:12px;color:#6B7280">Aviso automático de BATAB Connect.</p>');
  return jsonb_build_object('ok', true, 'enviado', true, 'renglones', v_n, 'a', to_jsonb(v_to));
end $$;

revoke all on function public.mt_seguridad_ficha(uuid, text) from public, anon, authenticated;
revoke all on function public.mt_seguridad_registrar(uuid, text, jsonb, uuid, text) from public, anon, authenticated;
revoke all on function public.mt_alerta_caducidad_seguridad(boolean) from public, anon, authenticated;
revoke all on function public.mt_destinos_seguridad(boolean) from public, anon, authenticated;
grant execute on function public.mt_seguridad_ficha(uuid, text) to service_role;
grant execute on function public.mt_seguridad_registrar(uuid, text, jsonb, uuid, text) to service_role;

select cron.schedule('connect-caducidad-seguridad', '5 14 * * *', $$select public.mt_alerta_caducidad_seguridad(false)$$);
