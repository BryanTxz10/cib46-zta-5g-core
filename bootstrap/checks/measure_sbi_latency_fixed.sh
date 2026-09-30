#!/usr/bin/env bash
# measure_sbi_latency_fixed.sh — RM-02: versión corregida de
# monitoring/measure_sbi_latency.sh.
#
# Correcciones frente al original:
#   1) La URL va ENTRECOMILLADA dentro del `sh -c`, de modo que el `&` de la
#      query es literal y no pone curl en segundo plano (bug que probablemente
#      invalidó la medición de OVERHEAD-L7).
#   2) Descarta N muestras de calentamiento (warm-up) para no sesgar la media.
#   3) No depende de `bc`: usa awk para milisegundos.
#   4) Emite unidades explícitas y separa condición para el análisis.
#
# NO reemplaza al script original (se conserva por trazabilidad de lo ya
# ejecutado). Úsalo para RE-MEDIR la latencia si confirmas que los CSV previos
# están afectados por el bug.
#
# Uso: measure_sbi_latency_fixed.sh <salida.csv> <n_mediciones> <condicion> [warmup]
set -euo pipefail
OUT="${1:?Uso: measure_sbi_latency_fixed.sh <salida.csv> <n> <condicion> [warmup]}"
N="${2:-50}"
CONDICION="${3:?Falta la condición (C0..C3) para etiquetar las filas}"
WARMUP="${4:-5}"
NS_CP="${NS_CP:-5g-cp}"
URL="http://open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777/nnrf-disc/v1/nf-instances?target-nf-type=SMF&requester-nf-type=AMF"

AMF_POD="$(kubectl -n "$NS_CP" get pod -l app.kubernetes.io/name=amf \
  -o jsonpath='{.items[0].metadata.name}')"

echo "measurement,condicion,latency_ms" > "$OUT"
total=$(( N + WARMUP ))
for i in $(seq 1 "$total"); do
  # URL entrecomillada => el & es literal (corrección clave).
  T=$(kubectl -n "$NS_CP" exec "$AMF_POD" -- sh -c \
    "curl -s --http2-prior-knowledge -o /dev/null -w '%{time_total}' \"${URL}\"")
  MS=$(awk "BEGIN{printf \"%.3f\", ${T:-0}*1000}")
  if [ "$i" -le "$WARMUP" ]; then
    echo "warmup ${i}/${WARMUP}: ${MS} ms (descartada)" >&2
  else
    idx=$(( i - WARMUP ))
    echo "${idx},${CONDICION},${MS}" | tee -a "$OUT"
  fi
  sleep 0.2
done
echo "OK: ${N} mediciones válidas escritas en ${OUT} (warm-up descartado: ${WARMUP})." >&2
