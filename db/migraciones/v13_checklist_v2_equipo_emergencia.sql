-- =====================================================================
-- BATAB Connect · v13 · Check-list versión 2 de camiones y plataformas
-- Fecha: 2026-11-03 · Solicitado por el Director.
-- Camión: se separa el equipo de emergencia y se agregan llanta de
-- refacción, gato con llave de birlos y herramienta básica.
-- Plataforma: trinquetes de amarre de 4" como punto propio.
-- La versión 1 se conserva (la app siempre usa la versión más alta).
-- Reversa: delete from public.mt_checklist_items where version = 2 and tipo_id in
--   (select id from public.mt_tipos_activo where codigo in ('CAMION','CAMION_RABON','TRACTOCAMION','PLATAFORMA'));
-- =====================================================================
insert into public.mt_checklist_items (tipo_id, version, orden, seccion, pregunta, tipo_respuesta, critica, fuente)
select i.tipo_id, 2, i.orden, i.seccion, i.pregunta, i.tipo_respuesta, i.critica, i.fuente
from public.mt_checklist_items i
join public.mt_tipos_activo t on t.id = i.tipo_id and t.codigo in ('CAMION','CAMION_RABON','TRACTOCAMION')
where i.version = 1 and i.orden <= 24
on conflict (tipo_id, version, orden) do nothing;

insert into public.mt_checklist_items (tipo_id, version, orden, seccion, pregunta, tipo_respuesta, critica, fuente)
select t.id, 2, v.orden, v.seccion, v.pregunta, 'ok_falla', v.critica, v.fuente
from (values
  (25, 'Equipo de emergencia', 'Extintor cargado y vigente', true, 'NOM-068 paso 29.2'),
  (26, 'Equipo de emergencia', 'Triángulos o reflejantes de emergencia a bordo', true, 'NOM-068 paso 29.2'),
  (27, 'Equipo de emergencia', 'Botiquín de primeros auxilios completo', false, 'Director BATAB'),
  (28, 'Refacción y herramienta', 'Llanta de refacción en buen estado e inflada', false, 'NOM-068 paso 13.4 · Director BATAB'),
  (29, 'Refacción y herramienta', 'Gato y llave de birlos (cruceta) a bordo y funcionando', false, 'Director BATAB'),
  (30, 'Refacción y herramienta', 'Herramienta básica completa', false, 'Director BATAB'),
  (31, 'Documentos', 'Tarjeta de circulación, póliza de seguro y licencia vigentes a bordo', true, 'Reglamento SCT')
) as v(orden, seccion, pregunta, critica, fuente)
cross join (select id from public.mt_tipos_activo where codigo in ('CAMION','CAMION_RABON','TRACTOCAMION')) t
on conflict (tipo_id, version, orden) do nothing;

insert into public.mt_checklist_items (tipo_id, version, orden, seccion, pregunta, tipo_respuesta, critica, fuente)
select t.id, 2, v.orden, v.seccion, v.pregunta, 'ok_falla', v.critica, v.fuente
from (values
  (1, 'Plataforma', 'Piso sin láminas rotas, sueltas o con hoyos', true, 'Especificación de la plataforma'),
  (2, 'Plataforma', 'Fijación al chasis: placas y tornillos completos y apretados', true, 'Especificación de la plataforma'),
  (3, 'Plataforma', 'Largueros y travesaños sin fisuras ni deformaciones', true, 'Especificación de la plataforma'),
  (4, 'Plataforma', 'Luces LED y cinta reflejante completas y funcionando', false, 'Especificación de la plataforma'),
  (5, 'Amarres', 'Trinquetes de amarre de 4": bandas sin cortes ni deshilachados; matraca y ganchos funcionan', true, 'NOM-068 pasos 9.4 y 11.2 · Director BATAB'),
  (6, 'Amarres', 'Puntos de amarre de la plataforma sin daño', true, 'NOM-068 pasos 9.4 y 11.2')
) as v(orden, seccion, pregunta, critica, fuente)
cross join (select id from public.mt_tipos_activo where codigo = 'PLATAFORMA') t
on conflict (tipo_id, version, orden) do nothing;
