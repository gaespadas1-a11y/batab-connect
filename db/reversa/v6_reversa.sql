-- BATAB Connect · REVERSA de v6 (volver a desplegar connect-api 0.3.0 antes)
delete from public.mt_avisos_destinos where area_aviso = 'reparto';
alter table public.mt_avisos_destinos drop column if exists area_aviso;
alter table public.mt_activos drop column if exists area_aviso;
