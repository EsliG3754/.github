#!/usr/bin/env bash
#
# quality-gate.sh — gate de calidad PORTABLE y canónico (qa-kit, org ESLIMX).
#
# El MISMO gate corre en los tres lugares, sin divergencia:
#   - local, antes de pushear   →  .husky/pre-commit (fast) y pre-push (full)
#   - local, a mano             →  `npm run gate`  (alias a --mode=full)
#   - en CI, antes de liberar   →  job `gate` del deploy (--mode=full --json)
#
# Uso:
#   scripts/quality-gate.sh --mode=fast              # typecheck (~rápido, pre-commit)
#   scripts/quality-gate.sh --mode=full              # lint + typecheck + test (pre-push / CI)
#   scripts/quality-gate.sh --mode=hotfix-security   # full + secret-scan (parche urgente)
#   scripts/quality-gate.sh --mode=full --json       # + reporte .quality-gate-report.json (NOC)
#
# Corre SOLO los gates cuyo npm script exista (lint / typecheck / test). Si no hay
# script `typecheck` pero hay tsconfig.json, cae a `npx tsc --noEmit`. Un repo puede
# definir un script `gate:prepare` (p.ej. `prisma generate`) que se corre antes de todo.
# Detecta el package manager por lockfile (pnpm/yarn/npm). No asume monorepo.
#
# Exit:  0 todos los gates pasaron · 1 algún gate falló · 2 error de uso/setup.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
APP_NAME="$(node -e "process.stdout.write((require('./package.json').name)||'repo')" 2>/dev/null || echo repo)"

MODE=""
JSON_OUT=false
for arg in "$@"; do
  case "$arg" in
    --mode=*) MODE="${arg#--mode=}" ;;
    --json)   JSON_OUT=true ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "✗ argumento desconocido: $arg" >&2; exit 2 ;;
  esac
done
case "$MODE" in
  fast|full|hotfix-security) ;;
  *) echo "✗ --mode requerido: fast | full | hotfix-security" >&2; exit 2 ;;
esac

# Package manager por lockfile.
if   [ -f pnpm-lock.yaml ]; then PM=pnpm
elif [ -f yarn.lock ];      then PM=yarn
else PM=npm
fi

has_script() { node -e "process.exit((require('./package.json').scripts||{})['$1']?0:1)" 2>/dev/null; }
pm_cmd() { case "$PM" in pnpm) echo "pnpm run $1" ;; yarn) echo "yarn $1" ;; *) echo "npm run $1" ;; esac; }

declare -a R_GATE R_STATUS R_DUR
FAILED=0
record() { R_GATE+=("$1"); R_STATUS+=("$2"); R_DUR+=("$3"); }

run_gate() { # run_gate <nombre> <command-string>
  local name="$1" cmd="$2" start end
  start=$(date +%s)
  if bash -c "$cmd" > "/tmp/qg-${name}.log" 2>&1; then
    end=$(date +%s); echo "  ✓ ${name} — $((end-start))s"; record "$name" pass "$((end-start))"
  else
    end=$(date +%s); echo "  ✗ ${name} — $((end-start))s — ver /tmp/qg-${name}.log"
    tail -n 25 "/tmp/qg-${name}.log" | sed 's/^/    /'
    record "$name" fail "$((end-start))"; FAILED=$((FAILED+1))
  fi
}

START_TOTAL=$(date +%s)
echo "═══ quality-gate ($MODE) · ${APP_NAME} · pm=${PM} ═══"

# Preparación opcional (p.ej. prisma generate) declarada por el repo.
if has_script "gate:prepare"; then
  echo "→ gate:prepare…"
  if ! bash -c "$(pm_cmd 'gate:prepare')" > /tmp/qg-prepare.log 2>&1; then
    echo "✗ gate:prepare falló — ver /tmp/qg-prepare.log"
    tail -n 25 /tmp/qg-prepare.log | sed 's/^/    /'
    exit 1
  fi
fi

# lint — solo full / hotfix-security.
if [ "$MODE" != "fast" ] && has_script lint; then
  run_gate lint "$(pm_cmd lint)"
fi

# typecheck — en todos los modos (es el corazón del fast).
if has_script typecheck; then
  run_gate typecheck "$(pm_cmd typecheck)"
elif [ -f tsconfig.json ]; then
  run_gate typecheck "npx --no-install tsc --noEmit || npx tsc --noEmit"
fi

# test — solo full / hotfix-security.
if [ "$MODE" != "fast" ] && has_script test; then
  run_gate test "$(pm_cmd test)"
fi

# secret-scan — solo hotfix-security (reemplazo de GHAS al bajar a Free).
if [ "$MODE" = "hotfix-security" ]; then
  if command -v gitleaks >/dev/null 2>&1; then
    run_gate secret-scan "gitleaks detect --no-banner --redact --exit-code 1"
  elif [ -f scripts/check-secrets.sh ]; then
    run_gate secret-scan "bash scripts/check-secrets.sh"
  else
    echo "  ⚠ secret-scan omitido (sin gitleaks ni scripts/check-secrets.sh)"
  fi
fi

END_TOTAL=$(date +%s)
TOTAL=$((END_TOTAL - START_TOTAL))

echo "═══════════════════════════════════════"
if [ "$FAILED" -eq 0 ]; then
  echo "✓ quality-gate ($MODE): TODOS los gates pasaron — ${TOTAL}s"
else
  echo "✗ quality-gate ($MODE): ${FAILED} gate(s) fallaron — ${TOTAL}s"
fi

# Reporte JSON (mismo esquema que el de hubwell_react; consumible por el NOC).
if [ "$JSON_OUT" = true ]; then
  REPORT=".quality-gate-report.json"
  {
    echo "{"
    echo "  \"app\": \"${APP_NAME}\","
    echo "  \"mode\": \"${MODE}\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"durationSeconds\": ${TOTAL},"
    echo "  \"failed\": ${FAILED},"
    echo "  \"gates\": ["
    for i in "${!R_GATE[@]}"; do
      sep=","; [ "$i" -eq "$((${#R_GATE[@]} - 1))" ] && sep=""
      echo "    {\"app\":\"${APP_NAME}\",\"gate\":\"${R_GATE[$i]}\",\"status\":\"${R_STATUS[$i]}\",\"durationSeconds\":${R_DUR[$i]}}${sep}"
    done
    echo "  ]"
    echo "}"
  } > "$REPORT"
  echo "→ reporte JSON: ${REPORT}"
fi

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
