# Verificación después de v1 — 2026-10-20

Conteos de control (iguales al estado base):
- operadores: 10 ✔
- reportes_paro: 438 ✔
- produccion_logs: 374 ✔
- netsuite_trace_log: 3515 ✔
- Columnas nuevas de operadores sin datos: 0 filas con valor ✔

Tablas en public: 59 → 71 (+12 tablas mt_) ✔

Datos de prueba cargados:
- 14 tipos de activo, 11 activos (planta, 3 líneas, grupo móvil, CFR02 y 5 componentes)
- 28 preguntas del check-list del cargador (OMM TEN00456-01)
- 1 autorización (OPERADOR PRUEBA → cargador), costo de ejemplo $100/h
- QR del CFR02: token b3ea6ade4362f1ab

Asesor de seguridad: las 12 tablas mt_ solo aparecen como "RLS sin políticas" (nivel INFO),
igual que operadores: es intencional, solo se accede por funciones del servidor.
Las funciones nuevas tienen search_path fijo (no aparecen en advertencias).
