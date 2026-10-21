# Estado base antes de BATAB Connect — 2026-10-20

Proyecto Supabase: szrcmvlgxxpmvgrfmxak
Última migración existente: 20260819173513 normalizar_nulls_alertas_produccion
Tablas en schema public: 59

Conteos de control (no deben cambiar):
- operadores: 10
- reportes_paro: 438
- produccion_logs: 374
- netsuite_trace_log: 3515

Columnas originales de `operadores` (no se modifican ni se borran):
id, codigo, pin_hash, nombre, rol, email, celular, activo, created_at, created_by,
last_login, requiere_cambio_pin, pin_cambiado_en, sesion_expira_en,
ultima_validacion_facial, oferta_enrolamiento_pospuesta_hasta

Seguridad: `operadores` tiene RLS activo sin políticas (solo accesible por funciones
con service role). Las tablas mt_ siguen el mismo patrón.
