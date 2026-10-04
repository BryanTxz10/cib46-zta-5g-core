# De tesis a paper: posicionamiento, fortalezas, debilidades y trabajos relacionados

> Análisis para convertir el trabajo CIB46 (ZTA incremental sobre núcleo 5G SA
> cloud-native) en un **paper presentable en un máster en Francia** (venues tipo
> NTMS, 6GNet, IEEE CNSM/NetSoft, EuCNC, IFIP). Se apoya en la bitácora de
> hallazgos (H26–H36, métricas C0→C3) y en una revisión de literatura
> comparable.
>
> **Nota de fuentes:** parte de la bibliografía (IEEE Xplore, Zenodo, MDPI full
> text) está bloqueada por el proxy de egress de esta sesión; los metadatos
> (autores, venue, año, cifras) se verificaron por buscador y se citan con URL.
> Confirma cada referencia en su versión final antes de enviar.

---

## 1. Veredicto en una línea

**Sí hay un paper aquí**, pero no el que la tesis cuenta hoy. La tesis se vende
como *"¿funciona Zero Trust en 5G?"* (pregunta ya respondida en la literatura:
sí). El paper debe venderse como lo que realmente es tu aporte diferencial:
**una caracterización experimental, capa por capa, de *qué* vector de ataque
cierra *cada* dimensión de ZTA en un core 5G real, con el costo medido y con los
anti-patrones de configuración que nadie documenta.** Ese reencuadre convierte
un trabajo "de verificación" en uno "de caracterización", que es lo publicable.

---

## 2. Fortalezas del trabajo como paper (pros)

| # | Fortaleza | Por qué vende en un paper |
|---|---|---|
| P1 | **Diseño incremental C0→C3 con un vector dedicado por dimensión** | Aísla el efecto marginal de cada control (segmentación / identidad / rol). La mayoría de los papers evalúan ZTA como un bloque monolítico; tú lo descompones. Es tu mayor activo metodológico. |
| P2 | **Distinción empírica SYN-drop (L3/L4, H31) vs 403 post-handshake (L7, H34)** | Es un resultado *mecanicístico*, no solo "pasa/no pasa". Mostrar que la identidad eBPF descarta en el SYN (coste casi nulo para el NRF) y el RBAC L7 descarta tras el handshake (coste mayor) es una contribución concreta y citable sobre el *coste de defensa por capa*. |
| P3 | **Overhead L7 medido y contextualizado (H35: +0.28 ms / +13 %, < jitter)** | Pone número a la pregunta "¿cuánto cuesta pasar de *quién eres* a *estás autorizado*?". El hallazgo contraintuitivo ("el costo es menor que el jitter natural") es titular de paper. |
| P4 | **Anti-patrones de configuración Cilium (H27, H30)** | `fromEndpoints` = allow (no deny implícito por listar), y la política amplia que **anula** (shadowing) a la granular de identidad. Esto es *conocimiento operacional transferible* que la literatura formaliza apenas ahora (ver §4, MDPI 2026). Un paper de "lecciones de implementación" con estos dos hallazgos ya tiene valor. |
| P5 | **Refutación experimental del fail-open L7 sobre h2c de Open5GS (H33)** | Resultado negativo útil: Envoy *sí* parsea HTTP/2 cleartext prior-knowledge y emite 403. Desmonta una creencia y habilita el control de C3. |
| P6 | **Honestidad sobre los límites (H10/H21: SPIRE sin enforcement; HE2/HE3: sin rate-limit SCTP)** | Un revisor premia que declares lo que *no* lograste. Muchos papers de ZTA ocultan esto. |
| P7 | **Trazabilidad y reproducibilidad del stack** (versiones pinneadas, bitácora por condición, Hubble como evidencia) | Con la capa `bootstrap/` añadida, el testbed es reproducible de extremo a extremo — raro en este subcampo. |
| P8 | **El SCP como línea base de tráfico legítimo constante** (nota de validez §8 de la bitácora) | Argumento de validez interna elegante: el discriminante de C3 explota una propiedad arquitectónica *preexistente* (Model D, TS 23.501 §6.3), no un artefacto introducido para la condición. |

---

## 3. Debilidades del trabajo como paper (contra) y cómo neutralizarlas

Ordenadas por lo que más daño hace en revisión. Las que vienen de la revisión
metodológica previa (`docs/revision-metodologica.md`) se referencian como RM-xx.

| # | Debilidad | Severidad en revisión | Mitigación para el paper |
|---|---|---|---|
| D1 | **"Identidad de workload" = label forjable, no identidad criptográfica** (RM-05). Bajo tu propio modelo de amenaza (pipeline CI/CD comprometido), el atacante pondría el label. | 🔴 Un revisor de seguridad lo verá al instante. | **Reencuadra el constructo**: C2 no es "workload identity" sino *microsegmentación basada en atributos verificados por el dataplane*. Declara la no-forjabilidad como supuesto del modelo de amenaza (atacante controla la red, no el orquestador/admission). Opcional fuerte: añade un `ValidatingAdmissionPolicy`/Kyverno que haga el label no-forjable y **mídelo** — eso sí es novedad. |
| D2 | **n pequeño, sin potencia, sin corrección múltiple, binarios deterministas** (RM-06/07). Overhead L7 con 50 reps es lo único continuo robusto. | 🟠 Ataque fácil de "¿significancia?". | Presenta los binarios (TBANA/TBOC) como **deterministas** (100%→0%), no como inferencia estadística — es más fuerte, no más débil. Para el overhead L7, reporta Kruskal-Wallis/Mann-Whitney + **rank-biserial + IC95 %** (ya tienes `bootstrap/analysis/`), no *d* de Cohen (RM-03). |
| D3 | **Posible bug en la medición de latencia** (RM-02, `&` sin comillas). | 🔴 Si el número de H35 salió de ahí, es tu resultado estrella en riesgo. | **Re-mide** con `checks/measure_sbi_latency_fixed.sh` antes de enviar. El +13 % es demasiado central para dejarlo en duda. |
| D4 | **Validez externa a "minería peruana" casi nula** (RM-09). 1 UE, 1 gNB, sin tráfico de fondo, sin carga OT. | 🟠 En Francia te preguntarán por qué "minería" y no "core 5G privado" a secas. | Para el paper, **abandona el gancho minero** como eje y quédate con "private 5G / edge industrial". La minería que sea un *párrafo de motivación*, no el claim. Añade tráfico de fondo multi-UE si hay tiempo (sube mucho la credibilidad del overhead). |
| D5 | **HE2/HE3 (DoS N2/SCTP) no tiene control que mitigue** por diseño. | 🟠 "Evalúas un control que sabías que no funciona." | Repósicionalo como **caracterización de una brecha**: "Cilium 1.15.4 no ofrece rate-limiting SCTP; cuantificamos la asimetría plano-control/plano-usuario (IDR) que esto deja abierta". Eso es un hallazgo, no un fracaso — y conecta con CVE-2025-63288 (ver §5). |
| D6 | **La prueba de humo de disponibilidad no tocaba el plano de control** (RM-01, `ping 8.8.8.8`). | 🟡 Debilita el claim "sin falsos positivos". | Usa `checks/smoke-control-plane.sh` (attach 5G + discovery SBI) y reporta **tasa de attach** por condición como métrica de disponibilidad. |
| D7 | **Open5GS 2.7 SÍ soporta TLS/mTLS en SBI** (`verify_client: true` en `nrf.yaml`). Tu H10/H21 dice que mTLS intra-core "rompe el core". | 🟠 Un revisor que conozca Open5GS objetará que descartaste mTLS por un problema de integración, no por imposibilidad. | Matiza H21: el problema no es que Open5GS no soporte TLS SBI, sino que **habilitar `verify_client` intra-core con las NF nativas (que no presentan cert cliente en esa topología) las rompe**. Es un hallazgo de *integración*, no una limitación del protocolo. Sé preciso o te lo refutan. |
| D8 | **Sin comparación cuantitativa con una alternativa** (service mesh / mTLS). | 🟠 "¿Por qué eBPF y no Istio?" sin datos. | Aunque sea breve, cita el overhead de service mesh de la literatura (§5: Istio mTLS +166 %, Cilium +99 %) para justificar que tu enfoque eBPF/L7-nativo evita el coste del sidecar. Tu +13 % L7 queda espectacular al lado. |

---

## 4. El cambio de enfoque (el pivote que hace publicable el trabajo)

**De:** *"Evaluación de si una arquitectura Zero Trust mejora la seguridad del
núcleo 5G SA en redes mineras."*
→ pregunta cerrada, respondida, con validez externa débil.

**A (opción recomendada):** *"Caracterización capa-por-capa del costo y la
cobertura de controles Zero Trust nativos de eBPF en un núcleo 5G SA
cloud-native: qué vector cierra cada dimensión, a qué coste de plano de
control, y qué anti-patrones de configuración los invalidan en silencio."*

Los tres ángulos vendibles, en orden de fuerza:

1. **"The cost of defense-in-depth, measured per layer."** Tu combinación
   SYN-drop (H31) / 403 post-handshake (H34) / +13 % L7 (H35) es un marco de
   *coste de enforcement por capa* que no he visto medido así. **Este es el
   paper.**
2. **"Silent misconfigurations in Cilium-based 5G Zero Trust."** H27 (semántica
   `fromEndpoints`) + H30 (shadowing de la política granular por la amplia) como
   un *experience paper* de lecciones de implementación. Muy publicable en un
   track práctico/operacional (CNSM, NOMS).
3. **"An attacker-model-driven, incremental ZTA testbed for 5G cores (open &
   reproducible)."** El testbed + `bootstrap/` + dataset anonimizado como
   contribución de *artefacto reproducible* (muchos venues tienen artifact
   track).

Recomendación: paper principal = ángulo 1, con H27/H30 como sección de "lessons
learned" y el testbed reproducible como contribución secundaria.

---

## 5. Comparación con trabajos similares

### 5.1 Tabla comparativa

| Trabajo | Core 5G | Mecanismo ZT | Evalúa ataques reales | Mide overhead | Incremental por capa | Anti-patrones de config |
|---|---|---|---|---|---|---|
| **CIB46 (este)** | Open5GS 2.7 | Cilium eBPF L3/L4 + **L7 por rol** + SPIRE perimetral | **Sí (A1, A2, A2′, A2″, A3)** | Sí (L7 +13 %) | **Sí (C0→C3)** | **Sí (H27, H30)** |
| THAALOUB — Benzaid, Guerd, Rehouma, Zeraoulia, Taleb (IEEE WCNC 2025) | cloud-native B5G | **Service Mesh + CNI**, intent-based access control, multinivel, 3GPP-compliant | Parcial | Sí ("minimal impact") | Multinivel, no por vector | No |
| Budigiri et al. (KU Leuven + Ericsson, EuCNC/6G Summit 2021) | 5G edge (contenedores) | NetworkPolicies Calico/Cilium eBPF | Analiza superficie de ataque | **Sí (overhead bajo)** | No | Parcial |
| Duong & Kim (ICOIN 2023) | 5GC | **Service Mesh con Cilium** (SCP) | No | Rendimiento | No | No |
| Duchesne, Blaise, (Braconnot) Velloso, Conan (6GNet 2025, París) | Open5GS | — (dataset de ataques para IDS/ML) | **Sí (dataset de ataques al core)** | No | No | No |

### 5.2 Qué dice cada uno y cómo te posicionas

- **THAALOUB** (tu competidor más directo, y además te interesa porque Taleb y
  Benzaid son referentes europeos). Hace ZT multinivel con **service mesh + CNI**
  e *intent-based access control*, "impacto mínimo en latencia". **Tu diferencia:**
  ellos usan sidecars de service mesh (coste del proxy por pod); tú usas
  enforcement **nativo de eBPF + L7 sin sidecar**, y **mides el coste por capa
  con vectores de ataque concretos**. Posiciónate como *"la alternativa
  sidecar-less, con atribución de coste por dimensión de control"*.
  → https://zenodo.org/records/14699793 · https://ieeexplore.ieee.org/document/10978671/

- **Budigiri et al.** es tu respaldo cuantitativo: NetworkPolicies eBPF reducen la
  superficie de ataque **75–99 %** con overhead despreciable para 5G edge de baja
  latencia. **Úsalo** para justificar la elección de eBPF y para contrastar que tú
  vas más allá de L3/L4 (ellos no hacen L7 por rol ni identidad de NF).
  → https://www.researchgate.net/publication/353542380

- **Duong & Kim** muestra que el SCP encaja con service-mesh/Cilium. Respalda tu
  nota de validez del SCP (§8 de la bitácora). → https://ieeexplore.ieee.org/document/10049044/

- **Duchesne et al. 2025 (6GNet, París)**: dataset de ataques realistas al core
  5G. **Clave para ti** porque (a) es francés/europeo y lo vas a presentar en
  Francia, y (b) ellos *generan* ataques para IDS; tú *bloqueas* ataques con ZTA.
  Complementarios: podrías proponer tus vectores como *casos de validación de
  controles* frente a su dataset. Corrige la cita (antes "Amponis et al.") a
  **Duchesne et al., 2025**. → https://ieeexplore.ieee.org/document/11314079/

### 5.3 Marcos de referencia que debes citar (dan rigor y encajan en Francia)

- **NSA/CISA — Security Guidance for 5G Cloud Infrastructures, Part I: Prevent and
  Detect Lateral Movement** (2021). Tu A1 (movimiento lateral) y tu C1 mapean
  literalmente a esta guía. Citarlo ancla tu modelo de amenaza en estándar
  institucional. → https://www.cisa.gov/sites/default/files/publications/Security_Guidance_For_5G_Cloud_Infrastructures_Part_I_508_Compliant.pdf
- **MITRE FiGHT** (5G threat framework). Mapea tus vectores A1/A2/A2′/A2″/A3 a
  técnicas FiGHT: da taxonomía común y credibilidad. → https://fight.mitre.org/
- **ITU-R M.2410** (control-plane latency: mínimo 20 ms, deseable 10 ms) y **3GPP
  TS 22.261**. Úsalos como umbral contra tu 2.43 ms de H35 (en vez de solo "edge
  minero 10 ms"). Tu overhead queda ~8× bajo el umbral ITU. → https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-M.2410-2017-PDF-E.pdf

### 5.4 Validación externa de tus vectores (esto fortalece MUCHO el paper)

Tus ataques no son inventados: la literatura y los CVE recientes los confirman
como amenazas reales del SBA. Cítalos para probar relevancia:

- **A2 / A2′ (registro no autenticado de NF en el NRF, CRUD spoofing).** Es una
  **clase de defecto confirmada con CVE** en 2026: free5GC **CVE-2026-55068**
  (GHSA-x8mj-6p3q-g5pp, crítica), con instancias en Open5GS (issue #4778) y OAI
  (issue #6): *registro PUT no autenticado con endpoints declarados por el
  atacante, persistido y devuelto por NFDiscovery*. **Tu C0/C1 reproducen
  exactamente esto y tu C2/C3 lo contienen.** Es el respaldo más potente que
  tienes. → https://github.com/openairinterface/oai-cn5g-nrf/issues/6
- **A3 (DoS por señalización N2/NGAP contra el AMF).** **CVE-2025-63288** (CVSS
  7.5): el AMF de Open5GS 2.7.6 cae ante un NGSetupRequest malformado. También
  issue #2576 (NRF crashea con `nfType` custom). Esto valida tu HE2 y conecta tu
  IDR con una vulnerabilidad real. → https://osv.dev/vulnerability/CVE-2025-63288
- **H30 (shadowing de política granular por política amplia).** Ya hay base
  formal: *"A Decision-Diagram Framework for Conflict Detection in Multi-Layer
  Cilium Network Policies"* (MDPI, 2026) formaliza la composición KNP (aditiva) /
  CNP (deny-wins) / CCNP (cluster-override) y detecta anomalías de **shadow** y
  redundancia. **Tu H30 es un caso empírico de shadow cross-layer** — cítalo y tu
  hallazgo deja de ser anecdótico. → https://www.mdpi.com/2624-800X/6/4/136
- **Coste del sidecar (justifica tu enfoque sin service mesh).** mediciones
  publicadas: mTLS añade **+166 % (Istio)**, **+99 % (Cilium mesh)**, **+33 %
  (Linkerd)** de latencia; Envoy consume 50–100 m CPU / 50–100 MiB por pod. Tu
  +13 % L7 sin sidecar es el argumento. → https://arxiv.org/pdf/2411.02267

---

## 6. Dónde está tu novedad defendible (y dónde NO)

**NO es novedad** (no lo reclames): "ZTA mejora la seguridad 5G", "Cilium hace
microsegmentación", "eBPF es rápido". Todo publicado (Budigiri, THAALOUB, Duong).

**SÍ es novedad defendible:**
1. La **atribución de coste de enforcement por capa** en un core 5G real
   (SYN-drop vs 403 post-handshake vs +13 % L7), con el mismo SUT y vectores
   dedicados. No lo he encontrado medido así.
2. Los **anti-patrones de configuración** H27/H30 como evidencia empírica en un
   core 5G (complementa la teoría de MDPI 2026).
3. El **testbed incremental dirigido por modelo de amenaza, reproducible y
   abierto** (C0→C3 con un vector por dimensión), como artefacto.

---

## 7. Estructura de paper sugerida (8 páginas, formato IEEE)

1. **Introduction** — SBA es confianza implícita; CVEs recientes (CVE-2026-55068,
   CVE-2025-63288) prueban el riesgo; pregunta: *¿qué cuesta y qué cubre cada
   capa de ZTA nativa-eBPF?*
2. **Background & Threat Model** — SBA/NRF/SCP; mapeo a MITRE FiGHT y NSA/CISA;
   modelo de adversario (externo RAN / interno sin identidad / interno con
   identidad y abuso de rol).
3. **Design** — C0→C3; qué añade cada capa; por qué eBPF sin sidecar.
4. **Implementation & Reproducibility** — stack, `bootstrap/`, Hubble como
   instrumento; publica el repo.
5. **Evaluation** — cobertura (determinista, binaria: 100%→0% por capa) +
   **coste** (overhead L7 con IC95 %, IDR bajo DoS) + mecanismo (SYN vs 403).
6. **Lessons Learned** — H27, H30, H33, el matiz mTLS de Open5GS (D7).
7. **Related Work** — tabla §5.1; posicionamiento frente a THAALOUB/Budigiri.
8. **Limitations & Future Work** — identidad criptográfica no-forjable (admission
   control / SPIFFE-aware SCP, tu H36), rate-limiting SCTP, escala/tráfico de fondo.

**Venues candidatos (Francia/Europa, alineados):** IFIP/IEEE **NTMS** (París),
**6GNet** (París — donde está el grupo de Duchesne/Conan), IEEE **CNSM**, IEEE
**NetSoft**, **EuCNC & 6G Summit**, IEEE **CSNet**. Para empezar: un **workshop**
o el **artifact/demo track** de uno de estos baja el listón y encaja con un
máster.

---

## 8. Checklist mínima antes de enviar

- [ ] Re-medir overhead L7 con el script corregido (D3/RM-02) y reportar IC95 %.
- [ ] Reencuadrar C2 (atributo verificado por dataplane, no identidad cripto) (D1).
- [ ] Matizar H21: Open5GS sí soporta TLS SBI; el problema es de integración (D7).
- [ ] Sustituir *d* de Cohen por rank-biserial/Cliff (RM-03).
- [ ] Cambiar el eje "minería" por "private/industrial 5G" (D4).
- [ ] Añadir la tabla de related work (§5.1) y las citas de CVE (§5.4).
- [ ] Corregir cita Amponis → **Duchesne et al., 2025**; no sobreafirmar
      Cabanillas Carbonell (2025) como minería.
- [ ] Mapear A1–A3 a MITRE FiGHT y a la guía NSA/CISA en el threat model.
- [ ] Publicar testbed + dataset consolidado anonimizado (artifact).

---

*Fuentes verificadas por búsqueda (metadatos). Confirmar cada referencia en su
versión final; varias fuentes full-text estaban bloqueadas por el proxy de esta
sesión.*
