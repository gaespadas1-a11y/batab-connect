-- =====================================================================
-- BATAB Connect · REVERSA de v1
-- Deja la base exactamente como estaba antes de v1 (ver respaldos/2026-10-20_estado_base.md).
-- Borra SOLO lo que creó v1. No toca ninguna otra tabla ni dato.
-- =====================================================================
drop table if exists public.mt_checklist_respuestas;
drop table if exists public.mt_checklists;
drop table if exists public.mt_checklist_items;
drop table if exists public.mt_lecturas;
drop table if exists public.mt_sesiones_uso;
drop table if exists public.mt_autorizaciones;
drop table if exists public.mt_colaborador_costos;
drop table if exists public.mt_activo_reparto;
drop table if exists public.mt_pieza_instalaciones;
drop table if exists public.mt_piezas;
drop table if exists public.mt_activos;
drop table if exists public.mt_tipos_activo;

drop function if exists public.mt_lecturas_validar();
drop function if exists public.mt_touch_updated_at();

-- Columnas agregadas a operadores (estaban vacías al crearse)
alter table public.operadores drop column if exists num_empleado;
alter table public.operadores drop column if exists puesto;
alter table public.operadores drop column if exists turno_habitual;
