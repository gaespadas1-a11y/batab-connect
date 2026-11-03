-- =====================================================================
-- BATAB Connect · v7 · Check-list diario de grúas y autorización de prueba
-- Fecha: 2026-11-03
-- Fuente: manual Palfinger PK18500/PK23500 (español), cap. 2.1-1 "Inspección
-- visual y comprobación funcional diarias", cap. 3 (gatos) y tabla 6.1-3.
-- Aplica al tipo GRUA (PK23500, PK15002 e IMT 34/235: misma inspección básica).
-- Las grúas no siempre tienen horómetro: el medidor del tipo GRUA pasa a
-- 'ninguno' y las horas de uso salen del tiempo de cada sesión.
-- Reversa: db/reversa/v7_reversa.sql
-- =====================================================================
update public.mt_tipos_activo set medidor = 'ninguno' where codigo = 'GRUA';

insert into public.mt_checklist_items (tipo_id, version, orden, seccion, pregunta, tipo_respuesta, critica, fuente)
select t.id, 1, v.orden, v.seccion, v.pregunta, 'ok_falla', v.critica, 'Manual Palfinger PK18500/23500 cap. 2.1-1, 3 y 6.1-3'
from (values
  (1, 'Sistema hidráulico', 'Sin fugas de aceite en racores, mangueras, tubos y cilindros', true),
  (2, 'Sistema hidráulico', 'Tuercas y tornillos del sistema hidráulico completos y sin daño', true),
  (3, 'Estructura', 'Sin fisuras ni deformaciones en base, columna, brazos y extensiones', true),
  (4, 'Estructura', 'Bulones y seguros de las extensiones colocados', true),
  (5, 'Estructura', 'Fijación de la grúa al chasis sin holgura ni tornillos flojos', false),
  (6, 'Elevación', 'Gancho y su seguro sin daño; cable o cabrestante en buen estado', true),
  (7, 'Gatos', 'Gatos y sus extensiones sin daño; salen y entran correctamente', true),
  (8, 'Mandos', 'Mandos suaves y regresan solos a la posición neutral', true),
  (9, 'Seguridad', 'Parada de emergencia funciona', true),
  (10, 'Seguridad', 'Seguro de sobrecarga (limitador / botón OLP) funciona', true),
  (11, 'Seguridad', 'Placa de cargas y calcomanías de seguridad legibles', false),
  (12, 'Zona de trabajo', 'Terreno firme para apoyar gatos y sin líneas eléctricas cerca', true),
  (13, 'Aceite', 'Nivel de aceite hidráulico correcto (en posición de transporte)', false)
) as v(orden, seccion, pregunta, critica)
cross join (select id from public.mt_tipos_activo where codigo = 'GRUA') t
on conflict (tipo_id, version, orden) do nothing;

-- Autorización de prueba: GEHO en la grúa PK23500
insert into public.mt_autorizaciones (operador_id, activo_id, capacitado_en, autorizado_por, notas)
select o.id, a.id, current_date, d.id, 'Autorización de prueba solicitada por el Director'
from public.operadores o
cross join (select id from public.mt_activos where codigo = 'BAT-EM-GRU03') a
cross join (select operador_id as id from public.mt_perfiles where 'director' = any(roles) limit 1) d
where o.codigo = 'GEHO'
  and not exists (select 1 from public.mt_autorizaciones x where x.operador_id = o.id and x.activo_id = a.id);
