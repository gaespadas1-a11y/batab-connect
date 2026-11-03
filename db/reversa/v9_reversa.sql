-- BATAB Connect · REVERSA de v9
select cron.unschedule('connect-alerta-licencias');
drop function if exists public.mt_alerta_licencias(boolean);
drop table if exists public.mt_avisos_licencias_log;
delete from public.mt_avisos_destinos where rol = 'licencias';
alter table public.mt_avisos_destinos drop constraint if exists mt_avisos_destinos_rol_check;
alter table public.mt_avisos_destinos add constraint mt_avisos_destinos_rol_check check (rol in ('mantenimiento','area'));
alter table public.mt_perfiles drop column if exists licencia_numero, drop column if exists licencia_tipo, drop column if exists licencia_vence;
