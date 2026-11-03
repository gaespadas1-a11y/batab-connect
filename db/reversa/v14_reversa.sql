-- BATAB Connect · REVERSA de v14
select cron.unschedule('connect-caducidad-seguridad');
drop trigger if exists mt_reportes_seguridad on public.mt_reportes;
drop function if exists public.mt_trg_reportes_seguridad();
drop function if exists public.mt_alerta_caducidad_seguridad(boolean);
drop function if exists public.mt_seguridad_registrar(uuid, text, jsonb, uuid, text);
drop function if exists public.mt_seguridad_ficha(uuid, text);
drop function if exists public.mt_destinos_seguridad(boolean);
drop function if exists public.mt_enviar_correo(text[], text, text, text);
alter table public.mt_checklist_items drop column if exists seguridad;
drop table if exists public.mt_seguridad_entregas;
drop table if exists public.mt_equipo_seguridad;
drop table if exists public.mt_seguridad_catalogo;
delete from public.mt_avisos_destinos where rol = 'seguridad';
alter table public.mt_avisos_destinos drop constraint if exists mt_avisos_destinos_rol_check;
alter table public.mt_avisos_destinos add constraint mt_avisos_destinos_rol_check check (rol in ('mantenimiento','area','licencias'));
update public.mt_perfiles set roles = array_remove(roles, 'seguridad');
alter table public.mt_perfiles drop constraint if exists mt_perfiles_roles_check;
alter table public.mt_perfiles add constraint mt_perfiles_roles_check
  check (roles <@ array['operador','mantenimiento','supervisor_area','almacen','director']::text[]);
