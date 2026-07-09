#!/bin/bash
# 02-patch-identity-labels.sh
# Condicion C2 - Identidad de workload eBPF
#
# Aplica el label de identidad cib46-nf-type=core-nf a los Deployments
# de las nueve funciones de red legitimas del core (chart
# towards5gs-helm). Este label es el que verifica la politica
# allow-sbi-legit-nfs-only. El pod nf-impostor (ver
# ../../attack-scripts/deploy-nf-impostor.yaml) se despliega
# deliberadamente sin este label, modelando un contenedor comprometido
# via pipeline CI/CD.

set -euo pipefail

NAMESPACE="5g-cp"
NFS=(amf smf nrf udm udr ausf pcf scp bsf)

for nf in "${NFS[@]}"; do
  kubectl patch deployment "open5gs-cp-${nf}" -n "$NAMESPACE" \
    --type=json \
    -p="[{\"op\":\"add\",\"path\":\"/spec/template/metadata/labels/cib46-nf-type\",\"value\":\"core-nf\"}]" \
    2>/dev/null && echo "Label aplicado: ${nf}" || echo "SKIP: ${nf} no encontrado"
done

echo "Esperando rollout de los deployments con nuevo label..."
sleep 15

echo "--- Pods con identidad de workload activa ---"
kubectl get pods -n "$NAMESPACE" -l cib46-nf-type=core-nf
