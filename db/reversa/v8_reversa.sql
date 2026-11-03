-- BATAB Connect · REVERSA de v8
update public.mt_activos set tipo_id = (select id from public.mt_tipos_activo where codigo = 'CAMION') where codigo = 'BAT-EM-CAM02';
delete from public.mt_autorizaciones where tipo_id in (select id from public.mt_tipos_activo where codigo in ('CAMION_RABON','CAMIONETA_3T','UTILITARIO','GRUA_TELESCOPICA'));
delete from public.mt_tipos_activo where codigo in ('CAMION_RABON','CAMIONETA_3T','UTILITARIO','GRUA_TELESCOPICA');
update public.mt_tipos_activo set nombre = 'Camión' where codigo = 'CAMION';
update public.mt_tipos_activo set nombre = 'Grúa articulada montada' where codigo = 'GRUA';
