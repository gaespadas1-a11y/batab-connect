-- BATAB Connect · REVERSA de v2: quita solo las funciones de uso diario.
drop function if exists public.mt_ficha(uuid, text);
drop function if exists public.mt_iniciar_uso(uuid, text, numeric, jsonb, text, numeric, numeric, text);
drop function if exists public.mt_cerrar_uso(uuid, numeric);
drop function if exists public.mt_horas_vigencia_checklist();
