-- =====================================================================
-- BATAB Connect · v5c · Plataforma de block y propiedad de los accesorios
-- Fecha: 2026-11-03
-- La grúa Palfinger (propia desde años anteriores) y la plataforma para
-- transportar block (adquisición nueva, pendiente de factura) son de BATAB y
-- van montadas en un camión arrendado (Bepensa).
-- Se registra la propiedad y que el seguro debe nombrar a BATAB como
-- beneficiario preferente de ambos accesorios.
-- Reversa: db/reversa/v5c_reversa.sql
-- =====================================================================

insert into public.mt_tipos_activo (codigo, nombre, categoria, medidor) values
  ('PLATAFORMA', 'Plataforma de carga montada', 'movil', 'ninguno')
on conflict (codigo) do nothing;

-- Plataforma para transportar block, montada en BAT-EM-CAM01
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, num_economico, ubicacion,
  forma_adquisicion, especificaciones, notas)
select 'BAT-EM-PLT01', 'Plataforma para transporte de block', t.id, 'equipo', c.id, 'BAT-EM-PLT01', 'Planta Teapa',
  'compra',
  jsonb_build_object(
    'propietario', 'Bloques y Agregados de Tabasco (adquisición nueva, pendiente de factura)',
    'montaje_destino', 'BAT-EM-CAM01',
    'seguro', jsonb_build_object('beneficiario_preferente', 'Bloques y Agregados de Tabasco',
      'estado', 'Pendiente: incluir en la póliza del camión como equipo especial')),
  'Accesorio propio de BATAB montado en un camión arrendado. Al devolver el camión a Bepensa se retira. Pendiente: factura del proveedor con medidas, materiales y valor.'
from (select id from public.mt_tipos_activo where codigo = 'PLATAFORMA') t
cross join (select id from public.mt_activos where codigo = 'BAT-EM-CAM01') c
on conflict (codigo) do nothing;

-- Grúa Palfinger: propiedad y seguro
update public.mt_activos set
  especificaciones = especificaciones || jsonb_build_object(
    'propietario', 'Bloques y Agregados de Tabasco (activo propio de años anteriores)',
    'seguro', jsonb_build_object('beneficiario_preferente', 'Bloques y Agregados de Tabasco',
      'estado', 'Pendiente: incluir en la póliza del camión como equipo especial')),
  notas = 'Propiedad de BATAB desde años anteriores. Pasa del camión de bloques al SITRAK BAT-EM-CAM01 (arrendado). Al devolver el camión a Bepensa se retira. Registrar aparte el costo del montaje. Pendiente: manual de partes y de servicio.'
where codigo = 'BAT-EM-GRU01';

-- Camión arrendado: qué accesorios son de BATAB
update public.mt_activos set
  especificaciones = especificaciones || jsonb_build_object(
    'accesorios_propios_batab', jsonb_build_array('BAT-EM-GRU01 Grúa Palfinger PK15002', 'BAT-EM-PLT01 Plataforma para transporte de block'),
    'seguro', jsonb_build_object('beneficiario_preferente_accesorios', 'Bloques y Agregados de Tabasco',
      'nota', 'La póliza del camión debe cubrir la grúa y la plataforma como equipo especial con BATAB como beneficiario preferente')),
  notas = 'Camión arrendado (Bepensa). Lleva la grúa Palfinger (BAT-EM-GRU01) y la plataforma de block (BAT-EM-PLT01), ambas propiedad de BATAB. Pedir a Bepensa un escrito que lo reconozca y que se retiran al devolver el camión.'
where codigo = 'BAT-EM-CAM01';
