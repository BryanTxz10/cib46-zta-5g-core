#!/bin/bash
# transition-to-c1.sh
# Transicion declarativa a la condicion C1 (microsegmentacion L3/L4).
# Aplica las cinco CiliumNetworkPolicy del directorio c1/.

set -euo pipefail

LOG="c1_setup.txt"
echo "=== TRANSICION A C1: $(date -u) ===" | tee "$LOG"

# Lab v2: quitar el ancla de C0. Antes no se borraba y C1-C3 corrian encima
# de ella (con la semantica vieja, un deny-all en los 3 namespaces).
for ns in 5g-cp 5g-ran 5g-up; do
  kubectl delete ciliumnetworkpolicy c0-allow-all-anchor -n "$ns" 2>/dev/null || true
done

kubectl apply -f c1/01-deny-ran-to-cp.yaml
kubectl apply -f c1/02-allow-sbi-intra-core.yaml
kubectl apply -f c1/03-allow-gnb-to-amf-n2.yaml
kubectl apply -f c1/04-deny-ran-to-mongodb.yaml
kubectl apply -f c1/05-ratelimit-n2-amf.yaml

sleep 10

echo "--- Politicas activas (esperado: 5) ---" | tee -a "$LOG"
kubectl get ciliumnetworkpolicies -n 5g-cp | tee -a "$LOG"

UE_POD=$(kubectl get pod -n 5g-ran --no-headers | grep ues | grep Running | grep -v attacker | awk '{print $1}')
kubectl exec -n 5g-ran "$UE_POD" -- ping -c 5 -I uesimtun0 8.8.8.8 | tail -2 | tee -a "$LOG"
# Esperado: 0% packet loss

ATK=attacker-ue-lateral
NRF_SVC=$(kubectl get svc -n 5g-cp | grep nrf-sbi | awk '{print $3}')
kubectl exec -n 5g-ran "$ATK" -- nc -zv -w3 "$NRF_SVC" 7777 2>&1 | tee -a "$LOG"
# Esperado: timeout (DROPPED por deny-ran-to-cp)

echo "=== C1 LISTO ===" | tee -a "$LOG"
