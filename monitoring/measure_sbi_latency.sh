#!/bin/bash
# measure_sbi_latency.sh
# Mide la latencia de senalizacion SBI en la ruta AMF -> NRF mediante el
# parametro time_total de curl, bajo condiciones operacionales normales
# (sin ataque activo). Utilizado para calcular el OVERHEAD-L7 (HE3,
# comparacion C2 vs C3).
#
# Uso: measure_sbi_latency.sh <salida.csv> <n_mediciones>

set -uo pipefail

OUT="${1:?Uso: measure_sbi_latency.sh <salida.csv> <n_mediciones>}"
N="${2:-50}"
NRF_URL="http://open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777"
AMF_POD=$(kubectl get pod -n 5g-cp -l app.kubernetes.io/name=amf \
  -o jsonpath='{.items[0].metadata.name}')

echo "measurement,latency_ms" > "$OUT"

for i in $(seq 1 "$N"); do
  LATENCY=$(kubectl exec -n 5g-cp "$AMF_POD" -- sh -c "
    curl -s --http2-prior-knowledge -o /dev/null \
      -w '%{time_total}' \
      ${NRF_URL}/nnrf-disc/v1/nf-instances?target-nf-type=SMF&requester-nf-type=AMF")
  LATENCY_MS=$(echo "$LATENCY * 1000" | bc)
  echo "${i},${LATENCY_MS}" | tee -a "$OUT"
  sleep 0.2
done
