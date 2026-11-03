-- =====================================================================
-- BATAB Connect · v5b · La ficha del equipo no muestra datos del contrato
-- Fecha: 2026-11-03
-- Único cambio respecto a v3: 'especificaciones' sale sin la llave 'contrato'
-- (rentas, montos) para que el operador que escanea el QR no la vea.
-- Reversa: volver a aplicar la función de v3 (db/migraciones/v3_connect_reportes_avisos.sql)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.mt_ficha(p_operador uuid, p_qr text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a public.mt_activos%rowtype;
  t public.mt_tipos_activo%rowtype;
  v_aut boolean;
  v_ses record;
  v_mia record;
  v_need boolean;
begin
  select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr) limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
  select * into t from mt_tipos_activo where id = a.tipo_id;

  select exists(
    select 1 from mt_autorizaciones au
    where au.operador_id = p_operador and au.vigente
      and (au.vence_en is null or au.vence_en >= current_date)
      and (au.activo_id = a.id or au.tipo_id = a.tipo_id)
  ) into v_aut;

  select s.id, s.inicio, o.nombre, s.operador_id into v_ses
  from mt_sesiones_uso s join operadores o on o.id = s.operador_id
  where s.activo_id = a.id and s.fin is null and s.actividad = 'operacion' limit 1;

  select s.id, s.activo_id into v_mia from mt_sesiones_uso s where s.operador_id = p_operador and s.fin is null limit 1;

  v_need := not exists(
    select 1 from mt_checklists c
    where c.activo_id = a.id and c.resultado <> 'no_apto'
      and c.fecha >= now() - make_interval(hours => mt_horas_vigencia_checklist())
  );

  return jsonb_build_object(
    'ok', true,
    'activo', jsonb_build_object(
      'id', a.id, 'codigo', a.codigo, 'nombre', a.nombre, 'tipo', t.nombre, 'medidor', t.medidor,
      'marca', a.marca, 'modelo', a.modelo, 'anio', a.anio, 'num_serie', a.num_serie,
      'num_economico', a.num_economico, 'ubicacion', a.ubicacion, 'estado', a.estado,
      'especificaciones', a.especificaciones - 'contrato', 'lectura_actual', a.lectura_actual,
      'lectura_actual_en', a.lectura_actual_en, 'forma_adquisicion', a.forma_adquisicion, 'notas', a.notas),
    'componentes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo', c.codigo, 'nombre', c.nombre, 'modelo', coalesce(p.modelo, c.modelo),
        'num_serie', p.num_serie, 'marca', coalesce(p.marca, c.marca)) order by c.codigo)
      from mt_activos c
      left join mt_pieza_instalaciones pi on pi.activo_id = c.id and pi.retirada_en is null
      left join mt_piezas p on p.id = pi.pieza_id
      where c.padre_id = a.id), '[]'::jsonb),
    'lineas', coalesce((select jsonb_agg(r.linea order by r.linea) from mt_activo_reparto r where r.activo_id = a.id), '[]'::jsonb),
    'lineas_detalle', coalesce((
      select jsonb_agg(jsonb_build_object('linea', r.linea, 'nombre', l.nombre,
               'disponible', coalesce(l.estado, 'operativo') = 'operativo', 'nota', l.notas) order by r.linea)
      from mt_activo_reparto r left join mt_activos l on l.codigo = r.linea and l.nivel = 'linea'
      where r.activo_id = a.id), '[]'::jsonb),
    'reportes_abiertos', coalesce((
      select jsonb_agg(x order by x->>'fecha' desc) from (
        select jsonb_build_object('folio', rp.folio, 'tipo', rp.tipo, 'critico', rp.critico,
               'descripcion', rp.descripcion, 'estado', rp.estado, 'fecha', rp.created_at, 'operador', o.nombre) x
        from mt_reportes rp join operadores o on o.id = rp.operador_id
        where rp.activo_id = a.id and rp.estado in ('abierto','en_revision')
        order by rp.created_at desc limit 10) q), '[]'::jsonb),
    'autorizado', v_aut,
    'sesion_en_equipo', case when v_ses.id is null then null else jsonb_build_object(
        'id', v_ses.id, 'inicio', v_ses.inicio, 'operador', v_ses.nombre, 'es_mia', v_ses.operador_id = p_operador) end,
    'mi_sesion_en_otro_equipo', v_mia.id is not null and v_mia.activo_id <> a.id,
    'requiere_checklist', v_need,
    'checklist', case when v_need then coalesce((
        select jsonb_agg(jsonb_build_object('id', i.id, 'orden', i.orden, 'seccion', i.seccion,
               'pregunta', i.pregunta, 'tipo', i.tipo_respuesta, 'critica', i.critica) order by i.orden)
        from mt_checklist_items i
        where i.tipo_id = a.tipo_id and i.activo
          and i.version = (select max(version) from mt_checklist_items x where x.tipo_id = a.tipo_id and x.activo)
      ), '[]'::jsonb) else '[]'::jsonb end
  );
end $function$;
