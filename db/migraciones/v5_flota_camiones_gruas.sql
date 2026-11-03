-- =====================================================================
-- BATAB Connect · v5 · Camiones SITRAK, grúas y contratos de adquisición
-- Fecha: 2026-11-03
-- Solo AGREGA tipos y activos y amplía las formas de adquisición.
-- No toca tablas de producción. Los montos y condiciones de los contratos
-- (costo, rentas, plazos) se cargaron aparte porque este repositorio es público.
-- Reversa: db/reversa/v5_reversa.sql
-- =====================================================================

-- Arrendamiento puro como forma de adquisición
alter table public.mt_activos drop constraint if exists mt_activos_forma_adquisicion_check;
alter table public.mt_activos add constraint mt_activos_forma_adquisicion_check
  check (forma_adquisicion in ('compra','arrendamiento_financiero','arrendamiento_puro','fabricacion_propia','otro'));

-- Tipos nuevos
insert into public.mt_tipos_activo (codigo, nombre, categoria, medidor) values
  ('CAMION',       'Camión',                 'movil', 'km'),
  ('TRACTOCAMION', 'Tractocamión',           'movil', 'km'),
  ('GRUA',         'Grúa articulada montada', 'movil', 'horas')
on conflict (codigo) do nothing;

-- Camión de reparto con grúa Palfinger · arrendamiento puro Bepensa CT-37604
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, anio, num_serie,
  num_economico, ubicacion, forma_adquisicion, fecha_alta, ns_referencia, especificaciones, notas)
select 'BAT-EM-CAM01', 'Camión SITRAK G5S 6x4 (grúa Palfinger)', t.id, 'equipo', p.id, 'SITRAK', 'G5S 62K 330 HP', 2026,
  '3DJ3D2DC4TA001382', 'BAT-EM-CAM01', 'Planta Teapa', 'arrendamiento_puro', '2026-08-14', 'Proveedor NetSuite 9832 (Bepensa Leasing)',
  jsonb_build_object(
    'motor', '260307820547', 'descripcion', 'Chasis cabina 6x4 diésel 330 HP', 'color', 'Blanco', 'proveedor_unidad', 'TGN Golfo (factura V-520)'),
  'Llevará la grúa Palfinger PK15002 (BAT-EM-GRU01). Ver condiciones del contrato sobre accesorios antes del montaje.'
from (select id from public.mt_tipos_activo where codigo = 'CAMION') t
cross join (select id from public.mt_activos where codigo = 'MOVIL') p
on conflict (codigo) do nothing;

-- Tractocamión con grúa IMT · compra de contado TGN Golfo F534
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, anio, num_serie,
  num_economico, ubicacion, forma_adquisicion, fecha_alta, ns_referencia, especificaciones, notas)
select 'BAT-EM-TRC01', 'Tractocamión SITRAK 6x4 400 HP (grúa IMT)', t.id, 'equipo', p.id, 'SITRAK', '77K cabina G7S 6x4 400 HP AMT', 2027,
  '3DJ4D2EC5VA000425', 'BAT-EM-TRC01', 'Planta Teapa', 'compra', '2026-09-30', 'Factura NetSuite F534 (TGN Golfo)',
  jsonb_build_object(
    'motor', 'MC11.40-61 Euro VI, núm. 260417231287', 'transmision', 'Automatizada HW25712XAC con retardador',
    'eje_delantero', 'MAN VGD95', 'eje_trasero', 'MAN MCP16ZG', 'llantas', 'Del. 385/65R22.5, tras. 315/80R22.5',
    'tanque_l', 400, 'clave_vehicular', '2984910'),
  'Llevará la grúa IMT 34/235 K4 (BAT-EM-GRU02).'
from (select id from public.mt_tipos_activo where codigo = 'TRACTOCAMION') t
cross join (select id from public.mt_activos where codigo = 'MOVIL') p
on conflict (codigo) do nothing;

-- Camión ligero para montacargas eléctrico · compra de contado TGN Golfo F538
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, anio, num_serie,
  num_economico, ubicacion, forma_adquisicion, fecha_alta, ns_referencia, especificaciones, notas)
select 'BAT-EM-CAM02', 'Camión ligero SITRAK 4x2 8 t', t.id, 'equipo', p.id, 'SITRAK', '8T G3W 4x2', 2026,
  '3DJ1B1BB7TA001104', 'BAT-EM-CAM02', 'Planta Teapa', 'compra', '2026-10-12', 'Factura NetSuite F538 (TGN Golfo)',
  jsonb_build_object(
    'motor', 'Cummins F3.8EVIE170 170 HP Euro VI, núm. 77793820', 'transmision', 'Manual Fast-Eaton 6DSX60T',
    'tanque_l', 120, 'clave_vehicular', '2984912'),
  'Llevará un montacargas eléctrico que está por adquirirse; se dará de alta cuando llegue.'
from (select id from public.mt_tipos_activo where codigo = 'CAMION') t
cross join (select id from public.mt_activos where codigo = 'MOVIL') p
on conflict (codigo) do nothing;

-- Grúas: activos propios; padre_id = camión donde está o estará montada
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, anio, num_serie,
  num_economico, ubicacion, forma_adquisicion, especificaciones, notas)
select 'BAT-EM-GRU01', 'Grúa Palfinger PK15002', t.id, 'equipo', c.id, 'Palfinger', 'PK15002 (S205-SK-A)', 2002,
  '0811178', 'BAT-EM-GRU01', 'Planta Teapa', 'compra',
  jsonb_build_object('montaje_destino', 'BAT-EM-CAM01', 'montaje_anterior', 'Camión de bloques (sin registrar en Connect)'),
  'Pasa del camión de bloques al SITRAK BAT-EM-CAM01. Registrar aparte el costo del montaje. Pendiente: manual de partes y de servicio.'
from (select id from public.mt_tipos_activo where codigo = 'GRUA') t
cross join (select id from public.mt_activos where codigo = 'BAT-EM-CAM01') c
on conflict (codigo) do nothing;

insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, num_serie,
  num_economico, ubicacion, especificaciones, notas)
select 'BAT-EM-GRU02', 'Grúa IMT 34/235 K4', t.id, 'equipo', c.id, 'IMT', '34/235 K4', '360615',
  'BAT-EM-GRU02', 'Planta Teapa',
  jsonb_build_object('montaje_destino', 'BAT-EM-TRC01', 'toma_fuerza', 'Válvula solenoide Parker Chelsea 379604-1'),
  'Montaje en BAT-EM-TRC01. Pendiente: bomba hidráulica y especificación de la toma de fuerza.'
from (select id from public.mt_tipos_activo where codigo = 'GRUA') t
cross join (select id from public.mt_activos where codigo = 'BAT-EM-TRC01') c
on conflict (codigo) do nothing;
