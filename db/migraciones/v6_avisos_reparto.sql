-- =====================================================================
-- BATAB Connect · v6 · Avisos separados para producción y reparto
-- Fecha: 2026-11-03
-- Los camiones, grúas y plataforma avisan a logística (reparto); el cargador
-- y las líneas siguen avisando al supervisor de producción. El taller recibe todo.
-- Reversa: db/reversa/v6_reversa.sql
-- =====================================================================
alter table public.mt_activos add column if not exists area_aviso text not null default 'produccion'
  check (area_aviso in ('produccion','reparto'));
alter table public.mt_avisos_destinos add column if not exists area_aviso text not null default 'produccion'
  check (area_aviso in ('produccion','reparto'));

update public.mt_activos set area_aviso = 'reparto' where codigo like 'BAT-EM-%';

insert into public.mt_avisos_destinos (rol, linea, nombre, email, telefono, ambito, area_aviso, notas) values
  ('area', null, 'Erick Rafael Pérez Valencia', 'sales4@batab.mx', null, 'real', 'reparto',
   'Supervisor de logística y distribución de planta (Coordinador de Logísticas y de Inventarios, NetSuite 114). Teléfono con WhatsApp cargado aparte.'),
  ('area', null, 'Supervisor de reparto (prueba)', 'ceo3@batab.mx', null, 'prueba', 'reparto',
   'Recibe lo que recibiría el supervisor de logística');
