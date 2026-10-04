# Guía de reproducibilidad — recrear el testbed CIB46 desde cero

Guía **automatizada** para levantar el testbed completo (núcleo 5G SA + ZTA con
Cilium) desde tres VMs Ubuntu limpias, ejecutar el experimento por condiciones y
procesar los datos. Todo el paso a paso está encapsulado en scripts idempotentes
bajo `bootstrap/` y en un `Makefile`; esta guía explica el porqué y el orden.

> **Convención:** cualquier valor marcado como `AJUSTAR` en `bootstrap/versions.env`
> o en los manifiestos depende de *tu* infraestructura (interfaces de red,
> versión exacta del chart, IPs). Revísalos antes del primer despliegue.

---

## 0. Qué añade esta capa frente al repo original

El repositorio original traía los **artefactos** (políticas Cilium, scripts de
ataque, configs, procesamiento) pero **no la capa de instalación** (k3s, Cilium,
Multus, metrics-server, SPIRE como manifiestos, el NAD de Multus) ni un
orquestador. Sin eso, "reproducir desde cero" exigía reconstruir todo a mano —el
mayor riesgo de irreproducibilidad. Esta capa cierra esa brecha:

```
bootstrap/
├── versions.env            # versiones y parámetros (fuente única de verdad)
├── lib.sh                  # utilidades (logging, waits idempotentes)
├── 00-prereqs.sh           # verifica kernel/SCTP/bpffs del host
├── 10-k3s.sh               # k3s sin CNI ni kube-proxy
├── 20-cilium.sh            # Cilium 1.15.4 (KPR + L7 + SCTP + Hubble)
├── 30-multus.sh            # Multus + NetworkAttachmentDefinition N2 (RM-25)
├── 40-metrics-server.sh    # metrics-server (kubectl top; IDR)
├── 50-namespaces.sh        # 5g-cp / 5g-ran / 5g-up
├── 60-open5gs.sh           # Open5GS vía Helm (helm-values del repo)
├── 70-subscribers.sh       # inserta suscriptor (envuelve insert-subscribers.sh)
├── 80-spire.sh             # SPIRE (por trazabilidad; sin enforcement)
├── 90-ueransim.sh          # gNB + UE (monta ueransim-config del repo)
├── bootstrap.sh            # orquestador idempotente de 00..90 + C0
├── run-experiment.sh       # recolección reproducible (Hubble + IDR) (RM-11/21)
├── manifests/              # spire.yaml, ueransim.yaml (+ NAD inline)
├── checks/
│   ├── smoke-control-plane.sh        # prueba de humo del plano de control (RM-01)
│   └── measure_sbi_latency_fixed.sh  # latencia SBI corregida (RM-02)
└── analysis/
    ├── effect_sizes.py               # tamaños de efecto por rangos (RM-03)
    └── omnibus_posthoc.py            # Kruskal-Wallis + Dunn + FDR + IC (RM-07)
```

Todos los scripts pasan `bash -n` / `py_compile` y son **idempotentes**:
re-ejecutarlos no duplica recursos (usan `helm upgrade --install`,
`kubectl apply`, `create ... --dry-run | apply`).

---

## 1. Requisitos previos

- 3 VMs Ubuntu 22.04 LTS (1 master + 2 workers) o, para pruebas, 1 nodo.
- Salida a Internet para descargar imágenes/charts (o un registry espejo).
- En el master: `helm`, `curl`, `kubectl` (k3s lo instala).
- Módulo `sctp` cargado y persistente (para N2 y el vector A3):
  ```bash
  sudo modprobe sctp && echo sctp | sudo tee /etc/modules-load.d/sctp.conf
  ```

Verifica con:
```bash
make prereqs        # == bash bootstrap/00-prereqs.sh
```

---

## 2. Despliegue desde cero (un comando)

```bash
# En el nodo master, desde la raíz del repo:
make up             # k3s -> Cilium -> Multus -> metrics -> ns -> Open5GS ->
                    # suscriptor -> SPIRE -> UERANSIM -> condición C0
```

Si algo falla a mitad, reanuda desde un paso concreto sin rehacer lo anterior:
```bash
bash bootstrap/bootstrap.sh --from 60      # reanuda en Open5GS
bash bootstrap/bootstrap.sh --skip-spire   # SPIRE es opcional (no afecta C0-C3)
```

Estado del testbed en cualquier momento:
```bash
make status
```

### Puntos que casi siempre requieren AJUSTE
1. **`versions.env` → `K8S_API_HOST`**: IP del master (Cilium KPR la necesita).
2. **`versions.env` → `OPEN5GS_CHART_VERSION`**: fija la versión del chart
   `towards5gs-helm` que corresponde a **Open5GS 2.7** en tu despliegue.
3. **`bootstrap/30-multus.sh` → `master: eth1`**: la interfaz física de tus
   workers que da a la red N2 `10.10.0.0/24`.
4. **Imágenes UERANSIM/netshoot**: pinnéalas por *digest* (RM-12).

---

## 3. Ejecución del experimento por condiciones

El diseño es incremental: se parte de C0 y se **añade** un control por condición,
sin redesplegar. Las transiciones ya existían en el repo:

```bash
make c0   # baseline (allow-all anchor)
make c1   # + microsegmentación L3/L4
make c2   # + identidad de workload (label eBPF)
make c3   # + autorización L7 por rol (Envoy)
```

### 3.1 Verificar disponibilidad SIN falsos positivos (RM-01)
Tras cada condición, en vez del `ping 8.8.8.8` (que solo prueba el plano de
usuario), ejecuta la prueba que **sí** atraviesa el plano de control:

```bash
make smoke C=C1        # re-registro 5G del UE + discovery SBI AMF->NRF
```
Reporta `attach_exitoso`, `tiempo_attach_s` y `sbi_discovery_http`. En C1-C3 el
attach y el discovery legítimo deben seguir funcionando; si no, la política
introdujo un falso positivo.

### 3.2 Recolección reproducible de datos (RM-11 / RM-21)
`run-experiment.sh` rodea cada vector con captura estructurada de Hubble
(evidencia objetiva de `DROPPED`/`FORWARDED`) y, para A3, muestreo del AMF
**mientras el flood vive**:

```bash
# Vector A3 (flujo N2/SCTP) en C1, muestreando el IDR sincronizado:
kubectl cp attack-scripts/sctp_flood.py 5g-ran/attacker-ue-lateral:/tmp/sctp_flood.py
AMF_IP=<ip-del-pod-amf> bash bootstrap/run-experiment.sh C1 a3

# Vectores CRUD (A2'/A2'') con captura Hubble:
SMF_UUID=<uuid> bash bootstrap/run-experiment.sh C2 a2p C2
```
Artefactos por corrida en `results/<cond>/<vector>/`: `*.meta.json` (qué/cuándo/
git SHA), `hubble_*.jsonl`, log del ataque y, para A3, `amf_top_*.csv` con fase
`pre/durante/post`.

> Los `results/` heredan la exclusión de `.gitignore`. Para publicar (RM-16),
> genera versiones **anonimizadas** y muévelas a `data/` (ver §5).

---

## 4. Procesamiento estadístico (corrige RM-02/03/04/07/08)

### 4.1 Latencia SBI corregida (OVERHEAD-L7)
El script original de latencia tenía un bug de shell (`&` sin comillas) que
probablemente invalidó los números. Re-mide con la versión corregida:

```bash
for c in C2 C3; do
  make $c
  bash bootstrap/checks/measure_sbi_latency_fixed.sh lat_$c.csv 50 $c 5
done
head -1 lat_C2.csv > latencia_todas.csv && tail -n +2 -q lat_C*.csv >> latencia_todas.csv
```

### 4.2 Ómnibus + post-hoc con corrección e intervalos de confianza
En vez de comparar solo pares adyacentes con *d* de Cohen, usa:

```bash
# Kruskal-Wallis (4 grupos) -> Dunn con Holm/FDR -> rank-biserial + IC95%:
make analyze-latency CSV=latencia_todas.csv
# o directamente, para cualquier métrica continua (p. ej. IDR-CPU):
python3 bootstrap/analysis/omnibus_posthoc.py idr_cpu.csv cpu_millicores condicion --correction fdr_bh
```

Tamaños de efecto congruentes con Mann-Whitney (para reemplazar la *d* de
Cohen del script original):
```bash
python3 bootstrap/analysis/effect_sizes.py latencia_todas.csv latency_ms condicion
```

> El script original `data-processing/statistical_analysis.py` se conserva; estos
> módulos lo **complementan/corrigen**. Decide *a priori* usar siempre pruebas de
> rango (defendible con n pequeño) y alinea el texto de la tesis (RM-04).

### 4.3 Bloqueo por condición con IC de proporción
Para "tasa de bloqueo" no reportes un porcentaje sobre 4 intentos: repite cada
vector ≥30 veces y usa el conteo de `DROPPED`/total de Hubble con IC de Wilson
(cualquier `statsmodels.stats.proportion.proportion_confint(count, n, method="wilson")`).

---

## 5. Publicación de datos para verificación (RM-16)

Para respaldar la afirmación de transparencia, publica los **consolidados
anonimizados** (no los crudos):

```bash
mkdir -p data
# Anonimiza IPs privadas de los consolidados antes de versionarlos:
sed -E 's/10\.(244|10)\.[0-9]+\.[0-9]+/10.x.x.x/g' a3_consolidado.csv > data/a3_consolidado.csv
# Documenta el esquema en data/README.md y, si puedes, crea un release/Zenodo (DOI).
```

Los CSV consolidados (códigos HTTP, millicores, latencias) no contienen PII ni
topología sensible, así que son seguros de publicar tras anonimizar rangos.

---

## 6. Limpieza / reinicio

```bash
# Reinicio a estado limpio conocido entre bloques (RM-19):
make c0                       # vuelve a baseline
make smoke C=C0               # verifica plano de control
# Desinstalar todo el clúster:
/usr/local/bin/k3s-uninstall.sh    # (destruye el nodo k3s por completo)
```

---

## 7. Checklist de reproducibilidad (para el anexo de la tesis)

- [ ] `versions.env` refleja las versiones exactas usadas (chart Open5GS incluido).
- [ ] Imágenes pinneadas por digest (sin `:latest`).
- [ ] NAD de Multus y exposición de N2 documentados y versionados.
- [ ] Suscriptor reinsertado automáticamente (o MongoDB con PVC).
- [ ] Prueba de humo del plano de control (no ICMP) tras cada condición.
- [ ] Latencia re-medida con el script corregido (si el bug afectó los datos).
- [ ] Análisis: Kruskal-Wallis + Dunn (Holm/FDR) + efecto por rangos + IC95%.
- [ ] n ≥ 30 por condición para métricas continuas (o limitación declarada).
- [ ] Hubble capturado en JSON estructurado por corrida.
- [ ] Consolidados anonimizados publicados (idealmente con DOI).
- [ ] Glosario de métricas (IDR, OVERHEAD-L7, TBANA, TBOC) con fórmulas.

Ver `docs/revision-metodologica.md` para el detalle de cada punto (RM-xx).
