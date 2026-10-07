# CIB46 — Evaluación de una Arquitectura Zero Trust sobre la Seguridad del Núcleo 5G SA Cloud-Native en Redes Privadas Mineras en Perú, 2026

Repositorio de código, manifiestos y scripts del testbed experimental utilizado en el
trabajo de investigación para optar el grado de Bachiller en Ingeniería de
Telecomunicaciones (UNI-FIEE).

**Autor:** Bryan Alejandro Cucho Suyo
**Asesor metodológico:** MSc. Alfredo Efrain Rodríguez Espinoza
**Asesor técnico:** Mg. Ing. Renzo Hurtado Garrafa

## Stack tecnológico

| Componente | Versión |
|---|---|
| k3s (Kubernetes) | v1.28.5 |
| Open5GS | v2.7 (lab v2: 2.7.5, chart Gradiant 2.3.4) |
| Cilium (CNI) | v1.15.4 |
| UERANSIM | v3.2.6 |
| SPIRE | v1.9.0 (opcional, sin enforcement) |

**Montar el lab desde VMs vacías:** [`docs/guia-lab-desde-cero.md`](docs/guia-lab-desde-cero.md)

## Estructura del repositorio

```
.
├── ansible/             # Despliegue declarativo con Ansible (recomendado) + guía desde cero
├── bootstrap/           # Despliegue con bash (respaldo), checks y análisis estadístico
├── cilium-policies/     # CiliumNetworkPolicy por condición + overlays Kustomize (conditions/)
├── helm-values/         # values.yaml del chart Open5GS (Gradiant)
├── attack-scripts/      # Scripts de ejecución de los vectores A1, A2, A2', A2'', A3
├── spire-config/         # Configuración de SPIRE Server y Agent
├── monitoring/          # Consultas de monitoreo de recursos del AMF
├── data-processing/     # Scripts Python de procesamiento estadístico
├── ueransim-config/     # Configuración de UERANSIM (gNB y UEs)
└── docs/                # Metodología, reproducibilidad, related work, revisión
```

## Despliegue automatizado

Dos caminos equivalentes (versiones fijadas, idempotentes):

| Camino | Comando | Para |
|---|---|---|
| **Ansible** (declarativo, recomendado) | `cd ansible && ansible-playbook site.yml` | calidad-paper; ver `ansible/README-ansible.md` (desde cero) |
| **Bash** (imperativo, respaldo) | `make up` | prototipado rápido; ver `docs/guia-reproducibilidad.md` |

Reproducibilidad del artefacto y pasos extremo a extremo: `REPRODUCIBILITY.md`.

## Condiciones experimentales

| Condición | Descripción |
|---|---|
| C0 | Sin controles ZTA activos (baseline) |
| C1 | Microsegmentación L3/L4 con Cilium |
| C2 | C1 + identidad de workload eBPF |
| C3 | C2 + autorización L7 por rol (SCP) |

El paso entre condiciones es declarativo (`kubectl apply` / `kubectl delete`), sin
redespliegue del clúster ni alteración del plano de datos.

## Reproducibilidad

Todo el software utilizado es de código abierto (Apache 2.0, BSD, MIT). El testbed se
ejecutó en un entorno virtualizado (VMware Workstation) con tres máquinas virtuales
Ubuntu 22.04 LTS, sin conectividad con redes en producción ni infraestructura de
terceros.

## Licencia

Este repositorio se distribuye con fines de verificación y reproducibilidad académica,
en conformidad con el principio de transparencia declarado en el capítulo de
responsabilidad ética de la investigación.
