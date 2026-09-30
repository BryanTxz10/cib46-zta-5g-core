#!/usr/bin/env bash
# 30-multus.sh — instala Multus CNI (para la segunda interfaz del plano N2,
# red 10.10.0.0/24 que usan gnb.yaml/ue.yaml) y crea el
# NetworkAttachmentDefinition. Cierra la brecha RM-25 (el NAD no estaba en el
# repo). Idempotente.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

log "Instalando Multus ${MULTUS_VERSION} (thick daemonset)..."
kubectl apply -f "https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/${MULTUS_VERSION}/deployments/multus-daemonset-thick.yml"
kubectl -n kube-system rollout status ds/kube-multus-ds --timeout=180s || \
  warn "Multus DS aún no Ready; continúa y verifica luego."

# NetworkAttachmentDefinition para N2 (macvlan sobre la subred del testbed).
# AJUSTA 'master' a la interfaz física/veth de tu VM worker que da a la red N2.
log "Creando NetworkAttachmentDefinition n2-net en ${NS_RAN} y ${NS_CP}..."
for ns in "${NS_RAN}" "${NS_CP}"; do
  ensure_ns "$ns"
  cat <<EOF | kubectl apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: n2-net
  namespace: ${ns}
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "eth1",
      "mode": "bridge",
      "ipam": {
        "type": "static"
      }
    }
EOF
done
ok "Multus + NAD n2-net listos. (AJUSTA 'master: eth1' a tu interfaz N2 real.)"
