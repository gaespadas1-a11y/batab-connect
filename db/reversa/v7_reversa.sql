-- BATAB Connect · REVERSA de v7
delete from public.mt_autorizaciones
where activo_id = (select id from public.mt_activos where codigo = 'BAT-EM-GRU03')
  and operador_id = (select id from public.operadores where codigo = 'GEHO');
-- Si ya hay check-lists llenados de grúas, desactivar en lugar de borrar:
-- update public.mt_checklist_items set activo = false where tipo_id = (select id from public.mt_tipos_activo where codigo = 'GRUA');
delete from public.mt_checklist_items
where tipo_id = (select id from public.mt_tipos_activo where codigo = 'GRUA')
  and not exists (select 1 from public.mt_checklist_respuestas r where r.item_id = mt_checklist_items.id);
update public.mt_tipos_activo set medidor = 'horas' where codigo = 'GRUA';
