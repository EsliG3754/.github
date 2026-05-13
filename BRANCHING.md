# BRANCHING — Convención de ramas (Logwell)

Aplica a los 4 repos del ecosistema:

| Repo | Dominio | Servicio |
|---|---|---|
| `logwellv2` | logwell.mx | Sitio público |
| `hubwell_portal` | clientes.logwell.mx | Portal de clientes |
| `hubwell_react` | hub.logwell.mx | Plataforma interna |
| `kario` | kairo.logwell.mx | IA en 3 niveles |

---

## Modelo: Trunk-Based

**`main`** es la única rama larga. Refleja exactamente lo que está en producción.

Toda otra rama es **efímera** y se borra automáticamente al mergear.

---

## Tipos de rama permitidos

| Prefijo | Propósito | Vida típica | Ejemplo |
|---|---|---|---|
| `feature/<slug>` | Trabajo nuevo (feature, refactor, mejora) | 1–7 días | `feature/trusted-devices-recovery` |
| `hotfix/<slug>` | Parche urgente a producción | < 24 horas | `hotfix/session-401-loop` |
| `release/<version>` | Solo si necesitas estabilizar antes de promover (raro) | < 2 días | `release/v1.40.0` |
| `dependabot/*` | Generadas por Dependabot. No tocar manualmente. | automático | — |

**Reglas:**
- `<slug>` = kebab-case, máx 40 caracteres, descriptivo de la entrega.
- Una rama = una feature. Si la rama crece > 2 semanas o > 800 líneas, **divídela** (Stacked PRs).
- Nunca trabajar directo en `main`. Nunca `git push --force` a `main`.

---

## Branches PROHIBIDAS

Estas no pueden volver a aparecer en ningún repo:

- ❌ `development`, `develop`, `dev` — usa `main` + feature branches
- ❌ `wip/*`, `snapshot/*`, `tmp/*`, `test/*` — usa stash, draft PR, o feature branch
- ❌ `worktree-*`, `worktree/*` — los worktrees viven solo en local, nunca push
- ❌ Branches personales `<usuario>/algo` — todo trabajo es del repo, no personal

---

## Flujo estándar (paso a paso)

```bash
# 1. Partir SIEMPRE de main fresco
git checkout main
git pull --ff-only origin main

# 2. Crear rama
git checkout -b feature/mi-cambio

# 3. Trabajar y commitear (Conventional Commits, ver COMMITS.md)
git commit -m "feat(scope): qué cambia"

# 4. Subir y abrir PR
git push -u origin feature/mi-cambio
gh pr create --fill --base main

# 5. CI verde + revisión + squash merge desde GitHub UI
# 6. La rama se borra sola (auto-delete activado)
```

---

## Reglas de Pull Request

| Regla | Aplica | Notas |
|---|---|---|
| Required PR | ✅ | No merges directos a main |
| Required CI checks | ✅ | lint + typecheck + tests + npm audit + build |
| Required code review | ⚠️ | Auto-aprobación del owner permitida en repos solo-él |
| Squash merge únicamente | ✅ | Sin merge commits, sin rebase merge |
| Auto-delete branch on merge | ✅ | La rama remota desaparece al mergear |
| No force-push a main | ✅ | Nunca |
| No bypass de protected branches | ✅ | Ni siquiera el owner |

---

## Tags y Releases

- Tag inmutable por release: `vYYYY.MM.DD-N` (N = release del día, base 1).
  - Ejemplo: `v2026.05.13-1`, `v2026.05.13-2`
- Tag adicional por imagen Docker: `YYYYMMDD-HHMMSS-shortSHA` (ya lo emiten los workflows).
- Releases generados automáticamente por **Release Please** desde Conventional Commits.

---

## ¿Cuándo usar `hotfix/*`?

Solo si:
1. Hay un bug **crítico** en producción (caída, pérdida de datos, vuln de seguridad).
2. No puedes esperar al ciclo normal de feature.

Flujo:
```bash
git checkout main && git pull
git checkout -b hotfix/<slug>
# fix mínimo
gh pr create --fill --label hotfix --base main
# Merge prioritario, deploy automático, post-mortem en issue
```

---

## ¿Cuándo dividir una rama? (Stacked PRs)

Si tu feature crece a:
- > 800 líneas modificadas, o
- > 15 archivos en el diff, o
- > 7 días de trabajo

**Divídela** en sub-features con dependencias:

```
feature/auth-base       (PR #1, base de main)
feature/auth-recovery   (PR #2, base de feature/auth-base)
feature/auth-mfa        (PR #3, base de feature/auth-recovery)
```

Mergea en orden. Cada PR pequeño = revisión más fácil = menos riesgo.

---

## Antipatrones (NO HACER)

| Antipatrón | Por qué es malo | Qué hacer en su lugar |
|---|---|---|
| Branch viva > 2 semanas | Drift contra main, conflictos crecientes | Mergear/cerrar o dividir |
| `git pull` sin `--ff-only` | Merges accidentales | Configurar `pull.ff = only` global |
| `git rebase main` en una rama compartida | Reescribe historia que otros tienen | Solo rebase ramas propias no pusheadas |
| Commit "WIP" pushed a main | Rompe el bisect y los releases | Squash siempre |
| Eliminar rama remota sin verificar merge | Pérdida de trabajo | Usar `git branch -d` (no `-D`) o tag de archivo |

---

## Si hay que recuperar una rama borrada

Antes de borrar cualquier rama dudosa, crear tag de archivo:
```bash
git tag archive/feature/x origin/feature/x
git push origin archive/feature/x
git push origin --delete feature/x
```

Para recuperar:
```bash
git checkout -b feature/x archive/feature/x
```

Los tags `archive/*` se conservan indefinidamente (cero costo).
