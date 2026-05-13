# Logwell

Plataforma de servicios profesionales operada por Logwell. 4 productos, una sola filosofía: simplificar lo complejo.

| Servicio | Dominio | Repo |
|---|---|---|
| Sitio público | [logwell.mx](https://logwell.mx) | [logwellv2](https://github.com/EsliG3754/logwellv2) |
| Portal de clientes | [clientes.logwell.mx](https://clientes.logwell.mx) | [hubwell_portal](https://github.com/EsliG3754/hubwell_portal) |
| Plataforma interna | [hub.logwell.mx](https://hub.logwell.mx) | [hubwell_react](https://github.com/EsliG3754/hubwell_react) |
| IA orquestadora | kairo.logwell.mx | [kario](https://github.com/EsliG3754/kario) |

## Documentación

- [BRANCHING.md](BRANCHING.md) — convención de ramas
- [COMMITS.md](COMMITS.md) — convención de commits (Conventional Commits)
- [CONTRIBUTING.md](CONTRIBUTING.md) — cómo contribuir
- [OPS.md](OPS.md) — runbook operativo
- [SECURITY.md](SECURITY.md) — política de seguridad

## Stack común

- Next.js 16 + Prisma + Postgres
- Docker Compose en VPS, Caddy como reverse proxy
- GitHub Actions para CI/CD, GHCR para imágenes
- TypeScript estricto en todos los repos
