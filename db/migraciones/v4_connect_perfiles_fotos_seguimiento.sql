-- =====================================================================
-- BATAB Connect · v4 · Perfiles por puesto, modo prueba, fotos, seguimiento
-- Fecha: 2026-10-21
-- Solo AGREGA tablas, columnas y funciones mt_*. No toca operadores.rol
-- (los puestos de Connect viven en mt_perfiles).
-- El alta del usuario de prueba GEHT (jefe de taller) se hizo aparte para
-- no publicar su PIN en el repositorio.
-- Reversa: db/reversa/v4_reversa.sql
-- =====================================================================

-- Puestos dentro de BATAB Connect (una persona puede tener varios)
create table public.mt_perfiles (
  operador_id  uuid primary key references public.operadores(id),
  roles        text[] not null default '{operador}'
               check (roles <@ array['operador','mantenimiento','supervisor_area','almacen','director']::text[]),
  es_prueba    boolean not null default false,
  telefono     text,
  notas        text,
  updated_at   timestamptz not null default now()
);
comment on table public.mt_perfiles is 'BATAB Connect: puestos de cada persona en Connect y si es usuario de prueba (sus avisos van solo a destinatarios de prueba).';

-- Destinatarios reales o de prueba
alter table public.mt_avisos_destinos add column if not exists ambito text not null default 'real'
  check (ambito in ('real','prueba'));

-- Fotos de evidencia
create table public.mt_reporte_fotos (
  id          uuid primary key default gen_random_uuid(),
  reporte_id  uuid not null references public.mt_reportes(id),
  ruta        text not null,
  subida_por  uuid references public.operadores(id),
  etapa       text not null default 'reporte' check (etapa in ('reporte','revision','reparacion')),
  created_at  timestamptz not null default now()
);
comment on table public.mt_reporte_fotos is 'BATAB Connect: fotos de evidencia por reporte (bucket privado connect_fotos).';
create index mt_reporte_fotos_rep_idx on public.mt_reporte_fotos(reporte_id);

-- Seguimiento de cada reporte (quién lo revisó, qué dijo, si liberó el equipo)
create table public.mt_reporte_seguimiento (
  id            bigint generated always as identity primary key,
  reporte_id    uuid not null references public.mt_reportes(id),
  operador_id   uuid not null references public.operadores(id),
  estado_nuevo  text not null check (estado_nuevo in ('abierto','en_revision','atendido','cerrado')),
  nota          text,
  libero_equipo boolean not null default false,
  created_at    timestamptz not null default now()
);
comment on table public.mt_reporte_seguimiento is 'BATAB Connect: bitácora de revisión y atención de reportes.';

alter table public.mt_perfiles             enable row level security;
alter table public.mt_reporte_fotos        enable row level security;
alter table public.mt_reporte_seguimiento  enable row level security;

-- Bucket privado para fotos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('connect_fotos', 'connect_fotos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- Perfiles iniciales
insert into public.mt_perfiles (operador_id, roles, es_prueba, notas) values
  ('c540caa0-721d-4e09-8ed8-30485ed70b5c', '{director}', false, 'Director General'),
  ('831a63ec-2cbe-4663-9c11-f3396bc0549c', '{operador}', true, 'Operador de prueba'),
  ('3fbc2df4-cb2c-436e-9c5d-e91c31aa8b7d', '{supervisor_area}', true, 'Supervisor de área de prueba'),
  ('11cb5407-7ddb-4ec0-a33c-e503f3f3bd6e', '{supervisor_area}', false, 'Supervisor de producción')
on conflict (operador_id) do nothing;

-- Destinatarios de prueba: todo llega al Director para revisar cómo se ve
insert into public.mt_avisos_destinos (rol, linea, nombre, email, ambito, notas) values
  ('mantenimiento', null, 'Jefe de taller (prueba)', 'ceo3@batab.mx', 'prueba', 'Recibe lo que recibiría el jefe de taller'),
  ('area', null, 'Supervisor de área (prueba)', 'ceo3@batab.mx', 'prueba', 'Recibe lo que recibiría el supervisor de producción');

-- ---------------------------------------------------------------------
-- Bandeja: reportes visibles para taller, supervisor y director
-- ---------------------------------------------------------------------
create or replace function public.mt_bandeja(p_operador uuid, p_estados text[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_roles text[]; v_prueba boolean;
begin
  select roles, es_prueba into v_roles, v_prueba from mt_perfiles where operador_id = p_operador;
  if v_roles is null or not (v_roles && array['mantenimiento','supervisor_area','director']) then
    return jsonb_build_object('ok', false, 'error', 'Tu puesto no tiene acceso a la bandeja de reportes.');
  end if;
  return jsonb_build_object('ok', true, 'roles', to_jsonb(v_roles), 'reportes', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'folio', r.folio, 'tipo', r.tipo, 'critico', r.critico, 'puede_operar', r.puede_operar,
      'descripcion', r.descripcion, 'lineas', r.lineas, 'estado', r.estado, 'origen', r.origen, 'fecha', r.created_at,
      'operador', o.nombre, 'es_prueba', coalesce(pf.es_prueba, false),
      'equipo', jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'estado', a.estado),
      'fotos', coalesce((select jsonb_agg(f.ruta order by f.created_at) from mt_reporte_fotos f where f.reporte_id = r.id), '[]'::jsonb),
      'seguimiento', coalesce((select jsonb_agg(jsonb_build_object('estado', s.estado_nuevo, 'nota', s.nota,
            'libero', s.libero_equipo, 'fecha', s.created_at, 'por', so.nombre) order by s.created_at)
          from mt_reporte_seguimiento s join operadores so on so.id = s.operador_id where s.reporte_id = r.id), '[]'::jsonb)
    ) order by (r.estado = 'abierto') desc, r.critico desc, r.created_at desc)
    from mt_reportes r
    join mt_activos a on a.id = r.activo_id
    join operadores o on o.id = r.operador_id
    left join mt_perfiles pf on pf.operador_id = r.operador_id
    where r.estado = any(coalesce(p_estados, array['abierto','en_revision']))
      -- los usuarios de prueba ven todo; los reales no ven reportes de prueba
      and (coalesce(v_prueba, false) or 'director' = any(v_roles) or not coalesce(pf.es_prueba, false))
  ), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- Seguimiento: cambia estado de un reporte y opcionalmente libera el equipo
-- Solo taller (mantenimiento) o director pueden atender y liberar.
-- ---------------------------------------------------------------------
create or replace function public.mt_reporte_estado(
  p_operador uuid, p_reporte uuid, p_estado text, p_nota text, p_liberar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_roles text[]; r public.mt_reportes%rowtype; v_libero boolean := false;
begin
  select roles into v_roles from mt_perfiles where operador_id = p_operador;
  if v_roles is null or not (v_roles && array['mantenimiento','director']) then
    return jsonb_build_object('ok', false, 'error', 'Solo el taller de mantenimiento puede atender reportes.');
  end if;
  if p_estado not in ('en_revision','atendido','cerrado') then
    return jsonb_build_object('ok', false, 'error', 'Estado no válido.');
  end if;
  select * into r from mt_reportes where id = p_reporte for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Reporte no encontrado.'); end if;
  if p_estado in ('atendido','cerrado') and nullif(trim(coalesce(p_nota, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Escribe qué se hizo para atenderlo.');
  end if;

  update mt_reportes set estado = p_estado where id = r.id;

  if coalesce(p_liberar, false) then
    update mt_activos set estado = 'operativo' where id = r.activo_id and estado in ('no_apto','en_reparacion');
    v_libero := found;
  elsif p_estado = 'en_revision' and not r.puede_operar then
    update mt_activos set estado = 'en_reparacion' where id = r.activo_id and estado = 'no_apto';
  end if;

  insert into mt_reporte_seguimiento (reporte_id, operador_id, estado_nuevo, nota, libero_equipo)
  values (r.id, p_operador, p_estado, nullif(trim(coalesce(p_nota, '')), ''), v_libero);

  return jsonb_build_object('ok', true, 'folio', r.folio, 'estado', p_estado, 'equipo_liberado', v_libero,
    'equipo_estado', (select estado from mt_activos where id = r.activo_id));
end $$;

revoke all on function public.mt_bandeja(uuid, text[]) from public, anon, authenticated;
revoke all on function public.mt_reporte_estado(uuid, uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.mt_bandeja(uuid, text[]) to service_role;
grant execute on function public.mt_reporte_estado(uuid, uuid, text, text, boolean) to service_role;
