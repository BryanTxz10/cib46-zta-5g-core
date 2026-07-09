#!/bin/bash
# run_a1_lateral_movement.sh
# Vector A1 -- Movimiento lateral este-oeste.
# Adversario externo (attacker-ue-lateral, namespace 5g-ran) intenta
# alcanzar los servicios del plano de control en 5g-cp mediante barrido
# de conectividad TCP. Valida HE1.
#
# Ejecutar dentro del pod atacante:
#   kubectl exec -it attacker-ue-lateral -n 5g-ran -- /bin/bash
#   luego pegar y correr este script.

set -uo pipefail

CONDICION="${1:?Uso: run_a1_lateral_movement.sh <C0|C1>}"
LOG="a1_${CONDICION}.txt"

echo "=== A1 -- Condicion: ${CONDICION} | $(date -u) ===" | tee "$LOG"

echo "" | tee -a "$LOG"
echo "=== VERIFICACION TCP -- nc (todos los servicios del core) ===" | tee -a "$LOG"
for target in \
  "open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777" \
  "open5gs-cp-smf-sbi.5g-cp.svc.cluster.local:7777" \
  "open5gs-cp-udm-sbi.5g-cp.svc.cluster.local:7777" \
  "open5gs-cp-ausf-sbi.5g-cp.svc.cluster.local:7777" \
  "open5gs-cp-udr-sbi.5g-cp.svc.cluster.local:7777" \
  "open5gs-cp-pcf-sbi.5g-cp.svc.cluster.local:7777" \
  "open5gs-cp-scp-sbi.5g-cp.svc.cluster.local:7777" \
  "open5gs-webui.5g-cp.svc.cluster.local:9999" \
  "mongodb.5g-cp.svc.cluster.local:27017"; do
  host=$(echo "$target" | cut -d: -f1)
  port=$(echo "$target" | cut -d: -f2)
  result=$(nc -zv -w2 "${host}" "${port}" 2>&1 | grep -E "succeeded|refused|timed")
  echo "${host}:${port} -> ${result}" | tee -a "$LOG"
done

echo "" | tee -a "$LOG"
echo "=== ENUMERACION NRF (solo si algun puerto SBI quedo abierto) ===" | tee -a "$LOG"
curl -s --max-time 5 --http2-prior-knowledge \
  http://open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777/nnrf-nfm/v1/nf-instances \
  | tee -a "$LOG"

echo "Timestamp cierre A1 ${CONDICION}: $(date -u)" | tee -a "$LOG"
