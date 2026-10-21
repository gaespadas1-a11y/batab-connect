# BATAB Connect

Plataforma de activos y mantenimiento de Bloques y Agregados de Tabasco.
Un solo acceso (mismo código y PIN que la app de producción) para operar equipos,
llenar el check-list diario, registrar horas efectivas y, en siguientes fases,
órdenes de trabajo, almacén, combustible y costos.

## Cómo está armado

| Parte | Dónde vive | Qué hace |
|---|---|---|
| `index.html` | GitHub Pages | Pantallas para el teléfono |
| `supabase/functions/connect-api` | Supabase (función `connect-api`) | Única puerta a la base de datos; valida PIN y emite acceso de 12 h |
| `db/migraciones` | Supabase (tablas `mt_*`, funciones `mt_*`) | Estructura y reglas |
| `db/reversa` | — | Scripts para deshacer cada versión |
| `db/respaldos` | — | Estado antes y después de cada cambio |

El navegador nunca lee ni escribe tablas directamente: todo pasa por `connect-api`,
y las reglas (autorización, check-list, lecturas) se aplican en la base de datos.

## Versiones

| Versión | Fecha | Cambio | Deshacer |
|---|---|---|---|
| v1.0-tablas | 2026-10-20 | 12 tablas `mt_*` y datos de prueba del Komatsu WA320-6 | `db/reversa/v1_reversa.sql` |
| v2 funciones | 2026-10-20 | `mt_ficha`, `mt_iniciar_uso`, `mt_cerrar_uso` | `db/reversa/v2_reversa.sql` |
| app 0.1.0 | 2026-10-20 | Entrar con PIN, escanear QR, ficha, check-list, iniciar y terminar uso | Revertir el merge en GitHub |
| app 0.1.1 | 2026-10-20 | Ícono oficial (engrane con QR) y opción de agregar a la pantalla de inicio | Revertir el merge en GitHub |

## QR de los equipos

Cada placa lleva la dirección `https://gaespadas1-a11y.github.io/batab-connect/?q=<qr_token>`.
Se puede escanear con la cámara normal del teléfono o desde el lector de la app.
Si la placa se daña, se escribe el número económico.
