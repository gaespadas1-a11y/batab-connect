-- =====================================================================
-- BATAB Connect · v11 · Check-list diario de camiones y plataformas
-- Fecha: 2026-11-03 · Aprobado por el Director.
-- Fuentes: Manual del conductor Freightliner Business Class M2 (cap. 11,
-- inspección diaria previaje) y NOM-068-SCT-2-2014 (procedimiento de verificación).
-- Aplica a torton (CAMION), rabón y tractocamión. La plataforma lleva un
-- check-list corto propio. Cada check-list guardado sirve como bitácora de
-- inspección ocular diaria.
-- Reversa: db/reversa/v11_reversa.sql
-- =====================================================================
insert into public.mt_checklist_items (tipo_id, version, orden, seccion, pregunta, tipo_respuesta, critica, fuente)
select t.id, 1, v.orden, v.seccion, v.pregunta, 'ok_falla', v.critica, 'Manual conductor Freightliner M2 cap. 11 · NOM-068-SCT-2-2014'
from (values
  (1,  'Llantas y ruedas', 'Llantas sin cortes ni desgaste y bien infladas; birlos y tuercas completos', true),
  (2,  'Llantas y ruedas', 'Rines sin fisuras; mazas sin fuga de aceite', true),
  (3,  'Recorrido', 'Muelles, soportes y amortiguadores sin roturas', true),
  (4,  'Recorrido', 'Sin fugas debajo de motor, transmisión o diferencial', true),
  (5,  'Recorrido', 'Tanque de combustible sujeto, sin fugas y con tapón', true),
  (6,  'Recorrido', 'Escape sin fugas ni piezas sueltas', false),
  (7,  'Recorrido', 'Chasis, plataforma o caja sin fisuras ni piezas sueltas', true),
  (8,  'Recorrido', 'Loderas en su lugar', false),
  (9,  'Recorrido', 'Carga sujeta (cadenas, bandas, redilas)', true),
  (10, 'Motor', 'Nivel de aceite de motor correcto', true),
  (11, 'Motor', 'Nivel de refrigerante correcto', true),
  (12, 'Motor', 'Nivel de aceite de dirección hidráulica', false),
  (13, 'Motor', 'Bandas y mangueras sin grietas', false),
  (14, 'Motor', 'Nivel de AdBlue (urea) suficiente — solo SITRAK Euro VI', false),
  (15, 'Aire y frenos', 'Tanques de aire purgados', false),
  (16, 'Aire y frenos', 'Presión de aire llega a su rango y la alarma de baja presión funciona', true),
  (17, 'Aire y frenos', 'Sin fugas de aire audibles; mangueras de freno sin daño', true),
  (18, 'Aire y frenos', 'Freno de servicio y freno de estacionamiento funcionan', true),
  (19, 'Cabina', 'Juego del volante normal', true),
  (20, 'Cabina', 'Testigos del tablero sin alarma al arrancar', true),
  (21, 'Cabina', 'Luces: faros, direccionales, stop, intermitentes y gálibo', true),
  (22, 'Cabina', 'Parabrisas, espejos y limpiaparabrisas en buen estado', false),
  (23, 'Cabina', 'Bocina y alarma de reversa funcionan', false),
  (24, 'Seguridad', 'Cinturón de seguridad funciona', true),
  (25, 'Seguridad', 'Extintor cargado, triángulos y botiquín a bordo', true),
  (26, 'Documentos', 'Tarjeta de circulación, póliza de seguro y licencia vigentes a bordo', true)
) as v(orden, seccion, pregunta, critica)
cross join (select id from public.mt_tipos_activo where codigo in ('CAMION','CAMION_RABON','TRACTOCAMION')) t
on conflict (tipo_id, version, orden) do nothing;

insert into public.mt_checklist_items (tipo_id, version, orden, seccion, pregunta, tipo_respuesta, critica, fuente)
select t.id, 1, v.orden, v.seccion, v.pregunta, 'ok_falla', v.critica, 'Especificación de la plataforma · NOM-068 pasos 9 y 11'
from (values
  (1, 'Plataforma', 'Piso sin láminas rotas, sueltas o con hoyos', true),
  (2, 'Plataforma', 'Fijación al chasis: placas y tornillos completos y apretados', true),
  (3, 'Plataforma', 'Largueros y travesaños sin fisuras ni deformaciones', true),
  (4, 'Plataforma', 'Luces LED y cinta reflejante completas y funcionando', false),
  (5, 'Plataforma', 'Puntos de amarre, cadenas y bandas en buen estado', true)
) as v(orden, seccion, pregunta, critica)
cross join (select id from public.mt_tipos_activo where codigo = 'PLATAFORMA') t
on conflict (tipo_id, version, orden) do nothing;
