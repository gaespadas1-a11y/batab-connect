-- =====================================================================
-- BATAB Connect · v12 · Check-list de equipos montados junto con el camión
-- Fecha: 2026-11-03
-- Al iniciar un camión, el chofer contesta en el mismo check-list los puntos
-- de la grúa y la plataforma montadas (equipos con padre_id = camión).
-- Cada equipo guarda su propio check-list y sus reportes. Una falla crítica
-- de la grúa la deja NO APTA sin detener el camión.
-- Reversa: volver a aplicar mt_ficha de v5b y mt_iniciar_uso_v2 de v3.
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
  v_hijos uuid[];
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

  -- Equipos montados (grúa, plataforma) que requieren su propio check-list
  select coalesce(array_agg(c.id), '{}') into v_hijos from mt_activos c
  where c.padre_id = a.id and c.nivel = 'equipo' and c.estado = 'operativo'
    and exists (select 1 from mt_checklist_items i where i.tipo_id = c.tipo_id and i.activo)
    and not exists (select 1 from mt_checklists k where k.activo_id = c.id and k.resultado <> 'no_apto'
                    and k.fecha >= now() - make_interval(hours => mt_horas_vigencia_checklist()));

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
    'requiere_checklist', v_need or cardinality(v_hijos) > 0,
    'equipos_montados', coalesce((select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre)) from mt_activos c where c.id = any(v_hijos)), '[]'::jsonb),
    'checklist', coalesce((
      select jsonb_agg(x order by (x->>'grupo'), (x->>'orden')::int) from (
        select jsonb_build_object('id', i.id, 'orden', i.orden, 'seccion', i.seccion, 'pregunta', i.pregunta,
               'tipo', i.tipo_respuesta, 'critica', i.critica, 'grupo', '0', 'equipo', a.codigo) x
        from mt_checklist_items i
        where v_need and i.tipo_id = a.tipo_id and i.activo
          and i.version = (select max(version) from mt_checklist_items z where z.tipo_id = a.tipo_id and z.activo)
        union all
        select jsonb_build_object('id', i.id, 'orden', i.orden, 'seccion', c.nombre || ' · ' || i.seccion, 'pregunta', i.pregunta,
               'tipo', i.tipo_respuesta, 'critica', i.critica, 'grupo', '1' || c.codigo, 'equipo', c.codigo)
        from mt_activos c join mt_checklist_items i on i.tipo_id = c.tipo_id and i.activo
          and i.version = (select max(version) from mt_checklist_items z where z.tipo_id = c.tipo_id and z.activo)
        where c.id = any(v_hijos)
      ) q), '[]'::jsonb)
  );
end $function$;

create or replace function public.mt_iniciar_uso_v2(
  p_operador uuid, p_qr text, p_lectura numeric, p_respuestas jsonb,
  p_lineas text[], p_observaciones text, p_lat numeric, p_lng numeric, p_dispositivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.mt_activos%rowtype;
  t public.mt_tipos_activo%rowtype;
  v_aut boolean;
  v_need boolean;
  v_version int;
  v_falta int;
  v_crit_falla int := 0;
  v_falla int := 0;
  v_res text;
  v_chk uuid;
  v_ses uuid;
  v_cerradas int := 0;
  v_lineas text[];
  v_obs text := nullif(trim(coalesce(p_observaciones, '')), '');
  v_rep uuid[];
  n int;
  hc record;
  v_hijos uuid[];
  v_cver int;
  v_cchk uuid;
  v_cres text;
  v_ccrit int;
  v_cfalla int;
  v_crep uuid[];
  v_hijos_no_apto text[] := '{}';
begin
  select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
  select * into t from mt_tipos_activo where id = a.tipo_id;

  select exists(
    select 1 from mt_autorizaciones au
    where au.operador_id = p_operador and au.vigente
      and (au.vence_en is null or au.vence_en >= current_date)
      and (au.activo_id = a.id or au.tipo_id = a.tipo_id)) into v_aut;
  if not v_aut then
    return jsonb_build_object('ok', false, 'codigo', 'no_autorizado',
      'error', 'No tienes autorización vigente para operar este equipo. Avisa a tu supervisor.');
  end if;
  if a.estado in ('no_apto','en_reparacion','fuera_servicio','baja') then
    return jsonb_build_object('ok', false, 'codigo', 'equipo_detenido',
      'error', 'El equipo está marcado como "' || replace(a.estado, '_', ' ') || '". No se puede operar hasta que mantenimiento lo libere.');
  end if;
  if t.medidor in ('horas','km') and p_lectura is null then
    return jsonb_build_object('ok', false, 'error', 'Captura la lectura del ' || case when t.medidor = 'km' then 'odómetro' else 'horómetro' end || '.');
  end if;
  if p_lectura is not null and a.lectura_actual is not null and p_lectura < a.lectura_actual then
    return jsonb_build_object('ok', false, 'codigo', 'lectura_menor',
      'error', 'La lectura ' || p_lectura || ' es menor a la última registrada (' || a.lectura_actual || '). Revisa el horómetro.');
  end if;

  -- Solo líneas válidas para este equipo y disponibles
  select array_agg(distinct x order by x) into v_lineas
  from unnest(coalesce(p_lineas, '{}')) x
  where exists (select 1 from mt_activo_reparto r where r.activo_id = a.id and r.linea = x)
    and not exists (select 1 from mt_activos l where l.codigo = x and l.nivel = 'linea' and l.estado <> 'operativo');
  if exists (select 1 from mt_activo_reparto r where r.activo_id = a.id) and coalesce(array_length(v_lineas, 1), 0) = 0 then
    return jsonb_build_object('ok', false, 'codigo', 'sin_linea', 'error', 'Elige al menos una línea a la que darás servicio.');
  end if;

  v_need := not exists(select 1 from mt_checklists c where c.activo_id = a.id and c.resultado <> 'no_apto'
                         and c.fecha >= now() - make_interval(hours => mt_horas_vigencia_checklist()));

  -- Equipos montados que requieren check-list: se validan antes de guardar nada
  select coalesce(array_agg(h.id), '{}') into v_hijos from mt_activos h
  where h.padre_id = a.id and h.nivel = 'equipo' and h.estado = 'operativo'
    and exists (select 1 from mt_checklist_items i where i.tipo_id = h.tipo_id and i.activo)
    and not exists (select 1 from mt_checklists k where k.activo_id = h.id and k.resultado <> 'no_apto'
                    and k.fecha >= now() - make_interval(hours => mt_horas_vigencia_checklist()));
  for hc in select h.* from mt_activos h where h.id = any(v_hijos) loop
    select count(*) into v_falta from mt_checklist_items i
    where i.tipo_id = hc.tipo_id and i.activo and i.tipo_respuesta = 'ok_falla'
      and i.version = (select max(version) from mt_checklist_items z where z.tipo_id = hc.tipo_id and z.activo)
      and not exists (select 1 from jsonb_array_elements(coalesce(p_respuestas, '[]'::jsonb)) r
                      where (r->>'item_id')::bigint = i.id and (r->>'ok') is not null);
    if v_falta > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'checklist_incompleto',
        'error', 'Faltan ' || v_falta || ' puntos del check-list de ' || hc.nombre || '.');
    end if;
  end loop;
  v_falta := null;
  if v_need then
    select max(version) into v_version from mt_checklist_items where tipo_id = a.tipo_id and activo;
    if v_version is not null then
      select count(*) into v_falta from mt_checklist_items i
      where i.tipo_id = a.tipo_id and i.activo and i.version = v_version and i.tipo_respuesta = 'ok_falla'
        and not exists (select 1 from jsonb_array_elements(coalesce(p_respuestas, '[]'::jsonb)) r
                        where (r->>'item_id')::bigint = i.id and (r->>'ok') is not null);
      if v_falta > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'checklist_incompleto',
          'error', 'Faltan ' || v_falta || ' puntos del check-list por contestar.');
      end if;

      select count(*) filter (where i.critica), count(*) into v_crit_falla, v_falla
      from jsonb_array_elements(p_respuestas) r join mt_checklist_items i on i.id = (r->>'item_id')::bigint
      where (r->>'ok')::boolean = false and i.tipo_id = a.tipo_id;

      v_res := case when v_crit_falla > 0 then 'no_apto' when v_falla > 0 or v_obs is not null then 'apto_observaciones' else 'apto' end;

      insert into mt_checklists (activo_id, operador_id, version, resultado, lectura, notas)
      values (a.id, p_operador, v_version, v_res, p_lectura, v_obs) returning id into v_chk;

      insert into mt_checklist_respuestas (checklist_id, item_id, ok, valor, comentario)
      select v_chk, (r->>'item_id')::bigint, (r->>'ok')::boolean, r->>'valor', nullif(r->>'comentario', '')
      from jsonb_array_elements(p_respuestas) r
      where exists (select 1 from mt_checklist_items i where i.id = (r->>'item_id')::bigint and i.tipo_id = a.tipo_id);
    end if;
  end if;

  if v_res = 'no_apto' then
    update mt_activos set estado = 'no_apto' where id = a.id;
    if p_lectura is not null then
      insert into mt_lecturas (activo_id, valor, fuente, operador_id) values (a.id, p_lectura, 'operador', p_operador);
    end if;
  else
    update mt_sesiones_uso set fin = now(), cierre_motivo = 'otro_equipo' where operador_id = p_operador and fin is null;
    get diagnostics n = row_count; v_cerradas := v_cerradas + n;
    update mt_sesiones_uso set fin = now(), cierre_motivo = 'otro_operador' where activo_id = a.id and fin is null and actividad = 'operacion';
    get diagnostics n = row_count; v_cerradas := v_cerradas + n;

    insert into mt_sesiones_uso (operador_id, activo_id, actividad, lectura_inicio, linea_atendida, lineas_atendidas, lat, lng, dispositivo)
    values (p_operador, a.id, 'operacion', p_lectura, v_lineas[1], v_lineas, p_lat, p_lng, p_dispositivo)
    returning id into v_ses;
    if v_chk is not null then update mt_checklists set sesion_id = v_ses where id = v_chk; end if;
    if p_lectura is not null and (a.lectura_actual is null or p_lectura >= a.lectura_actual) then
      insert into mt_lecturas (activo_id, valor, fuente, operador_id, sesion_id) values (a.id, p_lectura, 'operador', p_operador, v_ses);
    end if;
  end if;

  -- Reportes: una fila por cada falla del check-list y una por la observación general
  with ins as (
    insert into mt_reportes (activo_id, operador_id, sesion_id, checklist_id, item_id, origen, tipo, critico, puede_operar, descripcion, lineas)
    select a.id, p_operador, v_ses, v_chk, i.id, 'checklist', 'falla', i.critica, not i.critica,
           i.pregunta || coalesce(' — ' || nullif(r->>'comentario', ''), ''), v_lineas
    from jsonb_array_elements(case when v_chk is null then '[]'::jsonb else coalesce(p_respuestas, '[]'::jsonb) end) r
    join mt_checklist_items i on i.id = (r->>'item_id')::bigint and i.tipo_id = a.tipo_id
    where (r->>'ok')::boolean = false
    union all
    select a.id, p_operador, v_ses, v_chk, null, case when v_chk is null then 'operacion' else 'checklist' end,
           'observacion', false, true, v_obs, v_lineas
    where v_obs is not null
    returning id
  ) select array_agg(id) into v_rep from ins;

  -- Check-list de cada equipo montado (grúa, plataforma)
  for hc in select h.* from mt_activos h where h.id = any(v_hijos) loop
    select max(version) into v_cver from mt_checklist_items where tipo_id = hc.tipo_id and activo;
    select count(*) filter (where i.critica), count(*) into v_ccrit, v_cfalla
    from jsonb_array_elements(p_respuestas) r join mt_checklist_items i on i.id = (r->>'item_id')::bigint
    where (r->>'ok')::boolean = false and i.tipo_id = hc.tipo_id;
    v_cres := case when v_ccrit > 0 then 'no_apto' when v_cfalla > 0 then 'apto_observaciones' else 'apto' end;
    insert into mt_checklists (activo_id, operador_id, version, resultado, lectura, notas, sesion_id)
    values (hc.id, p_operador, v_cver, v_cres, null, 'Revisado junto con ' || a.codigo, v_ses) returning id into v_cchk;
    insert into mt_checklist_respuestas (checklist_id, item_id, ok, valor, comentario)
    select v_cchk, (r->>'item_id')::bigint, (r->>'ok')::boolean, r->>'valor', nullif(r->>'comentario', '')
    from jsonb_array_elements(p_respuestas) r
    where exists (select 1 from mt_checklist_items i where i.id = (r->>'item_id')::bigint and i.tipo_id = hc.tipo_id);
    with ins as (
      insert into mt_reportes (activo_id, operador_id, sesion_id, checklist_id, item_id, origen, tipo, critico, puede_operar, descripcion, lineas)
      select hc.id, p_operador, v_ses, v_cchk, i.id, 'checklist', 'falla', i.critica, not i.critica,
             '[' || hc.nombre || '] ' || i.pregunta || coalesce(' — ' || nullif(r->>'comentario', ''), ''), v_lineas
      from jsonb_array_elements(p_respuestas) r
      join mt_checklist_items i on i.id = (r->>'item_id')::bigint and i.tipo_id = hc.tipo_id
      where (r->>'ok')::boolean = false
      returning id
    ) select array_agg(id) into v_crep from ins;
    if v_crep is not null then v_rep := coalesce(v_rep, '{}') || v_crep; end if;
    if v_cres = 'no_apto' then
      update mt_activos set estado = 'no_apto' where id = hc.id;
      v_hijos_no_apto := v_hijos_no_apto || hc.nombre;
    end if;
  end loop;

  if v_res = 'no_apto' then
    return jsonb_build_object('ok', false, 'codigo', 'no_apto', 'checklist_id', v_chk, 'reportes', coalesce(to_jsonb(v_rep), '[]'::jsonb),
      'error', 'El check-list tiene fallas críticas. El equipo queda NO APTO y se avisó a mantenimiento. No lo operes.');
  end if;

  return jsonb_build_object('ok', true, 'sesion_id', v_ses, 'checklist', v_res, 'sesiones_cerradas', v_cerradas,
    'reportes', coalesce(to_jsonb(v_rep), '[]'::jsonb),
    'equipos_no_aptos', to_jsonb(v_hijos_no_apto),
    'mensaje', case when cardinality(v_hijos_no_apto) > 0
                 then 'Sesión iniciada. NO USES: ' || array_to_string(v_hijos_no_apto, ', ') || ' (falla crítica, se avisó a mantenimiento).'
               when v_rep is not null then 'Sesión iniciada. Tus observaciones se enviaron a mantenimiento.' else 'Sesión iniciada.' end);
end $$;
