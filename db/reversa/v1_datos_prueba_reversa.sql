-- BATAB Connect · REVERSA de los datos de prueba v1
-- Vacía las tablas mt_ (no toca operadores ni ninguna otra tabla).
truncate public.mt_checklist_respuestas, public.mt_checklists, public.mt_checklist_items,
         public.mt_lecturas, public.mt_sesiones_uso, public.mt_autorizaciones,
         public.mt_colaborador_costos, public.mt_activo_reparto, public.mt_pieza_instalaciones,
         public.mt_piezas, public.mt_activos, public.mt_tipos_activo restart identity;
