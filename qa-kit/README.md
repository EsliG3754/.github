# qa-kit — instalar E2E en un repo Logwell

Plantilla drop-in para dejar un repo con smoke E2E listo para el gate. Estándar
normativo: `../QA.md`. Workflow reutilizable: `../.github/workflows/e2e-smoke.yml`.

## Instalar

```bash
# 1. Dependencia
npm i -D @playwright/test
npx playwright install --with-deps chromium

# 2. Copiar la plantilla al repo
cp qa-kit/playwright.config.ts .
mkdir -p tests/e2e/smoke tests/e2e/regression
cp -r qa-kit/tests/e2e/_fixtures tests/e2e/
cp qa-kit/tests/e2e/smoke/example.smoke.spec.ts tests/e2e/smoke/

# 3. Scripts en package.json (sección 9 de QA.md)
#   "test:e2e": "playwright test"
#   "test:e2e:smoke": "playwright test --grep @smoke"
#   "test:e2e:ui": "playwright test --ui"
#   "test:e2e:codegen": "playwright codegen $E2E_BASE_URL"

# 4. Callers de CI: copiar e2e-pr.yml (gate ephemeral en PR) y
#    e2e-prod.yml (modo url post-deploy + cron) a .github/workflows/
#    y ajustar image/puerto/url. Ver ejemplos en el repo logwellv2.
```

## Variables de entorno que leen los specs

| Var | Para |
|-----|------|
| `E2E_BASE_URL` | URL objetivo. Default `http://127.0.0.1:<puerto>` en local/ephemeral. |
| `E2E_QA_TOKEN` | Token de modo QA (header `x-logwell-qa`) contra prod/staging. |
| `E2E_TARGET` | `ephemeral` \| `url`. Los specs evitan crear datos reales si no hay token. |
| `E2E_RUN_ID` | ID del run para aislar datos `__qa__` entre ejecuciones paralelas. |

## Reglas (resumen — completo en QA.md)

- Tag `@smoke` = entra al gate. Pocos, rápidos, deterministas.
- Selectores por rol/label/testid. Nunca por CSS.
- Datos creados llevan marcador `__qa__` y se limpian en teardown.
