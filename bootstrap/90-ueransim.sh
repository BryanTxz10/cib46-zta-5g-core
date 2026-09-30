#!/usr/bin/env bash
# 90-ueransim.sh — despliega gNB y UE de UERANSIM montando las configs del repo
# (ueransim-config/*.yaml) como ConfigMaps. Idempotente. Debe correr después de
# que Open5GS y el suscriptor estén listos.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

GNB="${BOOTSTRAP_DIR}/../ueransim-config/gnb.yaml"
UE="${BOOTSTRAP_DIR}/../ueransim-config/ue.yaml"
[ -f "$GNB" ] && [ -f "$UE" ] || die "Faltan ueransim-config/{gnb,ue}.yaml"

ensure_ns "${NS_RAN}"
log "Creando ConfigMaps de UERANSIM desde ueransim-config/..."
kubectl -n "${NS_RAN}" create configmap ueransim-gnb-conf \
  --from-file=gnb.yaml="$GNB" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NS_RAN}" create configmap ueransim-ue-conf \
  --from-file=ue.yaml="$UE" --dry-run=client -o yaml | kubectl apply -f -

apply "${BOOTSTRAP_DIR}/manifests/ueransim.yaml"
wait_rollout deployment ueransim-gnb "${NS_RAN}" 180s
wait_rollout deployment ueransim-ues "${NS_RAN}" 180s

log "Verificando registro del UE (uesimtun0 debe existir)..."
UE_POD="$(kubectl -n ${NS_RAN} get pod -l app.kubernetes.io/name=ueransim-ue -o jsonpath='{.items[0].metadata.name}')"
sleep 10
kubectl -n "${NS_RAN}" exec "$UE_POD" -- ip a show uesimtun0 2>/dev/null && \
  ok "UE registrado (uesimtun0 presente)." || \
  warn "uesimtun0 aún no aparece; revisa logs del UE y que el suscriptor esté insertado."
