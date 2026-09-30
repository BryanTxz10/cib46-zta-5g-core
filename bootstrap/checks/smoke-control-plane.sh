#!/usr/bin/env bash
# smoke-control-plane.sh — RM-01: prueba de humo que SÍ ejercita el plano de
# control (SBI), a diferencia de `ping 8.8.8.8` (que solo prueba el plano de
# usuario y no toca las políticas). Verifica, tras aplicar una condición, que:
#   1) el UE puede completar un registro 5G nuevo (Registration + PDU Session),
#   2) la señalización SBI legítima AMF->NRF (discovery) responde 200/2xx.
# Reporta éxito/tiempo por condición → base para "tasa de attach" (no falsos
# positivos) en vez de ICMP a Internet.
#
# Uso: smoke-control-plane.sh <C0|C1|C2|C3>
set -uo pipefail
CONDICION="${1:?Uso: smoke-control-plane.sh <C0|C1|C2|C3>}"
NS_CP="${NS_CP:-5g-cp}"; NS_RAN="${NS_RAN:-5g-ran}"
LOG="smoke_${CONDICION}.txt"
echo "=== SMOKE plano de control — ${CONDICION} | $(date -u) ===" | tee "$LOG"

# 1) Registro 5G nuevo: reinicia el UE y comprueba que uesimtun0 reaparece
#    (implica Registration+Auth+PDU Session completos por SBI).
UE_DEPLOY=ueransim-ues
echo "--- Forzando re-registro del UE ---" | tee -a "$LOG"
kubectl -n "$NS_RAN" rollout restart deployment "$UE_DEPLOY" >/dev/null 2>&1 || true
kubectl -n "$NS_RAN" rollout status deployment "$UE_DEPLOY" --timeout=120s | tee -a "$LOG"
UE_POD="$(kubectl -n "$NS_RAN" get pod -l app.kubernetes.io/name=ueransim-ue \
  -o jsonpath='{.items[0].metadata.name}')"

t0=$(date +%s.%N); OK_TUN="NO"
for _ in $(seq 1 30); do
  if kubectl -n "$NS_RAN" exec "$UE_POD" -- ip -o a show uesimtun0 >/dev/null 2>&1; then
    OK_TUN="SI"; break; fi
  sleep 2
done
t1=$(date +%s.%N)
ATTACH_S=$(awk "BEGIN{printf \"%.1f\", $t1-$t0}")
echo "attach_exitoso=${OK_TUN} tiempo_attach_s=${ATTACH_S}" | tee -a "$LOG"

# 2) SBI legítima AMF->NRF (discovery). Debe responder en TODAS las condiciones
#    (C1-C3 permiten discovery a NF legítimas). Si falla => falso positivo de la
#    política (rompió tráfico legítimo del plano de control).
AMF_POD="$(kubectl -n "$NS_CP" get pod -l app.kubernetes.io/name=amf \
  -o jsonpath='{.items[0].metadata.name}')"
echo "--- SBI legítima AMF->NRF (discovery) ---" | tee -a "$LOG"
CODE=$(kubectl -n "$NS_CP" exec "$AMF_POD" -- sh -c '
  curl -s --http2-prior-knowledge -o /dev/null -w "%{http_code}" \
    "http://open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777/nnrf-disc/v1/nf-instances?target-nf-type=SMF&requester-nf-type=AMF"')
echo "sbi_discovery_http=${CODE}" | tee -a "$LOG"

echo "=== Resultado ${CONDICION}: attach=${OK_TUN} sbi=${CODE} ===" | tee -a "$LOG"
