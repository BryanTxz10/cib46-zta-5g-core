#!/usr/bin/env bash
# 80-spire.sh — verifica SPIRE integrado en Cilium (lab v2). Idempotente.
#
# Lab v2: SPIRE ya NO se despliega aparte. Lo instala Cilium (20-cilium.sh con
# DEPLOY_SPIRE=1) en el namespace cilium-spire, y el operador de Cilium
# registra una entrada SPIFFE por identidad. Este paso solo espera y verifica,
# y reinicia operador/agentes si aún no hay entradas (como pide la doc de
# Cilium al activar mutual authentication).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

if [ "${DEPLOY_SPIRE}" != "1" ]; then
  warn "DEPLOY_SPIRE=0: SPIRE desactivado, nada que verificar."; exit 0
fi

SS() { kubectl -n cilium-spire exec spire-server-0 -c spire-server -- /opt/spire/bin/spire-server "$@"; }

wait_rollout statefulset spire-server cilium-spire 600s
wait_rollout daemonset spire-agent cilium-spire 300s

for _ in $(seq 1 20); do SS healthcheck 2>/dev/null | grep -q 'Server is healthy' && break; sleep 6; done
SS healthcheck

if ! SS entry show -selector cilium:mutual-auth 2>/dev/null | grep -qE 'Found [1-9]'; then
  warn "SPIRE sin entradas de Cilium todavía: reinicio operador y agentes."
  kubectl -n kube-system rollout restart deployment/cilium-operator
  kubectl -n kube-system rollout restart daemonset/cilium
  wait_rollout deployment cilium-operator kube-system 300s
  wait_rollout daemonset cilium kube-system 300s
fi

for _ in $(seq 1 20); do SS entry show -selector cilium:mutual-auth 2>/dev/null | grep -qE 'Found [1-9]' && break; sleep 6; done
SS agent list | grep -E 'Found|SPIFFE ID'
SS entry show -selector cilium:mutual-auth | head -1
ok "SPIRE integrado en Cilium operativo (trust domain ${SPIRE_TRUST_DOMAIN})."
