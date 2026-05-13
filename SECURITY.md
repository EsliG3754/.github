# SECURITY — Política de seguridad (Logwell)

## Reportar una vulnerabilidad

**No abras un issue público.**

Reportá directamente a: **bryan.epg3754@gmail.com** con asunto `[SECURITY] <repo>: <título>`.

Incluye:
- Repo afectado y versión.
- Descripción del problema.
- Pasos para reproducir.
- Impacto estimado.
- Sugerencia de fix si tienes una.

Respondemos en < 48 horas. Vulnerabilidades críticas se parchan dentro de 7 días.

## Versiones soportadas

Solo `main` y la última release tagged. Versiones más antiguas no reciben parches.

## Mecanismos activos

- **Secret scanning + push protection** activado en los 4 repos.
- **CodeQL** corre en cada PR a `main`.
- **Dependabot** alertas semanales.
- **npm audit** en CI bloquea PRs con vulnerabilidades HIGH+.
- **Pre-commit hook** revisa secretos con `gitleaks` o `check-secrets.sh`.

## Buenas prácticas para colaboradores

- Nunca commiteés `.env`, `*.pem`, `*.key`, `credentials.json`.
- Usá variables de entorno y referencias `${VAR}` en compose.
- Tokens de prueba: prefijo `test_` y rotación frecuente.
- Si ves un secreto commiteado por accidente: rotá el secret en el servicio originador antes de hacer cualquier `git filter-repo` o `BFG`.
