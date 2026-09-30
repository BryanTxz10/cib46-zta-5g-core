#!/usr/bin/env bash
# 50-namespaces.sh — crea los tres namespaces del testbed. Idempotente.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

for ns in "${NS_CP}" "${NS_RAN}" "${NS_UP}"; do ensure_ns "$ns"; done
ok "Namespaces ${NS_CP}, ${NS_RAN}, ${NS_UP} listos."
