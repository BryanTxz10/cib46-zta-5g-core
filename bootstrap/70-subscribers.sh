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

# Lab v2: el suscriptor lo inserta el Deployment <release>-populate del chart
# (helm-values/open5gs-values.yaml -> populate.initCommands). Aquí solo
# esperamos a que termine; insert-subscribers.sh lo re-ejecuta si hace falta.
kubectl -n "${NS_CP}" rollout status "deployment/${OPEN5GS_RELEASE}-populate" --timeout=300s || \
  die "El populate no terminó. Revisa: kubectl -n ${NS_CP} logs deploy/${OPEN5GS_RELEASE}-populate -c init."
ok "Suscriptor insertado por ${OPEN5GS_RELEASE}-populate."
