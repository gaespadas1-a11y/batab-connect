-- BATAB Connect · v5e · Camión Freightliner M2 con grúa Palfinger PK23500
-- Fecha: 2026-11-03. Datos de placa (serie, año, motor) pendientes.
-- Reversa: delete from public.mt_activos where codigo in ('BAT-EM-GRU03'); delete from public.mt_activos where codigo in ('BAT-EM-CAM03');

insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, num_economico, ubicacion, notas)
select 'BAT-EM-CAM03', 'Camión Freightliner M2 (grúa Palfinger PK23500)', t.id, 'equipo', p.id, 'Freightliner', 'M2',
  'BAT-EM-CAM03', 'Planta Teapa', 'Pendiente: año, serie (VIN), motor, transmisión y forma de adquisición.'
from (select id from public.mt_tipos_activo where codigo = 'CAMION') t
cross join (select id from public.mt_activos where codigo = 'MOVIL') p
on conflict (codigo) do nothing;

insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, num_economico, ubicacion, especificaciones, notas)
select 'BAT-EM-GRU03', 'Grúa Palfinger PK23500', t.id, 'equipo', c.id, 'Palfinger', 'PK23500',
  'BAT-EM-GRU03', 'Planta Teapa',
  jsonb_build_object('montaje_actual', 'BAT-EM-CAM03', 'manual', 'Biblioteca_Tecnica/BAT-EM-GRU03_Palfinger-PK23500'),
  'Pendiente: datos de la placa (código, número, año, presión).'
from (select id from public.mt_tipos_activo where codigo = 'GRUA') t
cross join (select id from public.mt_activos where codigo = 'BAT-EM-CAM03') c
on conflict (codigo) do nothing;
