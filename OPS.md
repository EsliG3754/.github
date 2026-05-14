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

### 4.1 Inventario consolidado

**GitHub Secrets** (a nivel repo, replicados en los 4):

| Secret | Propósito | Cadencia | Próxima rotación |
|---|---|---|---|
| `PROD_SSH_KEY` | Clave SSH para deploy al VPS | **90 días** | _ver Issues "ops: rotación de secrets"_ |
| `PROD_HOST` | IP/hostname del VPS | inmutable | — |
| `PROD_USER` | Usuario SSH para deploy | inmutable | — |
| `GHCR_PULL_USER` | Usuario para `docker login ghcr.io` | inmutable | — |
| `GHCR_PULL_TOKEN` | PAT con `read:packages` para pull | **90 días** | _ver Issues_ |
| `TELEGRAM_BOT_TOKEN` | Bot @logwell_ops_bot | **365 días** | _ver Issues_ |
| `TELEGRAM_CHAT_ID` | Canal "Logwell Deploys" | inmutable | — |

**VPS `/srv/<servicio>/.env`** (no en GitHub):

| Secret | Servicio | Cadencia | Notas |
|---|---|---|---|
| `NEXTAUTH_SECRET` | hubwell_portal, hubwell_react | **180 días** | rotación rota sesiones; coordinar |
| `KARIO_HANDOFF_SECRET` | hubwell_portal + kario (compartido) | **180 días** | DEBE ser el mismo valor en ambos |
| `KAIRO_KEY_WEB`, `_CLIENTS`, `_HUBWELL` | kario emite, callers consumen | **180 días** | rotar ALL al mismo tiempo |
| `KAIRO_ADMIN_KEY` | kario | 180 días | opcional, solo endpoints admin |
| `ANTHROPIC_API_KEY` | kario | **on-incident** | rotar inmediatamente si leak |
| `JWT_SECRET`, `JWT_CLIENT_SECRET` | hubwell_react/api | **180 días** | rotación rota sesiones |
| `RESEND_API_KEY` | hubwell_portal, logwellv2 | **365 días** | desde dashboard Resend |
| `TURNSTILE_SECRET_KEY` | logwellv2, portal | 365 días | Cloudflare Turnstile |
| `BANXICO_TOKEN` | logwellv2 | 365 días | bajo demanda, no leak crítico |

### 4.2 Procedimiento por tipo de secret

#### A. `PROD_SSH_KEY` (zero-downtime)

```bash
# 1. Generar nueva clave (ed25519, recomendado)
ssh-keygen -t ed25519 -f ~/.ssh/logwell_deploy_$(date +%Y%m) -C "logwell-deploy-$(date +%Y%m)" -N ""

# 2. Añadir la NUEVA al VPS (manteniendo la vieja activa)
cat ~/.ssh/logwell_deploy_$(date +%Y%m).pub | ssh user@vps "cat >> ~/.ssh/authorized_keys"

# 3. Actualizar GitHub Secret en los 4 repos
for repo in logwellv2 hubwell_portal hubwell_react Kairo; do
  gh secret set PROD_SSH_KEY --repo ESLIMX/$repo < ~/.ssh/logwell_deploy_$(date +%Y%m)
done

# 4. Disparar workflow_dispatch de deploy en cada repo y verificar success
for repo in logwellv2 hubwell_portal hubwell_react Kairo; do
  gh workflow run deploy-prod.yml --repo ESLIMX/$repo --ref main
done
# Esperar ~5 min y verificar todos verdes en GitHub Actions

# 5. Si los 4 deploys pasaron, eliminar la vieja del VPS
ssh user@vps "sed -i '/<huella-vieja>/d' ~/.ssh/authorized_keys"
ssh user@vps "grep -c '' ~/.ssh/authorized_keys"  # debe coincidir con num claves esperadas
```

#### B. `GHCR_PULL_TOKEN` (zero-downtime)

```bash
# 1. En GitHub web: Settings → Developer settings → Personal access tokens (classic)
#    → Generate new token con scope `read:packages`, expiración 90 días.
#    Nombre: "logwell-ghcr-pull-YYYYMM"
#    Copiar el token (solo se muestra una vez).

NEW_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxx"

# 2. Verificar que funciona contra GHCR
echo "$NEW_TOKEN" | docker login ghcr.io -u <user> --password-stdin

# 3. Actualizar en los 4 repos
for repo in logwellv2 hubwell_portal hubwell_react Kairo; do
  gh secret set GHCR_PULL_TOKEN --repo ESLIMX/$repo --body "$NEW_TOKEN"
done

# 4. Disparar workflow_dispatch en cada repo. Si pasan → revocar el token viejo
#    desde Settings → Developer settings → Personal access tokens → Delete
```

#### C. `KARIO_HANDOFF_SECRET` (afecta handoffs activos)

⚠️ Coordinar con el equipo: rotar este secret invalida prefills firmados existentes (sesiones de chat con quote handoff a la mitad fallarán al completar).

```bash
# 1. Generar nuevo secret (>= 32 chars)
NEW_SECRET=$(openssl rand -base64 48 | tr '/+' '_-' | tr -d '\n=')

# 2. SSH al VPS y actualizar EN AMBOS .env (atómico)
ssh user@vps "
sudo sed -i 's|^KARIO_HANDOFF_SECRET=.*|KARIO_HANDOFF_SECRET=$NEW_SECRET|' /srv/kario/.env /srv/hubwell-portal/.env
sudo grep '^KARIO_HANDOFF_SECRET=' /srv/kario/.env /srv/hubwell-portal/.env
"

# 3. Reiniciar AMBOS containers con rollback (sin rebuild)
gh workflow run rollback.yml --repo ESLIMX/Kairo -f version=latest
gh workflow run rollback.yml --repo ESLIMX/hubwell_portal -f version=latest
```

#### D. `KAIRO_KEY_*` (3 keys, rotar ALL al mismo tiempo)

```bash
# 1. Generar las 3 nuevas
KEY_WEB=$(openssl rand -base64 48 | tr '/+' '_-' | tr -d '\n=')
KEY_CLIENTS=$(openssl rand -base64 48 | tr '/+' '_-' | tr -d '\n=')
KEY_HUBWELL=$(openssl rand -base64 48 | tr '/+' '_-' | tr -d '\n=')

# 2. Actualizar en kario (emite) Y en cada caller (consume)
ssh user@vps "
# kario tiene las 3
sudo sed -i 's|^KAIRO_KEY_WEB=.*|KAIRO_KEY_WEB=$KEY_WEB|' /srv/kario/.env
sudo sed -i 's|^KAIRO_KEY_CLIENTS=.*|KAIRO_KEY_CLIENTS=$KEY_CLIENTS|' /srv/kario/.env
sudo sed -i 's|^KAIRO_KEY_HUBWELL=.*|KAIRO_KEY_HUBWELL=$KEY_HUBWELL|' /srv/kario/.env

# logwellv2 usa KAIRO_KEY_WEB (con nombre KARIO_KEY)
sudo sed -i 's|^KARIO_KEY=.*|KARIO_KEY=$KEY_WEB|' /srv/logwellv2/.env

# portal usa KAIRO_KEY_CLIENTS (con nombre KARIO_KEY)
sudo sed -i 's|^KARIO_KEY=.*|KARIO_KEY=$KEY_CLIENTS|' /srv/hubwell-portal/.env

# hubwell_react usa KAIRO_KEY_HUBWELL — buscar en su .env el nombre exacto
"

# 3. Rollback (reinicio) de los 4 containers para tomar nuevas keys
for repo in Kairo logwellv2 hubwell_portal hubwell_react; do
  gh workflow run rollback.yml --repo ESLIMX/$repo -f version=latest
done
```

#### E. `ANTHROPIC_API_KEY` (incident-driven)

```bash
# Solo en respuesta a un incidente o sospecha de leak.
# 1. Console Anthropic → API Keys → Generate new (revocar la vieja primero si es seguro)
# 2. SSH:
ssh user@vps "sudo sed -i 's|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=<nueva>|' /srv/kario/.env"
# 3. Rollback kario para tomar la nueva
gh workflow run rollback.yml --repo ESLIMX/Kairo -f version=latest
# 4. Revocar la vieja en console Anthropic
```

### 4.3 Recordatorio automático

Workflow [`rotation-reminder.yml`](.github/workflows/rotation-reminder.yml) corre cron `0 9 1 */3 *` (1 enero/abril/julio/octubre 9am UTC) y abre un **Issue** en `ESLIMX/.github` con checklist de rotación trimestral. Las rotaciones se consideran completas al cerrar el issue.

### 4.4 Reglas de oro

1. Rotar UN secret a la vez (no cambiar 3 simultáneamente fuera de KAIRO_KEY_*).
2. Validar con un deploy de prueba ANTES de revocar el viejo.
3. Documentar la rotación en el issue (fecha, quién, breve resumen).
4. Si rotaste por incidente, hacer post-mortem en 48 horas.

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
