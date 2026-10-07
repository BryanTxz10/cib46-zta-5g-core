#!/bin/bash
# insert-subscribers.sh
# Re-inserta el suscriptor de prueba en MongoDB. Necesario tras cada reinicio
# del pod mongodb, porque el volumen es efímero (persistence.enabled=false).
#
# Lab v2: el suscriptor lo define helm-values/open5gs-values.yaml
# (populate.initCommands) y lo inserta el Deployment "<release>-populate" del
# chart de Gradiant. Este script solo reinicia ese Deployment para que vuelva a
# ejecutar la inserción, y luego verifica el conteo con mongosh.

set -euo pipefail

NS="${NS_CP:-5g-cp}"
RELEASE="${OPEN5GS_RELEASE:-open5gs-cp}"

kubectl -n "$NS" wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=mongodb --timeout=180s

echo "Re-ejecutando populate (${RELEASE}-populate)..."
kubectl -n "$NS" rollout restart deployment "${RELEASE}-populate"
kubectl -n "$NS" rollout status deployment "${RELEASE}-populate" --timeout=180s

MONGO_POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/name=mongodb \
  -o jsonpath='{.items[0].metadata.name}')

echo "Suscriptores en la base 'open5gs':"
kubectl -n "$NS" exec "$MONGO_POD" -- mongosh open5gs --quiet \
  --eval 'db.subscribers.countDocuments()' 2>/dev/null || \
kubectl -n "$NS" exec "$MONGO_POD" -- mongo open5gs --quiet \
  --eval 'db.subscribers.count()'
