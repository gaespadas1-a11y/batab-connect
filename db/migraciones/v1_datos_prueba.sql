-- =====================================================================
-- BATAB Connect · v1 · Datos de prueba (piloto Komatsu WA320-6)
-- Fecha: 2026-10-20
-- Solo inserta en tablas mt_. Usa los usuarios de prueba existentes:
--   831a63ec-2cbe-4663-9c11-f3396bc0549c  GERARDO ESPADAS - OPERADOR PRUEBA
--   3fbc2df4-cb2c-436e-9c5d-e91c31aa8b7d  GERARDO ESPADAS - SUPERVISOR PRUEBA
-- Reversa: db/reversa/v1_datos_prueba_reversa.sql
-- =====================================================================

-- Tipos de activo
insert into public.mt_tipos_activo (codigo, nombre, categoria, medidor) values
 ('PLANTA','Planta','estructura','ninguno'),
 ('LINEA','Línea de producción','estructura','horas_linea'),
 ('SUBSISTEMA','Subsistema de línea','estructura','horas_linea'),
 ('GRUPO_MOVIL','Grupo de equipo móvil','estructura','ninguno'),
 ('CARGADOR','Cargador frontal','movil','horas'),
 ('MANIPULADOR','Manipulador telescópico','movil','horas'),
 ('MONTACARGAS','Montacargas','movil','horas'),
 ('MOTOR_DIESEL','Motor diésel','componente','horas'),
 ('BOMBA_HID','Bomba hidráulica','componente','horas'),
 ('TRANSMISION','Transmisión','componente','horas'),
 ('EJE','Eje','componente','horas'),
 ('TOLVA','Tolva','fijo','horas_linea'),
 ('BANDA','Banda transportadora','fijo','horas_linea'),
 ('REDUCTOR','Reductor','componente','horas_linea');

-- Árbol mínimo
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, ubicacion)
select 'PT-TEAPA','Planta Teapa', id, 'planta', 'Teapa, Tabasco' from mt_tipos_activo where codigo='PLANTA';

insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, linea, ubicacion)
select v.codigo, v.nombre, t.id, 'linea', p.id, v.linea, 'Planta Teapa'
from (values ('1B','Línea Besser 1','1B'),('2B','Línea Besser 2','2B'),('3C','Línea Columbia','3C')) v(codigo,nombre,linea)
cross join (select id from mt_tipos_activo where codigo='LINEA') t
cross join (select id from mt_activos where codigo='PT-TEAPA') p;

insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, ubicacion)
select 'MOVIL','Equipo móvil', t.id, 'linea', p.id, 'Planta Teapa'
from (select id from mt_tipos_activo where codigo='GRUPO_MOVIL') t
cross join (select id from mt_activos where codigo='PT-TEAPA') p;

-- Cargador Komatsu WA320-6
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo, num_serie, num_economico,
                               ubicacion, forma_adquisicion, especificaciones, notas)
select 'BAT-MP-CFR02', 'Cargador frontal Komatsu WA320-6', t.id, 'equipo', p.id, 'Komatsu', 'WA320-6', '75008', 'BAT-MP-CFR02',
       'Planta Teapa', 'arrendamiento_financiero',
       jsonb_build_object(
         'pin','KMTWA108VSA075008',
         'motor','Komatsu SAA6D107E-1 diésel common rail',
         'potencia','125 kW / 167 HP @ 2,000 rpm',
         'transmision','HST (hidrostática) + caja de transferencia',
         'peso_operativo_kg',14085,
         'carga_normal_kg',4480,
         'bote_m3',2.8,
         'manual_omm','TEN00456-01 (S/N 70587+)',
         'manual_taller','SEN03911-03 (S/N 70001+)',
         'manual_motor','SEN00161-24',
         'funcion','Apila y homogeniza agregados en la clasificación; carga tolvas según producción'),
       'Da servicio a Besser 1, Besser 2 y Columbia. Pendientes: año, horómetro al alta, series de componentes (solicitadas a Komatsu).'
from (select id from mt_tipos_activo where codigo='CARGADOR') t
cross join (select id from mt_activos where codigo='MOVIL') p;

-- Componentes mayores (posiciones)
insert into public.mt_activos (codigo, nombre, tipo_id, nivel, padre_id, marca, modelo)
select v.codigo, v.nombre, t.id, 'componente', e.id, 'Komatsu', v.modelo
from (values
  ('BAT-MP-CFR02-MOT','Motor','MOTOR_DIESEL','SAA6D107E-1'),
  ('BAT-MP-CFR02-BHI','Bomba hidráulica','BOMBA_HID',null),
  ('BAT-MP-CFR02-TRA','Transmisión HST','TRANSMISION',null),
  ('BAT-MP-CFR02-EJD','Eje delantero','EJE',null),
  ('BAT-MP-CFR02-EJT','Eje trasero','EJE',null)
) v(codigo,nombre,tipo,modelo)
join mt_tipos_activo t on t.codigo = v.tipo
cross join (select id from mt_activos where codigo='BAT-MP-CFR02') e;

-- Pieza física del motor (serie por capturar) e instalación
with pz as (
  insert into public.mt_piezas (tipo_id, marca, modelo, estado, notas)
  select id, 'Komatsu', 'SAA6D107E-1', 'instalada', 'Serie por capturar (solicitada a Komatsu)'
  from mt_tipos_activo where codigo='MOTOR_DIESEL'
  returning id
)
insert into public.mt_pieza_instalaciones (pieza_id, activo_id, motivo, registrado_por)
select pz.id, a.id, 'Alta inicial del equipo', '3fbc2df4-cb2c-436e-9c5d-e91c31aa8b7d'
from pz cross join (select id from mt_activos where codigo='BAT-MP-CFR02-MOT') a;

-- Reparto entre líneas (criterio por confirmar: horas de uso)
insert into public.mt_activo_reparto (activo_id, linea, criterio)
select a.id, l.linea, 'horas_uso'
from (select id from mt_activos where codigo='BAT-MP-CFR02') a
cross join (values ('1B'),('2B'),('3C')) l(linea);

-- Usuario de prueba: costo de ejemplo y autorización
insert into public.mt_colaborador_costos (operador_id, costo_hora, vigente_desde, es_ejemplo, notas)
values ('831a63ec-2cbe-4663-9c11-f3396bc0549c', 100, '2026-10-01', true, 'Costo de ejemplo para pruebas; no es real');

insert into public.mt_autorizaciones (operador_id, tipo_id, capacitado_en, autorizado_por, notas)
select '831a63ec-2cbe-4663-9c11-f3396bc0549c', id, '2026-10-20', '3fbc2df4-cb2c-436e-9c5d-e91c31aa8b7d', 'Autorización de prueba'
from mt_tipos_activo where codigo='CARGADOR';

-- Check-list diario del cargador (OMM TEN00456-01, pág. 3-89 a 3-92 y 4-43)
-- "critica" es criterio sugerido de BATAB Connect, por validar con mantenimiento.
insert into public.mt_checklist_items (tipo_id, version, orden, seccion, pregunta, tipo_respuesta, critica, fuente)
select t.id, 1, v.orden, v.seccion, v.pregunta, v.tipo, v.critica, 'OMM TEN00456-01 3-89 a 3-92, 4-43'
from (values
 (1,'Recorrido','Daños, desgaste u holgura en equipo de trabajo, cilindros, articulaciones y mangueras','ok_falla',true),
 (2,'Recorrido','Limpiar polvo y material inflamable alrededor de motor, batería, radiador, escape y turbo','ok_falla',false),
 (3,'Recorrido','Fugas de refrigerante o aceite alrededor del motor','ok_falla',true),
 (4,'Recorrido','Fugas en línea de combustible; mangueras y tubos sin daño','ok_falla',true),
 (5,'Recorrido','Fugas de aceite en tubería HST, caja de transferencia, ejes, tanque hidráulico, mangueras y conexiones','ok_falla',true),
 (6,'Recorrido','Fugas de aceite en línea de frenos','ok_falla',true),
 (7,'Recorrido','Llantas, rines y tornillos de maza: daño, desgaste, flojos','ok_falla',true),
 (8,'Recorrido','Pasamanos y escalones: daño o tornillos flojos','ok_falla',false),
 (9,'Recorrido','Tablero, indicadores y luces: daño o tornillos flojos','ok_falla',false),
 (10,'Recorrido','Tornillos de montaje del filtro de aire','ok_falla',false),
 (11,'Recorrido','Terminales de batería apretadas','ok_falla',false),
 (12,'Recorrido','Cinturón de seguridad y anclajes','ok_falla',true),
 (13,'Recorrido','Limpiar cristales de cabina','ok_falla',false),
 (14,'Recorrido','Llantas: no usar si la banda está bajo 15% de nueva, cortes a cuerdas o ceja dañada','ok_falla',true),
 (15,'Recorrido','Rines: deformación, corrosión o grietas','ok_falla',true),
 (16,'Antes de arrancar','Monitor: todas las luces y alarma encienden ~2 s al girar la llave a ON','ok_falla',true),
 (17,'Antes de arrancar','Nivel de refrigerante','ok_falla',true),
 (18,'Antes de arrancar','Nivel de aceite de motor','ok_falla',true),
 (19,'Antes de arrancar','Separador de agua: drenar','ok_falla',false),
 (20,'Antes de arrancar','Indicador del filtro de aire','ok_falla',false),
 (21,'Antes de arrancar','Nivel de combustible','ok_falla',false),
 (22,'Antes de arrancar','Cableado eléctrico','ok_falla',false),
 (23,'Antes de arrancar','Presión de inflado de llantas','ok_falla',false),
 (24,'Antes de arrancar','Limpiaparabrisas y lavador','ok_falla',false),
 (25,'Antes de arrancar','Claxon','ok_falla',true),
 (26,'Antes de arrancar','Desempañador','ok_falla',false),
 (27,'Antes de arrancar','Cerraduras y salida de emergencia','ok_falla',false),
 (28,'Turno','Horómetro inicial','numero',false)
) v(orden,seccion,pregunta,tipo,critica)
cross join (select id from mt_tipos_activo where codigo='CARGADOR') t;
