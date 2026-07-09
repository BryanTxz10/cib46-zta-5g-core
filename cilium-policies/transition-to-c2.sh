#!/bin/bash
# transition-to-c2.sh
# Transicion declarativa a la condicion C2 (identidad de workload eBPF).
# Se ejecuta partiendo de C1 activo. Etiqueta las NF legitimas y
# reemplaza allow-sbi-intra-core por allow-sbi-legit-nfs-only.

set -euo pipefail

LOG="c2_setup.txt"
echo "=== TRANSICION A C2: $(date -u) ===" | tee "$LOG"

# Paso 1: etiquetar las NF legitimas con el label de identidad
bash c2/02-patch-identity-labels.sh | tee -a "$LOG"

kubectl get pods -n 5g-cp -l cib46-nf-type=core-nf | tee -a "$LOG"

# Paso 2: reemplazar allow-sbi-intra-core por allow-sbi-legit-nfs-only
kubectl delete ciliumnetworkpolicy allow-sbi-intra-core -n 5g-cp 2>/dev/null || true
kubectl apply -f c2/01-allow-sbi-legit-nfs-only.yaml

sleep 10

echo "--- Politicas en C2 ---" | tee -a "$LOG"
kubectl get ciliumnetworkpolicies -n 5g-cp | tee -a "$LOG"

echo "--- Prueba de fuego: core legitimo con identidad activa ---" | tee -a "$LOG"
UE_POD=$(kubectl get pod -n 5g-ran --no-headers | grep ues | grep Running | grep -v attacker | awk '{print $1}')
kubectl exec -n 5g-ran "$UE_POD" -- ping -c 5 -I uesimtun0 8.8.8.8 | tail -2 | tee -a "$LOG"
# Esperado: 0% packet loss. Si falla: alguna NF no recibio el label.

echo "=== C2 LISTO ===" | tee -a "$LOG"
