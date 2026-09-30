#!/usr/bin/env bash
# 70-subscribers.sh — inserta el suscriptor de prueba. Envuelve el script
# existente helm-values/insert-subscribers.sh (fuente de verdad del perfil),
# esperando primero a que MongoDB esté Ready. Idempotente (el script hace drop
# + insert).
#
# RM-23: por el volumen emptyDir, esto debe re-ejecutarse tras cada reinicio de
# MongoDB. Para automatizarlo por completo, considera el Job idempotente de
# manifests/subscriber-job.yaml (ver guía).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

log "Esperando a MongoDB en ${NS_CP}..."
kubectl -n "${NS_CP}" wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=mongodb --timeout=180s || \
  die "MongoDB no llegó a Ready."

INS="${BOOTSTRAP_DIR}/../helm-values/insert-subscribers.sh"
[ -f "$INS" ] || die "No se encontró ${INS}"
log "Insertando suscriptor de prueba vía ${INS}..."
bash "$INS"
ok "Suscriptor insertado."
