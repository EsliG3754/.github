# CONTRIBUTING — Cómo contribuir (Logwell)

Lee primero:
- [BRANCHING.md](./BRANCHING.md) — convención de ramas
- [COMMITS.md](./COMMITS.md) — convención de commits
- [OPS.md](./OPS.md) — runbook operativo

---

## Setup local

```bash
git clone git@github.com:ESLIMX/<repo>.git
cd <repo>
nvm use         # respeta .nvmrc del repo
npm install     # o pnpm install si el repo lo usa
cp .env.example .env  # rellenar
npm run dev
```

---

## Antes de abrir PR — checklist

- [ ] Branch parte de `main` fresco
- [ ] Commits siguen [COMMITS.md](./COMMITS.md)
- [ ] `npm run lint` pasa
- [ ] `npx tsc --noEmit` pasa
- [ ] `npm test` pasa
- [ ] `npm run build` pasa
- [ ] No hay secretos hardcodeados (`scripts/check-secrets.sh` si existe)
- [ ] Si toca DB: migración aditiva con [reglas two-phase](./OPS.md#3-migraciones-de-db-prisma)
- [ ] Si toca UI: probado en mobile + desktop
- [ ] Si toca API pública: rate limit + RBAC + AuditEvent donde aplique

---

## Ciclo de PR

1. Push tu rama: `git push -u origin feature/<slug>`.
2. `gh pr create --fill --base main` (o desde GitHub UI).
3. CI debe pasar. Si falla, lee el log y arregla.
4. Pedí review (o auto-aprobá si el repo lo permite).
5. **Squash merge** (no merge commit, no rebase merge).
6. La rama se borra sola al mergear.

---

## Si bloquean tu PR

| Bloqueo | Qué hacer |
|---|---|
| CI falla | Reproduce local con el mismo comando. No `--no-verify`. |
| Review pide cambios | Hacelos en commits nuevos, no fuerce-push. |
| Conflictos con main | `git rebase main` (solo si tu rama no es compartida). |
| Branch protection no deja mergear | Verifica required status checks + reviewers. |

---

## Flags peligrosos (NO USAR salvo orden directa del owner)

- `--no-verify` (saltar pre-commit hooks) → si el hook molesta, arreglar el hook
- `--force` / `--force-with-lease` en `main` → NUNCA
- `git rebase -i` en commits ya pusheados a una rama compartida
- `git reset --hard` sin tag de respaldo

---

## Reportar bugs / proponer features

- **Bug**: `gh issue create --template bug_report.yml`
- **Feature**: `gh issue create --template feature_request.yml`

Incluye: contexto, pasos para reproducir, comportamiento esperado vs real, screenshots si aplica.

---

## Hotfix urgente

```bash
git checkout main && git pull
git checkout -b hotfix/<slug>
# fix mínimo, commit, push
gh pr create --fill --label hotfix --base main
# Mergear en cuanto CI pase
```

Después: post-mortem en issue dentro de 48 horas.

---

## Code review — qué busco

- ¿Resuelve el problema del título?
- ¿Sin código muerto / comentarios obsoletos / console.logs?
- ¿Sin secretos en el diff?
- ¿Tests para los caminos felices y al menos un edge case?
- ¿Migraciones DB son aditivas (two-phase)?
- ¿Errores manejados con contexto (no `try { } catch (e) { }` vacío)?
- ¿Performance razonable (N+1 queries, loads innecesarios, etc.)?
- ¿Accesibilidad (alt, aria, keyboard nav) si toca UI?

---

## Estructura del repo

Cada repo tiene:
- `CLAUDE.md` — instrucciones para Claude Code
- `AGENTS.md` — agentes y scripts disponibles
- `DEPLOY.md` — particularidades del deploy de ese repo (lo general en OPS.md)
- `.github/` — workflows, templates, CODEOWNERS

---

## Gracias por contribuir 🚀
