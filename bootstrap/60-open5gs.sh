#!/usr/bin/env bash
# 60-open5gs.sh — despliega Open5GS (chart towards5gs-helm) en 5g-cp/5g-up con
# los values del repo (helm-values/open5gs-values.yaml). Idempotente.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
need helm

VALUES="${BOOTSTRAP_DIR}/../helm-values/open5gs-values.yaml"
[ -f "$VALUES" ] || die "No se encontró ${VALUES}"

log "Desplegando Open5GS (chart ${OPEN5GS_CHART} ${OPEN5GS_CHART_VERSION}) en ${NS_CP}..."
helm upgrade --install "${OPEN5GS_RELEASE}" "${OPEN5GS_CHART}" \
  --version "${OPEN5GS_CHART_VERSION}" \
  --namespace "${NS_CP}" \
  -f "${VALUES}" \
  --wait --timeout 15m

# Service headless N2 (SCTP pod->pod; ver manifests/amf-n2-headless.yaml).
apply "${BOOTSTRAP_DIR}/manifests/amf-n2-headless.yaml"

wait_ns_ready "${NS_CP}" 420s
kubectl get pods -n "${NS_CP}"
ok "Open5GS desplegado (el suscriptor lo inserta ${OPEN5GS_RELEASE}-populate)."
