#!/bin/bash
# monitor_amf_resources.sh
# Captura periodica de CPU, RAM y RTT de la interfaz N2 del AMF, usada
# para calcular el Indice de Degradacion de Recursos (IDR) durante y
# despues del vector A3. Genera una linea CSV por muestra.
#
# Uso: monitor_amf_resources.sh <archivo_salida.csv> <intervalo_s> <n_muestras>

set -uo pipefail

OUT="${1:?Uso: monitor_amf_resources.sh <salida.csv> <intervalo_s> <n_muestras>}"
INTERVAL="${2:-5}"
SAMPLES="${3:-6}"

echo "timestamp,cpu_millicores,ram_mib,restart_count" > "$OUT"

for i in $(seq 1 "$SAMPLES"); do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  METRICS=$(kubectl top pod -n 5g-cp -l app.kubernetes.io/name=amf --no-headers)
  CPU=$(echo "$METRICS" | awk '{print $2}' | tr -d 'm')
  RAM=$(echo "$METRICS" | awk '{print $3}' | tr -d 'Mi')
  RESTARTS=$(kubectl get pod -n 5g-cp -l app.kubernetes.io/name=amf \
    -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
  echo "${TS},${CPU},${RAM},${RESTARTS}" | tee -a "$OUT"
  sleep "$INTERVAL"
done
