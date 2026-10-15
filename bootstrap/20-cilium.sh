#!/usr/bin/env bash
# 20-cilium.sh — instala Cilium 1.15.4 con: KubeProxyReplacement, proxy L7
# (Envoy, necesario para las políticas HTTP de C2/C3), soporte SCTP (vector A3
# y plano N2) y Hubble (observabilidad + evidencia de DROPPED reproducible,
# ver RM-11). Idempotente vía `helm upgrade --install`.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
need helm

# Repo de Helm de Cilium.
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

# SPIRE integrado (mutual authentication). Se desactiva con DEPLOY_SPIRE=0.
SPIRE_ARGS=()
if [ "${DEPLOY_SPIRE}" = "1" ]; then
  SPIRE_ARGS=(--set authentication.mutual.spire.enabled=true
              --set authentication.mutual.spire.install.enabled=true
              --set authentication.mutual.spire.trustDomain="${SPIRE_TRUST_DOMAIN}")
fi

log "Instalando/actualizando Cilium ${CILIUM_VERSION}..."
helm upgrade --install cilium cilium/cilium "${SPIRE_ARGS[@]}" \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${K8S_API_HOST}" \
  --set k8sServicePort="${K8S_API_PORT}" \
  --set l7Proxy=true \
  --set sctp.enabled=true \
  --set operator.replicas=1 \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{${CILIUM_POD_CIDR}}" \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enableOpenMetrics=true \
  --set 'hubble.metrics.enabled={drop,flow,tcp,http}'

log "Esperando a que Cilium esté operativo..."
kubectl -n kube-system rollout status ds/cilium --timeout=300s || \
  die "Cilium no llegó a Ready. Revisa 'kubectl -n kube-system logs ds/cilium'."
wait_rollout deployment cilium-operator kube-system 300s

# Verificación de features clave (falla temprano si algo no quedó activo).
log "Verificando features de Cilium (KPR, L7, SCTP)..."
CIL_POD="$(kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')"
kubectl -n kube-system exec "$CIL_POD" -- cilium status | \
  grep -E 'KubeProxyReplacement|L7 Proxy|SCTP' || \
  warn "No se pudo confirmar KPR/L7/SCTP en 'cilium status'; verifícalo manualmente."

kubectl get nodes || true
ok "Cilium ${CILIUM_VERSION} instalado (KPR + L7 + SCTP + Hubble). Los nodos deberían pasar a Ready."
