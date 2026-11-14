# Arquitectura v3: plano de control y plano de usuario separados

> Continúa `docs/arquitectura-v2-hardening.md`. La v2 endureció el testbed sin
> mover nada de sitio. La v3 hace el cambio que la v2 dejó diferido: el UPF sale
> de `5g-cp` y pasa a su propia zona (`5g-up`), con su propio release de Helm,
> su propio nodo y sus propias políticas. También corrige tres defectos de las
> condiciones C1 a C3 que aparecían al separar los planos.
>
> Estado: escrito y revisado contra las plantillas del chart de Gradiant 2.3.4.
> **No está probado en un clúster.** La sección 6 dice cómo validarlo.

## 1. Por qué separar

En la tesis y en la v2 el UPF vivía en `5g-cp` con las NF de control porque así
lo despliega el chart por defecto. El namespace `5g-up` existía pero estaba
vacío. Eso tiene tres problemas:

1. **No se parece a un core real.** 3GPP separa control y usuario (CUPS): el SMF
   gobierna al UPF por N4 (PFCP) y cada uno se ubica y escala por su cuenta.
2. **El teléfono queda dentro de la zona de control.** El UPF hace NAT del
   tráfico de los UE, así que lo que envía un suscriptor sale con la identidad
   del UPF. Con el UPF en `5g-cp`, esa identidad pertenece a la misma zona que
   la SBI y MongoDB.
3. **Las políticas no pueden expresar "nada entra desde el plano de usuario".**
   Había que excluir al UPF regla por regla (`NotIn [upf]`).

## 2. Cómo lo hacen los operadores y qué copia el testbed

| Aspecto | DISH / Boost Mobile en AWS | O2 Telefónica (Nokia en AWS) | Testbed CIB46 v3 |
|---|---|---|---|
| Plano de control (AMF, SMF) | En la Región (centro de datos regional) | Funciones de Nokia en EKS, en Regiones y Outposts | `5g-cp`, en `node-worker1` (sitio central) |
| Base de suscriptores | Centro de datos nacional, aparte | Datos en instalaciones propias o en AWS dentro de Europa | MongoDB en `5g-cp`, entrada solo desde UDR, PCF y populate |
| Plano de usuario (UPF) | En la Local Zone, junto a la CU | Tráfico de usuario separado del de control | `5g-up`, en `node-worker2` (sitio de borde), junto al gNB |
| Salida a internet (N6) | En la Local Zone, sin volver a la Región | n/d en la fuente | Solo el UPF sale a `world`; ninguna NF de control sale |
| Unidad de aislamiento | Una VPC por centro de datos | VPC y adjuntos ENI multi-VPC por tipo de tráfico | Un namespace por zona de confianza |
| Quién separa los tráficos | Tablas de rutas del Transit Gateway, VRF, security groups | Multus más ENI multi-VPC, con rutas y políticas distintas para control y usuario | CiliumNetworkPolicy por identidad, ingress y egress en default-deny |
| Ciclo de vida | n/d en la fuente | Funciones de red en contenedores, orquestadas por EKS | Dos releases de Helm: `open5gs-cp` y `open5gs-up` |

Lo que el testbed reproduce bien: **dónde vive cada plano, quién puede hablar con
quién entre zonas y por dónde sale el tráfico de los suscriptores.**

Lo que no reproduce, y hay que decirlo así:

| Diferencia con un operador | Efecto | Dónde queda |
|---|---|---|
| Un solo clúster. Los operadores usan clústeres o VPC distintos por sitio | El kernel y el plano de control de Kubernetes son compartidos | Límite declarado |
| Una sola interfaz por pod. Los operadores dan al UPF interfaces separadas para N3, N4 y N6 (Multus, VRF) | N4 y N6 comparten interfaz: por eso la política de egress del UPF es tan corta (sección 4) | Perfil B (Multus) |
| N4 sin cifrar. TS 33.501 pide proteger las interfaces internas no SBA salvo que haya otra protección, por ejemplo física | El PFCP viaja en claro entre nodos | WireGuard (`group_vars`, v2) |
| N6 sale por la red del nodo. No hay una red N6 con firewall o CGNAT propio | El UE sale con la IP del nodo de borde | Perfil B |

## 3. Qué cambia

**Despliegue**

| Antes (v2) | Ahora (v3) |
|---|---|
| Un release `open5gs-cp` en `5g-cp` con todo | `open5gs-up` en `5g-up` (solo UPF) y `open5gs-cp` en `5g-cp` (control y MongoDB) |
| SMF busca `open5gs-cp-upf-pfcp` | SMF apunta a `open5gs-up-upf-pfcp.5g-up.svc.cluster.local` |
| `5g-up` vacío | `5g-up` es la zona del plano de usuario |

Es el mismo chart y la misma versión, instalado dos veces. El segundo release
lleva todo apagado salvo el UPF (`helm-values/open5gs-upf-values.yaml`). El UPF
se instala primero porque el SMF resuelve su Service N4 al arrancar.

**Flujos entre zonas (todo lo demás se niega)**

| Flujo | Interfaz | Origen | Destino | Puerto |
|---|---|---|---|---|
| Señalización de radio | N2 | gNB (`5g-ran`) | AMF (`5g-cp`) | SCTP 38412 |
| Control del plano de usuario | N4 | SMF (`5g-cp`) | UPF (`5g-up`) | UDP 8805 |
| Tráfico de usuario | N3 | gNB (`5g-ran`) | UPF (`5g-up`) | UDP 2152 |
| Internet de los suscriptores | N6 | UPF (`5g-up`) | `world` | cualquiera |

Con la colocación fija, N2 y N4 cruzan siempre de nodo (worker2 a worker1 y
worker1 a worker2). N3 queda dentro del sitio de borde, como en un operador
que pone el UPF junto a la CU.

**Políticas**

| Archivo | Cambio |
|---|---|
| `hardening/ingress/00-default-deny-cp.yaml` (nuevo) | Default-deny real de ingress en `5g-cp`. Sustituye a `c1/01-deny-ran-to-cp`, que en Cilium era un allow de todo `5g-ran` |
| `hardening/ingress/02-allow-upf-n3-n4.yaml` | Pasa a `5g-up`: solo N3 del gNB y N4 del SMF |
| `hardening/egress/01-egress-upf-n6.yaml` | Pasa a `5g-up`: solo gNB y `world`. Sin DNS y sin regla hacia el SMF |
| `hardening/egress/03-egress-smf-n4.yaml` (nuevo) | Única salida entre zonas del plano de control: SMF hacia UPF, UDP 8805 |
| `hardening/egress/02-egress-ran-baseline.yaml` | N3 apunta a `5g-up` |
| `hardening/ingress/01-allow-mongodb-udr-pcf.yaml` | Entra populate (para `make subscribers` con la condición aplicada) y sale el BSF, que no usa la base |
| `c2/03-allow-sbi-core-nf.yaml` (nuevo, C2 y C3) | SBI entre NF que no va al NRF, exigiendo identidad. Sin ella el attach se rompía en C2 y C3 tras un reinicio limpio |
| `c1/02`, `c2/01`, `c3/01` | Se quita la exclusión `NotIn [upf]`: ya no hace falta |
| `c2/02-patch-identity-labels.sh` | Se añade el NSSF a las NF con identidad |

## 4. La decisión delicada: qué se le permite al UPF

El UPF enmascara el tráfico de los UE. Para Cilium, un paquete que envía un
teléfono y un paquete que envía el propio UPF tienen la misma identidad. Por
eso **todo lo que se le permite al UPF se le permite a cada suscriptor.**

En un operador esto no pasa porque N4 y N6 son interfaces y VRF distintas: el
tráfico de usuario no puede llegar a la red N4. En el testbed solo hay una
interfaz, así que el control compensatorio es dejar el egress del UPF en lo
mínimo:

- hacia el gNB por UDP 2152 (N3 de bajada),
- hacia `world` (N6).

No hay DNS del clúster (los UE usan 8.8.8.8, que es `world`) y no hay regla
hacia el SMF. El PFCP lo inicia siempre el SMF; las respuestas, los heartbeats y
los reportes del UPF vuelven por esa misma conexión (mismos puertos 8805 en
ambos lados, conntrack). Una regla `UPF -> SMF:8805` dejaría a un UE enviar PFCP
falso al SMF.

Riesgo conocido: si la asociación PFCP queda inactiva más que el tiempo de vida
de conntrack para UDP, un mensaje iniciado por el UPF se descartaría hasta el
siguiente heartbeat del SMF. Con los heartbeats de Open5GS no debería ocurrir.
Si aparece "No Heartbeat from UPF" en los logs del SMF, la regla opcional está
comentada al final de `01-egress-upf-n6.yaml`.

Sigue abierto: un UE puede dirigirse a la IP del propio UPF (puertos 8805 y
2152 por la interfaz `ogstun`). Open5GS recomienda cerrarlo con una regla de
iptables dentro del UPF. No está implementado.

## 5. Cómo aplicarlo

Instalación nueva: `ansible-playbook site.yml -K` y luego
`ansible-playbook hardening.yml -K`. No hay pasos extra.

Sobre un lab que ya funciona con el UPF en `5g-cp`:

```bash
# 0. Punto de retorno: snapshot de las tres VMs (lab-v2-C0-ok).
cd ~/cib46-zta-5g-core && git pull
cd ansible
ansible-playbook site.yml -K --tags open5gs     # UPF a 5g-up, SMF re-apuntado
ansible-playbook hardening.yml -K               # taint del master + PSS
```

El playbook instala primero `open5gs-up`, después actualiza `open5gs-cp` (que
elimina el UPF viejo y reinicia el SMF) y reinicia gNB y UE si el AMF cambió de
IP. Las sesiones PDU se pierden: el UE se registra de nuevo.

## 6. Validación

```bash
kubectl get pods -n 5g-up -o wide        # open5gs-up-upf en node-worker2
kubectl get pods -n 5g-cp -o wide        # sin UPF; todo en node-worker1
kubectl -n 5g-cp logs deploy/open5gs-cp-smf | grep -i pfcp     # "PFCP associated"
make condition C=c0 && make smoke C=C0   # attach=SI sbi=200
make condition C=c1 && make smoke C=C1   # attach=SI sbi=200
hubble observe --verdict DROPPED --last 50
```

Repetir el smoke en C2 y C3 (antes, `bash cilium-policies/c2/02-patch-identity-labels.sh`
y `make ran-restart`). En cada condición, `hubble observe -n 5g-up` debe mostrar
N3 y N4 como FORWARDED.

Comprobación sin clúster de la matriz de flujos (aproximación L3/L4 de las
políticas, no sustituye a Hubble):

```bash
make policy-matrix
```

**Prueba del hallazgo 1 (el teléfono y el core).** En C0, desde el UE por
`uesimtun0`, pedir la SBI del NRF. Si responde, el hallazgo queda confirmado. En
C1 la misma petición debe salir DROPPED en el egress del UPF:

```bash
UE=$(kubectl -n 5g-ran get pod -l app.kubernetes.io/name=ueransim-ue -o jsonpath='{.items[0].metadata.name}')
NRF=$(kubectl -n 5g-cp get svc open5gs-cp-nrf-sbi -o jsonpath='{.spec.clusterIP}')
kubectl -n 5g-ran exec $UE -- curl -s -m 5 --interface uesimtun0 --http2-prior-knowledge \
  -o /dev/null -w "%{http_code}\n" "http://$NRF:7777/nnrf-nfm/v1/nf-instances"
hubble observe -n 5g-up --verdict DROPPED --last 10
```

## 7. Efecto sobre el experimento

- **Comparabilidad con la v1.** Los números de la tesis se midieron con el UPF
  en `5g-cp`. La v2 del protocolo ya re-mide todo; hay que declarar el cambio
  de topología.
- **A1 y A2.** Mueren dos veces: en el egress de `5g-ran` y en el default-deny
  de `5g-cp`.
- **A2'.** En C2 el impostor sin identidad queda fuera de toda la SBI, no solo
  del NRF.
- **A3 (flood N2).** Desde la v2 solo el gNB puede abrir N2. El script
  `run_a3_n2_flood.sh` lanza el flood desde `attacker-ue-lateral`, que en C1 a C3
  ya no llega al AMF. Para sostener el hallazgo "la política decide quién, no
  cuánto", el flood debe salir del propio gNB o de un pod que haya conseguido
  su identidad. Pendiente de adaptar.
- **Nuevo vector medible.** El UE contra el core por N6 (sección 6): abierto en
  C0, cerrado en C1.

## 8. Fuentes

- AWS, *Telco Meets AWS Cloud: Deploying DISH's 5G Network in AWS Cloud*.
  https://aws.amazon.com/blogs/industries/telco-meets-aws-cloud-deploying-dishs-5g-network-in-aws-cloud
- AWS, *O2 Telefónica moves its 5G core network to the cloud with AWS and Nokia* (mayo de 2024).
  https://aws.amazon.com/blogs/industries/o2-telefonica-moves-its-5g-core-network-to-the-cloud-with-aws-and-nokia
- Amazon, *O2 Telefónica brings 5G cloud core to own data center with Nokia and AWS Outposts* (marzo de 2026).
  https://press.aboutamazon.com/aws/2026/3/o2-telefonica-brings-5g-cloud-core-to-own-data-center-with-nokia-and-aws-outposts
- 3GPP TS 23.501 (arquitectura, separación SMF y UPF) y TS 33.501, cláusula 9.9 (protección de interfaces internas no SBA).
- Chart de Gradiant `open5gs` 2.3.4: plantillas de `open5gs-smf` y `open5gs-upf`.
