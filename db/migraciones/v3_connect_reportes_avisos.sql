-- =====================================================================
-- BATAB Connect · v3 · Reportes de falla/observación, varias líneas y avisos
-- Fecha: 2026-10-20
-- Agrega tablas y funciones nuevas. La función mt_iniciar_uso de v2 se
-- conserva sin cambios para que la app 0.1.x siga funcionando.
-- Reversa: db/reversa/v3_reversa.sql
-- =====================================================================

-- Varias líneas atendidas por sesión
alter table public.mt_sesiones_uso add column if not exists lineas_atendidas text[];
alter table public.mt_sesiones_uso drop constraint if exists mt_sesiones_uso_cierre_motivo_check;
alter table public.mt_sesiones_uso add constraint mt_sesiones_uso_cierre_motivo_check
  check (cierre_motivo in ('manual','otro_equipo','otro_operador','fin_turno','supervisor','reporte_falla'));

-- Reportes del operador (antecedente de la orden de trabajo de la Fase 2)
create table public.mt_reportes (
  id            uuid primary key default gen_random_uuid(),
  folio         bigint generated always as identity unique,
  activo_id     uuid not null references public.mt_activos(id),
  operador_id   uuid not null references public.operadores(id),
  sesion_id     uuid references public.mt_sesiones_uso(id),
  checklist_id  uuid references public.mt_checklists(id),
  item_id       bigint references public.mt_checklist_items(id),
  origen        text not null check (origen in ('checklist','operacion')),
  tipo          text not null check (tipo in ('falla','observacion')),
  critico       boolean not null default false,
  puede_operar  boolean not null default true,
  descripcion   text not null,
  lineas        text[],
  estado        text not null default 'abierto' check (estado in ('abierto','en_revision','atendido','cerrado')),
  avisado_en    timestamptz,
  created_at    timestamptz not null default now()
);
comment on table public.mt_reportes is 'BATAB Connect: fallas y observaciones reportadas por el operador (en check-list o durante la operación).';
create index mt_reportes_activo_idx on public.mt_reportes(activo_id, created_at desc);

-- A quién avisar
create table public.mt_avisos_destinos (
  id          bigint generated always as identity primary key,
  rol         text not null check (rol in ('mantenimiento','area')),
  linea       text check (linea in ('1B','2B','3C')),   -- null = todas
  nombre      text not null,
  email       text,
  telefono    text,
  activo      boolean not null default true,
  notas       text,
  created_at  timestamptz not null default now()
);
comment on table public.mt_avisos_destinos is 'BATAB Connect: quién recibe los avisos de fallas. rol mantenimiento = taller; rol area = supervisor del área atendida.';

create table public.mt_avisos_log (
  id             bigint generated always as identity primary key,
  reporte_id     uuid references public.mt_reportes(id),
  canal          text not null default 'correo',
  destinatarios  text[],
  ok             boolean not null,
  detalle        text,
  created_at     timestamptz not null default now()
);
comment on table public.mt_avisos_log is 'BATAB Connect: bitácora de avisos enviados o fallidos.';

alter table public.mt_reportes         enable row level security;
alter table public.mt_avisos_destinos  enable row level security;
alter table public.mt_avisos_log       enable row level security;

-- Besser 2 en reconfiguración: no se ofrece como línea atendida
update public.mt_activos set estado = 'fuera_servicio', notas = 'En reconfiguración (octubre 2026)' where codigo = '2B';

-- Destinatario de área: Capetillo (supervisor de producción) para todas las líneas
insert into public.mt_avisos_destinos (rol, linea, nombre, email, notas)
values ('area', null, 'Jesús Miguel Reyes Capetillo', 'foreman1@batab.mx', 'Supervisor de producción; recibe avisos de equipos que dan servicio a producción');

-- ---------------------------------------------------------------------
-- FICHA v3: agrega detalle de líneas (disponibles o no) y reportes abiertos
-- (mantiene todas las claves de v2)
-- ---------------------------------------------------------------------
create or replace function public.mt_ficha(p_operador uuid, p_qr text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.mt_activos%rowtype;
  t public.mt_tipos_activo%rowtype;
  v_aut boolean;
  v_ses record;
  v_mia record;
  v_need boolean;
begin
  select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr) limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
  select * into t from mt_tipos_activo where id = a.tipo_id;

  select exists(
    select 1 from mt_autorizaciones au
    where au.operador_id = p_operador and au.vigente
      and (au.vence_en is null or au.vence_en >= current_date)
      and (au.activo_id = a.id or au.tipo_id = a.tipo_id)
  ) into v_aut;

  select s.id, s.inicio, o.nombre, s.operador_id into v_ses
  from mt_sesiones_uso s join operadores o on o.id = s.operador_id
  where s.activo_id = a.id and s.fin is null and s.actividad = 'operacion' limit 1;

  select s.id, s.activo_id into v_mia from mt_sesiones_uso s where s.operador_id = p_operador and s.fin is null limit 1;

  v_need := not exists(
    select 1 from mt_checklists c
    where c.activo_id = a.id and c.resultado <> 'no_apto'
      and c.fecha >= now() - make_interval(hours => mt_horas_vigencia_checklist())
  );

  return jsonb_build_object(
    'ok', true,
    'activo', jsonb_build_object(
      'id', a.id, 'codigo', a.codigo, 'nombre', a.nombre, 'tipo', t.nombre, 'medidor', t.medidor,
      'marca', a.marca, 'modelo', a.modelo, 'anio', a.anio, 'num_serie', a.num_serie,
      'num_economico', a.num_economico, 'ubicacion', a.ubicacion, 'estado', a.estado,
      'especificaciones', a.especificaciones, 'lectura_actual', a.lectura_actual,
      'lectura_actual_en', a.lectura_actual_en, 'forma_adquisicion', a.forma_adquisicion, 'notas', a.notas),
    'componentes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo', c.codigo, 'nombre', c.nombre, 'modelo', coalesce(p.modelo, c.modelo),
        'num_serie', p.num_serie, 'marca', coalesce(p.marca, c.marca)) order by c.codigo)
      from mt_activos c
      left join mt_pieza_instalaciones pi on pi.activo_id = c.id and pi.retirada_en is null
      left join mt_piezas p on p.id = pi.pieza_id
      where c.padre_id = a.id), '[]'::jsonb),
    'lineas', coalesce((select jsonb_agg(r.linea order by r.linea) from mt_activo_reparto r where r.activo_id = a.id), '[]'::jsonb),
    'lineas_detalle', coalesce((
      select jsonb_agg(jsonb_build_object('linea', r.linea, 'nombre', l.nombre,
               'disponible', coalesce(l.estado, 'operativo') = 'operativo', 'nota', l.notas) order by r.linea)
      from mt_activo_reparto r left join mt_activos l on l.codigo = r.linea and l.nivel = 'linea'
      where r.activo_id = a.id), '[]'::jsonb),
    'reportes_abiertos', coalesce((
      select jsonb_agg(x order by x->>'fecha' desc) from (
        select jsonb_build_object('folio', rp.folio, 'tipo', rp.tipo, 'critico', rp.critico,
               'descripcion', rp.descripcion, 'estado', rp.estado, 'fecha', rp.created_at, 'operador', o.nombre) x
        from mt_reportes rp join operadores o on o.id = rp.operador_id
        where rp.activo_id = a.id and rp.estado in ('abierto','en_revision')
        order by rp.created_at desc limit 10) q), '[]'::jsonb),
    'autorizado', v_aut,
    'sesion_en_equipo', case when v_ses.id is null then null else jsonb_build_object(
        'id', v_ses.id, 'inicio', v_ses.inicio, 'operador', v_ses.nombre, 'es_mia', v_ses.operador_id = p_operador) end,
    'mi_sesion_en_otro_equipo', v_mia.id is not null and v_mia.activo_id <> a.id,
    'requiere_checklist', v_need,
    'checklist', case when v_need then coalesce((
        select jsonb_agg(jsonb_build_object('id', i.id, 'orden', i.orden, 'seccion', i.seccion,
               'pregunta', i.pregunta, 'tipo', i.tipo_respuesta, 'critica', i.critica) order by i.orden)
        from mt_checklist_items i
        where i.tipo_id = a.tipo_id and i.activo
          and i.version = (select max(version) from mt_checklist_items x where x.tipo_id = a.tipo_id and x.activo)
      ), '[]'::jsonb) else '[]'::jsonb end
  );
end $$;

-- ---------------------------------------------------------------------
-- INICIAR USO v2: varias líneas + observaciones; genera reportes de cada falla
-- ---------------------------------------------------------------------
create or replace function public.mt_iniciar_uso_v2(
  p_operador uuid, p_qr text, p_lectura numeric, p_respuestas jsonb,
  p_lineas text[], p_observaciones text, p_lat numeric, p_lng numeric, p_dispositivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.mt_activos%rowtype;
  t public.mt_tipos_activo%rowtype;
  v_aut boolean;
  v_need boolean;
  v_version int;
  v_falta int;
  v_crit_falla int := 0;
  v_falla int := 0;
  v_res text;
  v_chk uuid;
  v_ses uuid;
  v_cerradas int := 0;
  v_lineas text[];
  v_obs text := nullif(trim(coalesce(p_observaciones, '')), '');
  v_rep uuid[];
  n int;
begin
  select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
  select * into t from mt_tipos_activo where id = a.tipo_id;

  select exists(
    select 1 from mt_autorizaciones au
    where au.operador_id = p_operador and au.vigente
      and (au.vence_en is null or au.vence_en >= current_date)
      and (au.activo_id = a.id or au.tipo_id = a.tipo_id)) into v_aut;
  if not v_aut then
    return jsonb_build_object('ok', false, 'codigo', 'no_autorizado',
      'error', 'No tienes autorización vigente para operar este equipo. Avisa a tu supervisor.');
  end if;
  if a.estado in ('no_apto','en_reparacion','fuera_servicio','baja') then
    return jsonb_build_object('ok', false, 'codigo', 'equipo_detenido',
      'error', 'El equipo está marcado como "' || replace(a.estado, '_', ' ') || '". No se puede operar hasta que mantenimiento lo libere.');
  end if;
  if t.medidor in ('horas','km') and p_lectura is null then
    return jsonb_build_object('ok', false, 'error', 'Captura la lectura del ' || case when t.medidor = 'km' then 'odómetro' else 'horómetro' end || '.');
  end if;
  if p_lectura is not null and a.lectura_actual is not null and p_lectura < a.lectura_actual then
    return jsonb_build_object('ok', false, 'codigo', 'lectura_menor',
      'error', 'La lectura ' || p_lectura || ' es menor a la última registrada (' || a.lectura_actual || '). Revisa el horómetro.');
  end if;

  -- Solo líneas válidas para este equipo y disponibles
  select array_agg(distinct x order by x) into v_lineas
  from unnest(coalesce(p_lineas, '{}')) x
  where exists (select 1 from mt_activo_reparto r where r.activo_id = a.id and r.linea = x)
    and not exists (select 1 from mt_activos l where l.codigo = x and l.nivel = 'linea' and l.estado <> 'operativo');
  if exists (select 1 from mt_activo_reparto r where r.activo_id = a.id) and coalesce(array_length(v_lineas, 1), 0) = 0 then
    return jsonb_build_object('ok', false, 'codigo', 'sin_linea', 'error', 'Elige al menos una línea a la que darás servicio.');
  end if;

  v_need := not exists(select 1 from mt_checklists c where c.activo_id = a.id and c.resultado <> 'no_apto'
                         and c.fecha >= now() - make_interval(hours => mt_horas_vigencia_checklist()));
  if v_need then
    select max(version) into v_version from mt_checklist_items where tipo_id = a.tipo_id and activo;
    if v_version is not null then
      select count(*) into v_falta from mt_checklist_items i
      where i.tipo_id = a.tipo_id and i.activo and i.version = v_version and i.tipo_respuesta = 'ok_falla'
        and not exists (select 1 from jsonb_array_elements(coalesce(p_respuestas, '[]'::jsonb)) r
                        where (r->>'item_id')::bigint = i.id and (r->>'ok') is not null);
      if v_falta > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'checklist_incompleto',
          'error', 'Faltan ' || v_falta || ' puntos del check-list por contestar.');
      end if;

      select count(*) filter (where i.critica), count(*) into v_crit_falla, v_falla
      from jsonb_array_elements(p_respuestas) r join mt_checklist_items i on i.id = (r->>'item_id')::bigint
      where (r->>'ok')::boolean = false and i.tipo_id = a.tipo_id;

      v_res := case when v_crit_falla > 0 then 'no_apto' when v_falla > 0 or v_obs is not null then 'apto_observaciones' else 'apto' end;

      insert into mt_checklists (activo_id, operador_id, version, resultado, lectura, notas)
      values (a.id, p_operador, v_version, v_res, p_lectura, v_obs) returning id into v_chk;

      insert into mt_checklist_respuestas (checklist_id, item_id, ok, valor, comentario)
      select v_chk, (r->>'item_id')::bigint, (r->>'ok')::boolean, r->>'valor', nullif(r->>'comentario', '')
      from jsonb_array_elements(p_respuestas) r
      where exists (select 1 from mt_checklist_items i where i.id = (r->>'item_id')::bigint and i.tipo_id = a.tipo_id);
    end if;
  end if;

  if v_res = 'no_apto' then
    update mt_activos set estado = 'no_apto' where id = a.id;
    if p_lectura is not null then
      insert into mt_lecturas (activo_id, valor, fuente, operador_id) values (a.id, p_lectura, 'operador', p_operador);
    end if;
  else
    update mt_sesiones_uso set fin = now(), cierre_motivo = 'otro_equipo' where operador_id = p_operador and fin is null;
    get diagnostics n = row_count; v_cerradas := v_cerradas + n;
    update mt_sesiones_uso set fin = now(), cierre_motivo = 'otro_operador' where activo_id = a.id and fin is null and actividad = 'operacion';
    get diagnostics n = row_count; v_cerradas := v_cerradas + n;

    insert into mt_sesiones_uso (operador_id, activo_id, actividad, lectura_inicio, linea_atendida, lineas_atendidas, lat, lng, dispositivo)
    values (p_operador, a.id, 'operacion', p_lectura, v_lineas[1], v_lineas, p_lat, p_lng, p_dispositivo)
    returning id into v_ses;
    if v_chk is not null then update mt_checklists set sesion_id = v_ses where id = v_chk; end if;
    if p_lectura is not null and (a.lectura_actual is null or p_lectura >= a.lectura_actual) then
      insert into mt_lecturas (activo_id, valor, fuente, operador_id, sesion_id) values (a.id, p_lectura, 'operador', p_operador, v_ses);
    end if;
  end if;

  -- Reportes: una fila por cada falla del check-list y una por la observación general
  with ins as (
    insert into mt_reportes (activo_id, operador_id, sesion_id, checklist_id, item_id, origen, tipo, critico, puede_operar, descripcion, lineas)
    select a.id, p_operador, v_ses, v_chk, i.id, 'checklist', 'falla', i.critica, not i.critica,
           i.pregunta || coalesce(' — ' || nullif(r->>'comentario', ''), ''), v_lineas
    from jsonb_array_elements(case when v_chk is null then '[]'::jsonb else coalesce(p_respuestas, '[]'::jsonb) end) r
    join mt_checklist_items i on i.id = (r->>'item_id')::bigint and i.tipo_id = a.tipo_id
    where (r->>'ok')::boolean = false
    union all
    select a.id, p_operador, v_ses, v_chk, null, case when v_chk is null then 'operacion' else 'checklist' end,
           'observacion', false, true, v_obs, v_lineas
    where v_obs is not null
    returning id
  ) select array_agg(id) into v_rep from ins;

  if v_res = 'no_apto' then
    return jsonb_build_object('ok', false, 'codigo', 'no_apto', 'checklist_id', v_chk, 'reportes', coalesce(to_jsonb(v_rep), '[]'::jsonb),
      'error', 'El check-list tiene fallas críticas. El equipo queda NO APTO y se avisó a mantenimiento. No lo operes.');
  end if;

  return jsonb_build_object('ok', true, 'sesion_id', v_ses, 'checklist', v_res, 'sesiones_cerradas', v_cerradas,
    'reportes', coalesce(to_jsonb(v_rep), '[]'::jsonb),
    'mensaje', case when v_rep is not null then 'Sesión iniciada. Tus observaciones se enviaron a mantenimiento.' else 'Sesión iniciada.' end);
end $$;

-- ---------------------------------------------------------------------
-- REPORTAR en cualquier momento (con o sin sesión abierta)
-- ---------------------------------------------------------------------
create or replace function public.mt_reportar(
  p_operador uuid, p_qr text, p_tipo text, p_puede_operar boolean, p_descripcion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.mt_activos%rowtype;
  s public.mt_sesiones_uso%rowtype;
  v_rep public.mt_reportes%rowtype;
  v_detenido boolean := false;
begin
  if nullif(trim(coalesce(p_descripcion, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Describe qué pasa con el equipo.');
  end if;
  if p_tipo not in ('falla','observacion') then
    return jsonb_build_object('ok', false, 'error', 'Tipo de reporte no válido.');
  end if;

  if nullif(p_qr, '') is null then
    select * into s from mt_sesiones_uso where operador_id = p_operador and fin is null;
    if not found then return jsonb_build_object('ok', false, 'error', 'Escanea el equipo que quieres reportar.'); end if;
    select * into a from mt_activos where id = s.activo_id for update;
  else
    select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr) for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
    select * into s from mt_sesiones_uso where operador_id = p_operador and activo_id = a.id and fin is null;
  end if;

  insert into mt_reportes (activo_id, operador_id, sesion_id, origen, tipo, critico, puede_operar, descripcion, lineas)
  values (a.id, p_operador, s.id, 'operacion', p_tipo, not coalesce(p_puede_operar, true), coalesce(p_puede_operar, true),
          trim(p_descripcion), coalesce(s.lineas_atendidas, case when s.linea_atendida is not null then array[s.linea_atendida] end))
  returning * into v_rep;

  if not coalesce(p_puede_operar, true) then
    update mt_activos set estado = 'no_apto' where id = a.id;
    update mt_sesiones_uso set fin = now(), cierre_motivo = 'reporte_falla' where id = s.id and fin is null;
    v_detenido := true;
  end if;

  return jsonb_build_object('ok', true, 'reporte_id', v_rep.id, 'folio', v_rep.folio, 'equipo', a.codigo,
    'equipo_detenido', v_detenido, 'sesion_cerrada', v_detenido and s.id is not null);
end $$;

revoke all on function public.mt_iniciar_uso_v2(uuid, text, numeric, jsonb, text[], text, numeric, numeric, text) from public, anon, authenticated;
revoke all on function public.mt_reportar(uuid, text, text, boolean, text) from public, anon, authenticated;
grant execute on function public.mt_iniciar_uso_v2(uuid, text, numeric, jsonb, text[], text, numeric, numeric, text) to service_role;
grant execute on function public.mt_reportar(uuid, text, text, boolean, text) to service_role;
