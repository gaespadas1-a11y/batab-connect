-- =====================================================================
-- BATAB Connect · v1 · Catálogo de activos, personas y uso diario
-- Fecha: 2026-10-20
-- Solo AGREGA: 12 tablas nuevas con prefijo mt_ y 3 columnas vacías en
-- operadores. No modifica ni borra datos existentes.
-- Reversa: db/reversa/v1_reversa.sql
-- =====================================================================

-- ---------- ACTIVOS ----------
create table public.mt_tipos_activo (
  id          bigint generated always as identity primary key,
  codigo      text not null unique,
  nombre      text not null,
  categoria   text not null check (categoria in ('estructura','movil','fijo','componente')),
  medidor     text not null default 'horas' check (medidor in ('horas','km','horas_linea','ninguno')),
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);
comment on table public.mt_tipos_activo is 'BATAB Connect: catálogo de tipos de activo (cargador, banda, reductor...) y cómo se mide su uso.';

create table public.mt_activos (
  id                 uuid primary key default gen_random_uuid(),
  codigo             text not null unique,
  nombre             text not null,
  tipo_id            bigint references public.mt_tipos_activo(id),
  nivel              text not null check (nivel in ('planta','linea','subsistema','equipo','componente')),
  padre_id           uuid references public.mt_activos(id),
  linea              text check (linea in ('1B','2B','3C')),
  marca              text,
  modelo             text,
  anio               int,
  num_serie          text,
  num_economico      text,
  ubicacion          text,
  estado             text not null default 'operativo'
                       check (estado in ('operativo','no_apto','en_reparacion','fuera_servicio','baja')),
  especificaciones   jsonb not null default '{}'::jsonb,
  qr_token           text not null unique default substr(md5(gen_random_uuid()::text), 1, 16),
  lectura_actual     numeric,
  lectura_actual_en  timestamptz,
  forma_adquisicion  text check (forma_adquisicion in ('compra','arrendamiento_financiero','fabricacion_propia','otro')),
  -- Fase 3 (contable): previstas, vacías por ahora
  costo_adquisicion  numeric,
  fecha_alta         date,
  vida_util_meses    int,
  ns_referencia      text,
  notas              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
comment on table public.mt_activos is 'BATAB Connect: árbol de activos (planta > línea > subsistema > equipo > componente). Cada fila es una POSICIÓN.';
create index mt_activos_padre_idx on public.mt_activos(padre_id);

create table public.mt_piezas (
  id          uuid primary key default gen_random_uuid(),
  tipo_id     bigint references public.mt_tipos_activo(id),
  marca       text,
  modelo      text,
  num_serie   text,
  num_parte   text,
  estado      text not null default 'instalada'
                check (estado in ('instalada','en_reparacion','en_almacen','baja')),
  notas       text,
  created_at  timestamptz not null default now()
);
comment on table public.mt_piezas is 'BATAB Connect: pieza física con serie (motor, bomba, reductor). Conserva su historial aunque cambie de posición.';

create table public.mt_pieza_instalaciones (
  id                   bigint generated always as identity primary key,
  pieza_id             uuid not null references public.mt_piezas(id),
  activo_id            uuid not null references public.mt_activos(id),
  instalada_en         timestamptz not null default now(),
  lectura_instalacion  numeric,
  retirada_en          timestamptz,
  lectura_retiro       numeric,
  motivo               text,
  registrado_por       uuid references public.operadores(id),
  created_at           timestamptz not null default now()
);
comment on table public.mt_pieza_instalaciones is 'BATAB Connect: historial de qué pieza ocupó cada posición.';
create unique index mt_pieza_inst_posicion_abierta on public.mt_pieza_instalaciones(activo_id) where retirada_en is null;
create unique index mt_pieza_inst_pieza_abierta on public.mt_pieza_instalaciones(pieza_id) where retirada_en is null;

create table public.mt_activo_reparto (
  id             bigint generated always as identity primary key,
  activo_id      uuid not null references public.mt_activos(id),
  linea          text not null check (linea in ('1B','2B','3C')),
  criterio       text not null default 'horas_uso' check (criterio in ('horas_uso','porcentaje_fijo')),
  porcentaje     numeric check (porcentaje is null or (porcentaje >= 0 and porcentaje <= 100)),
  vigente_desde  date not null default current_date,
  created_at     timestamptz not null default now(),
  unique (activo_id, linea, vigente_desde)
);
comment on table public.mt_activo_reparto is 'BATAB Connect: cómo se reparte el costo de un equipo compartido entre líneas.';

-- ---------- PERSONAS ----------
alter table public.operadores add column if not exists num_empleado   text;
alter table public.operadores add column if not exists puesto         text;
alter table public.operadores add column if not exists turno_habitual text;

create table public.mt_colaborador_costos (
  id             bigint generated always as identity primary key,
  operador_id    uuid not null references public.operadores(id),
  costo_hora     numeric not null check (costo_hora > 0),
  vigente_desde  date not null,
  es_ejemplo     boolean not null default false,
  notas          text,
  created_at     timestamptz not null default now(),
  unique (operador_id, vigente_desde)
);
comment on table public.mt_colaborador_costos is 'BATAB Connect: costo real por hora del colaborador, con historial por fecha.';

create table public.mt_autorizaciones (
  id              bigint generated always as identity primary key,
  operador_id     uuid not null references public.operadores(id),
  tipo_id         bigint references public.mt_tipos_activo(id),
  activo_id       uuid references public.mt_activos(id),
  capacitado_en   date,
  vence_en        date,
  autorizado_por  uuid references public.operadores(id),
  vigente         boolean not null default true,
  notas           text,
  created_at      timestamptz not null default now(),
  check (tipo_id is not null or activo_id is not null)
);
comment on table public.mt_autorizaciones is 'BATAB Connect: qué tipo de equipo o equipo específico puede operar cada persona.';
create index mt_autorizaciones_operador_idx on public.mt_autorizaciones(operador_id);

-- ---------- USO DIARIO ----------
create table public.mt_sesiones_uso (
  id               uuid primary key default gen_random_uuid(),
  operador_id      uuid not null references public.operadores(id),
  activo_id        uuid not null references public.mt_activos(id),
  actividad        text not null default 'operacion'
                     check (actividad in ('operacion','reparacion','servicio','inspeccion')),
  inicio           timestamptz not null default now(),
  fin              timestamptz,
  horas            numeric generated always as (extract(epoch from (fin - inicio)) / 3600.0) stored,
  lectura_inicio   numeric,
  lectura_fin      numeric,
  linea_atendida   text check (linea_atendida in ('1B','2B','3C')),
  lat              numeric,
  lng              numeric,
  dispositivo      text,
  cierre_motivo    text check (cierre_motivo in ('manual','otro_equipo','otro_operador','fin_turno','supervisor')),
  orden_trabajo_id uuid,  -- Fase 2
  created_at       timestamptz not null default now(),
  check (fin is null or fin >= inicio)
);
comment on table public.mt_sesiones_uso is 'BATAB Connect: cada uso de un equipo (escaneo de QR). Da horas efectivas y costo de mano de obra.';
create unique index mt_sesion_abierta_por_operador on public.mt_sesiones_uso(operador_id) where fin is null;
create unique index mt_sesion_operacion_abierta_por_equipo on public.mt_sesiones_uso(activo_id) where fin is null and actividad = 'operacion';
create index mt_sesiones_activo_inicio_idx on public.mt_sesiones_uso(activo_id, inicio desc);

create table public.mt_lecturas (
  id                 bigint generated always as identity primary key,
  activo_id          uuid not null references public.mt_activos(id),
  fecha              timestamptz not null default now(),
  valor              numeric not null check (valor >= 0),
  fuente             text not null check (fuente in ('operador','komtrax','manual','correccion')),
  operador_id        uuid references public.operadores(id),
  sesion_id          uuid references public.mt_sesiones_uso(id),
  motivo_correccion  text,
  created_at         timestamptz not null default now(),
  check (fuente <> 'correccion' or motivo_correccion is not null)
);
comment on table public.mt_lecturas is 'BATAB Connect: horas/km de cada equipo en el tiempo. La lectura nunca baja salvo corrección con motivo.';
create index mt_lecturas_activo_fecha_idx on public.mt_lecturas(activo_id, fecha desc);

create table public.mt_checklist_items (
  id              bigint generated always as identity primary key,
  tipo_id         bigint not null references public.mt_tipos_activo(id),
  version         int not null default 1,
  orden           int not null,
  seccion         text not null,
  pregunta        text not null,
  tipo_respuesta  text not null default 'ok_falla' check (tipo_respuesta in ('ok_falla','numero','texto','foto')),
  critica         boolean not null default false,
  fuente          text,
  activo          boolean not null default true,
  created_at      timestamptz not null default now(),
  unique (tipo_id, version, orden)
);
comment on table public.mt_checklist_items is 'BATAB Connect: preguntas del check-list diario por tipo de equipo y versión.';

create table public.mt_checklists (
  id           uuid primary key default gen_random_uuid(),
  sesion_id    uuid references public.mt_sesiones_uso(id),
  activo_id    uuid not null references public.mt_activos(id),
  operador_id  uuid not null references public.operadores(id),
  version      int not null default 1,
  fecha        timestamptz not null default now(),
  resultado    text not null check (resultado in ('apto','apto_observaciones','no_apto')),
  lectura      numeric,
  notas        text,
  created_at   timestamptz not null default now()
);
comment on table public.mt_checklists is 'BATAB Connect: cada check-list llenado.';

create table public.mt_checklist_respuestas (
  id            bigint generated always as identity primary key,
  checklist_id  uuid not null references public.mt_checklists(id),
  item_id       bigint not null references public.mt_checklist_items(id),
  ok            boolean,
  valor         text,
  comentario    text,
  foto_url      text,
  unique (checklist_id, item_id)
);
comment on table public.mt_checklist_respuestas is 'BATAB Connect: respuesta a cada pregunta de un check-list.';

-- ---------- REGLAS ----------
-- Regla 5: la lectura nunca baja (salvo corrección con motivo); actualiza la lectura actual del activo.
create or replace function public.mt_lecturas_validar()
returns trigger language plpgsql set search_path = public as $$
declare v_actual numeric;
begin
  select lectura_actual into v_actual from public.mt_activos where id = new.activo_id for update;
  if v_actual is not null and new.valor < v_actual and new.fuente <> 'correccion' then
    raise exception 'La lectura % es menor a la actual % del equipo', new.valor, v_actual;
  end if;
  update public.mt_activos
     set lectura_actual = new.valor, lectura_actual_en = new.fecha, updated_at = now()
   where id = new.activo_id;
  return new;
end $$;
create trigger mt_lecturas_validar_trg before insert on public.mt_lecturas
  for each row execute function public.mt_lecturas_validar();

create or replace function public.mt_touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end $$;
create trigger mt_activos_updated_trg before update on public.mt_activos
  for each row execute function public.mt_touch_updated_at();

-- ---------- SEGURIDAD ----------
-- Mismo patrón que operadores: RLS activo sin políticas. Solo se accede
-- mediante funciones del servidor (service role); el navegador no lee directo.
alter table public.mt_tipos_activo          enable row level security;
alter table public.mt_activos               enable row level security;
alter table public.mt_piezas                enable row level security;
alter table public.mt_pieza_instalaciones   enable row level security;
alter table public.mt_activo_reparto        enable row level security;
alter table public.mt_colaborador_costos    enable row level security;
alter table public.mt_autorizaciones        enable row level security;
alter table public.mt_sesiones_uso          enable row level security;
alter table public.mt_lecturas              enable row level security;
alter table public.mt_checklist_items       enable row level security;
alter table public.mt_checklists            enable row level security;
alter table public.mt_checklist_respuestas  enable row level security;
