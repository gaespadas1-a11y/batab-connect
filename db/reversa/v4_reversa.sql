-- BATAB Connect · REVERSA de v4
drop function if exists public.mt_reporte_estado(uuid, uuid, text, text, boolean);
drop function if exists public.mt_bandeja(uuid, text[]);
drop table if exists public.mt_reporte_seguimiento;
drop table if exists public.mt_reporte_fotos;
delete from public.mt_avisos_destinos where ambito = 'prueba';
alter table public.mt_avisos_destinos drop column if exists ambito;
drop table if exists public.mt_perfiles;
-- Fotos: vaciar el bucket desde el panel de Storage y luego:
-- delete from storage.buckets where id = 'connect_fotos';
-- Usuario de prueba GEHT (si se quiere quitar):
-- update public.operadores set activo = false where codigo = 'GEHT';
