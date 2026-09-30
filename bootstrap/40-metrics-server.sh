#!/usr/bin/env bash
# 40-metrics-server.sh — instala metrics-server (necesario para `kubectl top`,
# base del IDR del AMF en el vector A3). Idempotente.
#
# NOTA sobre RM-08: metrics-server agrega con resolución ~15 s por defecto.
# Para el experimento se ajusta --metric-resolution a 15s y se DOCUMENTA que
# el muestreo del IDR no debe hacerse a intervalos menores (evita
# pseudo-replicación). Si necesitas mayor resolución, usa la ruta cgroup
# directa de bootstrap/checks/ (ver guía).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

log "Instalando metrics-server ${METRICS_SERVER_VERSION}..."
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

# En k3s/testbed sin TLS de kubelet firmado por la CA del clúster, hay que
# permitir --kubelet-insecure-tls. Parche idempotente.
log "Aplicando parche --kubelet-insecure-tls y --metric-resolution=15s..."
kubectl -n kube-system patch deployment metrics-server --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--metric-resolution=15s"}
]' 2>/dev/null || warn "Parche ya aplicado o no necesario."

wait_rollout deployment metrics-server kube-system 180s
log "Verificando 'kubectl top' (puede tardar ~30s en tener datos)..."
sleep 20
kubectl top nodes || warn "'kubectl top' aún sin datos; reintenta en unos segundos."
ok "metrics-server listo."
