#!/usr/bin/env bash
# bootstrap.sh — orquesta el despliegue completo del testbed desde cero, en
# orden. Cada paso es idempotente, así que puedes re-ejecutar este script tras
# un fallo sin duplicar recursos.
#
# Uso:
#   ./bootstrap.sh              # todo
#   ./bootstrap.sh --from 60    # reanuda desde el paso 60 (Open5GS)
#   ./bootstrap.sh --skip-spire # omite SPIRE (no afecta métricas C0-C3)
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

FROM="00"; SKIP_SPIRE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --skip-spire) SKIP_SPIRE=1; shift ;;
    *) die "Opción desconocida: $1" ;;
  esac
done

run_step() {
  local num="$1" script="$2"
  [ "$num" -lt "$FROM" ] 2>/dev/null && { log "Omitiendo paso ${num} (${script})"; return; }
  [ "$SKIP_SPIRE" -eq 1 ] && [ "$script" = "80-spire.sh" ] && { log "Omitiendo SPIRE (--skip-spire)"; return; }
  log "========== PASO ${num}: ${script} =========="
  bash "./${script}"
}

run_step 00 00-prereqs.sh
run_step 10 10-k3s.sh
run_step 20 20-cilium.sh
# Lab v2: Multus es opcional (N2 va por Cilium). Actívalo con DEPLOY_MULTUS=1.
if [ "${DEPLOY_MULTUS:-0}" = "1" ]; then run_step 30 30-multus.sh; else log "Omitiendo Multus (DEPLOY_MULTUS=0)"; fi
run_step 40 40-metrics-server.sh
run_step 50 50-namespaces.sh
run_step 60 60-open5gs.sh
run_step 70 70-subscribers.sh
run_step 80 80-spire.sh
run_step 90 90-ueransim.sh

log "========== Aplicando condición baseline C0 =========="
( cd ../cilium-policies && bash transition-to-c0.sh )

ok "Testbed desplegado y en condición C0. Siguiente: ejecutar el experimento"
ok "con ./run-experiment.sh, o pasar de condición con cilium-policies/transition-to-cN.sh"
