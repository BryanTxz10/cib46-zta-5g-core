# Reproducibilidad del artefacto

> Qué necesitas y cómo reproduces el testbed y los experimentos de extremo a
> extremo. Pensado para revisión de artefacto (*artifact evaluation*) y para la
> defensa de la tesis.

## Insignias objetivo (artifact evaluation)
- [ ] **Disponible** — código y datos públicos con DOI (Zenodo). *(pendiente de release)*
- [ ] **Funcional** — se despliega y ejecuta con los pasos de abajo.
- [ ] **Reproducido** — un tercero obtiene los mismos resultados cualitativos
      (bloqueo 100 %→0 % por capa) y cuantitativos (overhead L7, IDR) dentro de
      intervalos de confianza.

## Requisitos
- 3 nodos Ubuntu 22.04 LTS (1 master + 2 workers), VMs o bare-metal (para
  métricas de rendimiento, preferible bare-metal; ver `docs/protocolo-experimental.md §4-bis`).
- Nodo de control con Ansible (ver `ansible/README-ansible.md`).
- Acceso SSH con sudo a los nodos; módulo del kernel `sctp`.

## Dos caminos (equivalentes)
| Camino | Cuándo | Comando |
|---|---|---|
| **Ansible** (recomendado, declarativo) | calidad-paper | `cd ansible && ansible-playbook site.yml` |
| **Bash** (respaldo, imperativo) | prototipado rápido | `make up` |

## Reproducir de principio a fin
1. **Desplegar:** `cd ansible && ansible-playbook site.yml` (o `make up`).
2. **Baseline:** aplicar C0 y validar plano de control:
   `make condition C=c0 && make smoke C=C0` (espera attach OK + SBI 200).
3. **Condiciones:** `make condition C=c1` (… c2, c3). Para C2, etiquetar NF o
   activar admisión (`bootstrap/admission/`).
4. **Experimento:** `bootstrap/run-experiment.sh <cond> <vector>` (≥5 bloques,
   orden aleatorizado, reset entre condiciones — ver protocolo).
5. **Latencia:** `bootstrap/checks/measure_sbi_latency_fixed.sh`.
6. **Análisis:** `bootstrap/analysis/omnibus_posthoc.py` y `effect_sizes.py`.

## Versiones (fijadas)
Fuente de verdad: `ansible/group_vars/all.yml` y `bootstrap/versions.env`.
k3s v1.28.5 · Cilium 1.15.4 · Multus v4.0.2 · Open5GS (chart towards5gs) ·
UERANSIM v3.2.6 · SPIRE 1.9.0.

**Pin por digest (hazlo antes del release):** sustituye los tags de imagen por
digests inmutables. Ejemplo para obtener el digest:
```bash
docker buildx imagetools inspect nicolaka/netshoot:v0.13 | grep -i digest
# luego usa  nicolaka/netshoot@sha256:<digest>  en group_vars/all.yml y en los
# manifiestos de bootstrap/manifests/ y attack-scripts/
```

## Datos
Los crudos quedan fuera del repo (IPs internas). Publica los **consolidados
anonimizados** en `data/` + un `data/README.md` con el esquema, y archiva un
**release en Zenodo** para obtener el DOI (pégalo en `CITATION.cff`).

## Cómo citar
Ver `CITATION.cff` (GitHub lo muestra como "Cite this repository").

## Mapa de documentación
- `docs/protocolo-experimental.md` — metodología correcta (qué medir y cómo).
- `docs/guia-reproducibilidad.md` — guía operativa (camino bash).
- `ansible/README-ansible.md` — despliegue con Ansible desde cero.
- `docs/revision-metodologica.md` — auditoría de la v1 (RM-01…RM-28).
- `docs/related-work-y-gaps.md` + `docs/referencias.bib` — estado del arte.
