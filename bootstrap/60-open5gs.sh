#!/usr/bin/env bash
# 60-open5gs.sh — despliega Open5GS (chart de Gradiant) en dos releases:
# el UPF en 5g-up (open5gs-upf-values.yaml) y el plano de control en 5g-cp
# (open5gs-values.yaml). Idempotente.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
need helm

VALUES="${BOOTSTRAP_DIR}/../helm-values/open5gs-values.yaml"
VALUES_UP="${BOOTSTRAP_DIR}/../helm-values/open5gs-upf-values.yaml"
[ -f "$VALUES" ] || die "No se encontró ${VALUES}"
[ -f "$VALUES_UP" ] || die "No se encontró ${VALUES_UP}"

# Arquitectura v3: dos releases del mismo chart. El UPF (plano de usuario) va
# primero y en su propio namespace; el SMF resuelve su Service N4 al arrancar.
log "Desplegando el UPF (release ${OPEN5GS_UP_RELEASE}) en ${NS_UP}..."
helm upgrade --install "${OPEN5GS_UP_RELEASE}" "${OPEN5GS_CHART}" \
  --version "${OPEN5GS_CHART_VERSION}" \
  --namespace "${NS_UP}" \
  -f "${VALUES_UP}" \
  --wait --timeout 10m

log "Desplegando el plano de control (chart ${OPEN5GS_CHART} ${OPEN5GS_CHART_VERSION}) en ${NS_CP}..."
helm upgrade --install "${OPEN5GS_RELEASE}" "${OPEN5GS_CHART}" \
  --version "${OPEN5GS_CHART_VERSION}" \
  --namespace "${NS_CP}" \
  -f "${VALUES}" \
  --wait --timeout 15m

# Service headless N2 (SCTP pod->pod; ver manifests/amf-n2-headless.yaml).
apply "${BOOTSTRAP_DIR}/manifests/amf-n2-headless.yaml"

wait_ns_ready "${NS_CP}" 420s
kubectl get pods -n "${NS_CP}"
kubectl get pods -n "${NS_UP}"
ok "Open5GS desplegado (el suscriptor lo inserta ${OPEN5GS_RELEASE}-populate)."
