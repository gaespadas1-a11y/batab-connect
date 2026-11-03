-- BATAB Connect · REVERSA de v5
delete from public.mt_activos where codigo in ('BAT-EM-GRU01','BAT-EM-GRU02');
delete from public.mt_activos where codigo in ('BAT-EM-CAM01','BAT-EM-CAM02','BAT-EM-TRC01');
delete from public.mt_tipos_activo where codigo in ('CAMION','TRACTOCAMION','GRUA');
-- Datos de contrato cargados aparte (cargador):
update public.mt_activos set costo_adquisicion = null, fecha_alta = null,
  especificaciones = especificaciones - 'contrato'
where codigo = 'BAT-MP-CFR02';
alter table public.mt_activos drop constraint if exists mt_activos_forma_adquisicion_check;
alter table public.mt_activos add constraint mt_activos_forma_adquisicion_check
  check (forma_adquisicion in ('compra','arrendamiento_financiero','fabricacion_propia','otro'));
