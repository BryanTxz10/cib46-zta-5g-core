#!/usr/bin/env bash
# 60-open5gs.sh — despliega Open5GS (chart towards5gs-helm) en 5g-cp/5g-up con
# los values del repo (helm-values/open5gs-values.yaml). Idempotente.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
need helm

VALUES="${BOOTSTRAP_DIR}/../helm-values/open5gs-values.yaml"
[ -f "$VALUES" ] || die "No se encontró ${VALUES}"

helm repo add towards5gs "${TOWARDS5GS_REPO}" >/dev/null 2>&1 || true
helm repo update towards5gs >/dev/null

log "Desplegando Open5GS (chart ${OPEN5GS_CHART} ${OPEN5GS_CHART_VERSION}) en ${NS_CP}..."
helm upgrade --install open5gs "${OPEN5GS_CHART}" \
  --version "${OPEN5GS_CHART_VERSION}" \
  --namespace "${NS_CP}" \
  -f "${VALUES}"

wait_ns_ready "${NS_CP}" 420s
kubectl get pods -n "${NS_CP}"
ok "Open5GS desplegado. Recuerda insertar suscriptores (70-subscribers.sh)."
