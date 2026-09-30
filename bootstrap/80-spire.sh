#!/usr/bin/env bash
# 80-spire.sh — despliega SPIRE (server + agent) usando las configuraciones del
# repo (spire-config/*.conf) como ConfigMaps. Idempotente.
#
# Coherente con la documentación del propio SPIRE en el repo: se despliega por
# completitud/trazabilidad (H10/H21); NO ejerce enforcement. Opcional: puedes
# saltar este paso sin afectar las métricas de seguridad (C0-C3 dependen de
# Cilium, no de SPIRE).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

SERVER_CONF="${BOOTSTRAP_DIR}/../spire-config/server.conf"
AGENT_CONF="${BOOTSTRAP_DIR}/../spire-config/agent.conf"
[ -f "$SERVER_CONF" ] && [ -f "$AGENT_CONF" ] || die "Faltan spire-config/*.conf"

log "Creando ConfigMaps de SPIRE desde spire-config/*.conf..."
kubectl -n "${NS_CP}" create configmap spire-server-conf \
  --from-file=server.conf="$SERVER_CONF" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NS_CP}" create configmap spire-agent-conf \
  --from-file=agent.conf="$AGENT_CONF" \
  --dry-run=client -o yaml | kubectl apply -f -

apply "${BOOTSTRAP_DIR}/manifests/spire.yaml"
kubectl -n "${NS_CP}" rollout status statefulset/spire-server --timeout=180s || \
  warn "spire-server no llegó a Ready; no bloquea el experimento (SPIRE no hace enforcement)."
ok "SPIRE desplegado (sin enforcement, por trazabilidad)."
