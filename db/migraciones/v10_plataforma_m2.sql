-- BATAB Connect · v10 · Plataforma del Freightliner M2
-- Fecha: 2026-11-03. Vino incluida en la compra del camión a Madisa (Maquinaria Diesel); no tiene número de serie.
-- Reversa: delete from public.mt_activos where codigo = 'BAT-EM-PLT02';
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, num_economico, ubicacion, forma_adquisicion,
  area_aviso, especificaciones, notas)
select 'BAT-EM-PLT02', 'Plataforma del Freightliner M2', t.id, 'equipo', c.id, 'BAT-EM-PLT02', 'Planta Teapa', 'compra',
  'reparto',
  jsonb_build_object('propietario', 'Bloques y Agregados de Tabasco', 'montaje_actual', 'BAT-EM-CAM03',
    'origen', 'Incluida en la compra del Freightliner M2 a Madisa (Maquinaria Diesel)', 'num_serie', 'Sin número de serie; se identifica con BAT-EM-PLT02'),
  'Sin número de serie de fábrica: usar BAT-EM-PLT02 como identificación (placa o grabado). Pendiente: medidas.'
from (select id from public.mt_tipos_activo where codigo = 'PLATAFORMA') t
cross join (select id from public.mt_activos where codigo = 'BAT-EM-CAM03') c
on conflict (codigo) do nothing;
