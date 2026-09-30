#!/usr/bin/env bash
# lib.sh — utilidades comunes para los scripts de bootstrap.
# Se hace `source` desde cada script. Provee logging, espera de readiness
# idempotente y verificación de prerrequisitos. No ejecuta nada por sí solo.

# Directorio de este archivo, para localizar versions.env y manifests/.
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${BOOTSTRAP_DIR}/versions.env"

# --- Logging ----------------------------------------------------------------
_c_reset='\033[0m'; _c_blue='\033[0;34m'; _c_green='\033[0;32m'
_c_yellow='\033[0;33m'; _c_red='\033[0;31m'
log()  { printf "${_c_blue}[*]${_c_reset} %s\n" "$*"; }
ok()   { printf "${_c_green}[+]${_c_reset} %s\n" "$*"; }
warn() { printf "${_c_yellow}[!]${_c_reset} %s\n" "$*" >&2; }
die()  { printf "${_c_red}[x]${_c_reset} %s\n" "$*" >&2; exit 1; }

# --- Prerrequisitos ----------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "Falta el comando requerido: $1"; }

# Espera a que un deployment (o daemonset) esté disponible. Idempotente.
wait_rollout() {
  local kind="$1" name="$2" ns="$3" timeout="${4:-180s}"
  log "Esperando rollout de ${kind}/${name} en ${ns} (timeout ${timeout})..."
  kubectl -n "$ns" rollout status "$kind/$name" --timeout="$timeout" \
    || die "Rollout de ${kind}/${name} no completó a tiempo"
}

# Espera a que TODOS los pods de un namespace estén Ready. Idempotente.
wait_ns_ready() {
  local ns="$1" timeout="${2:-300s}"
  log "Esperando que todos los pods de ${ns} estén Ready..."
  kubectl -n "$ns" wait --for=condition=Ready pods --all --timeout="$timeout" \
    || warn "Algunos pods de ${ns} no llegaron a Ready (revisa 'kubectl get pods -n ${ns}')"
}

# Aplica un manifiesto solo si difiere (kubectl apply ya es idempotente, esto
# es azúcar para logging uniforme).
apply() { log "kubectl apply -f $*"; kubectl apply -f "$@"; }

# Crea un namespace si no existe.
ensure_ns() {
  local ns="$1"
  kubectl get ns "$ns" >/dev/null 2>&1 && { ok "namespace ${ns} ya existe"; return; }
  kubectl create ns "$ns" && ok "namespace ${ns} creado"
}
