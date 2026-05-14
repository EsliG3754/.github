## Qué cambia

<!-- 1-3 líneas. El "qué" lo ve cualquiera en el diff; aquí importa el "por qué". -->

## Tipo de cambio

- [ ] feat (nueva funcionalidad)
- [ ] fix (bug fix)
- [ ] perf (mejora de performance)
- [ ] refactor (sin cambio funcional)
- [ ] docs / test / build / ci / chore
- [ ] BREAKING CHANGE (requiere coordinación)

## Issue / contexto

<!-- Closes #N, Refs #N, link a Linear, o nada -->

## Checklist técnico

- [ ] `npm run lint` pasa (o equivalente del repo)
- [ ] `npx tsc --noEmit` pasa
- [ ] `npm test` pasa
- [ ] `npm run build` pasa
- [ ] No hay secretos hardcodeados
- [ ] Si toca DB: migración aditiva, reglas two-phase respetadas
- [ ] Si toca API pública: rate limit + RBAC + AuditEvent donde aplique
- [ ] Si toca UI: probado en mobile + desktop

## Riesgos / rollback

<!-- ¿Qué puede romperse? ¿Cómo se revierte? -->

## Screenshots / video

<!-- Si aplica (cambios visuales) -->

---

📚 [BRANCHING](https://github.com/ESLIMX/.github/blob/main/BRANCHING.md) · [COMMITS](https://github.com/ESLIMX/.github/blob/main/COMMITS.md) · [OPS](https://github.com/ESLIMX/.github/blob/main/OPS.md)
