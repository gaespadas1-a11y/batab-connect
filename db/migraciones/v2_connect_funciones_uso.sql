-- =====================================================================
-- BATAB Connect · v2 · Funciones de uso diario (reglas del servidor)
-- Fecha: 2026-10-20
-- Solo AGREGA 3 funciones. Solo las puede ejecutar el servidor (service_role);
-- el navegador no puede llamarlas directamente.
-- Reversa: db/reversa/v2_reversa.sql
-- =====================================================================

-- Horas que "dura" un check-list: si el equipo tuvo check-list en este lapso,
-- el siguiente operador no lo repite. Ajustable cuando se definan turnos.
create or replace function public.mt_horas_vigencia_checklist() returns int
language sql immutable as $$ select 10 $$;

-- ---------------------------------------------------------------------
-- FICHA: lo que ve el operador al escanear el QR
-- ---------------------------------------------------------------------
create or replace function public.mt_ficha(p_operador uuid, p_qr text)
returns jsonb language plpgsql security definer set search_path = public as $$
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
      'especificaciones', a.especificaciones, 'lectura_actual', a.lectura_actual,
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
end $$;

-- ---------------------------------------------------------------------
-- INICIAR USO: valida autorización, check-list, lectura; abre la sesión
-- p_respuestas: [{"item_id":1,"ok":true,"valor":null,"comentario":null}, ...]
-- ---------------------------------------------------------------------
create or replace function public.mt_iniciar_uso(
  p_operador uuid, p_qr text, p_lectura numeric, p_respuestas jsonb,
  p_linea text, p_lat numeric, p_lng numeric, p_dispositivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.mt_activos%rowtype;
  t public.mt_tipos_activo%rowtype;
  v_aut boolean;
  v_need boolean;
  v_version int;
  v_falta int;
  v_crit_falla int;
  v_falla int;
  v_res text;
  v_chk uuid;
  v_ses uuid;
  v_cerradas int := 0;
  n int;
begin
  select * into a from mt_activos where qr_token = p_qr or codigo = upper(p_qr) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Código QR no reconocido'); end if;
  select * into t from mt_tipos_activo where id = a.tipo_id;

  -- Regla 1: solo opera quien está autorizado
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

  -- Regla 2: check-list obligatorio si no hay uno vigente
  v_need := not exists(select 1 from mt_checklists c where c.activo_id = a.id and c.resultado <> 'no_apto'
                         and c.fecha >= now() - make_interval(hours => mt_horas_vigencia_checklist()));
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
      where (r->>'ok')::boolean = false;

      v_res := case when v_crit_falla > 0 then 'no_apto' when v_falla > 0 then 'apto_observaciones' else 'apto' end;

      insert into mt_checklists (activo_id, operador_id, version, resultado, lectura)
      values (a.id, p_operador, v_version, v_res, p_lectura) returning id into v_chk;

      insert into mt_checklist_respuestas (checklist_id, item_id, ok, valor, comentario)
      select v_chk, (r->>'item_id')::bigint, (r->>'ok')::boolean, r->>'valor', nullif(r->>'comentario', '')
      from jsonb_array_elements(p_respuestas) r
      where exists (select 1 from mt_checklist_items i where i.id = (r->>'item_id')::bigint and i.tipo_id = a.tipo_id);

      if v_res = 'no_apto' then
        update mt_activos set estado = 'no_apto' where id = a.id;
        if p_lectura is not null then
          insert into mt_lecturas (activo_id, valor, fuente, operador_id) values (a.id, p_lectura, 'operador', p_operador);
        end if;
        return jsonb_build_object('ok', false, 'codigo', 'no_apto', 'checklist_id', v_chk,
          'error', 'El check-list tiene fallas críticas. El equipo queda NO APTO y se avisará a mantenimiento. No lo operes.');
      end if;
    end if;
  end if;

  -- Reglas 3 y 4: una sesión abierta por persona y una de operación por equipo
  update mt_sesiones_uso set fin = now(), cierre_motivo = 'otro_equipo'
   where operador_id = p_operador and fin is null;
  get diagnostics n = row_count; v_cerradas := v_cerradas + n;
  update mt_sesiones_uso set fin = now(), cierre_motivo = 'otro_operador'
   where activo_id = a.id and fin is null and actividad = 'operacion';
  get diagnostics n = row_count; v_cerradas := v_cerradas + n;

  insert into mt_sesiones_uso (operador_id, activo_id, actividad, lectura_inicio, linea_atendida, lat, lng, dispositivo)
  values (p_operador, a.id, 'operacion', p_lectura, nullif(p_linea, ''), p_lat, p_lng, p_dispositivo)
  returning id into v_ses;

  if v_chk is not null then update mt_checklists set sesion_id = v_ses where id = v_chk; end if;

  if p_lectura is not null and (a.lectura_actual is null or p_lectura >= a.lectura_actual) then
    insert into mt_lecturas (activo_id, valor, fuente, operador_id, sesion_id) values (a.id, p_lectura, 'operador', p_operador, v_ses);
  end if;

  return jsonb_build_object('ok', true, 'sesion_id', v_ses, 'checklist', v_res, 'sesiones_cerradas', v_cerradas,
    'mensaje', case when v_res = 'apto_observaciones' then 'Sesión iniciada. El check-list tuvo observaciones; se avisará a mantenimiento.'
                    else 'Sesión iniciada.' end);
end $$;

-- ---------------------------------------------------------------------
-- CERRAR USO: cierra la sesión abierta del operador
-- ---------------------------------------------------------------------
create or replace function public.mt_cerrar_uso(p_operador uuid, p_lectura numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s public.mt_sesiones_uso%rowtype;
  a public.mt_activos%rowtype;
  t public.mt_tipos_activo%rowtype;
  v_costo numeric;
  v_horas numeric;
begin
  select * into s from mt_sesiones_uso where operador_id = p_operador and fin is null for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'No tienes una sesión abierta.'); end if;
  select * into a from mt_activos where id = s.activo_id for update;
  select * into t from mt_tipos_activo where id = a.tipo_id;

  if t.medidor in ('horas','km') and p_lectura is null then
    return jsonb_build_object('ok', false, 'error', 'Captura la lectura final del ' || case when t.medidor = 'km' then 'odómetro' else 'horómetro' end || '.');
  end if;
  if p_lectura is not null and a.lectura_actual is not null and p_lectura < a.lectura_actual then
    return jsonb_build_object('ok', false, 'codigo', 'lectura_menor',
      'error', 'La lectura ' || p_lectura || ' es menor a la última registrada (' || a.lectura_actual || ').');
  end if;

  update mt_sesiones_uso set fin = now(), lectura_fin = p_lectura, cierre_motivo = 'manual' where id = s.id
  returning horas into v_horas;

  if p_lectura is not null then
    insert into mt_lecturas (activo_id, valor, fuente, operador_id, sesion_id) values (a.id, p_lectura, 'operador', p_operador, s.id);
  end if;

  -- Regla 6: costo = horas × costo vigente de la persona a la fecha de inicio
  select c.costo_hora into v_costo from mt_colaborador_costos c
   where c.operador_id = p_operador and c.vigente_desde <= s.inicio::date
   order by c.vigente_desde desc limit 1;

  return jsonb_build_object('ok', true, 'sesion_id', s.id, 'equipo', a.codigo,
    'horas', round(v_horas, 2),
    'horas_horometro', case when p_lectura is not null and s.lectura_inicio is not null then p_lectura - s.lectura_inicio end,
    'costo_mano_obra', case when v_costo is not null then round(v_horas * v_costo, 2) end);
end $$;

-- Solo el servidor puede ejecutarlas
revoke all on function public.mt_ficha(uuid, text) from public, anon, authenticated;
revoke all on function public.mt_iniciar_uso(uuid, text, numeric, jsonb, text, numeric, numeric, text) from public, anon, authenticated;
revoke all on function public.mt_cerrar_uso(uuid, numeric) from public, anon, authenticated;
grant execute on function public.mt_ficha(uuid, text) to service_role;
grant execute on function public.mt_iniciar_uso(uuid, text, numeric, jsonb, text, numeric, numeric, text) to service_role;
grant execute on function public.mt_cerrar_uso(uuid, numeric) to service_role;
