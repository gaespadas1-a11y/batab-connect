-- =====================================================================
-- BATAB Connect · v8 · Tipos de vehículo y grúa según las capacidades
-- que se autorizan a los choferes (torton, rabón, camioneta 3 t, utilitario,
-- tractocamión, grúa articulada, grúa telescópica).
-- Fecha: 2026-11-03
-- Reversa: db/reversa/v8_reversa.sql
-- =====================================================================
update public.mt_tipos_activo set nombre = 'Camión torton' where codigo = 'CAMION';
update public.mt_tipos_activo set nombre = 'Grúa articulada' where codigo = 'GRUA';

insert into public.mt_tipos_activo (codigo, nombre, categoria, medidor) values
  ('CAMION_RABON',      'Camión rabón',          'movil', 'km'),
  ('CAMIONETA_3T',      'Camioneta de 3 toneladas', 'movil', 'km'),
  ('UTILITARIO',        'Vehículo utilitario',   'movil', 'km'),
  ('GRUA_TELESCOPICA',  'Grúa telescópica',      'movil', 'ninguno')
on conflict (codigo) do nothing;

-- El SITRAK 8 t 4x2 es rabón (un solo eje trasero)
update public.mt_activos set tipo_id = (select id from public.mt_tipos_activo where codigo = 'CAMION_RABON')
where codigo = 'BAT-EM-CAM02';
