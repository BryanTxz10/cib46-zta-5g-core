#!/bin/bash
# transition-to-c3.sh
# Transicion declarativa a la condicion C3 (autorizacion L7 por rol).
# Se ejecuta partiendo de C2 activo. Reemplaza
# allow-sbi-legit-nfs-only por allow-sbi-rbac-c3.

set -euo pipefail

LOG="c3_setup.txt"
echo "=== TRANSICION A C3: $(date -u) ===" | tee "$LOG"

kubectl delete ciliumnetworkpolicy allow-sbi-legit-nfs-only -n 5g-cp 2>/dev/null || true
kubectl apply -f c3/01-allow-sbi-rbac-c3.yaml

sleep 10

echo "--- Politicas en C3 ---" | tee -a "$LOG"
kubectl get ciliumnetworkpolicies -n 5g-cp | tee -a "$LOG"

echo "--- Prueba de fuego: core legitimo con RBAC L7 activo ---" | tee -a "$LOG"
UE_POD=$(kubectl get pod -n 5g-ran --no-headers | grep ues | grep Running | grep -v attacker | awk '{print $1}')
kubectl exec -n 5g-ran "$UE_POD" -- ping -c 5 -I uesimtun0 8.8.8.8 | tail -2 | tee -a "$LOG"
# Esperado: 0% packet loss

echo "=== C3 LISTO ===" | tee -a "$LOG"
