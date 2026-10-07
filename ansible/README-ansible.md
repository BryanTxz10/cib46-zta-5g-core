# Guía desde cero: desplegar el testbed con Ansible

> **Lab v2:** si partes de VMs vacías (crear VMs, red NAT, IP estática,
> clonado, SSH), usa **`docs/guia-lab-desde-cero.md`**, que cubre todo de punta
> a punta y usa este playbook. Este archivo queda como referencia de Ansible.
>
> Para alguien que **programa pero nunca usó Ansible**. Explica qué es, cómo
> instalarlo, cómo conectar las máquinas y cómo lanzar el despliegue. Sigue los
> pasos en orden.

---

## 0. La idea en 2 minutos

- **Ansible** automatiza la configuración de máquinas por **SSH**. Tú describes
  "qué quieres" en un archivo (el *playbook*) y Ansible lo consigue.
- Hay **dos papeles**:
  - **Nodo de control:** la máquina donde instalas Ansible y desde la que lanzas
    todo. Puede ser **tu laptop** o el propio **master**.
  - **Nodos gestionados:** las 3 VMs/servidores del clúster (master + 2 workers).
    En ellos **no** instalas Ansible; solo necesitan SSH y Python (ya lo traen).
- Ansible **no se instala en las 3 VMs**, solo en el nodo de control.

```
   [Nodo de control: tu laptop]  --SSH-->  master + worker1 + worker2
        (aquí va Ansible)                   (aquí NO va Ansible)
```

---

## 1. Requisitos previos

- Las **3 máquinas** ya creadas, con **Ubuntu 22.04**, encendidas y con IP
  conocidas (ej. 192.168.1.10/.11/.12).
- Un **usuario** en cada máquina con el que entres por SSH y que pueda hacer
  `sudo` (ej. `ubuntu`).
- Tu **nodo de control** con Linux o macOS (si usas Windows, usa WSL2).

---

## 2. Instalar Ansible en el NODO DE CONTROL

### Opción A — Ubuntu/Debian (o WSL2) — recomendada con pipx
```bash
sudo apt update
sudo apt install -y python3 python3-pip pipx git
pipx ensurepath
# cierra y reabre la terminal (para que tome el PATH), luego:
pipx install --include-deps ansible
```

### Opción A' — Ubuntu, más simple (del repositorio del sistema)
```bash
sudo apt update && sudo apt install -y ansible git
```

### Opción B — macOS (con Homebrew)
```bash
brew install ansible git
```

### Verifica que quedó instalado
```bash
ansible --version
```
Debe imprimir una versión (2.15 o superior idealmente). Si dice "command not
found", reabre la terminal (por el `pipx ensurepath`).

### Colecciones extra
**No necesitas ninguna.** El playbook usa solo módulos de `ansible-core`
(a propósito, para que no tengas que instalar colecciones). Si en el futuro
quieres la versión "más declarativa" con `kubernetes.core`, es opcional.

---

## 3. Preparar el acceso SSH a las 3 máquinas

Ansible entra por SSH **sin contraseña** usando una llave. Desde el nodo de
control:

```bash
# 1) Crea una llave SSH (si no tienes una). Pulsa Enter a todo.
ssh-keygen -t ed25519

# 2) Copia tu llave a cada máquina (te pedirá la contraseña una vez):
ssh-copy-id ubuntu@192.168.1.10
ssh-copy-id ubuntu@192.168.1.11
ssh-copy-id ubuntu@192.168.1.12

# 3) Prueba que entras sin contraseña:
ssh ubuntu@192.168.1.10   # debe entrar directo; luego 'exit'
```

> Si usas los servidores de Télécom Paris, pídeles el método de acceso (puede
> ser una llave ya provista o un salto por bastión); el resto es igual.

---

## 4. Traer el proyecto al nodo de control

```bash
git clone https://github.com/BryanTxz10/cib46-zta-5g-core.git
cd cib46-zta-5g-core
git checkout revision-metodologica-automatizacion
cd ansible
```

---

## 5. Decirle a Ansible cuáles son tus máquinas

Edita **`inventory/hosts.ini`** y pon tus IP y tu usuario:

```ini
[master]
node-master ansible_host=192.168.1.10 ansible_user=ubuntu

[workers]
node-worker1 ansible_host=192.168.1.11 ansible_user=ubuntu
node-worker2 ansible_host=192.168.1.12 ansible_user=ubuntu

[cluster:children]
master
workers
```

Revisa **`group_vars/all.yml`**. Con la topología de la guía de lab v2 no
hace falta cambiar nada (Multus está apagado y el chart de Open5GS ya está
fijado). Solo si activas `deploy_multus: true` tienes que poner en
`multus_master_iface` la 2.a interfaz de los workers (míralo con `ip -br a`).

---

## 6. Probar la conexión (antes de tocar nada)

```bash
ansible all -m ping
```
Debe responder `SUCCESS` / `"ping": "pong"` en las 3 máquinas. Si falla, revisa
IP, usuario y el paso 3 (SSH).

---

## 7. Lanzar el despliegue completo

```bash
ansible-playbook site.yml
```
Si tu usuario necesita contraseña para `sudo`, añade:
```bash
ansible-playbook site.yml --ask-become-pass
```

Tarda varios minutos (instala k3s, Cilium, Multus, Open5GS, etc.). Es
**idempotente**: si algo falla y lo vuelves a lanzar, retoma sin romper.

**Desplegar solo una parte** (con etiquetas):
```bash
ansible-playbook site.yml --tags k3s        # solo k3s
ansible-playbook site.yml --tags cilium      # solo Cilium
ansible-playbook site.yml --tags open5gs,subscribers
```

Saltarte SPIRE: pon `deploy_spire: false` en `group_vars/all.yml`.

---

## 8. Aplicar las condiciones experimentales (C0–C3) con Kustomize

Las condiciones son conjuntos declarativos de políticas. Necesitas `kustomize`
(o `kubectl` reciente, que lo trae). Desde la **raíz del repo, en el master**
(o donde tengas el `KUBECONFIG`):

```bash
# Transición limpia a una condición (ej. C1). kubectl ya trae kustomize:
make condition C=c1
# equivale a:
kubectl delete ciliumnetworkpolicy -A -l cib46.io/managed=true 2>/dev/null || true
kubectl kustomize --load-restrictor=LoadRestrictionsNone cilium-policies/conditions/c1 | kubectl apply -f -
```
Cambia `c1` por `c0`, `c2` o `c3`. Para **C2** recuerda el paso previo de
etiquetar las NF (`bash cilium-policies/c2/02-patch-identity-labels.sh`) o activar
el control de admisión (`bootstrap/admission/`).

> El flag `--load-restrictor=LoadRestrictionsNone` es necesario porque los
> overlays referencian los manifiestos de políticas existentes (fuera de la
> carpeta del overlay). Es un uso estándar y seguro aquí.

---

## 9. Verificar

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml   # en el master
kubectl get nodes                              # los 3 en Ready
kubectl get pods -A | grep -E '5g-|cilium|multus'
kubectl get ciliumnetworkpolicies -A
```

---

## 10. Problemas frecuentes

| Síntoma | Causa / arreglo |
|---|---|
| `ansible: command not found` | Reabre la terminal (pipx PATH) o usa la opción A'. |
| `ping` SSH falla | IP/usuario mal en `hosts.ini`, o no copiaste la llave (paso 3). |
| Pide contraseña de sudo | Añade `--ask-become-pass`. |
| Nodos en `NotReady` | Normal hasta que Cilium instala; si persiste: `kubectl -n kube-system logs ds/cilium`. |
| El plano N2 no levanta | `multus_master_iface` no coincide con la interfaz real del worker. |
| `kustomize: load restrictor` | Usa el flag `--load-restrictor=LoadRestrictionsNone` (paso 8). |
| MongoDB reinició, UE no registra | Re-ejecuta `--tags subscribers`. |

---

## 11. ¿Y si no tengo las 3 máquinas todavía?

Puedes probar el playbook contra **una sola máquina** poniéndola en `[master]`
y dejando `[workers]` vacío (será un clúster de 1 nodo). Sirve para validar que
todo instala, aunque **no** prueba el enforcement entre nodos (para eso necesitas
≥2 nodos; ver `docs/protocolo-experimental.md §4-bis`).
