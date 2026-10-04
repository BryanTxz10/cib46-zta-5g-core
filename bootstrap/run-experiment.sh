#!/usr/bin/env bash
# run-experiment.sh — envoltura reproducible de recolección de datos que
# resuelve RM-11 (evidencia de bloqueo estructurada vía Hubble) y RM-21
# (muestreo del IDR sincronizado con la vida real del flood).
#
# Rodea la ejecución de un vector de ataque con:
#   - captura de Hubble en JSON estructurado (verdict FORWARDED/DROPPED),
#   - captura de recursos del AMF mientras el ataque esté vivo,
#   - metadatos de corrida (condición, vector, timestamps, git SHA).
#
# Uso:
#   run-experiment.sh <condicion C0..C3> <vector a1|a2|a2p|a2pp|a3> [args del ataque...]
#
# Ejemplos:
#   AMF_IP=10.244.0.15 run-experiment.sh C1 a3
#   SMF_UUID=... run-experiment.sh C2 a2p C2
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

COND="${1:?Uso: run-experiment.sh <C0..C3> <a1|a2|a2p|a2pp|a3> [args...]}"
VECTOR="${2:?Falta el vector}"
shift 2 || true

need hubble
OUTDIR="results/${COND}/${VECTOR}"
mkdir -p "$OUTDIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"

# Metadatos de la corrida (reproducibilidad: qué, cuándo, con qué versión).
cat > "${OUTDIR}/run_${STAMP}.meta.json" <<EOF
{"condicion":"${COND}","vector":"${VECTOR}","inicio_utc":"${STAMP}","git_sha":"${GIT_SHA}"}
EOF

# --- 1) Hubble en background, JSON estructurado (RM-11) ---------------------
HUBBLE_OUT="${OUTDIR}/hubble_${STAMP}.jsonl"
log "Iniciando captura Hubble en ${HUBBLE_OUT}..."
hubble observe --namespace "${NS_CP}" -f -o jsonpb > "${HUBBLE_OUT}" 2>/dev/null &
HUBBLE_PID=$!
trap '[ -n "${HUBBLE_PID:-}" ] && kill "${HUBBLE_PID}" 2>/dev/null || true' EXIT
sleep 2

# --- 2) Ejecutar el vector, con muestreo del AMF si aplica ------------------
ATTACK_LOG="${OUTDIR}/${VECTOR}_${COND}_${STAMP}.txt"
case "$VECTOR" in
  a3)
    : "${AMF_IP:?Define AMF_IP para el vector A3}"
    ATK=attacker-ue-lateral
    TOP_OUT="${OUTDIR}/amf_top_${STAMP}.csv"
    echo "timestamp,fase,cpu_millicores,ram_mib" > "$TOP_OUT"
    for run in A:1000 B:5000 C:10000 D:50000 E:100000; do
      LABEL=${run%:*}; CONNS=${run#*:}
      log "RUN ${LABEL} (${CONNS} conexiones)"
      # muestra baseline
      _sample() { local fase="$1"
        local m; m=$(kubectl top pod -n "$NS_CP" -l app.kubernetes.io/name=amf --no-headers 2>/dev/null | head -1)
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),${fase},$(echo "$m"|awk '{print $2}'|tr -d m),$(echo "$m"|awk '{print $3}'|tr -d Mi)" >> "$TOP_OUT"; }
      _sample "pre_${LABEL}"
      kubectl exec -n "$NS_RAN" "$ATK" -- python3 /tmp/sctp_flood.py "$AMF_IP" 38412 "$CONNS" >>"$ATTACK_LOG" 2>&1 &
      FLOOD_PID=$!
      # RM-21: muestrear MIENTRAS el flood viva (no un número fijo de muestras).
      while kill -0 "$FLOOD_PID" 2>/dev/null; do _sample "durante_${LABEL}"; sleep 15; done
      wait "$FLOOD_PID" || true
      _sample "post_${LABEL}"
    done
    ;;
  a1|a2|a2p|a2pp)
    SCRIPT="${BOOTSTRAP_DIR}/../attack-scripts/run_${VECTOR}_"*.sh
    # shellcheck disable=SC2086
    RUNNER=$(ls $SCRIPT 2>/dev/null | head -1) || die "No hallé el script de ${VECTOR}"
    log "Ejecutando ${RUNNER} ${COND} $*"
    bash "$RUNNER" "$COND" "$@" | tee "$ATTACK_LOG" || true
    ;;
  *) die "Vector desconocido: ${VECTOR}" ;;
esac

sleep 2
kill "${HUBBLE_PID}" 2>/dev/null || true; trap - EXIT

# --- 3) Resumen de verdicts (evidencia objetiva de bloqueo) -----------------
DROPS=$(grep -c '"verdict":"DROPPED"' "${HUBBLE_OUT}" 2>/dev/null || echo 0)
FWD=$(grep -c '"verdict":"FORWARDED"' "${HUBBLE_OUT}" 2>/dev/null || echo 0)
ok "Corrida ${COND}/${VECTOR} completa. Hubble: ${DROPS} DROPPED, ${FWD} FORWARDED."
ok "Artefactos en ${OUTDIR}/ (meta, hubble.jsonl, log del ataque$([ "$VECTOR" = a3 ] && echo ', amf_top.csv'))."
