# OPS — Runbook único de Logwell

Documento operativo para los 4 servicios:

| Servicio | Repo | Dominio | VPS path |
|---|---|---|---|
| Sitio público | `logwellv2` | logwell.mx | `/srv/logwellv2/` |
| Portal clientes | `hubwell_portal` | clientes.logwell.mx | `/srv/hubwell-portal/` |
| Hub interno | `hubwell_react` | hub.logwell.mx | `/srv/hubwell/` |
| IA orquestadora | `kario` | kairo.logwell.mx (interno) | `/srv/kario/` |

Todos comparten la red docker `hubwell_network` (external) en el VPS principal. Caddy del stack `hubwell_react` reverse-proxiea los 4 dominios.

---

## 1. Deploy a producción

### 1.1 Flujo automático (lo normal)

1. Mergear PR a `main` (squash, vía GitHub UI).
2. El workflow `deploy-prod.yml` se dispara automáticamente.
3. Build de imagen → push a `ghcr.io/ESLIMX/<servicio>:<tag>`.
4. SSH al VPS → `docker compose pull && up -d`.
5. Healthcheck. Si falla → el contenedor previo sigue corriendo (rolling).
6. Notificación a Telegram/Slack con resultado.

**Tag inmutable**: `YYYYMMDD-HHMMSS-shortSHA`. Ejemplo: `20260513-184500-abc1234`.

### 1.2 Deploy manual (forzar redeploy sin cambios)

```bash
gh workflow run deploy-prod.yml --repo ESLIMX/<repo> -f ref=main
```

### 1.3 ¿Qué se preserva entre deploys?

| Elemento | ¿Se preserva? | Dónde vive |
|---|---|---|
| `.env` | ✅ SIEMPRE | `/srv/<servicio>/.env` (no commiteado) |
| Volúmenes Postgres (`.pg-data`) | ✅ | volumen docker |
| Documentos cliente | ✅ | volumen docker o S3/B2 |
| Logs históricos | ✅ | volumen docker, rotación 30 días |
| Imágenes Docker previas | ✅ últimas 5 | GHCR + cache local |

**Nunca** se sobreescriben estos elementos en deploy. Si alguna vez ves "se borró el .env tras un deploy" → es bug crítico, abrir incidente.

---

## 2. Rollback

### 2.1 Rollback rápido (mismo día)

Si el deploy actual rompe producción:

```bash
gh workflow run rollback.yml --repo ESLIMX/<repo> -f version=<tag-previo>
```

`<tag-previo>` se obtiene del listado de imágenes en GHCR:
```bash
gh api /user/packages/container/<servicio>/versions --jq '.[].metadata.container.tags[]' | head -10
```

O usa `version=latest` para volver a la última estable conocida.

### 2.2 Rollback de schema DB

**No se hace rollback de migraciones aplicadas**. Si una migración rompió:

1. Ejecutar la migración inversa (debe existir según convención two-phase).
2. Si no existe migración inversa: restaurar desde backup `pg_dump` automático pre-deploy.
3. Backups viven en `/srv/backups/<servicio>/<timestamp>.sql.gz` (últimos 30 días).

### 2.3 Rollback de incidente mayor (> 1 hora caído)

1. Switchear DNS a servidor espejo (cuando esté operativo, ver §6).
2. Diagnosticar root cause en principal.
3. Post-mortem en 48 horas.

---

## 3. Migraciones de DB (Prisma)

### 3.1 Reglas de oro

1. **Two-phase deploys**: nunca DROP/RENAME en una sola release.
   - Release N: añadir columna nueva (nullable) + escribir a ambas.
   - Release N+1: backfill + dejar de escribir a vieja.
   - Release N+2: marcar vieja deprecated.
   - Release N+3 (≥ 1 semana): drop vieja.
2. **Migraciones aditivas siempre primero**: añadir antes de quitar.
3. **Backup automático antes de cada `migrate deploy`** (pg_dump → /srv/backups/).
4. **Validar en staging antes de prod** (cuando esté operativo).

### 3.2 Flujo de migración

```bash
# Local
npx prisma migrate dev --name <nombre>
git add prisma/migrations/
git commit -m "feat(db): <qué cambia>"
# Push, abrir PR, merge

# En CI/CD del deploy:
# 1. pg_dump backup
# 2. npx prisma migrate deploy
# 3. Si falla: restore desde backup, abortar deploy
```

### 3.3 Comandos manuales (emergencia)

```bash
# Conectarse al VPS y al contenedor
ssh user@vps
docker compose -f /srv/<servicio>/compose.prod.yml exec api sh

# Ver estado
npx prisma migrate status

# Aplicar pendientes (si CI no pudo)
npx prisma migrate deploy

# Reset (¡PELIGRO! solo en staging/dev)
npx prisma migrate reset
```

---

## 4. Secrets y rotación

### 4.1 Inventario de secrets

| Secret | Dónde | Rotación | Última |
|---|---|---|---|
| `PROD_SSH_KEY` | GitHub Secrets (org) | 90 días | TBD |
| `PROD_HOST` | GitHub Secrets | inmutable | — |
| `PROD_USER` | GitHub Secrets | inmutable | — |
| `GHCR_PULL_USER` | GitHub Secrets | 90 días | TBD |
| `GHCR_PULL_TOKEN` | GitHub Secrets | 90 días | TBD |
| `NEXTAUTH_SECRET` | VPS .env por servicio | 180 días | TBD |
| `KARIO_KEY_*` | VPS .env (kario emite, otros consumen) | 180 días | TBD |
| `RESEND_API_KEY` | VPS .env | 365 días | TBD |
| `TURNSTILE_SECRET_KEY` | VPS .env | 365 días | TBD |
| `BANXICO_TOKEN` | VPS .env | 365 días | TBD |

### 4.2 Procedimiento de rotación de `PROD_SSH_KEY`

```bash
# 1. Generar nueva clave
ssh-keygen -t ed25519 -f ~/.ssh/logwell_deploy_new -C "logwell-deploy-$(date +%Y%m%d)"

# 2. Añadir al VPS (mantener la vieja activa todavía)
ssh-copy-id -i ~/.ssh/logwell_deploy_new.pub user@vps

# 3. Actualizar GitHub Secret en cada repo
for repo in logwellv2 hubwell_portal hubwell_react kario; do
  gh secret set PROD_SSH_KEY --repo ESLIMX/$repo < ~/.ssh/logwell_deploy_new
done

# 4. Disparar un deploy de prueba en cada repo. Si pasa → eliminar la vieja.
ssh user@vps "sed -i '/<huella-vieja>/d' ~/.ssh/authorized_keys"
```

### 4.3 Rotación de `GHCR_PULL_TOKEN`

```bash
# 1. Crear nuevo PAT con scope read:packages, expiración 90 días
gh auth refresh -s read:packages

# 2. Generar token con gh + actualizar en los 4 repos (en paralelo)
NEW_TOKEN=$(gh api user/packages-token ...)  # TBD comando exacto
for repo in logwellv2 hubwell_portal hubwell_react kario; do
  gh secret set GHCR_PULL_TOKEN --repo ESLIMX/$repo --body "$NEW_TOKEN"
done

# 3. Validar pulleando manualmente en el VPS
ssh user@vps "echo $NEW_TOKEN | docker login ghcr.io -u <user> --password-stdin"
```

Ver §10 para automatización con `/schedule`.

---

## 5. Healthchecks y monitoreo

### 5.1 Healthcheck por servicio

Definido en `compose.prod.yml`:
```yaml
healthcheck:
  test: ["CMD", "curl", "-fsS", "http://127.0.0.1:<port>/api/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 20s
```

Si falla → docker marca unhealthy → no recibe tráfico vía Caddy.

### 5.2 Endpoints de salud

| Servicio | Endpoint público | Endpoint interno |
|---|---|---|
| logwellv2 | https://logwell.mx/api/health | http://web:3003/api/health |
| portal | https://clientes.logwell.mx/api/health | http://portal:3000/api/health |
| react | https://hub.logwell.mx/api/health | http://api:3001/api/health |
| kario | (interno) | http://kario:3004/health |

### 5.3 Monitoreo externo

- **Better Stack** (o Healthchecks.io) pingea los 4 endpoints públicos cada 1 min.
- Alerta en SMS + Telegram + email si baja > 90 segundos.
- Dashboard en https://hub.logwell.mx/admin/ops (cuando esté operativo).

---

## 6. Servidor espejo (staging → hot-standby)

### 6.1 Fase actual: STAGING

El espejo recibe deploys automáticos de `main` con datos sintéticos para validar antes de promover a prod.

| Servicio | Dominio staging |
|---|---|
| logwellv2 | https://stg.logwell.mx |
| portal | https://stg.clientes.logwell.mx |
| react | https://stg.hub.logwell.mx |
| kario | (interno staging) |

### 6.2 Flujo de promoción staging → prod

1. Push a `main` → deploy a staging automático.
2. Validar manual (smoke tests, casos críticos).
3. `gh workflow run promote-to-prod.yml -f tag=<version>` → reusa el mismo tag GHCR sin rebuild.

### 6.3 Migración futura a hot-standby

Cuando los pipelines lleven 2-4 semanas estables:
- Replicar Postgres en caliente (logical replication o streaming).
- Caddy con failover automático.
- Switchover manual con `failover.sh`.
- Staging migra a tercer entorno o se elimina.

---

## 7. Incidentes (runbook abreviado)

### 7.1 Sitio caído

1. ¿Caddy responde? Si no → revisar VPS (uptime, RAM, disco).
2. ¿Healthcheck del contenedor pasa? `docker compose ps` en `/srv/<svc>/`.
3. ¿Logs muestran error reciente? `docker compose logs --tail=200 <svc>`.
4. ¿Último deploy es el problema? → §2 rollback.

### 7.2 DB lenta o caída

1. `docker stats` ver consumo.
2. `pg_stat_activity` para queries lentas.
3. Si DB caída → restart contenedor; si datos corruptos → §3.3 + restore.

### 7.3 Deploy en loop o atascado

1. Concurrency group debe prevenir duplicados (ver `concurrency:` en workflow).
2. Cancel manual: `gh run cancel <run-id> --repo ESLIMX/<repo>`.
3. Si el contenedor nuevo no arranca → docker compose up -d con imagen previa.

---

## 8. Dashboard visual

### 8.1 Vista cross-repo

URL: https://hub.logwell.mx/admin/ops

Muestra por servicio:
- Última versión desplegada (tag GHCR + commit SHA + autor + fecha).
- Estado healthcheck (verde/amarillo/rojo).
- Último workflow run (success/failure/in-progress).
- Uptime últimas 24h.

Refresh automático cada 30 segundos. Implementación: página estática consumiendo GitHub API + Better Stack API.

### 8.2 Vistas nativas de GitHub

- **Environments**: https://github.com/ESLIMX/<repo>/deployments
- **Actions**: https://github.com/ESLIMX/<repo>/actions
- **Releases**: https://github.com/ESLIMX/<repo>/releases

---

## 9. Notificaciones

Cada deploy postea a Telegram bot `@logwell_ops_bot` (canal privado):

```
🚀 Deploy <servicio> → prod
Versión: 20260513-184500-abc1234
Commit: feat(scope): mensaje
Autor: @ESLIMX
Estado: ✅ success (2m 14s)
Run: https://github.com/ESLIMX/<repo>/actions/runs/<id>
```

Si falla → `❌ failed` + link al run + mention.

---

## 10. Tareas programadas

Configuradas con `/schedule`:

| Tarea | Cron | Acción |
|---|---|---|
| Rotación PROD_SSH_KEY | `0 9 1 */3 *` (1 enero/abril/julio/octubre 9am) | Ejecutar §4.2 |
| Rotación GHCR_PULL_TOKEN | `0 9 1 */3 *` (igual) | Ejecutar §4.3 |
| Reporte semanal de deploys | `0 9 * * 1` (cada lunes 9am) | Resumen Telegram |
| Limpieza de branches mergeadas en remoto | `0 9 * * 1` | Auto-delete (debe estar activo en branch protection) |
| Limpieza de imágenes GHCR > 60 días | `0 3 * * 0` (domingos 3am) | `gh api DELETE /packages/...` |

---

## 11. Cuándo escalar

- DB > 80% disco → migrar a Postgres con más almacenamiento.
- > 5 incidentes/mes → revisar capacity planning.
- > 100 PRs/mes en un solo repo → considerar dividir el repo.
- Tiempo de deploy > 10 min → optimizar build (cache layers, multi-stage).

---

## 12. Contactos y accesos

| Rol | Persona | Contacto |
|---|---|---|
| Owner / DevOps | Eslí (Bryan) | bryan.epg3754@gmail.com |
| GitHub org | ESLIMX | https://github.com/ESLIMX |

---

**Última actualización**: 2026-05-13. Este documento vive en `ESLIMX/.github/OPS.md`. PRs para mantenerlo al día son bienvenidos.
