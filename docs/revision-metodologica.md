# Revisión metodológica del testbed CIB46 (ZTA sobre núcleo 5G SA)

> Documento de revisión crítica del diseño experimental, la ejecución del plan y
> las oportunidades de mejora del trabajo *"Evaluación de una Arquitectura Zero
> Trust sobre la Seguridad del Núcleo 5G SA Cloud-Native en Redes Privadas
> Mineras en Perú, 2026"*.
>
> Alcance de esta revisión: se realizó **únicamente sobre el contenido del
> repositorio** (`cilium-policies/`, `attack-scripts/`, `monitoring/`,
> `data-processing/`, `helm-values/`, `spire-config/`, `ueransim-config/`). No
> se tuvo acceso a las bitácoras del proyecto de Claude Desktop ni a los datos
> crudos (`*.txt`, `*.csv`), que están excluidos por `.gitignore`. Donde una
> observación dependa de datos que no están en el repo, se indica explícitamente
> como *"a verificar contra bitácora"*.

---

## 0. Cómo leer este documento

Cada hallazgo tiene un identificador `RM-xx` (Revisión Metodológica), una
severidad y una acción propuesta. La severidad se define así:

| Severidad | Significado |
|---|---|
| 🔴 **Crítica** | Amenaza directa a la validez de una conclusión de la tesis. Puede invalidar un dato reportado o una prueba de hipótesis. Atender antes de la defensa. |
| 🟠 **Alta** | Debilita la fuerza de una conclusión o la reproducibilidad. Debe discutirse explícitamente en el capítulo de limitaciones. |
| 🟡 **Media** | Reduce rigor o claridad; mejora recomendada pero no invalida resultados. |
| 🔵 **Baja / Nota** | Observación de forma, estilo o buenas prácticas. |

Se organiza por **tipo de validez** (marco clásico de Shadish, Cook &
Campbell), porque es el lenguaje con el que un jurado metodológico va a atacar
la tesis, y termina con una **lista priorizada de acciones**.

---

## 1. Resumen ejecutivo

**Lo que está bien hecho** (y conviene defender con orgullo):

- El **diseño incremental aditivo** C0 → C1 → C2 → C3 es conceptualmente sólido:
  cada condición añade una sola dimensión de control (segmentación → identidad →
  autorización L7), lo que permite atribuir el cambio observado a esa dimensión.
- La **transición declarativa** entre condiciones (`kubectl apply/delete`, sin
  redespliegue) reduce el confundido por "reinstalar todo entre condiciones".
- **Honestidad metodológica ejemplar**: las limitaciones más graves (SPIRE sin
  enforcement, Cilium sin rate-limit SCTP, MongoDB efímero) están documentadas
  *en el propio código*, no escondidas. Esto es una fortaleza real de cara a un
  jurado.
- **Trazabilidad**: hallazgos numerados (H8, H9, H10, H21), versiones del stack
  pinneadas, PLMN de rango reservado (999/70), licencia y marco ético.
- Mapeo limpio **vector → hipótesis** (A1/A2 → HE1; A3 → HE2; A2'/A2'' → HE3).

**Lo que amenaza la validez** (y hay que corregir o al menos discutir):

1. 🔴 **La "prueba de humo" de disponibilidad no prueba lo que dice probar**
   (`ping 8.8.8.8` va por el plano de usuario/GTP, no por la SBI que las
   políticas restringen). → RM-01.
2. 🔴 **El script de latencia SBI tiene un bug de shell (`&` sin escapar)** que
   muy probablemente invalida los números de OVERHEAD-L7 reportados. → RM-02.
3. 🔴 **Inconsistencia estadística**: se usa Mann-Whitney (no paramétrico) pero
   se reporta *d* de Cohen (paramétrico); además el código *siempre* corre
   Mann-Whitney aunque documente lo contrario. → RM-03, RM-04.
4. 🔴 **La "identidad de workload" de C2 es un label de Kubernetes forjable**, no
   una identidad criptográfica (SPIRE no hace enforcement). Bajo el propio
   modelo de amenaza (atacante que despliega pods), la distinción C1↔C2 es
   frágil. → RM-05.
5. 🟠 **Potencia estadística**: n muy pequeños (6 muestras IDR, 4 ops CRUD),
   sin análisis de potencia, sin corrección por comparaciones múltiples,
   sin test ómnibus. → RM-06, RM-07, RM-08.
6. 🟠 **Validez externa**: nada del testbed modela "red privada minera peruana"
   más allá de la narrativa; sin tráfico de fondo, sin escala, sin IoT
   industrial. → RM-09.
7. 🟠 **HE2 es esencialmente no falsable por diseño**: se sabía de antemano que
   Cilium 1.15.4 no contiene A3, así que C0 vs C1 mide lo mismo. → RM-10.
8. 🟠 **Reproducibilidad incompleta**: falta toda la capa de instalación
   (k3s, Cilium, Multus, metrics-server, SPIRE como manifiestos, NAD de Multus)
   y los datos crudos anonimizados. → RM-11 … RM-16.

---

## 2. Validez de constructo
*(¿las variables miden realmente lo que dicen medir?)*

### RM-01 🔴 La verificación de disponibilidad no ejercita el plano que las políticas afectan
**Evidencia:** en `transition-to-c0/c1/c2/c3.sh` la única prueba de que "el core
legítimo sigue operativo" es:

```bash
kubectl exec -n 5g-ran "$UE_POD" -- ping -c 5 -I uesimtun0 8.8.8.8
# Esperado: 0% packet loss
```

**Problema:** `uesimtun0` es el túnel de datos del UE. Ese ping sale por el
**plano de usuario** (UE → gNB → UPF → N6 → Internet). Las CiliumNetworkPolicy
que introduces en C1/C2/C3 restringen la **SBI del plano de control** (puerto
7777, N2/SCTP, MongoDB). Es decir: la prueba de humo puede dar 0% de pérdida
**aunque las políticas hayan roto por completo el plano de control**, porque una
vez que la sesión PDU ya está establecida, el reenvío de datos no vuelve a tocar
la SBI. La afirmación *"no hay falsos positivos / el servicio legítimo no se
degrada"* —que es central para argumentar que ZTA es desplegable en producción—
**no está respaldada por esta prueba**.

**Además hay una contradicción de aislamiento:** el README afirma *"sin
conectividad con redes en producción ni infraestructura de terceros"*, pero la
prueba hace `ping 8.8.8.8` (DNS público de Google). O el testbed tiene salida a
Internet (y entonces la afirmación de aislamiento es falsa), o el ping falla y la
prueba de humo nunca fue válida. Hay que resolver esta inconsistencia antes de
la defensa.

**Acción propuesta:**
- Sustituir la prueba de humo por una que **ejercite el plano de control**: un
  *fresh UE registration + PDU session establishment* con UERANSIM
  (`nr-ue` reiniciado) después de aplicar cada condición, verificando que el
  attach 5G completo (Registration → Authentication → PDU Session Establishment)
  sigue funcionando. Eso sí atraviesa AMF↔AUSF↔UDM↔SMF↔NRF por SBI.
- Como métrica de "no falso positivo", medir **tasa de éxito de attach** y
  **tiempo de establecimiento de sesión PDU** por condición, no ICMP.
- Reemplazar `8.8.8.8` por una IP interna del propio testbed (p. ej. la del UPF
  o un pod eco en `5g-up`) para no contradecir el aislamiento; o documentar
  explícitamente que existe egress NAT controlado.

> Ver versión corregida propuesta en `bootstrap/checks/smoke-control-plane.sh`.

### RM-05 🔴 "Identidad de workload" está operacionalizada como un label forjable
**Evidencia:** `spire-config/server.conf` documenta que SPIRE **no ejerce
enforcement** (Open5GS 2.7 no emite SVIDs en su SBI). La "identidad" de C2 se
implementa como:

```yaml
fromEndpoints:
  - matchLabels:
      io.kubernetes.pod.namespace: 5g-cp
      cib46-nf-type: core-nf
```

y el atacante `nf-impostor` "pasa C1 y es bloqueado en C2" únicamente porque
*no* lleva el label `cib46-nf-type=core-nf`.

**Problema (construct validity):** un label de pod **no es una identidad de
workload**. Es un atributo declarativo, sin autenticación, que cualquier
principal con permiso de crear pods en `5g-cp` puede fijar arbitrariamente. Pero
el modelo de amenaza de C2 asume exactamente eso: `deploy-nf-impostor.yaml`
modela *"un pod del plano de control comprometido mediante una imagen alterada
en el pipeline CI/CD"*. Si el adversario controla el pipeline que despliega en
`5g-cp`, **también controla los labels del manifiesto**, y añadiría
`cib46-nf-type: core-nf` trivialmente, derrotando C2. La condición C2 solo bloquea
a un atacante que *elige* no ponerse el label — que es precisamente lo que hace
tu pod de prueba, por construcción.

Esto **no invalida el experimento**, pero sí redefine lo que C2 realmente
demuestra: C2 demuestra **microsegmentación basada en atributos de pod**, no
"identidad de workload de confianza cero" en el sentido de SPIFFE/mTLS. La tesis
debe ser muy precisa en este punto o el jurado lo desmontará.

**Acción propuesta (elige una, en orden de esfuerzo):**
1. **Mínima (redacción):** renombrar el constructo. C2 = *"segmentación basada en
   identidad de pod verificada por el dataplane (label + namespace + selector
   eBPF)"*. Declarar explícitamente en Limitaciones que la identidad **no es
   criptográfica** y por tanto es forjable por un adversario con control del
   plano de despliegue; argumentar que aun así eleva el listón frente a un
   atacante que solo controla la red (no el orquestador).
2. **Media (control de admisión):** añadir un `ValidatingAdmissionPolicy` /
   Kyverno / OPA-Gatekeeper que **rechace** la creación de pods en `5g-cp` con el
   label `cib46-nf-type=core-nf` salvo desde un ServiceAccount/emisor autorizado.
   Eso vuelve el label *no forjable* por el pipeline atacante y cierra la brecha
   de constructo. Es automatizable y fortalece C2 sustancialmente.
3. **Máxima (fuera de alcance realista con Open5GS 2.7):** mTLS/SPIFFE real vía
   un service mesh (Istio/Linkerd con sidecars) o esperar a una versión de
   Open5GS con soporte SPIFFE. Documentar como trabajo futuro (ya lo haces con
   H10/H21).

### RM-17 🟡 Métricas TBANA / TBOC nunca se definen
**Evidencia:** `generate_figures.py` menciona en su docstring *"TBANA/TBOC por
condición"* pero ninguna de esas siglas se define en el repositorio, ni hay
código que las calcule.

**Acción:** definir formalmente cada métrica derivada en un único glosario
(unidades, fórmula, instrumento de captura, script que la produce). Sugerido:
`docs/glosario-metricas.md`. Toda métrica citada en resultados debe tener una
fila con: nombre, símbolo, definición operacional, fuente de datos, script.

### RM-18 🟡 IDR (Índice de Degradación de Recursos) sin definición formal ni normalización
**Evidencia:** `monitor_amf_resources.sh` captura `cpu_millicores`, `ram_mib`,
`restart_count`; los comentarios hablan de "IDR-CPU/RAM/RTT" pero el índice como
tal no se calcula en ningún script. Además `restart_count` se captura pero
**RTT no se captura en ningún lado** (el script se llama "resources" y no mide
RTT de N2).

**Acción:** definir IDR con fórmula explícita (p. ej. `IDR-CPU = (CPU_bajo_ataque
- CPU_baseline) / CPU_baseline`), normalizada y adimensional, para que sea
comparable entre condiciones. Y añadir un instrumento real de RTT de N2 (p. ej.
`sctping`/latencia SCTP o el tiempo de setup de asociación), porque hoy "IDR-RTT"
no tiene fuente de datos.

---

## 3. Validez de conclusión estadística
*(¿las inferencias numéricas están bien hechas?)*

### RM-02 🔴 Bug de shell invalida la medición de latencia SBI (OVERHEAD-L7)
**Evidencia:** `monitoring/measure_sbi_latency.sh`:

```bash
LATENCY=$(kubectl exec -n 5g-cp "$AMF_POD" -- sh -c "
  curl -s --http2-prior-knowledge -o /dev/null \
    -w '%{time_total}' \
    ${NRF_URL}/nnrf-disc/v1/nf-instances?target-nf-type=SMF&requester-nf-type=AMF")
```

**Problema:** la URL contiene `&` **sin comillas ni escape** dentro del `sh -c`.
El shell interno interpreta `...target-nf-type=SMF` como un comando puesto en
**segundo plano** (`&`) y `requester-nf-type=AMF` como un **segundo comando**
(que falla con "command not found"). Consecuencias:
- `curl` corre en background; `-w '%{time_total}'` se emite de forma asíncrona y
  la captura por `$(...)` es una carrera → `LATENCY` puede quedar **vacía o
  truncada**.
- La query real que llega al NRF **no tiene** el parámetro `requester-nf-type`,
  así que ni siquiera es la petición de discovery que se pretendía medir.
- Aguas abajo, `LATENCY_MS=$(echo "$LATENCY * 1000" | bc)` recibe algo vacío →
  error de `bc` o `0`.

**Impacto:** si los números de OVERHEAD-L7 (comparación C2 vs C3, central para
HE3) provienen de este script tal cual, **son inválidos**. Esto es lo más urgente
de verificar contra tus bitácoras: revisa si los `*.csv` de latencia tienen
valores plausibles y no ceros/vacíos.

**Corrección** (URL entre comillas para que el `&` sea literal):

```bash
LATENCY=$(kubectl exec -n 5g-cp "$AMF_POD" -- sh -c '
  curl -s --http2-prior-knowledge -o /dev/null -w "%{time_total}" \
    "http://open5gs-cp-nrf-sbi.5g-cp.svc.cluster.local:7777/nnrf-disc/v1/nf-instances?target-nf-type=SMF&requester-nf-type=AMF"')
```

> Versión corregida y endurecida en `bootstrap/checks/measure_sbi_latency_fixed.sh`
> (comillas, descarte de warm-up, sin dependencia de `bc`, unidades explícitas).
> **No sobrescribe tu script original**, para preservar la trazabilidad de lo ya
> ejecutado.

### RM-03 🔴 *d* de Cohen sobre datos no normales, junto a Mann-Whitney
**Evidencia:** `statistical_analysis.py::compare_conditions` corre Shapiro-Wilk,
luego Mann-Whitney U (no paramétrico, correcto para no normalidad) **y además**
reporta `cohens_d`. La *d* de Cohen asume distribuciones aproximadamente normales
y homocedasticidad; usarla como tamaño de efecto *justo cuando eliges Mann-Whitney
por no cumplir normalidad* es contradictorio y un jurado estadístico lo señalará.

**Acción:** reportar un **tamaño de efecto congruente con la prueba de rango**:
- **Correlación rango-biserial** `r = 1 − 2U/(n1·n2)` (derivable directo del U
  que ya calculas), o
- **Delta de Cliff**, o
- El **effect size del lenguaje común / AUC** = `U/(n1·n2)`.

> Implementación lista en `bootstrap/analysis/effect_sizes.py`.

### RM-04 🔴 La lógica de selección de prueba documentada no está implementada
**Evidencia:** el docstring dice *"Mann-Whitney U … aplicada cuando no se cumple
el supuesto de normalidad"*, pero el código calcula `normal_a`/`normal_b` y
**nunca los usa**: siempre ejecuta Mann-Whitney, pasen o no la normalidad.

**Problema:** discrepancia entre método documentado y método ejecutado. Si en la
tesis escribiste *"se usó t de Student cuando había normalidad y Mann-Whitney en
caso contrario"*, eso **no es lo que hizo el código**. Un revisor que lea ambos
lo detecta.

**Acción:** o bien (a) implementar de verdad la bifurcación (t de Welch si ambos
grupos son normales; Mann-Whitney si no), o (b) decidir a priori usar siempre
Mann-Whitney (defendible con n pequeño y no-normalidad esperada) y **corregir el
docstring y el texto de la tesis** para que digan eso. La opción (b) es la más
limpia con tus tamaños de muestra. Documenta la decisión *a priori*, no *post
hoc*.

### RM-06 🟠 Tamaños de muestra minúsculos, sin análisis de potencia
**Evidencia:**
- IDR: `monitor_amf_resources.sh` toma **6 muestras** por run; A2/A2' ejecutan
  **4 operaciones CRUD** una sola vez por condición.
- No hay cálculo de potencia (a priori ni post hoc), ni tamaño de muestra
  objetivo, ni justificación de por qué 6/50.

**Problema:** Mann-Whitney con n=6 vs 6 tiene potencia bajísima; un p<0.05 con
esos n es frágil y un p>0.05 es no concluyente (ausencia de evidencia ≠ evidencia
de ausencia). Y un "block rate" sobre 4 intentos solo puede tomar los valores
0/25/50/75/100 % — granularidad insuficiente para cualquier inferencia.

**Acción:**
- Para métricas continuas (CPU/RAM/latencia): **≥ 30 muestras por condición**
  como mínimo defendible; idealmente calcular n con potencia 0.8, α=0.05 y el
  tamaño de efecto mínimo de interés. `statsmodels` lo hace en 5 líneas.
- Para block rate: **repetir cada vector N veces** (p. ej. 30 repeticiones de las
  4 ops) y reportar proporción con **intervalo de confianza de Wilson**, no un
  porcentaje sobre 4.
- Si re-ejecutar todo no es viable, **declarar explícitamente la limitación de
  potencia** y presentar los resultados como *exploratorios/descriptivos*, no
  confirmatorios.

### RM-07 🟠 Comparaciones múltiples sin corrección, sin test ómnibus
**Evidencia:** `statistical_analysis.py` compara solo pares **adyacentes**
(C0-C1, C1-C2, C2-C3) y para varias métricas (CPU, RAM, RTT, latencia), cada uno
a α=0.05, **sin corregir** y **sin un test ómnibus previo**.

**Problemas:**
1. Múltiples pruebas → inflación del error tipo I. Con ~3 pares × ~4 métricas ≈
   12 pruebas, la probabilidad de ≥1 falso positivo ronda 0.46.
2. Solo comparar adyacentes deja fuera el **efecto total C0 vs C3**, que es la
   pregunta más importante (¿ZTA completo vs sin ZTA?).
3. Sin ómnibus (Kruskal-Wallis) no hay control global antes del post-hoc.

**Acción:** flujo estándar por métrica:
`Kruskal-Wallis (ómnibus, 4 grupos)` → si significativo →
`post-hoc de Dunn` con **corrección de Holm o Benjamini-Hochberg (FDR)** →
reportar **todas** las comparaciones relevantes (incluida C0-C3) con p ajustado,
tamaño de efecto rango-biserial e **IC del 95 %**.

> Implementado en `bootstrap/analysis/omnibus_posthoc.py`.

### RM-08 🟠 Shapiro-Wilk no informa con n=6; posible pseudo-replicación en IDR
**Dos cosas:**
1. Shapiro-Wilk con n≈6 tiene potencia casi nula: casi nunca rechaza, así que
   "pasó normalidad" no significa nada a ese tamaño. No bases decisiones en él a
   ese n.
2. **Pseudo-replicación:** `kubectl top` lee de metrics-server, que agrega con
   ventana/resolución ~15 s por defecto. Muestrear cada 5 s (como en A3 y en
   `monitor_amf_resources.sh`) produce **muestras autocorrelacionadas que repiten
   el mismo valor subyacente**, no observaciones independientes. Tratarlas como n
   independientes **infla artificialmente el n** y viola el supuesto de
   independencia de Mann-Whitney.

**Acción:** muestrear a un intervalo ≥ resolución del backend (≥15 s), o mejor
usar una fuente de mayor resolución (cAdvisor/`/metrics/resource`, o
`kubectl exec -- cat /sys/fs/cgroup/.../cpu.stat` con delta temporal, o Prometheus
con scrape de 1-5 s directo al cgroup). Reportar independencia o modelar la
autocorrelación (medias por run como unidad de análisis).

---

## 4. Validez interna
*(¿el cambio observado se debe a la condición y no a otra cosa?)*

### RM-19 🟠 Orden fijo de condiciones + estado acumulado (sin contrabalanceo)
**Evidencia:** las condiciones se aplican siempre en el mismo orden creciente
C0→C1→C2→C3 sobre el **mismo clúster en ejecución**, sin redespliegue. El pod
`mongodb` es `emptyDir` (efímero) y hay que reinsertar suscriptores tras cada
reinicio.

**Problemas:**
- **Efecto de orden / arrastre de estado:** caches del NRF, tablas de conexión,
  registros de NF que persisten entre condiciones, deriva térmica/carga del
  hipervisor a lo largo de la sesión. Cualquier tendencia temporal se confunde
  con "la condición".
- Sin **repeticiones intercaladas** (p. ej. C0,C1,C2,C3,C0,C1,… en varios
  bloques) no se puede separar "efecto de la condición" de "efecto del momento".

**Acción:**
- Ejecutar **varios bloques** con las condiciones **contrabalanceadas o
  aleatorizadas** dentro de cada bloque, y modelar el bloque como factor.
- Reiniciar a un **estado limpio conocido** entre condiciones (registro NF
  vacío, suscriptor reinsertado, esperar a `Ready` de todas las NF) mediante un
  script idempotente, y **loguear el estado inicial** de cada corrida.
- Registrar métricas del hipervisor (carga del host) como covariable.

### RM-20 🟡 Generador de carga A3 posiblemente limitado por el propio instrumento
**Evidencia:** `sctp_flood.py` usa threading de Python (GIL) con lotes de 200,
join sincrónico, desde **un solo pod**. Para 100 000 "conexiones" crea/une hilos
en serie por lotes.

**Problema:** no está caracterizada la **capacidad del generador**. Si el cuello
de botella es el cliente (GIL, un solo pod, un solo core), el IDR del AMF podría
reflejar el límite del atacante, no la resistencia del AMF. Además "conexiones" y
"asociaciones SCTP reales establecidas" no son lo mismo (muchas fallan en
`connect` con timeout de 2 s y se cuentan en `FAIL`).

**Acción:** caracterizar el generador (conexiones/s efectivas sostenidas) antes
del experimento; reportar `OK/FAIL` por run (ya se imprimen — asegúrate de
capturarlos en el CSV); considerar multiproceso o varios pods atacantes para
garantizar que el AMF es el limitante. Distinguir "asociaciones establecidas" de
"intentos".

### RM-21 🟡 Ventana de muestreo del flood no sincronizada con la duración del flood
**Evidencia:** en `run_a3_n2_flood.sh` se lanzan **6 muestras cada 5 s (=30 s)** y
luego `wait $FLOOD_PID`. Para runs grandes (D=50 000, E=100 000) el flood dura
mucho más de 30 s → **el muestreo termina antes que el ataque** y se pierde el
pico. Para runs pequeños (A=1 000) el flood puede terminar en <5 s → se muestrea
mayormente *post*-flood.

**Acción:** muestrear **mientras el flood viva** (bucle `while kill -0 $PID`),
con marca de fase (pre/durante/post), y reportar el pico y la recuperación, no un
número fijo de muestras.

---

## 5. Validez externa
*(¿los resultados generalizan a la población objetivo?)*

### RM-09 🟠 Brecha entre el objeto declarado (minería peruana) y el testbed
**Evidencia:** el título y la narrativa hablan de *redes privadas mineras en
Perú* y de un *"sensor industrial de galería subterránea"*, pero el testbed es un
Open5GS genérico con **1 suscriptor, 1 UE, 1 gNB, sin tráfico de fondo, sin carga
industrial (IoT/OT), sin escala, sin perfiles de tráfico mineros**.

**Problema:** la validez externa hacia la población objetivo es débil. Las
conclusiones aplican a "un núcleo 5G SA cloud-native mínimo en laboratorio", no
específicamente a una red minera. El jurado puede cuestionar la pertinencia del
marco.

**Acción (elige según tiempo):**
- **Redacción honesta:** acotar las conclusiones al testbed y argumentar
  *transferibilidad* (no generalización estadística): por qué los mecanismos
  (segmentación/identidad/RBAC L7) son agnósticos al vertical y por qué los
  vectores elegidos son representativos de amenazas OT/5G. Citar la limitación de
  escala explícitamente.
- **Refuerzo empírico (si hay tiempo):** añadir un **generador de tráfico de
  fondo** (varios UEs, tráfico N3 sostenido, señalización periódica) para que las
  mediciones de IDR/latencia ocurran bajo carga realista, no en vacío. Esto
  aumenta muchísimo la credibilidad de "el overhead de ZTA es asumible en
  operación".

### RM-22 🟡 Un solo entorno (n=1 a nivel de infraestructura)
Todo corre en una VMware con 3 VMs. No hay réplica en otro hardware/proveedor.
No es exigible replicar en cloud para una tesis de bachiller, pero **decláralo**:
los valores absolutos de IDR/latencia son específicos de este hardware; lo
transferible son las **diferencias relativas entre condiciones**, no los números
absolutos.

---

## 6. Fiabilidad e instrumentación

### RM-11 🟠 El pipeline de datos espera entradas que ningún script produce (Hubble)
**Evidencia:** `clean_and_consolidate.py` para A1 cuenta `parse_hubble_drops`
(líneas `DROPPED`). Pero **ningún script del repo captura salida de Hubble**:
`run_a1_lateral_movement.sh` solo hace `nc` y `curl`; no hay `hubble observe`.
El README menciona Hubble implícitamente pero no hay instalación ni captura.

**Problema:** hay una brecha entre recolección y análisis: la métrica principal
de A1 (drops observados en el dataplane) depende de datos que el flujo
documentado no genera. O los generabas a mano (no reproducible) o vienen de otra
parte no versionada.

**Acción:** añadir un script de captura de Hubble sincronizado con cada vector
(`hubble observe --namespace 5g-cp -f -o jsonpb > a1_hubble_<cond>.json`) y hacer
que el parser lea el JSON estructurado de Hubble (verdict `DROPPED`/`FORWARDED`),
no texto libre. Así la evidencia de bloqueo es objetiva y reproducible.
> Propuesto en `bootstrap/run-experiment.sh` (captura Hubble + attack + top en
> paralelo).

### RM-12 🟠 Imágenes sin pin de versión → no reproducible
**Evidencia:** los tres pods atacantes usan `nicolaka/netshoot:latest`.
`:latest` no es reproducible (cambia con el tiempo).

**Acción:** pinnear por **digest** (`nicolaka/netshoot@sha256:...`) o al menos por
tag de versión, y registrarlo en `bootstrap/versions.env`. Igual para cualquier
imagen del chart no fijada.

### RM-23 🟡 `emptyDir` en MongoDB introduce un paso manual frágil
El volumen efímero obliga a reinsertar suscriptores tras cada reinicio. Es una
fuente de error humano (olvidar reinsertar → attach falla → se atribuye
erróneamente a una política). Está documentado como limitación, bien; pero es
trivial de eliminar.

**Acción:** para reproducibilidad, usar un `PersistentVolumeClaim` (aunque sea
`local-path` de k3s) **o** un `initContainer`/`Job` idempotente que reinserte el
suscriptor automáticamente al arrancar el pod. Elimina un confundido operacional.
> Incluido en `bootstrap/70-subscribers.sh` como Job idempotente.

### RM-24 🟡 Sin sincronización de reloj declarada entre VMs
Timestamps en UTC (`date -u`), correcto. Pero con 3 VMs y métricas por marca de
tiempo, conviene declarar **NTP/chrony sincronizado** entre nodos; si no,
cualquier correlación temporal entre logs de nodos distintos es sospechosa.

---

## 7. Coherencia técnica de las políticas y configs

### RM-25 🟡 `gnb.yaml`: N2 sobre Multus vs resolución por DNS de servicio
**Evidencia:** `gnb.yaml` fija `ngapIp: 10.10.0.20` (red Multus 10.10.0.0/24) pero
`amfConfigs.address: open5gs-cp-amf-ngap.5g-cp.svc.cluster.local` (DNS de
ClusterIP). Mezclar la IP macvlan de Multus para el origen con un FQDN de
ClusterIP para el destino puede funcionar o no según cómo esté publicada la
interfaz N2 del AMF (¿ClusterIP SCTP? ¿segunda interfaz Multus del AMF?).

**Acción:** documentar exactamente **cómo el AMF expone N2** (¿svc ClusterIP con
`protocol: SCTP`? ¿interfaz Multus dedicada?) y verificar que la ruta 10.10.0.20 →
AMF-N2 es consistente. Incluir el `NetworkAttachmentDefinition` de Multus en el
repo (hoy no está). Sin el NAD, nadie puede recrear el plano N2.

### RM-26 🔵 C0 no es "cero políticas" sino "allow-all" — bien documentado, pero verifica equivalencia
La nota en `c0-allow-all-anchor.yaml` es correcta y honesta. Solo asegúrate de
verificar empíricamente que el datapath de "allow-all explícito" es equivalente a
"sin política" para tus métricas (en Cilium, tener una política —aunque sea
allow-all— puede cambiar el modo de un endpoint de *default-allow* a
*policy-enabled*). Un `hubble observe` mostrando `FORWARDED` para todo en C0 lo
zanja.

### RM-27 🔵 `ratelimit-n2-amf` no hace rate-limit (solo acota origen)
El nombre del archivo/política dice "ratelimit" pero, como el propio comentario
admite, **no limita tasa** (Cilium 1.15.4 no soporta rate-limit SCTP); solo
restringe el origen al namespace `5g-ran`. Renombrar a `restrict-n2-origin-amf`
para que el nombre no prometa lo que no hace (higiene, evita malentendidos del
jurado al leer los manifiestos).

### RM-28 🔵 C3: la regla 2 (discovery) es redundante con la regla 1 para el SCP y conviene documentar el orden L7
En `allow-sbi-rbac-c3.yaml`, un pod SCP hace match tanto con la Regla 1 como con
la Regla 2 (ambas exigen `core-nf`, y la 1 además `scp`). Cilium hace unión de
reglas L7 (OR), así que el SCP obtiene el superconjunto — correcto. Solo
documenta que la semántica es **aditiva (OR)**, no de precedencia, para que quede
claro por qué el `nf-compromised-legit` (core-nf, no-scp) cae en la Regla 2 y solo
lee.

---

## 8. Ética y transparencia (fortaleza, con un ajuste)

El marco ético y la transparencia son un punto fuerte. Un solo ajuste de
reproducibilidad:

### RM-16 🟠 Los datos crudos y procesados están excluidos por `.gitignore`
`.gitignore` excluye `*.txt`, `*.csv`, `*.png`. Es decir, **ningún dato del
experimento está en el repo**. La justificación ("contienen IPs internas") es
razonable para los crudos, pero:
- La **verificación independiente de los resultados es imposible** sin los datos.
  Para una tesis que invoca el "principio de transparencia", esto es una tensión.
- Las IPs internas se **anonimizan trivialmente** (sed de rangos privados) y los
  CSV consolidados (códigos HTTP, millicores, latencias) **no contienen PII ni
  topología sensible**.

**Acción:** publicar en el repo (o en un release / Zenodo con DOI) los **datasets
consolidados anonimizados** (`*_consolidado.csv`) y las **figuras finales**, con
un `data/README.md` que describa el esquema. Mantén fuera solo los crudos si
insistes, pero los consolidados deberían ser públicos para respaldar la
afirmación de reproducibilidad. Un DOI de Zenodo además es citable en la tesis.

---

## 9. Lista priorizada de acciones

### Antes de la defensa (críticas — pueden afectar datos ya reportados)
1. **RM-02** Verificar contra bitácora si el bug del `&` afectó los CSV de
   latencia. Si sí, re-medir OVERHEAD-L7 con el script corregido. *(Bloqueante
   para HE3.)*
2. **RM-01** Reemplazar/complementar la prueba de humo `ping 8.8.8.8` por un
   attach 5G completo; resolver la contradicción de aislamiento vs Internet.
3. **RM-03 / RM-04** Corregir el tamaño de efecto (rango-biserial) y alinear
   docstring↔código↔texto de la tesis sobre qué prueba se usó y por qué.
4. **RM-05** Redefinir con precisión el constructo "identidad de workload" de C2
   (label ≠ identidad criptográfica) y decidir si añades control de admisión.

### Refuerzo fuerte (altas — para el capítulo de limitaciones o re-corrida)
5. **RM-06/07/08** Aumentar n, añadir Kruskal-Wallis + post-hoc Dunn con
   corrección FDR, incluir C0 vs C3 e ICs; corregir pseudo-replicación del
   muestreo.
6. **RM-10** Reencuadrar HE2: dado que C1 no puede contener A3 por diseño,
   presentarlo como *demostración de una brecha* (Cilium no mitiga SCTP flood),
   no como prueba fallida; o añadir un control que sí pueda mitigar.
7. **RM-11** Capturar Hubble de forma estructurada y sincronizada (reproducible).
8. **RM-09** Declarar la brecha de validez externa; idealmente añadir tráfico de
   fondo.
9. **RM-16** Publicar datasets consolidados anonimizados (+ DOI).

### Higiene y reproducibilidad (medias/bajas)
10. **RM-11–15** Completar la capa de automatización desde cero (ver
    `docs/guia-reproducibilidad.md` y `bootstrap/`).
11. **RM-12/23/24** Pinnear imágenes por digest; MongoDB con PVC/Job; declarar
    NTP.
12. **RM-17/18** Glosario formal de métricas (TBANA/TBOC/IDR) con fórmulas.
13. **RM-25** Incluir el NAD de Multus y documentar la exposición de N2.
14. **RM-27** Renombrar `ratelimit-n2-amf` → `restrict-n2-origin-amf`.

---

## 10. Veredicto

**¿Se ejecutó bien el plan?** En lo conceptual y en la honestidad, **sí**: el
diseño incremental es correcto, la transición declarativa es elegante, y la
documentación de limitaciones es ejemplar. Es un trabajo de bachiller por encima
del promedio en rigor de ingeniería.

**¿Tiene deficiencias metodológicas serias?** También **sí**, y son atacables por
un jurado: la prueba de disponibilidad no prueba disponibilidad del plano de
control (RM-01), un bug puede haber invalidado la latencia (RM-02), el análisis
estadístico mezcla paradigmas y carece de potencia/corrección (RM-03/04/06/07), y
el constructo estrella "identidad de workload" es, en su implementación, un label
forjable (RM-05). Ninguna es fatal si se **corrige lo corregible y se declara con
precisión lo demás**. La diferencia entre "aprobado con observaciones" y "muy
buena tesis" está casi toda en la sección estadística y en el reencuadre honesto
de constructos.

La guía de reproducibilidad y la capa de automatización (`docs/guia-reproducibilidad.md`
+ `bootstrap/`) permiten **re-ejecutar todo desde cero** y, con ello, atender las
acciones 1–9 sin depender de configurar el clúster a mano.
