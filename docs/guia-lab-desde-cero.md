# Guía paso a paso: levantar el lab CIB46 desde cero (lab v2)

> De **VMs vacías** a un **core 5G SA en Kubernetes con Cilium**, con el UE
> registrado y la condición **C0** verificada. Pensado para hacerlo copiando y
> pegando, sin saltarse nada.
>
> Hipervisor: **VMware Workstation Pro** (el que usaste en la tesis). Si vas a
> usar VirtualBox o un Mac con chip Apple, para en la sección 2 y revisa la
> nota del final de esa sección.
>
> Rama del repo: **`lab-v2`**. Tiempo total aproximado: 2 a 3 horas la primera
> vez (la mayor parte es esperar instalaciones y descargas).

---

## Índice

0. [Qué vas a construir](#0-qué-vas-a-construir)
1. [Requisitos de tu laptop y descargas](#1-requisitos-de-tu-laptop-y-descargas)
2. [Red de las VMs: por qué NAT y no bridge](#2-red-de-las-vms-por-qué-nat-y-no-bridge)
3. [Crear la primera VM (node-master)](#3-crear-la-primera-vm-node-master)
4. [Instalar Ubuntu Server con IP estática](#4-instalar-ubuntu-server-con-ip-estática)
5. [Configuración base del sistema](#5-configuración-base-del-sistema)
6. [Clonar la VM para los dos workers](#6-clonar-la-vm-para-los-dos-workers)
7. [Entrar por SSH desde tu laptop](#7-entrar-por-ssh-desde-tu-laptop)
8. [Preparar Ansible en el master](#8-preparar-ansible-en-el-master)
9. [Desplegar todo con un comando](#9-desplegar-todo-con-un-comando)
10. [Verificar que el core 5G funciona](#10-verificar-que-el-core-5g-funciona)
11. [Aplicar C0 y la prueba de humo](#11-aplicar-c0-y-la-prueba-de-humo)
12. [Snapshots, apagar y volver a encender](#12-snapshots-apagar-y-volver-a-encender)
13. [Problemas frecuentes](#13-problemas-frecuentes)
14. [Qué cambió en el repo (lab v2) y por qué](#14-qué-cambió-en-el-repo-lab-v2-y-por-qué)
15. [Antes de medir: revisar las políticas C1 a C3](#15-antes-de-medir-revisar-las-políticas-c1-a-c3)

---

## 0. Qué vas a construir

```
              Tu laptop con VMware Workstation
              Red VMnet8 (NAT) 192.168.100.0/24
              gateway y DNS = 192.168.100.2   ·   tu laptop = 192.168.100.1
   ┌────────────────────────┬────────────────────────┬────────────────────────┐
   │ node-master  .10       │ node-worker1  .11      │ node-worker2  .12      │
   │ k3s server + Cilium    │ k3s agent + Cilium     │ k3s agent + Cilium     │
   │ Ansible, kubectl, helm │ pods del core / RAN    │ pods del core / RAN    │
   └────────────────────────┴────────────────────────┴────────────────────────┘

   Pods (red de Cilium 10.42.0.0/16, túnel VXLAN entre nodos)
     5g-cp  : nrf scp amf smf upf ausf udm udr pcf bsf nssf mongodb webui populate
     5g-ran : ueransim-gnb  ueransim-ues   (más adelante, los pods atacantes)

   N2 (SCTP 38412)  gNB -> AMF   y   N3 (GTP-U 2152)  gNB -> UPF
   viajan pod a pod por Cilium, así las políticas C1 a C3 los ven.
```

| Nodo | Hostname | IP | vCPU | RAM | Disco |
|---|---|---|---|---|---|
| Master | `node-master` | 192.168.100.10 | 2 | 4 GB | 40 GB |
| Worker 1 | `node-worker1` | 192.168.100.11 | 2 | 4 GB | 40 GB |
| Worker 2 | `node-worker2` | 192.168.100.12 | 2 | 4 GB | 40 GB |

Usuario en las tres VMs: **`cib46`** (puedes usar otro, pero entonces cámbialo
también en `ansible/inventory/hosts.ini`).

Por qué 3 nodos y no 1: tus hallazgos de identidad eBPF dependen del camino
**entre nodos** (ipcache de Cilium). Con un solo nodo eso no se ve.

---

## 1. Requisitos de tu laptop y descargas

**Laptop**

- CPU **x86_64** (Intel o AMD). Las imágenes de UERANSIM son solo amd64; en un
  Mac con chip Apple no van a correr.
- Virtualización activada en la BIOS/UEFI (Intel VT-x o AMD-V). En Windows lo
  ves en *Administrador de tareas → Rendimiento → CPU → Virtualización:
  Habilitado*.
- RAM: **16 GB** recomendados (las 3 VMs usan 12 GB). Con 8 GB monta solo
  master + 1 worker de 3 GB cada uno y avísame, porque cambia el experimento.
- Disco libre: **~120 GB** (los discos de las VMs crecen según se usan).
- Conexión a internet estable (se descargan varios GB de imágenes).

**Descargas**

1. **VMware Workstation Pro 17** (gratis para uso personal). Se descarga desde
   el portal de soporte de Broadcom; pide crear una cuenta.
2. **Ubuntu Server 22.04.5 LTS** (amd64):
   `https://releases.ubuntu.com/22.04/` → archivo
   `ubuntu-22.04.5-live-server-amd64.iso`.
   Usamos 22.04 porque es la versión de referencia de la tesis y de Open5GS;
   no la cambies por 24.04 en esta ronda.

---

## 2. Red de las VMs: por qué NAT y no bridge

VMware ofrece tres modos de red para cada VM:

| Modo | Qué hace | ¿Para este lab? |
|---|---|---|
| **Bridged** | La VM aparece en tu red física (wifi de casa o del campus) y pide IP al router de esa red | **No.** En eduroam y redes de campus normalmente no te dan IP para VMs o está prohibido; en wifi suele fallar; y cada vez que cambias de red cambian las IPs y el clúster se rompe |
| **NAT** | Red privada dentro de tu laptop. Las VMs salen a internet a través del laptop y el laptop las ve directamente | **Sí.** IPs fijas que no cambian estés donde estés (casa, Télécom Paris, KCD) |
| **Host-only** | Red privada sin salida a internet | No, necesitas descargar imágenes |

Y las IPs van **estáticas** (no DHCP) porque k3s registra cada nodo con su IP
y Cilium usa la IP del master para hablar con el API server. Si una IP cambia,
el clúster deja de funcionar.

### 2.1 Fijar la subred NAT de VMware a 192.168.100.0/24

VMware elige una subred NAT al azar al instalarse. La fijamos para que todas
las IPs de esta guía sirvan tal cual.

1. Abre VMware Workstation.
2. Menú **Edit → Virtual Network Editor**.
3. Abajo a la derecha, pulsa **Change Settings** (pide permisos de
   administrador en Windows).
4. En la lista, selecciona **VMnet8** (tipo *NAT*).
5. Abajo:
   - **Subnet IP:** `192.168.100.0`
   - **Subnet mask:** `255.255.255.0`
   - Marcado: *Connect a host virtual adapter to this network*
   - Marcado: *Use local DHCP service to distribute IP address to VMs*
6. Pulsa **NAT Settings…** y comprueba que **Gateway IP** sea
   `192.168.100.2`. Si no, ponlo. **OK**.
7. Pulsa **DHCP Settings…** y deja el rango en `192.168.100.128` a
   `192.168.100.254` (nuestras IPs fijas .10, .11 y .12 quedan fuera del rango,
   así nunca chocan). **OK**.
8. **Apply** y **OK**.

> Ojo: esto cambia la red NAT para **todas** tus VMs de VMware. Si tenías
> otras VMs en NAT, tomarán IPs nuevas de la subred 192.168.100.0/24.

**Comprobación en tu laptop (Windows):** abre PowerShell y ejecuta
`ipconfig`. Debe aparecer *Adaptador de Ethernet VMware Network Adapter
VMnet8* con la IP `192.168.100.1`. En Linux: `ip -br a | grep vmnet8`.

> **VirtualBox o Mac:** en VirtualBox la red NAT funciona distinto (el laptop
> no ve las VMs sin reglas de reenvío de puertos) y en Mac con chip Apple las
> imágenes no corren. Si es tu caso, dímelo y te adapto esta sección.

---

## 3. Crear la primera VM (node-master)

Creamos y dejamos lista **una** VM. Luego la clonamos dos veces (sección 6).

1. **File → New Virtual Machine…**
2. Elige **Typical (recommended)** → **Next**.
3. Elige **I will install the operating system later** → **Next**.
   (No uses la opción del ISO aquí: activa el *Easy Install* de VMware, que
   instala Ubuntu con sus propias decisiones y sin preguntarte la red.)
4. **Guest operating system:** *Linux* · **Version:** *Ubuntu 64-bit* →
   **Next**.
5. **Virtual machine name:** `node-master` · elige la carpeta → **Next**.
6. **Maximum disk size:** `40` GB · deja *Split virtual disk into multiple
   files* → **Next**.
7. Pulsa **Customize Hardware…** y ajusta:
   - **Memory:** `4096` MB.
   - **Processors:** *Number of processors* `1`, *Number of cores per
     processor* `2`.
   - **New CD/DVD (SATA):** marca *Use ISO image file* y elige
     `ubuntu-22.04.5-live-server-amd64.iso`. Marca *Connect at power on*.
   - **Network Adapter:** marca **NAT** y *Connect at power on*.
   - **Sound Card** y **Printer:** selecciónalos y pulsa *Remove* (no hacen
     falta).
   - **Close**.
8. **Finish**.

---

## 4. Instalar Ubuntu Server con IP estática

Enciende `node-master` (**Power on this virtual machine**). Haz clic dentro de
la ventana para que el teclado vaya a la VM (para soltarlo: `Ctrl+Alt`).

1. Menú de arranque: **Try or Install Ubuntu Server** (Enter).
2. **Language:** *English*. (Los mensajes de error en inglés se buscan mucho
   mejor en internet.)
3. Si aparece *Installer update available*: **Continue without updating**.
4. **Keyboard:** elige tu teclado (por ejemplo *Spanish (Latin American)* o
   *French*). → **Done**.
5. **Choose type of install:** *Ubuntu Server* (no la versión *minimized*). →
   **Done**.
6. **Network connections:** verás una interfaz (normalmente `ens33`) con DHCP.
   - Muévete con las flechas hasta `ens33`, Enter → **Edit IPv4**.
   - **IPv4 Method:** *Manual*.
   - **Subnet:** `192.168.100.0/24`
   - **Address:** `192.168.100.10`
   - **Gateway:** `192.168.100.2`
   - **Name servers:** `192.168.100.2,1.1.1.1`
   - **Search domains:** (vacío)
   - **Save** → **Done**.
7. **Proxy address:** vacío → **Done**.
8. **Ubuntu archive mirror:** deja el que propone; espera a que pase la
   prueba → **Done**.
9. **Guided storage configuration:**
   - *Use an entire disk* (marcado).
   - **Desmarca** *Set up this disk as an LVM group*. (Con LVM, Ubuntu solo
     usa la mitad del disco para `/` y te quedas sin espacio al bajar imágenes.)
   - **Done** → **Done** → **Continue** (confirma que borra el disco virtual,
     que está vacío).
10. **Profile setup:**
    - *Your name:* `Bryan`
    - *Your server's name:* `node-master`
    - *Pick a username:* `cib46`
    - *Password:* la que quieras (la usarás para `sudo`). → **Done**.
11. **Upgrade to Ubuntu Pro:** *Skip for now* → **Continue**.
12. **SSH Setup:** marca **Install OpenSSH server**. No importes llaves. →
    **Done**.
13. **Featured Server Snaps:** no marques nada → **Done**.
14. Espera a que termine (*Installation complete!*). Pulsa **Reboot Now**.
15. Si dice *Please remove the installation medium, then press ENTER*: pulsa
    Enter (VMware ya desconecta el ISO).

Entra con `cib46` y tu contraseña en la consola de la VM.

### 4.1 Si la IP no quedó estática (o quieres cambiarla después)

La red se define en un archivo de **netplan**:

```bash
ls /etc/netplan/                       # normalmente 00-installer-config.yaml
sudo nano /etc/netplan/00-installer-config.yaml
```

Contenido para el master (respeta los espacios; YAML no acepta tabs):

```yaml
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      addresses:
        - 192.168.100.10/24
      routes:
        - to: default
          via: 192.168.100.2
      nameservers:
        addresses: [192.168.100.2, 1.1.1.1]
```

Guarda (`Ctrl+O`, Enter, `Ctrl+X`) y aplica:

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan apply
ip -br a                                # ens33 debe mostrar 192.168.100.10/24
```

Si tu interfaz no se llama `ens33`, usa el nombre que salga en `ip -br a`.

---

## 5. Configuración base del sistema

Todo esto se hace **una sola vez en node-master**; al clonarla, los workers lo
heredan. Puedes hacerlo desde la consola de VMware o ya por SSH (sección 7).

### 5.1 Comprobar la red

```bash
ip -br a                         # ens33 UP con 192.168.100.10/24
ip route                         # default via 192.168.100.2
ping -c 3 192.168.100.2          # gateway de VMware
ping -c 3 1.1.1.1                # salida a internet
ping -c 3 github.com             # DNS
```

Si `ping 1.1.1.1` falla pero el gateway responde, prueba
`curl -I https://github.com` (algunas redes bloquean ping hacia afuera). Si
falla todo, revisa la sección 2.1 y la tabla de problemas (sección 13).

### 5.2 Actualizar y paquetes base

```bash
sudo apt update && sudo apt -y full-upgrade
sudo apt install -y curl git make vim htop jq open-vm-tools
sudo timedatectl set-timezone Europe/Paris
```

Si `apt` dice *Could not get lock*, es la actualización automática del primer
arranque. Espera 2 o 3 minutos y repite.

### 5.3 Swap apagado

Kubernetes trabaja mejor sin swap (el playbook también lo apaga, pero así ya
queda en la plantilla).

```bash
sudo swapoff -a
sudo sed -i '/\sswap\s/ s/^#*/#/' /etc/fstab
free -h                          # la fila Swap debe quedar en 0B
```

### 5.4 Módulo SCTP (N2/NGAP y el vector A3)

```bash
sudo modprobe sctp
echo sctp | sudo tee /etc/modules-load.d/sctp.conf
lsmod | grep sctp                # debe aparecer una línea "sctp"
```

Si dice `Module sctp not found`:
`sudo apt install -y linux-modules-extra-$(uname -r)` y repite.

### 5.5 Nombres de los nodos

```bash
cat <<'EOF' | sudo tee -a /etc/hosts
192.168.100.10 node-master
192.168.100.11 node-worker1
192.168.100.12 node-worker2
EOF
```

### 5.6 Firewall

```bash
sudo ufw status                  # debe decir: Status: inactive
# si dijera active:
# sudo ufw disable
```

### 5.7 Apagar y tomar snapshot "base"

```bash
sudo poweroff
```

En VMware, con la VM apagada: **VM → Snapshot → Take Snapshot…** → nombre
`base-limpia` → **Take Snapshot**.

---

## 6. Clonar la VM para los dos workers

### 6.1 Crear los clones

Con `node-master` apagada:

1. **VM → Manage → Clone…** → **Next**.
2. **Clone from:** *An existing snapshot* → `base-limpia` → **Next**.
3. **Clone type:** **Create a full clone** (independiente del original) →
   **Next**.
4. **Name:** `node-worker1` · carpeta → **Finish** → **Close**.
5. Repite para `node-worker2`.

VMware asigna una MAC nueva a cada clon automáticamente. Si alguna vez copias
la carpeta de una VM a mano y al encenderla pregunta *moved it* o *copied it*,
responde **I copied it**.

### 6.2 Personalizar cada clon (uno por uno)

> **Importante:** el clon arranca con la **misma IP que el master** (.10). Haz
> esto con `node-master` **apagada** y con un solo clon encendido a la vez,
> para que no choquen las IPs.

Enciende `node-worker1`, entra por la consola de VMware con `cib46` y ejecuta
(cambia las dos primeras líneas para el worker 2):

```bash
NEW_NAME=node-worker1
NEW_IP=192.168.100.11

# 1) Hostname (k3s usa el hostname como nombre del nodo)
sudo hostnamectl set-hostname "$NEW_NAME"
sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $NEW_NAME/" /etc/hosts

# 2) IP estática
sudo sed -i "s#192.168.100.10/24#$NEW_IP/24#" /etc/netplan/*.yaml
grep -n "/24" /etc/netplan/*.yaml          # debe mostrar la IP nueva

# 3) machine-id único (los clones lo heredan igual; systemd y la red lo usan)
sudo rm -f /etc/machine-id /var/lib/dbus/machine-id
sudo systemd-machine-id-setup

# 4) Llaves SSH del servidor nuevas (si no, los 3 nodos tienen la misma)
sudo rm -f /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server

sudo reboot
```

Al volver a entrar, comprueba:

```bash
hostname                    # node-worker1
ip -br a                    # 192.168.100.11/24
ping -c 2 192.168.100.2
```

Apaga `node-worker1` (`sudo poweroff`) y repite todo con `node-worker2`
(`NEW_NAME=node-worker2`, `NEW_IP=192.168.100.12`).

### 6.3 Encender los tres

Enciende `node-master`, `node-worker1` y `node-worker2`. Desde el master:

```bash
ping -c 2 node-worker1
ping -c 2 node-worker2
```

---

## 7. Entrar por SSH desde tu laptop

Trabajar por SSH es mucho más cómodo que la consola de VMware (copiar y pegar
funciona bien). En Windows usa **PowerShell** o **Windows Terminal**:

```powershell
ssh cib46@192.168.100.10
```

La primera vez pregunta si confías en la llave: escribe `yes`. Abre una
pestaña por nodo si quieres (.11 y .12).

Opcional, para escribir solo `ssh master`: crea el archivo
`C:\Users\<tu_usuario>\.ssh\config` con:

```
Host master
  HostName 192.168.100.10
  User cib46
Host worker1
  HostName 192.168.100.11
  User cib46
Host worker2
  HostName 192.168.100.12
  User cib46
```

---

## 8. Preparar Ansible en el master

Usamos el **master como nodo de control**: Ansible se instala solo ahí y desde
ahí configura los 3 nodos (incluido él mismo) por SSH. Así no necesitas WSL ni
nada en Windows.

Todo lo de esta sección va **en node-master**.

### 8.1 Instalar Ansible

```bash
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
ansible --version            # debe mostrar "ansible [core 2.1x...]"
```

Si el PPA fallara, la versión de Ubuntu también sirve:
`sudo apt install -y ansible`.

### 8.2 Llave SSH del master hacia los 3 nodos

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

for h in 192.168.100.10 192.168.100.11 192.168.100.12; do
  ssh-copy-id -o StrictHostKeyChecking=accept-new cib46@$h
done
```

Te pedirá la contraseña de `cib46` una vez por nodo (también la del propio
master, es normal). Comprueba que ya entra sin contraseña:

```bash
for h in 192.168.100.10 192.168.100.11 192.168.100.12; do ssh cib46@$h hostname; done
# node-master
# node-worker1
# node-worker2
```

### 8.3 Bajar el repo

```bash
cd ~
git clone https://github.com/BryanTxz10/cib46-zta-5g-core.git
cd cib46-zta-5g-core
git checkout lab-v2
```

### 8.4 Revisar inventario y variables

```bash
cat ansible/inventory/hosts.ini
```

Debe tener tus IPs y tu usuario. Con los valores de esta guía ya está bien:

```ini
[master]
node-master ansible_host=192.168.100.10 ansible_user=cib46

[workers]
node-worker1 ansible_host=192.168.100.11 ansible_user=cib46
node-worker2 ansible_host=192.168.100.12 ansible_user=cib46
```

En `ansible/group_vars/all.yml` no hace falta cambiar nada. Lo importante que
fija: k3s `v1.28.5+k3s1`, Cilium `1.15.4`, chart de Open5GS de Gradiant
`2.3.4` (Open5GS 2.7.5), `deploy_multus: false`, `deploy_spire: false`.

### 8.5 Probar la conexión

```bash
cd ~/cib46-zta-5g-core/ansible
ansible all -m ping
```

Las tres máquinas deben responder `SUCCESS` con `"ping": "pong"`.

---

## 9. Desplegar todo con un comando

En **node-master**, dentro de `~/cib46-zta-5g-core/ansible`:

```bash
ansible-playbook site.yml -K
```

`-K` hace que te pida **BECOME password**: es tu contraseña de `cib46`
(la de `sudo`).

Qué hace, en orden (tarda entre 15 y 30 minutos según tu internet):

| Fase | Qué instala | Si falla aquí, mira |
|---|---|---|
| Play 1 | Paquetes, SCTP, swap off en los 3 nodos | internet / `apt` |
| Play 2 | k3s server en el master (sin flannel ni kube-proxy) | `sudo journalctl -u k3s -n 50` |
| Play 3 | k3s agent en los 2 workers | `sudo journalctl -u k3s-agent -n 50` en el worker |
| Play 4 | Helm, **Cilium** (KPR, L7, SCTP, Hubble), CLIs `cilium` y `hubble`, metrics-server, **Open5GS** (espera hasta 15 min), suscriptor, Service N2, **gNB y UE** | sección 13 |

Al final debe salir un `PLAY RECAP` con **`failed=0`** en los tres nodos.

**Si falla a mitad:** lee el mensaje rojo, arregla la causa y vuelve a lanzar
el mismo comando. El playbook es idempotente: lo que ya está hecho no se
rehace. También puedes repetir solo una parte:

```bash
ansible-playbook site.yml -K --tags cilium
ansible-playbook site.yml -K --tags open5gs
ansible-playbook site.yml -K --tags ueransim
```

---

## 10. Verificar que el core 5G funciona

En **node-master** (el playbook dejó el kubeconfig en `~/.kube/config`, así
que `kubectl` funciona sin `sudo`).

### 10.1 Nodos y Cilium

```bash
kubectl get nodes -o wide
```

Los tres en **Ready**, cada uno con su IP 192.168.100.x en *INTERNAL-IP*.

```bash
cilium status
```

Debe decir `Cilium: OK`, `Operator: OK`, `Hubble Relay: OK` y
`Cluster Pods: N/N managed by Cilium`.

### 10.2 Pods del core

```bash
kubectl -n 5g-cp get pods -o wide
```

Todos en `Running` (y `1/1`): `open5gs-cp-amf`, `-ausf`, `-bsf`, `-mongodb`,
`-nrf`, `-nssf`, `-pcf`, `-populate`, `-scp`, `-smf`, `-udm`, `-udr`, `-upf`,
`-webui`.

### 10.3 gNB conectado al AMF (N2)

```bash
kubectl -n 5g-ran logs deploy/ueransim-gnb | tail -n 20
```

Busca:

```
gNB con IP 10.42.x.x; AMF en 10.42.y.y
[ngap] [info] NG Setup procedure is successful
```

### 10.4 UE registrado y con sesión PDU

```bash
kubectl -n 5g-ran logs deploy/ueransim-ues | tail -n 30
```

Busca:

```
[nas] [info] Initial Registration is successful
[nas] [info] PDU Session establishment is successful PSI[1]
[app] [info] Connection setup for PDU session[1] is successful, TUN interface[uesimtun0, 10.45.0.2] is up.
```

### 10.5 Tráfico real por el plano de usuario

```bash
UE=$(kubectl -n 5g-ran get pod -l app.kubernetes.io/name=ueransim-ue -o jsonpath='{.items[0].metadata.name}')

kubectl -n 5g-ran exec $UE -- ip -br a show uesimtun0
kubectl -n 5g-ran exec $UE -- ping -c 4 -I uesimtun0 8.8.8.8
kubectl -n 5g-ran exec $UE -- curl -s --interface uesimtun0 -o /dev/null -w "%{http_code}\n" https://www.google.com
```

`uesimtun0` con IP `10.45.0.x`, ping con `0% packet loss` y el `curl`
devolviendo `200`. Ese tráfico va UE → gNB → (GTP-U por Cilium) → UPF →
internet. **Si llegas aquí, el core 5G funciona.**

### 10.6 Ver los flujos con Hubble (te servirá para la charla)

```bash
cilium hubble port-forward &
hubble observe -n 5g-ran --last 20
hubble observe -n 5g-cp --to-port 38412 --last 10     # N2 hacia el AMF
```

Interfaz gráfica de Hubble en el navegador de tu laptop:

```bash
# en node-master
cilium hubble ui --open-browser=false        # queda escuchando en el puerto 12000
```

```powershell
# en tu laptop, otra terminal
ssh -L 12000:localhost:12000 cib46@192.168.100.10
```

Abre `http://localhost:12000` y elige el namespace `5g-cp` o `5g-ran`.

---

## 11. Aplicar C0 y la prueba de humo

En **node-master**, desde la raíz del repo:

```bash
cd ~/cib46-zta-5g-core
make condition C=c0
```

Debe listar las 3 políticas `c0-allow-all-anchor` (en `5g-cp`, `5g-ran` y
`5g-up`). Ahora la prueba que sí ejercita el plano de control (RM-01):

```bash
make smoke C=C0
```

Resultado esperado al final:

```
=== Resultado C0: attach=SI sbi=200 ===
```

- `attach=SI`: el UE hizo un registro 5G nuevo completo (Registration + PDU
  Session) con C0 aplicado.
- `sbi=200`: el discovery SBI legítimo AMF → NRF responde.

Para cambiar de condición usa siempre `make condition C=c1` (c2, c3). Ese
camino borra primero todas las políticas del experimento y aplica las de la
condición, así no se acumula estado. Antes de usar C1 a C3 lee la sección 15.

---

## 12. Snapshots, apagar y volver a encender

### 12.1 Snapshot del testbed funcionando

Con C0 verificado es el momento de guardar un punto de retorno. Apaga
ordenadamente:

```bash
# primero los workers, luego el master
ssh cib46@192.168.100.11 sudo poweroff
ssh cib46@192.168.100.12 sudo poweroff
sudo poweroff
```

En VMware, en cada una de las 3 VMs: **VM → Snapshot → Take Snapshot…** →
`lab-v2-C0-ok`.

Volver a ese snapshot es la forma más limpia de hacer el **reset a estado
limpio entre bloques** del protocolo v2 (RM-19): **VM → Snapshot → Revert to
Snapshot** en las tres.

### 12.2 Encender de nuevo

Enciende primero `node-master`, luego los workers. Espera 2 o 3 minutos y:

```bash
make status
```

Si los pods vuelven pero el UE no se registra:

```bash
make subscribers      # MongoDB no es persistente: re-inserta el suscriptor
make ran-restart      # reinicia gNB y luego UE (el gNB resuelve la IP del AMF al arrancar)
```

---

## 13. Problemas frecuentes

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La VM no sale a internet | Subred NAT mal puesta o servicio NAT de VMware caído | Revisa la sección 2.1. En Windows: *Servicios* → *VMware NAT Service* en ejecución |
| `ssh` desde el laptop da *timed out* | El adaptador VMnet8 del host está desactivado | Sección 2.1, paso 5 (*Connect a host virtual adapter*) y `ipconfig` |
| Dos VMs con la misma IP | Encendiste un clon antes de cambiarle la IP | Apaga una, sigue la sección 6.2 |
| `Module sctp not found` | Falta el paquete de módulos extra | `sudo apt install -y linux-modules-extra-$(uname -r)` |
| Ansible: `UNREACHABLE` | Falta la llave SSH en ese nodo | Repite `ssh-copy-id cib46@IP` (sección 8.2) |
| Ansible: `Missing sudo password` | Lanzaste sin `-K` | `ansible-playbook site.yml -K` |
| Ansible: `Invalid callback for stdout` | `ansible.cfg` viejo | Asegúrate de estar en la rama `lab-v2` |
| Nodos en `NotReady` | Cilium aún no arranca en ese nodo | `kubectl -n kube-system get pods -l k8s-app=cilium -o wide` y `kubectl -n kube-system logs <pod>` |
| Open5GS: el `helm --wait` se agota | Imágenes descargando lento o bloqueadas | `kubectl -n 5g-cp get pods` y `kubectl -n 5g-cp describe pod <pod>` (mira *Events*) |
| `ImagePullBackOff` con `toomanyrequests` | Límite de descargas anónimas de Docker Hub (por IP pública; en el campus la comparte mucha gente) | Espera un rato y relanza `--tags open5gs`; si se repite, avísame y configuramos credenciales de Docker Hub en k3s |
| `populate` en `Init:CrashLoopBackOff` | MongoDB todavía no estaba listo | Normal al inicio; se arregla solo en 1 o 2 minutos |
| gNB repite *Esperando DNS del AMF* | No existe el Service `amf-n2` o el AMF no corre | `kubectl -n 5g-cp get endpoints amf-n2` (debe mostrar la IP del pod AMF) |
| gNB: SCTP no conecta / *NG Setup failure* | El AMF se reinició y cambió de IP | `make ran-restart` |
| UE: *no cells in coverage* / *PLMN selection failure* | El UE no llega al gNB por RLS (UDP 4997) | Mira que el gNB corra y que `ueransim-gnb` resuelva: `kubectl -n 5g-ran exec $UE -- getent hosts ueransim-gnb.5g-ran.svc.cluster.local` |
| UE: falla autenticación / *Registration reject* | Falta el suscriptor en MongoDB | `make subscribers` y luego `kubectl -n 5g-ran rollout restart deploy/ueransim-ues` |
| `uesimtun0` existe pero el ping a 8.8.8.8 falla | NAT del UPF o salida a internet del nodo | `kubectl -n 5g-cp logs deploy/open5gs-cp-upf` y prueba internet desde el nodo |
| `make smoke` da `sbi=000` | El curl desde el AMF no llega al NRF | `kubectl -n 5g-cp get svc | grep nrf-sbi` y revisa la condición aplicada |

Comandos que siempre ayudan:

```bash
make status
kubectl get events -A --sort-by=.lastTimestamp | tail -n 30
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --previous      # logs del intento anterior si se reinició
```

---

## 14. Qué cambió en el repo (lab v2) y por qué

Al revisar la rama `revision-metodologica-automatizacion` contra las fuentes
encontré cosas que habrían roto el despliegue o la validez del experimento.
La rama `lab-v2` las corrige:

| Archivo | Problema | Arreglo |
|---|---|---|
| `group_vars/all.yml`, `60-open5gs.sh` | El chart `towards5gs/open5gs` **no existe**: ese repo solo publica free5GC y UERANSIM. Tus values eran del chart de **Gradiant** | Chart OCI de Gradiant `2.3.4` (Open5GS 2.7.5). La 2.2.4 dependía de imágenes de MongoDB de Bitnami que ya no se pueden descargar |
| `site.yml` | El release se llamaba `open5gs`, pero `gnb.yaml`, los checks y el script de C2 esperan `open5gs-cp-*` | Release `open5gs-cp` |
| `insert-subscribers.sh` | Usaba el shell `mongo`, que ya no viene en las imágenes de MongoDB actuales | El suscriptor lo inserta el `populate` del chart; el script solo lo re-ejecuta |
| `ueransim.yaml` | Las imágenes tienen `nr-gnb`/`nr-ue` en `/ueransim/build/`, no en el PATH: no arrancaban | Ruta completa |
| `ue.yaml` | `gnbSearchList` apuntaba al **AMF**; el UE busca al **gNB** (RLS, UDP 4997) | Service headless `ueransim-gnb` |
| `gnb.yaml`, Multus | N2 iba por macvlan (10.10.0.20). **Cilium no ve ese tráfico**, así que las políticas 03 y 05 no aplicaban al N2 real | N2 y N3 por la red de pods de Cilium; Multus queda opcional y apagado |
| `amf-n2-headless.yaml` (nuevo) | Cilium 1.15 **no soporta SCTP sobre la VIP de un Service con KPR** (doc oficial de SCTP) | Service headless: el gNB abre SCTP directo al pod del AMF |
| `c0-allow-all-anchor.yaml` | `ingress: [{}]` / `egress: [{}]` en Cilium **no es allow-all, es deny-all** (es el patrón "default deny" de los ejemplos oficiales de Cilium) | `fromEntities: [all]` / `toEntities: [all]` |
| `transition-to-c1.sh` | Nunca borraba el ancla de C0: C1 a C3 corrían encima de ella | La borra antes de aplicar C1 (y usa `make condition`) |
| `ansible.cfg` | `stdout_callback = yaml` ya no existe en Ansible reciente | `callback_result_format = yaml` |
| `site.yml` | Sin `--node-ip`, pool de pods de Cilium por defecto `10.0.0.0/8` | `--node-ip` explícito y pool `10.42.0.0/16` |
| `Makefile` | Necesitaba instalar `kustomize` aparte | Usa `kubectl kustomize`; nuevos `make subscribers` y `make ran-restart` |

---

## 15. Antes de medir: revisar las políticas C1 a C3

Esto **no** es parte del montaje, pero hay que resolverlo antes de recolectar
datos del protocolo v2 (y antes de afirmar resultados en el KCD). Lo dejo
anotado, no lo cambié todavía porque son decisiones de diseño del experimento:

1. **`c1/01-deny-ran-to-cp.yaml` en realidad permite.** Es una regla
   `ingress` con `fromEndpoints` de `5g-ran`: en Cilium eso es **allow** de
   todo `5g-ran` hacia todos los pods de `5g-cp`, en cualquier puerto. Para
   bloquear basta con no permitir (default deny) o usar `ingressDeny`.
2. **`c1/05-ratelimit-n2-amf.yaml` no limita nada.** CiliumNetworkPolicy no
   tiene rate limiting para ningún protocolo; la política permite N2 desde
   **cualquier** pod de `5g-ran`, atacante incluido. Para la charla, el
   hallazgo "Cilium no limita SCTP" hay que reformularlo con precisión.
3. **`c1/02` solo permite TCP 7777 dentro del core.** PFCP (UDP 8805,
   SMF ↔ UPF) y GTP-U del gNB al UPF (UDP 2152) no están permitidos de forma
   explícita. Si en la v1 seguía funcionando, probablemente fue por el
   conntrack de sesiones ya establecidas; con el reset limpio del protocolo v2
   se puede romper.
4. **El ancla de C0 de la v1 era deny-all y no se borraba** al pasar a C1
   a C3. Hay que revisar qué resultados de la v1 afecta antes de reutilizar
   cualquier número.
5. **Versiones:** Cilium 1.15 y k3s 1.28 ya no tienen soporte. En el KCD es
   probable que pregunten si lo de SCTP sigue igual en el Cilium actual.

Cuando el lab esté arriba y en C0, el siguiente paso es corregir estas
políticas y validarlas con Hubble (ver los `DROPPED` donde deben estar).
