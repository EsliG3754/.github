# COMMITS — Convención de mensajes (Logwell)

Usamos **Conventional Commits** estricto. Es la base para:
- Generar CHANGELOG automático con Release Please.
- Decidir bump semver (patch / minor / major) automático.
- Búsqueda y filtrado consistente del historial.
- Linting automático en commit-msg hook.

---

## Formato

```
<type>(<scope>): <subject>

<body opcional, líneas de máx 100 chars>

<footer opcional: BREAKING CHANGE / Refs / Closes>
```

### Tipos válidos

| Type | Cuándo | Bump semver |
|---|---|---|
| `feat` | Nueva funcionalidad para el usuario | minor |
| `fix` | Bug fix | patch |
| `perf` | Mejora de performance sin cambiar API | patch |
| `refactor` | Cambio de código que no añade feature ni fix | (no bump) |
| `docs` | Solo documentación | (no bump) |
| `test` | Añadir/modificar tests | (no bump) |
| `build` | Build system, dependencias | (no bump) |
| `ci` | Cambios a CI/CD | (no bump) |
| `chore` | Tarea sin impacto en código de producción | (no bump) |
| `style` | Formato (no afecta lógica) | (no bump) |
| `revert` | Revertir commit previo | depende |

### Scopes recomendados (por repo)

**logwellv2**: `web`, `seo`, `i18n`, `forms`, `chat`, `infra`

**hubwell_portal**: `auth`, `portal`, `dashboard`, `documents`, `cotizaciones`, `comunicados`, `ui`, `infra`

**hubwell_react**: `web`, `api`, `auth`, `operations`, `compliance`, `documents`, `tickets`, `clients`, `admin`, `kairo`, `whatsapp`, `infra`

**kario**: `core`, `tools`, `web`, `clients`, `hub`, `infra`

---

## BREAKING CHANGES

Trigger major bump. Dos formas válidas:

### Opción 1: `!` después del type/scope

```
feat(api)!: cambia formato del endpoint /tickets

El campo `id` ahora es UUID en lugar de int.
```

### Opción 2: footer `BREAKING CHANGE:`

```
feat(api): nuevo formato de tickets

BREAKING CHANGE: el campo `id` ahora es UUID en lugar de int.
Clientes deben actualizar el parser.
```

---

## Ejemplos buenos

```
feat(auth): añadir trusted devices con OTP por SMS

Implementa ADR-005. Usa Twilio para SMS, fallback a email.
TTL de 90 días por device. Auditoría completa en AuditEvent.

Closes #142
```

```
fix(documents): corrige race condition en upload concurrente

El usuario podía subir el mismo archivo dos veces si daba doble click.
Añade lock optimista en el state local + idempotency key en API.

Refs incident-2026-05-08
```

```
perf(api): cachea queries de catalog (TTL 5 min, invalidación por evento)
```

```
refactor(operations): extrae folio generator a service compartido
```

```
chore(deps): bump next from 16.2.5 to 16.2.6
```

---

## Ejemplos malos (NO HACER)

```
❌ fix bugs                           # sin scope, sin contexto
❌ WIP                                # nunca commitear WIP
❌ asdf                               # mensaje basura
❌ feat: stuff                        # vago
❌ Updated 3 files                    # describe el qué, no el por qué
❌ fix portal/page.tsx                # describe path, no intención
❌ FIX(AUTH): ALGO                    # mayúsculas, parece grito
❌ feat(auth): added trusted devices  # past tense (usar imperativo)
```

---

## Imperativo, presente, español

- ✅ "añadir trusted devices"
- ❌ "añadido trusted devices"
- ❌ "añadiendo trusted devices"

Test mental: "Si aplico este commit, va a `<subject>`".
- ✅ "Si aplico este commit, va a `añadir trusted devices`" — tiene sentido.
- ❌ "Si aplico este commit, va a `añadido trusted devices`" — no.

---

## Multi-commit en un PR

Está bien tener varios commits durante el desarrollo. Al mergear con **squash**, el commit final usa el título del PR — asegurate de que el título del PR siga la convención:

```
PR title: feat(portal): selector multi-empresa con cookie firmada
↓ squash merge ↓
Commit en main: feat(portal): selector multi-empresa con cookie firmada (#42)
```

---

## Linting automático

`commitlint` corre en pre-commit hook (vía `husky` o `simple-git-hooks`):

```bash
# Si rechaza tu commit, lee el error y arregla el mensaje:
echo "feat(auth): añadir MFA" | npx commitlint
```

Configuración en `.commitlintrc.json` (heredado del repo `.github`).

---

## Releases automáticas

**Release Please** corre en cada push a `main` y:
1. Lee los commits desde el último release.
2. Calcula el bump semver según types.
3. Genera/actualiza CHANGELOG.md.
4. Abre un PR titulado "chore(release): vX.Y.Z".
5. Al mergear ese PR → tag + GitHub Release automáticos.

Por eso es vital que los mensajes sean correctos. Un `feat(...)` por error en lo que era un `fix(...)` causa un minor bump innecesario.
