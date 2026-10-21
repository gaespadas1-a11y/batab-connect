-- BATAB Connect · REVERSA de v3
-- Vuelve a v2: quita reportes y avisos, regresa la ficha de v2 (ejecutar después
-- db/migraciones/v2_connect_funciones_uso.sql para restaurar mt_ficha original).
drop function if exists public.mt_reportar(uuid, text, text, boolean, text);
drop function if exists public.mt_iniciar_uso_v2(uuid, text, numeric, jsonb, text[], text, numeric, numeric, text);
drop table if exists public.mt_avisos_log;
drop table if exists public.mt_avisos_destinos;
drop table if exists public.mt_reportes;
alter table public.mt_sesiones_uso drop constraint if exists mt_sesiones_uso_cierre_motivo_check;
alter table public.mt_sesiones_uso add constraint mt_sesiones_uso_cierre_motivo_check
  check (cierre_motivo in ('manual','otro_equipo','otro_operador','fin_turno','supervisor'));
alter table public.mt_sesiones_uso drop column if exists lineas_atendidas;
update public.mt_activos set estado = 'operativo', notas = null where codigo = '2B';
