#!/bin/bash
# insert-subscribers.sh
# Inserta el perfil de suscriptor de prueba en MongoDB. Necesario tras
# cada reinicio del pod mongodb, dado que el volumen es emptyDir
# (efimero) en el testbed. Ejecutar antes de cualquier registro de UE
# con UERANSIM.

set -euo pipefail

MONGO_POD=$(kubectl get pod -n 5g-cp -l app.kubernetes.io/name=mongodb \
  -o jsonpath='{.items[0].metadata.name}')

echo "Suscriptores actuales:"
kubectl exec -n 5g-cp "$MONGO_POD" -- mongo open5gs --quiet \
  --eval 'db.subscribers.count()'

kubectl exec -n 5g-cp "$MONGO_POD" -- mongo open5gs --eval '
db.subscribers.drop();
function makeSubscriber(imsi) { return {
  schema_version: NumberInt(1), imsi: imsi, msisdn: [], imeisv: [],
  mme_host: [], mme_realm: [], purge_flag: [],
  security: { k: "465B5CE8B199B49FAA5F0A2EE238A6BC", amf: "8000", op: null,
              opc: "E8ED289DEBA952E4283B54E88E6183CA" },
  ambr: { downlink:{value:NumberInt(1),unit:NumberInt(3)},
          uplink:{value:NumberInt(1),unit:NumberInt(3)} },
  slice: [{ sst: NumberInt(1), default_indicator: true, session: [{
    name: "internet", type: NumberInt(3), pcc_rule: [],
    ambr: { downlink:{value:NumberInt(1),unit:NumberInt(3)},
            uplink:{value:NumberInt(1),unit:NumberInt(3)} },
    qos: { index: NumberInt(9), arp: { priority_level: NumberInt(8),
           pre_emption_capability: NumberInt(1),
           pre_emption_vulnerability: NumberInt(1) }}
  }]}],
  access_restriction_data: NumberInt(32), network_access_mode: NumberInt(0),
  subscriber_status: NumberInt(0), operator_determined_barring: NumberInt(0),
  __v: NumberInt(0)
};}
db.subscribers.insertOne(makeSubscriber("999700000000001"));
'

echo "Suscriptores tras insercion:"
kubectl exec -n 5g-cp "$MONGO_POD" -- mongo open5gs --quiet \
  --eval 'db.subscribers.count()'
