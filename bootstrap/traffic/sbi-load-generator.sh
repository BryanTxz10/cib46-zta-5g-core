#!/usr/bin/env bash
# sbi-load-generator.sh — genera carga de señalización SBI LEGÍTIMA de fondo
# (peticiones de discovery al NRF) a una TASA OBJETIVO, para fijar el punto de
# operación (L1/L2) bajo el que se miden OVERHEAD-L7 e IDR (punto 3 / §6.5).
#
# Emula la señalización agregada de M dispositivos sin tener que levantar M UEs.
# El tráfico sale de una NF legítima (AMF por defecto), así que PASA C2/C3 (es
# carga de fondo legítima, no un ataque).
#
# Uso:
#   sbi-load-generator.sh <req_por_seg> <duracion_seg> [nf_consumidora]
# Ej. (nivel L1 ~ 30 req/s durante 5 min desde el AMF):
#   sbi-load-generator.sh 30 300 amf
#
# IMPORTANTE (RM-20): antes de usarlo en el experimento, CARACTERÍZALO —
# comprueba que el core sostiene la tasa pedida (si rate_real << rate_objetivo,
# el cuello de botella eres tú, no el core). El script reporta la tasa lograda.
set -uo pipefail
RATE="${1:?Uso: sbi-load-generator.sh <req_por_seg> <duracion_seg> [nf]}"
DUR="${2:?Falta duración en segundos}"
NF="${3:-amf}"
NS_CP="${NS_CP:-5g-cp}"
NRF_URL="http://open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777/nnrf-disc/v1/nf-instances?target-nf-type=SMF&requester-nf-type=AMF"

POD="$(kubectl -n "$NS_CP" get pod -l app.kubernetes.io/name="$NF" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
[ -n "$POD" ] || { echo "No encontré pod de la NF '$NF' en $NS_CP" >&2; exit 1; }

# Intervalo entre peticiones (en segundos, con decimales) para aproximar la tasa.
INTERVAL=$(awk "BEGIN{printf \"%.4f\", 1.0/$RATE}")
END=$(( $(date +%s) + DUR ))
ok=0; fail=0; t0=$(date +%s.%N)

echo "=== Carga SBI de fondo: objetivo ${RATE} req/s, ${DUR}s, desde ${NF} (${POD}) ==="
while [ "$(date +%s)" -lt "$END" ]; do
  # Petición de discovery legítima; URL entrecomillada (evita el bug del & — RM-02).
  if kubectl -n "$NS_CP" exec "$POD" -- sh -c \
      "curl -s -o /dev/null --http2-prior-knowledge --max-time 3 \"${NRF_URL}\"" 2>/dev/null; then
    ok=$((ok+1)); else fail=$((fail+1)); fi
  sleep "$INTERVAL"
done

t1=$(date +%s.%N)
elapsed=$(awk "BEGIN{printf \"%.1f\", $t1-$t0}")
rate_real=$(awk "BEGIN{printf \"%.1f\", ($ok+$fail)/$elapsed}")
echo "=== Fin. OK=${ok} FAIL=${fail} tiempo=${elapsed}s tasa_lograda=${rate_real} req/s ==="
# Si tasa_lograda << objetivo: usa concurrencia (varias NFs consumidoras en
# paralelo) o reduce el objetivo; documenta la tasa efectiva en el experimento.
