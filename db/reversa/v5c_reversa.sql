-- BATAB Connect · REVERSA de v5c
delete from public.mt_activos where codigo = 'BAT-EM-PLT01';
delete from public.mt_tipos_activo where codigo = 'PLATAFORMA';
update public.mt_activos set
  especificaciones = especificaciones - 'propietario' - 'seguro',
  notas = 'Pasa del camión de bloques al SITRAK BAT-EM-CAM01. Registrar aparte el costo del montaje. Pendiente: manual de partes y de servicio.'
where codigo = 'BAT-EM-GRU01';
update public.mt_activos set
  especificaciones = especificaciones - 'accesorios_propios_batab' - 'seguro',
  notas = 'Llevará la grúa Palfinger PK15002 (BAT-EM-GRU01). Ver condiciones del contrato sobre accesorios antes del montaje.'
where codigo = 'BAT-EM-CAM01';
