# QA.md — Estándar de Calidad y Pruebas · Logwell

> Normativo para todos los repos de `ESLIMX`. Si un repo no cumple, es un bug del
> repo. Contexto y roadmap: `LOGWELL_QA_PLATFORM.md`. Deploy/branching: `OPS.md`,
> `BRANCHING.md`.

## 1. Pirámide de tests

```
 E2E regresión   → staging, nocturno + on-demand        (Playwright, tag @regression)
 smoke E2E       → GATE: PR ephemeral + post-deploy + 24/7 (Playwright, tag @smoke)
 integración     → CI con Postgres service               (vitest/jest + Prisma)
 unit            → CI, lógica pura, milisegundos          (vitest / tsx --test)
```

Regla de oro: **un bug que llegó a prod implica un test nuevo** en el nivel más
bajo que lo habría atrapado. No se "arregla y ya".

## 2. Smoke vs regresión

- **`@smoke`** — el camino dorado que si se rompe, el negocio sangra. Pocos,
  rápidos (< 90s toda la suite), deterministas, sagrados. Bloquean el merge y el
  deploy. Ejemplos: login, RFQ/cotización, SSO cross-subdominio, kario handoff,
  alta de ticket.
- **`@regression`** — todo lo demás, exhaustivo: cada botón, validación de form,
  estado de error, paginación, permisos. Corre en staging, no bloquea el deploy
  de prod (corre después / nocturno).

## 3. Tags obligatorios

| Tag | Significado |
|-----|-------------|
| `@smoke` | Entra al gate (`--grep @smoke`). |
| `@regression` | Suite completa. |
| `@critical` | Si falla, página/alerta inmediata (P1). |
| `@<area>` | Dominio: `@auth`, `@rfq`, `@chat`, `@tickets`, `@billing`, … |

Un spec smoke típico: `test('@smoke @rfq crea una cotización válida', …)`.

## 4. Selectores — resiliencia primero

Orden de preferencia (de más a menos robusto):

1. `getByRole('button', { name: 'Enviar' })` — accesible y semántico.
2. `getByLabel('Correo')` / `getByPlaceholder(...)`.
3. `getByTestId('cotizar-submit')` — añadir `data-testid` cuando 1–2 no bastan.

**Prohibido:** seleccionar por clase CSS, por orden del DOM, o por texto que cambia
con copy/i18n. Convención de testid: `data-testid="<area>-<accion|elemento>"`
(kebab-case), ej. `cotizar-submit`, `login-email`, `chat-input`, `nav-cta`.

## 5. Datos sintéticos `__qa__` (entornos reales)

Cuando un test corre contra prod o staging y **crea/muta** datos:

- **Email:** `qa+<slug>-<runId>@logwell.mx` (sub-addressing; siempre enrutable y
  reconocible).
- **Texto libre / nombres / empresa:** prefijo `__qa__` (ej. `__qa__ Acme S.A.`).
- **Teardown obligatorio:** cada spec borra lo que creó en `afterEach`/`afterAll`.
  Nunca dejar basura.
- **Red de seguridad:** un job nocturno purga cualquier registro con marcador
  `__qa__` y antigüedad > 24h. No reemplaza el teardown; lo respalda.
- **Aislamiento por run:** incluir `runId` (ej. `process.env.GITHUB_RUN_ID` o un
  uuid) en el marcador para que runs en paralelo no colisionen.
- **⚠️ Cleanup en DB — NO filtrar por el texto `__qa__` en SQL `LIKE`.** El `_` es
  comodín en `LIKE` (y Prisma `contains` NO lo escapa), así que `notes LIKE
  '%__qa__%'` borra falsos positivos. Para limpiar registros, **scopea por el email
  del creador `qa+...`** (`startsWith: 'qa+'` — sin comodines, seguro) o por una
  columna dedicada `isQa`. El `__qa__` en texto sirve para reconocer a simple vista,
  no como predicado de borrado.

## 6. Modo QA en el backend (seguro contra prod)

Todo endpoint que un smoke pueda golpear contra prod debe respetar un **modo QA**:

- Activación: header `x-logwell-qa: <QA_TOKEN>` **o** payload con marcador `__qa__`.
- Efecto: persiste en la DB normal (para poder asertar el insert), pero **suprime
  efectos colaterales externos**: NO envía correo real, NO dispara webhooks a
  operaciones, NO cobra, NO notifica a humanos. Marca el registro como `isQa=true`.
- `QA_TOKEN` vive en secrets del repo y del runner. **Nunca** en el código ni en
  `.env.example` con valor real.

Sin esto, no se corre el gate contra prod. (Contra `ephemeral`/`staging` es opcional
pero recomendado.)

## 7. Feature flags — deploy ≠ release

- Arranque: flags por env var, leídas por **un único helper** por repo
  (`src/lib/flags.ts`), formato `FLAG_<NOMBRE>=on|off` (default off).
- Toda feature no trivial entra detrás de un flag apagado; se mergea a `main`
  aunque esté incompleta (trunk-based). Se enciende en prod cuando su `@smoke` pasa.
- No leer `process.env.FLAG_*` disperso por el código — siempre vía el helper, para
  poder migrar a un servicio (Unleash/Flagsmith) sin tocar call-sites.

## 8. Migraciones expand/contract (Postgres compartida)

Una sola instancia Postgres sirve `public` + `client_portal` + `noc_dashboard`.
Romper un schema tumba código aún corriendo. **Toda migración riesgosa = 3 deploys:**

1. **Expand** — añadir nullable / tabla / índice `CONCURRENTLY`. Código viejo OK.
2. **Migrate code + backfill** — código nuevo usa lo nuevo; backfill de datos.
3. **Contract** — borrar lo viejo, solo cuando ninguna versión lo referencia.

Prohibido en un paso: `DROP`/`RENAME` de columna en uso, `NOT NULL` sin default
sobre tabla poblada, cambio de tipo incompatible, borrar tabla con FKs vivas. El
backup pre-migrate (`deploy-prod.yml: backup_before_migrate`) es la última red,
no la primera.

## 9. Estructura de archivos por repo

```
playwright.config.ts
tests/e2e/
  _fixtures/
    qa.ts            # marcadores __qa__, runId, base fixtures, modo QA header
    teardown.ts      # helpers de limpieza (borrar registros __qa__)
  smoke/
    *.smoke.spec.ts  # tag @smoke — entran al gate
  regression/
    *.spec.ts        # tag @regression — suite completa (staging)
```

Scripts `package.json` (estándar):

```jsonc
"test:e2e":        "playwright test",
"test:e2e:smoke":  "playwright test --grep @smoke",
"test:e2e:ui":     "playwright test --ui",        // headed, modo 'a mano'
"test:e2e:codegen":"playwright codegen $E2E_BASE_URL"
```

## 10. CI / gate

- **PR:** el CI llama a `e2e-smoke.yml@main` en modo `ephemeral` → build+start la
  app (+Postgres service si aplica) y corre `@smoke` contra localhost. **Required
  check** → un smoke roto bloquea el merge.
- **Post-deploy:** el caller de `deploy-prod.yml` corre `@smoke` (modo `url`) contra
  la URL de prod. Hoy (deploy in-place) **detecta + alerta + facilita rollback**;
  con blue-green (F4) pasa a **preflight** antes del flip de tráfico.
- **24/7 (F4):** cron cada 5 min corre `@smoke` contra prod como synthetic monitoring.

## 11. Qué NO hacer

- No `waitForTimeout` arbitrarios — usar `expect(...).toBeVisible()` con auto-wait.
- No tests que dependen del orden entre sí — cada uno crea y limpia su estado.
- No correr `@regression` destructiva contra prod — eso es solo staging.
- No hardcodear URLs/credenciales — todo por env (`E2E_BASE_URL`, secrets).
- No marcar un test como `@smoke` si tarda > ~15s o es flaky. El gate es sagrado.
