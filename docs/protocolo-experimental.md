# Protocolo experimental corregido (rehacer desde 0 con metodología rigurosa)

> Diseño experimental **preregistrable** para re-ejecutar el estudio CIB46 (ZTA
> incremental sobre núcleo 5G SA cloud-native) corrigiendo de raíz las
> deficiencias detectadas en `docs/revision-metodologica.md` (RM-01…RM-28).
>
> Principio rector: **todo se decide y se escribe ANTES de recolectar datos.**
> Cada sección indica qué hallazgo RM corrige. La capa de automatización
> (`bootstrap/`) y los scripts de análisis (`bootstrap/analysis/`) ya existen y
> hacen este protocolo ejecutable y reproducible.
>
> Supuesto de trabajo: se mantiene el mismo stack (Open5GS 2.7 + Cilium 1.15.4 +
> UERANSIM + k3s), porque el objetivo es **medir bien lo que ya montaste**, no
> cambiar de tecnología. Donde una decisión cambia el diseño, se marca como
> **[DECISIÓN]**.
>
> **Encuadre (v2):** el objeto NO es la 5G pública de un operador, sino la **red
> privada 5G industrial (SNPN, 3GPP Rel-16/17)** — Industria 4.0. Esa elección no
> es cosmética: ajusta el alcance a lo que realmente modela tu testbed (core
> cloud-native on-premise, open-source, single-tenant, con amenaza interna/OT y de
> supply-chain). La **minería peruana es un vertical/caso motivador**, no la
> población. Ver §1 (contribution statement) y §4-bis (escenario).

---

## 0. Qué cambia frente a la primera versión (resumen)

| Antes (tesis v1) | Ahora (protocolo v2) | Corrige |
|---|---|---|
| Prueba de disponibilidad = `ping 8.8.8.8` (plano de usuario) | Attach 5G completo + discovery SBI (plano de control) | RM-01 |
| Latencia con bug de shell (`&`) | Script corregido + warm-up descartado | RM-02 |
| *d* de Cohen con prueba no paramétrica | Tamaño de efecto por rangos (rank-biserial / Cliff) | RM-03 |
| Normalidad documentada pero no implementada | Plan estadístico pre-especificado y coherente | RM-04 |
| n=6, sin potencia, sin corrección | n calculado por potencia; ómnibus + corrección FDR | RM-06/07 |
| Muestreo IDR cada 5 s (pseudo-replicación) | Muestreo ≥ resolución del backend; media por run | RM-08 |
| Orden fijo C0→C3, estado acumulado | Bloques con orden aleatorizado + reset a estado limpio | RM-19 |
| Generador de flood sin caracterizar | Caracterización previa de capacidad del generador | RM-20 |
| Identidad = label forjable (ambiguo) | Constructo redefinido + control de admisión [DECISIÓN] | RM-05 |
| Métricas IDR/OVERHEAD/TBANA/TBOC sin fórmula | Glosario operacional formal | RM-17/18 |
| Datos crudos fuera del repo | Consolidados anonimizados + DOI | RM-16 |

---

## 1. Preguntas de investigación e hipótesis (falsables)

> **Contribution statement (úsalo literal en abstract e introducción):**
> *Medimos, por capa y por vector de ataque, qué **cubre** y cuánto **cuesta** un
> enforcement Zero Trust nativo de eBPF (identidad L3/L4 + autorización L7 por rol)
> sobre un core 5G SA open-source real para **redes privadas 5G industriales**,
> caracterizando el **mecanismo de bloqueo** (drop en el SYN vs 403 post-handshake)
> y los **anti-patrones de configuración**, de forma **reproducible**.*
> Es una contribución **comparativa / de caracterización**, no "un framework ZT
> nuevo" — y así debe presentarse (ver nota de novedad al final de §1).

**Pregunta general.** En un núcleo 5G SA cloud-native para **redes privadas
industriales (SNPN)**, ¿cuánto **cubre** y cuánto **cuesta** cada dimensión
incremental de control Zero Trust nativo de eBPF frente a vectores de ataque
representativos del SBA?

Hipótesis (cada una con su prueba y métrica; ver §4 y §7):

- **H1 (segmentación).** La microsegmentación L3/L4 (C1) reduce a 0 el acceso
  este-oeste no autorizado desde el segmento RAN (A1) y el CRUD externo sobre el
  NRF (A2), respecto a C0. *Métrica:* tasa de bloqueo (proporción, IC Wilson).
- **H2 (identidad).** La identidad de workload verificada por el dataplane (C2)
  bloquea al impostor interno sin identidad (A2′) que C1 permite. *Métrica:*
  tasa de bloqueo.
- **H3 (autorización).** La autorización L7 por rol (C3) bloquea el abuso de
  privilegios de una NF con identidad legítima pero sin rol (A2″) que C2 permite.
  *Métrica:* tasa de bloqueo.
- **H4 (coste).** El coste de enforcement crece con la capa y es operacionalmente
  asumible: OVERHEAD-L7 (C2→C3) < umbral ITU-R M.2410 de plano de control (20 ms;
  deseable 10 ms). *Métrica:* latencia SBI (continua).
- **H5 (brecha DoS) — reformulada.** Cilium 1.15.4 **no** ofrece rate-limiting
  SCTP; por tanto C1 **no** contiene el flood N2 (A3). Se **caracteriza** la
  asimetría plano-control/plano-usuario (IDR) que la brecha deja abierta, en vez
  de afirmar una mitigación. *Métrica:* IDR-CPU/RAM/RTT (continuas). *(Corrige
  RM-10: H5 pasa de "control que falla" a "caracterización de una brecha",
  falsable como "no hay diferencia C0 vs C1 en IDR".)*

> **Nota de constructo (RM-05).** C2 se define explícitamente como
> *microsegmentación basada en identidad de workload verificada por el dataplane
> eBPF (namespace + label de identidad)*, **no** como identidad criptográfica. Se
> declara el supuesto de amenaza bajo el que es efectiva (§3) y se añade el
> control de admisión que la vuelve no-forjable **[DECISIÓN, ver §3.2]**.

> **Nota de novedad (cómo defenderla ante el jurado).** Los *componentes* no son
> nuevos (Cilium/Budigiri; ZT-5GC/5GC-SDP, THAALOUB; L7 eBPF). Lo que **nadie de
> la literatura hace** y es tu aporte: (1) **ablación incremental por capa dirigida
> por un vector dedicado** (C0→C3) que aísla el efecto marginal de cada dimensión;
> (2) **atribución de coste de enforcement por capa** (SYN-drop vs 403); (3)
> **prevención inline determinista** frente a la mayoría basada en *detección*
> (5GLatte, DL-anomaly); (4) **testbed abierto reproducible** dirigido por modelo de
> amenaza. Preséntalo como estudio **comparativo/de caracterización**; si lo vendes
> como "un framework ZT nuevo", es refutable con THAALOUB/5GC-SDP. Nivel adecuado:
> **maestría** (rigor + posicionamiento honesto), no un mecanismo/teoría nuevos.

---

## 2. Variables

### 2.1 Independiente
**Condición de control ZTA**, factor intra-sujeto de 4 niveles **aditivos**:
`C0` (baseline allow-all), `C1` (+L3/L4), `C2` (+identidad), `C3` (+L7 rol).

### 2.2 Dependientes (con definición operacional — corrige RM-17/18)
| Símbolo | Definición operacional | Unidad | Instrumento |
|---|---|---|---|
| **TBLOQ** | Tasa de bloqueo = operaciones bloqueadas / operaciones intentadas del vector | proporción [0,1] | Hubble (verdict) + código HTTP |
| **IDR-CPU** | (CPU_bajo_ataque − CPU_baseline) / CPU_baseline del AMF | adimensional | cgroup / metrics-server |
| **IDR-RAM** | (RAM_bajo_ataque − RAM_baseline) / RAM_baseline del AMF | adimensional | cgroup / metrics-server |
| **IDR-RTT** | (RTT_N2_bajo_ataque − RTT_N2_baseline) / RTT_N2_baseline | adimensional | sctping / setup de asociación |
| **OVERHEAD-L7** | latencia_SBI(C3) − latencia_SBI(C2), por petición de discovery | ms | curl `time_total` (script corregido) |
| **TATTACH** | tiempo de registro 5G completo (Registration→PDU Session) | ms | UERANSIM (timestamp attach) |
| **PDR** | packet delivery ratio del plano de usuario bajo ataque | % | iperf/ping sobre `uesimtun0` |

> Define cada símbolo UNA vez aquí y úsalo igual en toda la tesis. Elimina
> "TBANA/TBOC" si no tienen fórmula; si los conservas, defínelos aquí.

### 2.3 Controladas (constantes del SUT) y covariables
- **Constantes:** versiones del stack (pinneadas, `bootstrap/versions.env`), PLMN
  999/70, 1 suscriptor, rol del SCP como broker (Model D, TS 23.501 §6.3),
  hardware del hipervisor.
- **Covariables a registrar** (para control estadístico, RM-19): carga del host
  (load average), hora de la corrida, número de bloque, temperatura si disponible.

---

## 3. Modelo de amenaza (corrige RM-05, da rigor)

### 3.1 Taxonomía y mapeo
Cada vector se mapea a **MITRE FiGHT** y a la guía **NSA/CISA — Prevent and
Detect Lateral Movement**:

| Vector | Descripción | Adversario | MITRE FiGHT (ejemplo) |
|---|---|---|---|
| A1 | Movimiento lateral este-oeste RAN→CP | Externo en 5g-ran (sin credenciales) | Lateral Movement |
| A2 | CRUD no autenticado sobre NRF (externo) | Externo | Resource/Discovery, SBI abuse |
| A2′ | CRUD interno sin identidad de workload | Interno, pod sin label (pipeline CI/CD) | Impersonation |
| A2″ | Abuso de privilegios con identidad legítima | Interno, NF legítima comprometida, sin rol SCP | Privilege abuse |
| A3 | Flood N2/SCTP contra el AMF | Externo en 5g-ran | Network DoS |

Respaldo de realismo (threat model, no related work): **CVE-2026-55068** (registro
NRF no autenticado → A2/A2′), **CVE-2025-63288** (AMF NGSetupRequest DoS → A3).

### 3.2 Supuesto de identidad y control de admisión [DECISIÓN]
El adversario de A2′ "controla el pipeline que despliega en 5g-cp". Si eso incluye
fijar labels, el label de C2 es forjable (RM-05). **Dos opciones, elige y
decláralo:**

- **Opción A (mínima, honesta):** acotar el adversario de A2′ a "controla la red /
  despliega cargas pero **no** puede fijar labels de identidad reservados" (p. ej.
  porque el pipeline legítimo los inyecta vía un paso firmado). Declarar la
  limitación.
- **Opción B (recomendada, cierra la brecha y es novedad):** añadir una
  `ValidatingAdmissionPolicy` / Kyverno / OPA-Gatekeeper que **rechace** crear
  pods en 5g-cp con `cib46-nf-type=core-nf` salvo desde un ServiceAccount
  autorizado. Entonces el label deja de ser forjable y C2 gana solidez. Es
  automatizable y medible (añade un vector A2‴: "impostor que intenta ponerse el
  label" → bloqueado en admission).

---

## 4. Diseño experimental (corrige RM-19)

- **Tipo:** cuasi-experimental intra-sujeto, 4 condiciones, con **repeticiones en
  bloques**.
- **Bloques y aleatorización:** ejecutar **B ≥ 5 bloques**. Dentro de cada bloque,
  recorrer las 4 condiciones en **orden aleatorizado** (contrabalanceo), no siempre
  C0→C3. Registrar el orden y el bloque como factores.
- **Reset a estado limpio entre condiciones** (idempotente): registro NF vacío,
  suscriptor reinsertado, esperar a `Ready` de las 9 NF, verificar baseline. Script
  dedicado (extender `bootstrap/`), y **loguear el estado inicial** de cada corrida.
- **Unidad de análisis:** para métricas continuas con muestreo autocorrelacionado
  (IDR), la unidad es **la media por run**, no cada muestra (evita pseudo-replicación,
  RM-08).

---

## 4-bis. Escenario y topología experimental (infraestructura)

> Responde a dos dudas: *(i)* ¿VMs o "un clúster"? y *(ii)* ¿qué modela realmente
> el testbed? Corrige RM-22 (declaración de entorno) y refuerza la validez.

### 4b.1 "Clúster" vs "VMs": es lo mismo, lo que cambia es de qué están hechos los nodos
Un clúster de Kubernetes **está hecho de nodos**, y un nodo es una VM o una máquina
bare-metal. Tus **3 VMs = un clúster de 3 nodos**. El multinodo **no es opcional**
aquí: tus hallazgos H26/H28 son sobre propagación de **identidad eBPF *entre
nodos*** (ipcache). Un solo nodo escondería esa clase de efectos. Espectro de lo
que hace la literatura (de tu propio corpus):

| Opción | Ejemplos | Fidelidad | Cuándo usarla |
|---|---|---|---|
| 1 host + Docker/Compose | 5GC-SDP, eBPF-vuln (IIT Jammu) | Baja (sin cross-node) | prototipado funcional rápido |
| **K8s sobre VMs** (VMware/KVM/ESXi) | 5GLatte, **tú (v1)** | Media | claims de **seguridad** (¿bloquea?) |
| **K8s bare-metal** (testbed compartido) | Sidecarless mesh (Chameleon) | Alta | claims de **rendimiento/IDR/latencia** |
| VMs cloud | PoCs Nokia/Ericsson | Alta | escala / disponibilidad |

**[DECISIÓN] Recomendación para ti (estás en Francia):**
- Para **H1–H3 (cobertura/bloqueo)** → tus **3 VMs bastan** (incluso k3d multinodo).
- Para **H4 (OVERHEAD-L7) y H5 (IDR)** → migra a **bare-metal multinodo en un
  testbed nacional francés**: **Grid'5000** (bare-metal reservable, gratis para
  investigación) o **SLICES-FR / FIT (R2lab)**. Quita el ruido del hipervisor
  tipo-2 y es mucho más defendible. Confírmalo con tu laboratorio (Télécom Paris
  participa). Si no hay acceso, las VMs son válidas: **decláralo** como limitación.

### 4b.2 Distribución y nodos (declarar para reproducibilidad)
- **SO:** Ubuntu 22.04 LTS — correcto (SO de referencia de Open5GS; compila
  UERANSIM; kernel 5.15 soporta eBPF/Cilium 1.15 y el módulo **SCTP** de N2).
  **Declara la versión de kernel** (y si usaste HWE). No cambies de distro.
- **Rellena esta tabla** (hoy el README no da specs → no es reproducible):

| Nodo | Rol | vCPU | RAM | Kernel | Namespaces / NFs alojados |
|---|---|---|---|---|---|
| master | control-plane k3s, SPIRE server | ? | ? | ? | — |
| worker1 | worker | ? | ? | ? | 5g-cp (parte de las 9 NFs) |
| worker2 | worker, N2/Multus | ? | ? | ? | 5g-ran (gNB), resto 5g-cp |

> Referencia: THAALOUB usó ~7 vCPU / 25 GB para un stack similar (Open5GS+OAI +
> Cilium+Istio+SPIRE). Dimensiona para que el **host no sea el cuello de botella**.

### 4b.3 Colocación de pods (controlar, no dejar al azar)
- **Fija la colocación** con `nodeSelector`/affinity y **documéntala**: qué NF en
  qué nodo, idéntico en todas las corridas.
- **Atacante en un nodo DISTINTO del NRF/AMF.** Así A1/A2′ atraviesan el camino
  **cross-node** (el caso difícil para el defensor y el que de verdad valida la
  identidad eBPF). Si atacante y víctima caen en el mismo nodo, el tráfico va por
  fast-path intra-nodo y el resultado **no significa lo mismo** → regístralo como
  parte del diseño, no como accidente.

### 4b.4 Control del ruido de medición
- Hipervisor tipo-2 (VMware Workstation) añade ruido a IDR/latencia → **CPU pinning**
  si puedes, **nada más corriendo en el host** durante las corridas, y registra la
  **carga del host** como covariable (RM-19). En bare-metal (Grid'5000) este
  problema desaparece.
- **NTP/chrony** sincronizado entre nodos (RM-24); módulo **SCTP** cargado y
  persistente; NAD de Multus versionado (RM-25).

### 4b.5 Qué modela el testbed (y qué no) — private vs public 5G
El escenario es una **red privada 5G industrial (SNPN)**, no una pública. Diferencias
que **justifican** tu testbed y tu modelo de amenaza:

| Dimensión | 5G pública (telco) | **Private/industrial 5G (tu objeto)** |
|---|---|---|
| Frontera de confianza | Operador telco, endurecido | La **empresa** opera el core; menos madurez; comparte infra con OT/IT |
| Core | Propietario (Ericsson/Nokia) | **Open-source on-premise** (Open5GS/free5GC) ✔ como el tuyo |
| Escala / tenancy | Masivo, multi-tenant | **Pequeño, 1/pocos tenants** ✔ tu 1 suscriptor es abstracción razonable |
| Amenaza dominante | Externa, señalización inter-operador | **Interna / OT / supply-chain (CI/CD)** ✔ tus A2′/A2″ |
| Despliegue | Centralizado | **Edge/on-prem, URLLC local-breakout** ✔ tu argumento de OVERHEAD-L7 |

→ El reencuadre **hace tu testbed MÁS válido**, no menos: un core open-source,
single-tenant, con atacante interno, es una red privada, no una pública. La
**minería peruana es un vertical** (como puertos, fábricas, energía); el aporte
transfiere por mecanismo, no por datos de Perú (resuelve RM-09 y tu restricción de
recolectar datos desde Francia: el testbed genera sus propios datos).

---

## 5. Tamaño de muestra y potencia (corrige RM-06)

Antes de recolectar:

1. **Métricas continuas (OVERHEAD-L7, IDR).** Fijar potencia 0.80, α=0.05 y el
   **tamaño de efecto mínimo de interés** (p. ej. una diferencia de latencia de
   0.5 ms, o d≈0.8). Calcular n con `statsmodels.stats.power`
   (`TTestIndPower().solve_power`), y añadir ~15 % por usar prueba no paramétrica.
   Resultado esperado: **n ≥ 30 mediciones por condición** como piso.
2. **Tasas de bloqueo (TBLOQ).** Repetir cada vector **R ≥ 30 veces** (no 4). Cada
   repetición = las 4 operaciones CRUD. Reportar proporción con **IC de Wilson**.
3. **A3 (IDR).** B bloques × 5 runs (A–E) con muestreo según §6.4; la media por run
   es la observación.

Documentar el cálculo de n en el anexo (reproducible, `bootstrap/analysis/`).

---

## 6. Instrumentación y medición

### 6.1 Disponibilidad del plano de control (corrige RM-01)
Tras **cada** condición: `bootstrap/checks/smoke-control-plane.sh` →
(1) re-registro 5G del UE (attach completo), (2) discovery SBI legítimo AMF→NRF
(debe responder 2xx en C1–C3). Métrica de "no falso positivo" = **TATTACH** y éxito
de attach, **no** ICMP a Internet. Usar destino **interno** del testbed, no 8.8.8.8
(coherencia con el aislamiento declarado).

### 6.2 Latencia SBI / OVERHEAD-L7 (corrige RM-02)
`bootstrap/checks/measure_sbi_latency_fixed.sh` (URL entrecomillada, warm-up
descartado, sin `bc`). N≥30 por condición, 5 de warm-up. **Re-medir** C2 y C3.

### 6.3 Evidencia de bloqueo (corrige RM-11)
Captura **estructurada** de Hubble en JSON (`hubble observe -o jsonpb`) sincronizada
con cada vector (`bootstrap/run-experiment.sh`). TBLOQ se calcula de los verdicts
`DROPPED/FORWARDED`, no de texto libre.

### 6.4 Flood A3 (corrige RM-20/21)
- **Caracterizar el generador antes** del experimento: conexiones/s sostenidas,
  OK/FAIL por run; si el cliente es el cuello de botella (GIL, 1 pod), usar
  multiproceso o varios pods hasta garantizar que el AMF es el limitante.
- **Muestrear mientras el flood viva** (`while kill -0 $PID`), con fase pre/durante/
  post; reportar pico y recuperación.
- Muestreo de recursos a intervalo **≥ resolución del backend** (metrics-server
  15 s) o leer cgroup directo con delta temporal (mayor resolución).

### 6.5 Tráfico de fondo (corrige RM-09, refuerza validez externa) [DECISIÓN]
Añadir **N UEs** y tráfico N3 sostenido durante las mediciones de IDR/latencia,
para medir bajo carga realista (private/industrial 5G), no en vacío. Reportar con y
sin carga de fondo.

---

## 7. Plan de análisis estadístico (pre-especificado; corrige RM-03/04/07/08)

**Decisión a priori:** usar **pruebas de rango** en todas las métricas continuas
(justificado por n moderado y no-normalidad esperada). No se usa *d* de Cohen.

Por cada métrica continua y conjunto de 4 condiciones:
1. **Descriptivos:** mediana, IQR, P95, P99 (y media/DE como complemento).
2. **Ómnibus:** **Kruskal-Wallis** sobre los 4 grupos
   (`bootstrap/analysis/omnibus_posthoc.py`).
3. **Post-hoc** (si ómnibus significativo): **Dunn** con corrección **Holm o
   Benjamini-Hochberg (FDR)**; reportar **todas** las comparaciones relevantes,
   **incluida C0 vs C3** (efecto total).
4. **Tamaño de efecto:** **rank-biserial** (+ Cliff's delta)
   (`bootstrap/analysis/effect_sizes.py`).
5. **Intervalos de confianza 95 %** (bootstrap) de la diferencia de medianas.

Para **TBLOQ** (binaria): proporción por condición + **IC de Wilson**; comparación
entre condiciones con test de proporciones. Los resultados deterministas (100 %→0 %)
se reportan como tales, no como inferencia.

Normalidad: Shapiro-Wilk es informativo solo con n suficiente; no se usa para
decidir la prueba (decisión ya tomada a priori). Independencia: media por run como
unidad (RM-08).

---

## 8. Amenazas a la validez (declaración explícita)

- **Constructo:** "identidad de workload" = atributo verificado por dataplane, no
  criptográfico (mitigado con §3.2 opción B). Métricas con fórmula (§2.2).
- **Interna:** orden/arrastre → bloques aleatorizados + reset (§4); generador como
  posible limitante → caracterización (§6.4).
- **Externa:** 1 testbed, 1 hipervisor → los **valores absolutos** son específicos;
  lo transferible son las **diferencias relativas** entre condiciones. El objeto es
  **private/industrial 5G (SNPN)**, no pública (§4b.5): el testbed open-source,
  single-tenant y con atacante interno **modela una red privada**, lo que refuerza
  la validez. Carga de fondo (§6.5) acerca a operación realista. El gancho "minería"
  es un **vertical/motivación**, no población estadística (RM-09). Migrar a
  bare-metal (Grid'5000/SLICES, §4b.1) eleva la fidelidad de los valores absolutos.
- **Conclusión estadística:** potencia a priori (§5), corrección múltiple (§7).

---

## 9. Gestión de datos y reproducibilidad (corrige RM-16)

- Datos crudos: fuera del repo (IPs internas) **pero** se publican los
  **consolidados anonimizados** (`data/*.csv`) + figuras + un `data/README.md` con
  el esquema. Idealmente release con **DOI (Zenodo)** citable.
- Pipeline reproducible: `bootstrap/bootstrap.sh` (despliegue) →
  `bootstrap/run-experiment.sh` (recolección) → `bootstrap/analysis/` (estadística).
- Imágenes pinneadas por digest (RM-12); MongoDB con PVC/Job idempotente (RM-23);
  NTP/chrony declarado (RM-24); NAD de Multus versionado (RM-25).

---

## 10. Ética
Entorno virtualizado aislado (sin producción ni terceros), software open-source,
PLMN de rango reservado. Los vectores de ataque se ejecutan solo contra el propio
testbed. Divulgación responsable si se hallan vulnerabilidades nuevas.

---

## 11. Fases de ejecución (checklist)

1. **Preparación.** Fijar hipótesis, métricas, n (potencia), plan estadístico →
   *congelar este protocolo* (preregistro).
2. **Despliegue.** `make up`; validar baseline C0 con `make smoke C=C0`.
3. **[DECISIÓN] Admission control** (§3.2 B) y **tráfico de fondo** (§6.5) si se
   adoptan.
4. **Caracterización** del generador A3 (§6.4).
5. **Corridas.** B≥5 bloques, orden aleatorizado, reset entre condiciones, captura
   Hubble + IDR + latencia + attach; loguear covariables.
6. **Consolidación.** Parseo (`data-processing/`) → CSV anonimizados.
7. **Análisis.** Kruskal-Wallis + Dunn/FDR + rank-biserial + IC; Wilson para TBLOQ.
8. **Redacción.** Resultados con IC y tamaños de efecto; limitaciones (§8);
   related work (`docs/related-work-y-gaps.md`, incluye Télécom Paris).
9. **Publicación.** Dataset + DOI; repo con `bootstrap/`.

---

*Este protocolo convierte las observaciones de `revision-metodologica.md` en un
diseño ejecutable. Léelo junto a `guia-reproducibilidad.md` (cómo) y
`paper-posicionamiento.md` (cómo contarlo).*
