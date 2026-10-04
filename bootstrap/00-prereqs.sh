#!/usr/bin/env bash
# 00-prereqs.sh — verifica prerrequisitos del host antes de instalar nada.
# Idempotente y de solo lectura (no instala; solo comprueba y avisa).
#
# Requisitos del testbed (README): 3 VMs Ubuntu 22.04 LTS. Este script se
# ejecuta en el nodo master. Verifica kernel eBPF, herramientas y módulo SCTP.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Verificando prerrequisitos del host..."

# Herramientas cliente que necesitaremos (se instalan en pasos siguientes si
# faltan; aquí solo avisamos de las imprescindibles del sistema).
for c in curl tar sha256sum; do need "$c"; done

# Cilium en modo eBPF requiere kernel >= 5.4 (ideal >= 5.10). Ubuntu 22.04 ok.
KREL="$(uname -r)"; log "Kernel: ${KREL}"

# El vector A3 (SCTP) y el plano N2 requieren el módulo SCTP cargable.
if lsmod | grep -q '^sctp'; then
  ok "Módulo SCTP cargado."
else
  warn "Módulo SCTP no cargado. Cárgalo con: sudo modprobe sctp"
  warn "Y hazlo persistente: echo sctp | sudo tee /etc/modules-load.d/sctp.conf"
fi

# BPF filesystem montado (Cilium lo necesita; k3s/Cilium suele montarlo).
if mount | grep -q '/sys/fs/bpf'; then ok "bpffs montado."; else
  warn "bpffs no montado (Cilium lo montará; si falla: sudo mount bpffs -t bpf /sys/fs/bpf)"
fi

ok "Prerrequisitos verificados. Revisa cualquier [!] antes de continuar."
