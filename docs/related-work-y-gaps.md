# Related work y análisis de brechas (sobre tu biblioteca de Drive)

> Complemento de `docs/paper-posicionamiento.md`, ahora con tu **corpus real**
> (carpeta `Material bibliografico/Papers` + `Trabajos de Grado`, ~42 PDFs + 5
> tesis, leídos vía el conector de Google Drive).
>
> **Transparencia de lectura:** leí **a fondo** los 5 competidores más decisivos
> (marcados ✅ *leído*). El resto los clasifiqué **por título/tema** (marcados ○
> *por título*) — no afirmo cifras internas de esos sin haberlos abierto. Si
> quieres que lea a fondo alguno concreto, dime cuál y lo abro.

---

## 1. Inventario clasificado de tu corpus

### A. Frameworks ZT para el core 5G (competidores directos)
| Paper | Mecanismo | Relación con CIB46 |
|---|---|---|
| ✅ **5GC-SDP** (Yan et al., CSCWD 2024) | SDP + Single Packet Authorization (SPA) sobre **free5GC**, + ML para SPA-DoS | Competidor directo, **mecanismo distinto** (perímetro por autenticación, no microsegmentación eBPF ni L7 RBAC). |
| ✅ **On Sustained ZT / vEPC-vSDP** (Bello et al., IEEE TNSM 2022) | SDP virtualizado en el core (EPC/5GC) | Base conceptual de 5GC-SDP; "ZT sostenido". Mismo paradigma SDP/SPA. |
| ○ Intelligent ZT Architecture for 5G/6G (Ramezanpour & Jagannath, i-ZTA) | ZT conceptual + ML/O-RAN | Marco teórico; sin testbed de enforcement como el tuyo. |
| ○ Toward ZT Security in 5G Open Architecture Network Slices (Kholidy et al., MILCOM 2022) | Cuantificación de confianza E2E en slices | Antecedente ZT; no mide coste por capa. |
| ○ Zero Trust Integration in 5G Military Communication Networks | Framework de resiliencia ciber | Dominio militar; marco, no ablación experimental. |
| ○ Securing 5G Cloud-Native NFV Architecture with ZT | ZT sobre NFV | Revisar: puede solaparse con tu marco. |
| ○ Zero Trust Architecture for 5G Networks / …for 5G-enabled MCC | ZT general | Antecedentes de encuadre. |
| ○ Quantum-resilient cross-trust evaluation for ZT 5G | Evaluación de confianza post-cuántica | Tangencial (futuro). |
| ○ Flexible ZTA for industrial IoT infrastructures | ZT para IIoT | Útil para el gancho "industrial/OT". |
| ○ GAZETA: Game-Theoretic ZT Auth against Lateral Movement in 5G IoT | ZT teórico-juegos vs movimiento lateral | Mismo problema (A1) con enfoque teórico, no eBPF. |

### B. eBPF / Cilium / service mesh (tu plano de enforcement)
| Paper | Tema | Relación con CIB46 |
|---|---|---|
| ✅ **Evaluating Sidecar vs Sidecarless Service Mesh** (Hasanth & Nadig, Purdue, IEEE ANTS 2024) | Cilium (sidecarless) vs Istio/Linkerd; Cilium = CNI+mesh, menor OPEX/recursos; "apto para edge" | **Respalda tu argumento central** eBPF-sin-sidecar. Cítalo en la justificación de diseño. |
| ✅ **Vulnerability Analysis of eBPF-enabled Containerized 5G Core** (Deshpande & Bera, IIT Jammu, arXiv 2603.19867) | Ataques **contra** eBPF (cross-container, DoS por `bpf_send_signal`, robo de claves, bash injection) sobre Open5GS + eUPF | **Limitación que debes citar**: tu plano de enforcement (eBPF) es a la vez superficie de ataque. Lo conviertes en "trabajo futuro / amenaza complementaria". |
| ○ eBPF: A New Approach to Cloud-Native Observability… (Soldani et al., IEEE Access 2023) | eBPF para observabilidad/seguridad 5G/6G | Cita fundacional para justificar eBPF. |
| ○ Monitoring 5G Core Vulnerabilities with eBPF | Detección de vulns con eBPF | Observabilidad (Hubble-like). |
| ○ Enhancing 5G Core security with eBPF/XDP | Seguridad plano de datos eBPF/XDP | Complementa tu enfoque en plano de control. |
| ○ From Packets to Defense: eBPF-based IDS patterns | Patrones de IDS eBPF | Detección, no prevención. |
| ○ eSeMeshA (eBPF service mesh acceleration) / NAS (eBPF mesh scheduling) | Rendimiento de mesh eBPF | Cita de rendimiento. |

### C. Ataques / vulnerabilidades / datasets del core 5G (validan tus vectores)
| Paper | Tema | Relación con CIB46 |
|---|---|---|
| ✅ **Malicious Lateral Movement in 5GC with Network Slicing + 5GLatte** (Kumar & Thing, ST Eng., ITNAC 2023) | **Detección** de movimiento lateral (A1) con grafo+anomalías sobre OAI; MITRE ATT&CK+FiGHT | Eje de venta clave: ellos **detectan** post-hoc; tú **previenes** inline (drop en el SYN). |
| ○ 5G-Attacks: A New Dataset From Realistic 5G-Core Attacks (Duchesne et al., 6GNet 2025, París) | Dataset de ataques al core | Francés/europeo; complementario (ellos generan, tú contienes). |
| ○ A Vulnerability Assessment of Open-Source Implementations of [5G] | Vulns en free5GC/Open5GS/OAI | Respalda A2/A2′ (registro NRF no autenticado). |
| ○ Mobile Core Network Attack Techniques Using UE | Ataques desde el UE | Respalda tu adversario externo RAN (A1/A3). |
| ○ Cross-Service Token: Finding Attacks in 5G Core (`2509.08992`) | Abuso de tokens OAuth2 entre servicios SBI | Respalda A2″ (abuso de privilegios/rol). |
| ○ Deep Learning Proactive Anomaly Detection for 5GC Control-Plane NF Interactions | Detección ML de anomalías SBI | Detección (contraste con tu prevención). |

### D. Resiliencia / integridad / infraestructura cloud-native 5G
○ A Scalable & Fault-Tolerant 5G Core on Kubernetes · ○ Toward a Robust Ingress
for Open-Sourced 5GC · ○ Security Assurance for 5G Split gNB and AMF · ○
**TPM-Based Continuous Remote Attestation & Integrity Verification for 5G VNFs on
Kubernetes** (clave: identidad/atestación *no forjable* — rebate tu RM-05) · ○
Securing the Cloud-Native 5G Control Plane · ○ Techniques for Secure, Resilient
and Differentiated 5G Operations · ○ Application Relocation in Edge-Enabled 5G ·
○ Zero-Day Guardian (FL para IIoT) · ○ TinyEdge (TinyML edge IIoT).

### E. Estándares y marcos (dan rigor, cítalos en el threat model)
○ **NIST SP 800-207** (definición ZTA) · ○ **NIST SP 1800-19** (Trusted Cloud) ·
○ A Systematic Survey on 5G & 6G Security · ○ 5G Network Security Challenges &
Solutions · ○ **ENISA Threat Landscape 2024**.

### F. Contexto Perú / minería (motivación, NO el claim técnico)
○ Mining 4.0: A Digital Transformation… Peruvian Case Study · ○ Goggin &
Villanueva-Mansilla (2023) 5G in emerging economies: Indonesia & Peru · ○
Validación Tecno-Económica LTE-5G en Perú (tesis) · ○ Propuesta red MESH mina sur
del Perú.

### G. Tesis de referencia (`Trabajos de Grado`)
○ TFM Gallego Vara · ○ TFM Valero Martí · ○ Bolívar de la Cruz (plataforma) · ○
Validación Tecno-Económica LTE-5G Perú · (NIST SP 1800-19 está aquí también).

> Archivos de nombre opaco a revisar y renombrar: `IJCSP24C1128`,
> `Conferenceproceeding1`, `1570976591`, `AJACE2013…`, `ACFrOg…`, `MCPTT.docx`,
> `TSP - BORDA CASTILLO`. Ábrelos y clasifícalos (o dime y los abro).

---

## 2. Posicionamiento exacto frente a los competidores leídos

| Trabajo | Core | Plano de control ZT | Enforcement | ¿Incremental por capa? | ¿Coste medido? | Prevención/Detección |
|---|---|---|---|---|---|---|
| **CIB46 (tú)** | **Open5GS 2.7** | **Cilium eBPF** (L3/L4 identidad) + **L7 RBAC (Envoy)** | **In-kernel, pre-handshake (SYN) + L7 403** | **Sí (C0→C3, 1 vector/capa)** | **Sí (+13% L7, IDR)** | **Prevención** |
| 5GC-SDP | free5GC | SDP + SPA (NRF=controlador) | Firewall dinámico por SPA | No (bloque) | Sí (+59µs NF-NF; 0.8s abrir core) | Prevención + detección ML de SPA-DoS |
| vEPC-vSDP (Sustained ZT) | EPC/5GC | SDP virtualizado | Perímetro por autenticación | No | Resiliencia DoS/DDoS/portscan | Prevención |
| Sidecarless mesh eval | (microservicios genéricos) | Cilium vs Istio/Linkerd | eBPF sidecarless | No | **Sí (Cilium > Istio; menor OPEX)** | n/a (rendimiento) |
| 5GLatte | OAI | — (detección) | Grafo+anomalías sobre logs | No | TPR 100%/FPR 8.3% | **Detección** post-hoc |
| eBPF-vuln (IIT Jammu) | Open5GS+eUPF | — (ataca eBPF) | n/a | No | n/a | Ataque (superficie eBPF) |

**Lecturas clave para tu defensa:**

- **5GC-SDP es tu competidor más cercano y conviene diferenciarte con precisión.**
  Ellos: free5GC + SDP/SPA (puertos ocultos, el NRF actúa de controlador SDP) +
  detección ML de DoS sobre paquetes SPA; overhead **+59 µs** NF↔NF y **0.8 s**
  para "abrir" todo el core. Tú: **no** ocultas puertos con SPA sino que **filtras
  por identidad de workload en el dataplane eBPF** y **autorizas por rol en L7**;
  tu overhead L7 es **+0.28 ms** sobre 2.15 ms. Son enfoques **complementarios y
  distintos**: SDP = *perímetro por autenticación de paquete*; CIB46 = *segmentación
  por identidad + RBAC L7 nativo de kernel*. Dilo así y no competís en lo mismo.

- **5GLatte habilita tu mejor eje de venta: prevención vs detección.** La mayoría
  de tu corpus de ataques (5GLatte, Deep-Learning anomaly, Zero-Day Guardian) son
  **detección** (ML/grafos, post-hoc, con falsos positivos). CIB46 **previene en
  línea** (drop en el SYN, 403 L7), con resultado **determinista 100%→0%** y sin
  falsos positivos de detección. Ese contraste es un argumento fuerte y honesto.

- **El paper sidecarless (Purdue) te da la cita que te faltaba (D8).** Cilium como
  CNI+mesh sidecarless reduce OPEX/recursos frente a Istio y es "apto para edge
  donde un mesh completo es inviable". Es exactamente tu justificación para no usar
  service mesh con sidecar. Combínalo con los overheads mTLS de la literatura
  (Istio +166%, Cilium-mesh +99%) para que tu +13% L7 destaque.

- **El paper de vulns eBPF (IIT Jammu) te obliga a una limitación honesta.** Tu
  plano de enforcement (eBPF) es **también** superficie de ataque: un contenedor
  con `CAP_BPF/CAP_SYS_ADMIN` comprometido puede abusar de helpers eBPF para DoS o
  robo de claves, cruzando el aislamiento de namespaces. Decláralo en Limitaciones
  y remite a LSM/allow-listing de helpers como mitigación (ellos lo proponen).

---

## 3. Tu novedad, refinada contra TU propio corpus

Con esta biblioteca delante, el hueco que **nadie de tu corpus ocupa** es:

> **Una evaluación experimental incremental y dirigida por vectores de ataque del
> *coste y la cobertura por capa* de controles Zero Trust nativos de eBPF
> (identidad L3/L4 + autorización L7 por rol) que *previenen* en línea sobre un
> core 5G SA real (Open5GS), con el mecanismo de bloqueo caracterizado (SYN-drop
> vs 403 post-handshake) y los anti-patrones de configuración que los invalidan.**

- Los ZT-5GC de tu corpus son **SDP/SPA** (5GC-SDP, vEPC-vSDP) o **conceptuales/ML**
  (i-ZTA, GAZETA, Kholidy) → no es microsegmentación eBPF + L7 RBAC medida por capa.
- Los de ataques son **detección** (5GLatte, DL anomaly) → no prevención.
- Los de eBPF son **observabilidad/IDS** (Soldani, Monitoring, From Packets) o
  **ataques contra eBPF** (IIT Jammu) → no enforcement ZT por capa.
- El sidecarless es **rendimiento genérico**, sin 5G ni ataques.

Nadie cruza las tres dimensiones (5G SA real + eBPF-prevención por capa + coste por
vector). **Ahí está tu paper.**

---

## 4. Cómo citar cada grupo, sección por sección

- **Introduction / motivación:** ENISA 2024 + los CVE del NRF/AMF (CVE-2026-55068,
  CVE-2025-63288) + Mining 4.0 Perú (un párrafo) para el gancho industrial.
- **Background / Threat model:** NIST SP 800-207 (definición ZT), MITRE FiGHT +
  NSA/CISA (mapea A1–A3), "A Vulnerability Assessment of Open-Source 5G" y
  "Mobile Core Attack Techniques Using UE" (realismo de A1/A2), Cross-Service Token
  (A2″).
- **Related work:** tabla §2 — 5GC-SDP y vEPC-vSDP (SDP/SPA), i-ZTA/GAZETA/Kholidy
  (ZT conceptual), 5GLatte y DL-anomaly (detección), THAALOUB y Budigiri (eBPF/mesh,
  **faltan en tu biblioteca**, ver §6).
- **Design / por qué eBPF sin sidecar:** sidecarless eval (Purdue) + Soldani +
  eSeMeshA/NAS; contrástalo con overheads mTLS de service mesh.
- **Evaluation:** tu C0→C3; compara tu +13% L7 contra el +59 µs/0.8 s de 5GC-SDP
  (coste de distinto tipo) y contra overheads mTLS.
- **Limitations / Future work:** eBPF como superficie de ataque (IIT Jammu);
  identidad **no forjable** vía atestación (TPM-based attestation paper + SPIRE/
  SPIFFE) para cerrar tu RM-05; correlación por instancia (tu H36, Cross-Service
  Token).

---

## 5. Referencias incorporadas (los 4 que faltaban) — fichas y enlaces

Estos 4 trabajos son centrales para tu related work y **no estaban** en tu Drive.
Ya están incorporados al `.bib` del repo (`docs/referencias.bib`) y como entradas
de related work aquí abajo.

> **No pude subir los PDF a tu Drive desde esta sesión:** el proxy de egress del
> contenedor bloquea IEEE Xplore, Zenodo, MDPI, arXiv y KU Leuven (403 en CONNECT).
> Descárgalos tú con tu acceso institucional de la **UNI** (tus PDFs ya llevan la
> marca "Universidad Nacional de Ingeniería … IEEE Xplore") desde estos enlaces y
> déjalos en `Material bibliografico/Papers`; si luego quieres, los leo a fondo
> desde Drive e integro sus cifras exactas.

### Ficha 1 — THAALOUB (competidor multinivel service-mesh + CNI)
- **Cita:** C. Benzaid, N. Guerd, N. E. H. Rehouma, K. Zeraoulia, T. Taleb,
  *A Multi-Layered Zero Trust Microsegmentation Solution for Cloud-Native 5G &
  Beyond Networks*, **IEEE WCNC 2025**, Milán.
- **Afiliaciones:** Univ. Oulu (Benzaid); USTHB (Guerd/Rehouma/Zeraoulia); Ruhr
  Univ. Bochum (Taleb).
- **Qué hace:** ZT multinivel con **Service Mesh + CNI** e *intent-based access
  control*, 3GPP-compliant; "impacto mínimo en latencia/recursos".
- **Cómo lo posicionas:** su enforcement es **con sidecar** (service mesh); CIB46 es
  **sidecarless (eBPF/Envoy nativo)** y atribuye **coste por capa**. Clave citarlo:
  Taleb/Benzaid son referentes europeos → tu jurado en Francia lo conocerá.
- **Enlaces:** Zenodo (OA) `https://zenodo.org/records/14699793` · DOI
  `10.5281/zenodo.14699793` · IEEE `https://ieeexplore.ieee.org/document/10978671/`

### Ficha 2 — Budigiri et al. (respaldo cuantitativo de NetworkPolicies eBPF)
- **Cita:** G. Budigiri, C. Baumann, J. T. Mühlberg, E. Truyen, W. Joosen,
  *Network Policies in Kubernetes: Performance Evaluation and Security Analysis*,
  **EuCNC/6G Summit 2021**.
- **Afiliaciones:** imec-DistriNet, KU Leuven + Ericsson Research.
- **Qué aporta:** NetworkPolicies eBPF (Calico/Cilium) reducen **75–99 %** la
  superficie de ataque con overhead **despreciable** para uRLLC edge.
- **Cómo lo posicionas:** respaldo para tu elección de eBPF y para C1 (segmentación);
  tú vas más allá (identidad de NF + L7 por rol, que ellos no hacen).
- **Enlaces:** Lirias KU Leuven (OA, PDF)
  `https://lirias.kuleuven.be/server/api/core/bitstreams/14e501bd-e6bb-41d6-bf72-360c4850443a/content`
  · Zenodo `https://zenodo.org/records/5776322`

### Ficha 3 — Duong & Kim (Cilium + SCP en el 5GC)
- **Cita:** B. V. Duong, Y. Kim, *A Design of Service Mesh Based 5G Core Network
  Using Cilium*, **ICOIN 2023**.
- **Qué hace:** service mesh con Cilium aplicado al 5GC usando el SCP.
- **Cómo lo posicionas:** antecedente directo de Cilium+SCP; respalda tu **nota de
  validez del SCP** como broker (Model D, 3GPP TS 23.501 §6.3).
- **Enlaces:** IEEE `https://ieeexplore.ieee.org/document/10049044/` · DOI
  `10.1109/ICOIN56518.2023.10049044` (verificar).

### Ficha 4 — Detección de conflictos en políticas Cilium (formaliza tu H30)
- **Cita:** *A Decision-Diagram Framework for Conflict Detection in Multi-Layer
  Cilium Network Policies*, **J. Cybersecurity and Privacy (MDPI)**, 6(4):136, 2026.
  *(autores: verificar en la página)*
- **Qué aporta:** semántica formal de la composición KNP (aditiva) / CNP (deny-wins)
  / CCNP (cluster-override); detecta anomalías de **shadow** y redundancia.
- **Cómo lo posicionas:** convierte tu **H30** (la política amplia anula a la
  granular de identidad) de anécdota a caso empírico de un fenómeno ya formalizado.
- **Enlace:** `https://www.mdpi.com/2624-800X/6/4/136` (OA).

> **Evidencia de amenaza (no son "related work" sino threat model):**
> CVE-2026-55068 (free5GC NRF) + Open5GS issue #4778 + OAI issue #6 (validan A2/A2′);
> CVE-2025-63288 (AMF NGSetupRequest DoS, valida A3). Ya están en `referencias.bib`.

---

## 6. Acciones recomendadas

1. Reescribir **Related Work** con la tabla §2 y el encuadre prevención-vs-detección.
2. Descargar los 4 PDF de §5 con tu acceso UNI y dejarlos en `Papers` (ver nota:
   no pude subirlos yo por el bloqueo de egress). El `.bib` ya los incluye.
3. Insertar la **limitación eBPF-como-superficie** (IIT Jammu) y la vía de
   **identidad no forjable** (TPM/SPIFFE) — cierra RM-05/D1 con respaldo del propio
   corpus.
4. Reposicionar el gancho Perú/minería como motivación (Mining 4.0, Goggin 2023),
   no como claim técnico (D4).
5. Abrir y clasificar los archivos de nombre opaco (§1) para no perder material.

> Todo esto se integra con `docs/paper-posicionamiento.md` (pros/contras P1–P8,
> D1–D8) y `docs/revision-metodologica.md` (RM-01…RM-28). Juntos forman el dossier
> para convertir la tesis en paper.
