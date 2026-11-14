# Arquitectura v2 — Hardening Perfil A aplicado

> Traduce la *Revisión de arquitectura del testbed CIB46 v2* (14 nov 2026) a
> cambios concretos en el repo. Como el lab **aún no está instalado**, se aplicó
> el **Perfil A completo** (el objetivo pre-KCD de la review) directo sobre los
> manifiestos, values y playbooks. El **Perfil B** (Multus, redes por interfaz,
> MultiNetworkPolicy) y el **split de namespaces** de UPF/MongoDB quedan como
> seguimiento documentado (§3), tal como la propia review los difiere.
>
> **Actualización (arquitectura v3):** el split del UPF a `5g-up` ya está hecho.
> Ver `docs/arquitectura-v3-planos.md`. MongoDB sigue en `5g-cp`.

## 1. Mapa hallazgo → cambio

| # | Sev | Hallazgo | Cambio aplicado | Archivo(s) |
|---|---|---|---|---|
| 1 | Alta | N6 colapsado (UE puede alcanzar la SBI) | Egress del UPF solo a `world` (N6) + N3; UPF excluido como origen de la SBI | `hardening/egress/01-egress-upf-n6.yaml`, `c1/02`, `c2/01`, `c3/01` |
| 2 | Alta | Sin egress en ninguna condición | **Default-deny de egress** en 5g-cp y 5g-ran + DNS + flujos por interfaz | `hardening/egress/00`, `02`; overlays C1–C3 |
| 3 | Alta | Control y usuario sin separar | Colocación por plano (control→worker1, UPF→worker2); PSS por zona; split de namespaces documentado (§3) | `helm-values/open5gs-values.yaml`, `ansible/hardening.yml` |
| 4 | Alta | RAN sin fronteras | Se retira la regla N2 sobre-amplia (c1/05); guarda Kyverno extendida al label del gNB; ingress N3/N4 explícito en el UPF | overlays, `bootstrap/admission/kyverno-identity-guard.yaml`, `hardening/ingress/02` |
| 5 | Alta | Colocación al azar | `nodeSelector` por plano en todas las NF, gNB, UE y pods de ataque; **taint** del master | `helm-values/…`, `bootstrap/manifests/ueransim.yaml`, `attack-scripts/*.yaml`, `ansible/hardening.yml` |
| 6 | Media | Nada cifrado | Cifrado **WireGuard entre nodos** (condición aparte, `node_encryption`/`DEPLOY_ENCRYPTION`) | `bootstrap/20-cilium.sh`, `ansible/site.yml`, `group_vars/all.yml` |
| 7 | Media | MongoDB sin autenticación | Ingress a MongoDB restringido a **UDR/PCF/BSF** (reemplaza c1/04) | `hardening/ingress/01-allow-mongodb-udr-pcf.yaml` |
| 8 | Media | WebUI innecesaria | `webui.enabled: false` | `helm-values/open5gs-values.yaml` |
| 9 | Media | API de K8s al alcance de las NF | Egress default-deny cierra el API server; `automountServiceAccountToken: false` en los manifiestos propios | `hardening/egress/00`, `ueransim.yaml`, `attack-scripts/*` |
| 10 | Media | Privilegios amplios | **Pod Security Standards** por namespace (warn/audit baseline; privileged en 5g-up) | `ansible/hardening.yml` |
| 11 | Baja | Red de VMs plana | Perfil B (segunda NIC / host firewall) — **diferido** (§3) | — |
| 12 | Baja | Una sola subred de pods | Sin cambio (no afecta al enforcement; Cilium decide por identidad) | — |

## 2. Consecuencias metodológicas (léelas antes de medir)

El hardening **mejora la seguridad** pero cambia dónde se bloquean algunos
vectores. Decláralo en la tesis o ajústalo según tu objetivo:

- **A3 (flood N2/SCTP) ahora se contiene por ORIGEN en C1.** Al retirar c1/05, el
  único origen permitido a `AMF:38412` es el gNB (c1/03). Un atacante sin el label
  del gNB ya no alcanza N2 en C1 → el flood se bloquea en el ingress, no por
  volumen. El punto *"Cilium no hace rate-limit de SCTP"* sigue siendo válido
  (ni siquiera al gNB legítimo se le limita), pero reencuádralo: **C1 contiene A3
  por origen**, no por tasa. Si quieres conservar el relato original de A3,
  vuelve a añadir `../../c1/05-ratelimit-n2-amf.yaml` a los overlays.
- **Egress default-deny bloquea el intento del atacante externo (A1/A2) en el
  propio 5g-ran**, además del ingress `deny-ran-to-cp`. El contraste C0→C1 se
  mantiene (en C0 pasa, en C1 no), solo que ahora hay **dos** capas que lo
  paran; repórtalo (Hubble muestra cuál evalúa primero).
- **Los atacantes internos (A2′/A2″) siguen pudiendo intentar contra el NRF**: el
  egress de 5g-cp permite intra-zona, así que su petición sale y la **identidad
  (C2) / el rol L7 (C3)** la bloquean, como en el diseño original. El experimento
  de identidad/rol no se altera.
- **C0 sigue siendo baseline limpio**: el hardening vive en las condiciones C1+,
  no en la política ancla de C0.

## 3. Diferido (con razón) — para después de KCD

| Tema | Por qué se difiere | Cómo hacerlo |
|---|---|---|
| **MongoDB→5g-db** (el UPF→5g-up ya está hecho en la v3) | Alto riesgo: el chart de Gradiant despliega todo en un release; separarlos exige releases Helm aparte y re-emparejar PFCP (N4) entre namespaces. La review lo marca P2 y recomienda, pre-KCD, dejarlos en 5g-cp **aislados por label** (ya hecho: egress UPF, ingress N3/N4, MongoDB UDR/PCF). | Releases Helm separados para upf y mongodb; referencias de servicio cross-namespace; subir 5g-cp/5g-db a `enforce=baseline`. |
| **UE + ataque → 5g-ue** | Ripplea el modelo de amenaza (A1 cambia de zona de origen) y la política `deny-ran-to-cp`. Se mantiene en 5g-ran por ahora; PSS en warn/audit para no romper. | Crear ns `5g-ue` privileged; mover `ueransim.yaml` (UE) y los pods de ataque; añadir `deny-ue-to-cp`. |
| **Perfil B (Multus multi-interfaz)** | Es **otro experimento** (1–2 semanas): Cilium deja de ver N2/N3/N4/N6 y necesitas MultiNetworkPolicy. La review dice que NO entra en la charla. | `ipvlan L2` (no macvlan en Workstation), una NAD por red y namespace, medir qué enforcement se pierde al salir de Cilium. |
| **Taint + SPIRE** | Con SPIRE integrado en Cilium (cilium-spire), el server se reprograma a un worker sin problema (ya no está atado al master como en la v1), así que el taint es seguro. | `ansible-playbook hardening.yml --tags taint` en despliegue nuevo. |

## 4. Cómo aplicarlo (lab nuevo)

```bash
# 1) Despliegue con la colocación y webui-off ya en los values:
cd ansible && ansible-playbook site.yml -K
# 2) Hardening del clúster (PSS + taint):
ansible-playbook hardening.yml -K
# 3) (opcional) Guarda de admisión no-forjable (identidad NF + gNB):
kubectl apply -f ../bootstrap/admission/kyverno-identity-guard.yaml   # requiere Kyverno
# 4) Condición endurecida (incluye egress, N6, N3/N4, MongoDB):
make condition C=c1     # o c2 / c3 / c2-spire / c3-spire
# 5) Validar que NO hay falso positivo (el attach del plano de control sigue vivo):
make smoke C=C1
# 6) (condición aparte) Cifrado entre nodos y re-medir latencia:
#    node_encryption: true en group_vars  (o DEPLOY_ENCRYPTION=1 en la ruta bash)
```

## 5. Checklist pre-KCD (Porto, 19 nov)

- [ ] `make smoke C=C1` verde tras aplicar C1 endurecida (ningún allow de egress
      olvidado rompe el attach). Si falla: revisa qué flujo bloquea Hubble y
      añádelo al egress de la zona correspondiente.
- [ ] Confirmar hallazgo 1: `helm show values <chart> | grep -i enableNAT` y una
      prueba desde el UE (`uesimtun0`) hacia el Service del NRF. Si responde en C1
      sin hardening, es el 6.º *gotcha* de la charla (el teléfono llega al core).
- [ ] Alinear el slide 10 / diagrama con la colocación worker1 (central) /
      worker2 (borde).
- [ ] Ajustar en la guarda Kyverno los SA reales del desplegador (NF y gNB).
- [ ] Ajustar `node-worker1`/`node-worker2` a los hostnames reales.

> Fuente: *Revisión de arquitectura del testbed CIB46 v2* (14 nov 2026). Este
> documento registra qué se implementó y qué se difirió, para trazabilidad.
