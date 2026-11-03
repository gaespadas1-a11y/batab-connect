-- BATAB Connect · REVERSA de v11 (si ya hay check-lists llenados, desactivar: update ... set activo = false)
delete from public.mt_checklist_items i
where i.tipo_id in (select id from public.mt_tipos_activo where codigo in ('CAMION','CAMION_RABON','TRACTOCAMION','PLATAFORMA'))
  and not exists (select 1 from public.mt_checklist_respuestas r where r.item_id = i.id);
