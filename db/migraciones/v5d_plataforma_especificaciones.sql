-- BATAB Connect · v5d · Especificaciones de la plataforma BAT-EM-PLT01 (según pedido al fabricante)
-- Reversa: update public.mt_activos set especificaciones = especificaciones - 'medidas' - 'estructura' - 'piso' - 'acabado' - 'iluminacion' - 'capacidad_diseno_t' - 'fijacion' where codigo = 'BAT-EM-PLT01';
update public.mt_activos set
  marca = null, modelo = 'Plataforma torton 6.10 × 2.50 m',
  especificaciones = especificaciones || jsonb_build_object(
    'medidas', '6.10 m de largo × 2.50 m de ancho',
    'estructura', 'Largueros de 10" en canal U; travesaños de 4" tipo I a cada 45 cm',
    'piso', 'Lámina lisa de 3/16"',
    'iluminacion', 'LED perimetral y cinta reflejante',
    'acabado', 'Primario RP-6 y esmalte Center Stage Sherwin-Williams, color verde',
    'capacidad_diseno_t', 25,
    'fijacion', 'Placa de 1/4" y tornillos al bastidor; desmontable sin dañar el vehículo')
where codigo = 'BAT-EM-PLT01';
