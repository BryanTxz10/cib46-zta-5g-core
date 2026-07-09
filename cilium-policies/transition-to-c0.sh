#!/bin/bash
# transition-to-c0.sh
# Transicion declarativa a la condicion C0 (baseline sin controles ZTA).
# Borra todas las politicas de segmentacion/identidad/autorizacion y
# aplica la politica ancla permisiva requerida por Cilium 1.15.4 en modo
# KubeProxyReplacement Strict (ver c0-allow-all-anchor.yaml).

set -euo pipefail

LOG="c0_setup.txt"
echo "=== TRANSICION A C0: $(date -u) ===" | tee "$LOG"

kubectl delete ciliumnetworkpolicies --all -n 5g-cp 2>/dev/null || true
kubectl delete ciliumnetworkpolicies --all -n 5g-ran 2>/dev/null || true
kubectl delete ciliumnetworkpolicies --all -n 5g-up 2>/dev/null || true

kubectl apply -f c0-allow-all-anchor.yaml

sleep 10

echo "--- Politicas activas (esperado: 1 por namespace, anchor) ---" | tee -a "$LOG"
kubectl get ciliumnetworkpolicies --all-namespaces | tee -a "$LOG"

echo "--- Core 5G (esperado: todos Running) ---" | tee -a "$LOG"
kubectl get pods -n 5g-cp | tee -a "$LOG"
kubectl get pods -n 5g-ran | tee -a "$LOG"

UE_POD=$(kubectl get pod -n 5g-ran --no-headers | grep ues | grep Running | grep -v attacker | awk '{print $1}')
kubectl exec -n 5g-ran "$UE_POD" -- ping -c 5 -I uesimtun0 8.8.8.8 | tail -2 | tee -a "$LOG"
# Esperado: 0% packet loss

echo "=== C0 LISTO ===" | tee -a "$LOG"
