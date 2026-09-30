#!/usr/bin/env bash
# 10-k3s.sh — instala k3s SIN su CNI ni kube-proxy, para que Cilium tome el
# control total del dataplane (necesario para KubeProxyReplacement e identidad
# eBPF de las condiciones C2/C3).
#
# Idempotente: si k3s ya está instalado en la versión pedida, no reinstala.
#
# NOTA: se desactiva flannel, la NetworkPolicy nativa, traefik, servicelb y
# kube-proxy. Cilium reemplaza kube-proxy (KubeProxyReplacement). Verifica que
# tu versión de k3s soporte --disable-kube-proxy (v1.19+).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if command -v k3s >/dev/null 2>&1 && k3s --version | grep -q "${K3S_VERSION%+*}"; then
  ok "k3s ${K3S_VERSION} ya instalado."
else
  log "Instalando k3s ${K3S_VERSION} (sin CNI, sin kube-proxy)..."
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="server \
      --flannel-backend=none \
      --disable-network-policy \
      --disable-kube-proxy \
      --disable=traefik \
      --disable=servicelb \
      --write-kubeconfig-mode=644" \
    sh -
  ok "k3s instalado."
fi

# Exporta kubeconfig para el resto de scripts y para el usuario.
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
mkdir -p "${HOME}/.kube"
cp -f "$KUBECONFIG" "${HOME}/.kube/config" 2>/dev/null || \
  sudo cp -f "$KUBECONFIG" "${HOME}/.kube/config"
sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config" 2>/dev/null || true

log "Esperando a que el API server responda (los nodos estarán NotReady hasta instalar Cilium)..."
for _ in $(seq 1 30); do
  kubectl get nodes >/dev/null 2>&1 && break; sleep 2
done
kubectl get nodes || die "El API server de k3s no respondió."
warn "Los nodos aparecerán NotReady hasta que 20-cilium.sh instale el CNI. Es lo esperado."
ok "k3s listo. KUBECONFIG=${HOME}/.kube/config"
