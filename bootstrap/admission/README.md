# Control de admisión — identidad de workload no forjable (punto 2 / RM-05)

Cierra la crítica de constructo más fuerte de la tesis: en C2 la "identidad de
workload" es un **label de pod** (`cib46-nf-type=core-nf`), y un label es
**auto-asignable** por quien pueda crear pods en `5g-cp`. Sin control de admisión,
el atacante de A2′ **se pondría el label** y derrotaría C2. El control de admisión
lo vuelve **no forjable**.

## Mecanismo (capas)

| Capa | Pregunta | Dónde actúa | Momento |
|---|---|---|---|
| **Admisión** (este control) | ¿Puede *existir* esta identidad? | API server (webhook) | al **crear** el pod |
| Identidad eBPF (C2) | ¿Puede *hablar* esta identidad? | dataplane Cilium | en el **SYN** |
| RBAC L7 (C3) | ¿Está *autorizada* para esta operación? | proxy Envoy | en el **método HTTP** |

La admisión es **ortogonal a Cilium**: no es red, es el API server. Por eso
complementa —no sustituye— a C2/C3.

## Qué cubre y qué no (declarar en la tesis)

- **Cubre:** un adversario que despliega un impostor **con** el label siendo un
  principal distinto del desplegador autorizado (tu A2′, y el nuevo **A2‴**).
  Es rechazado en la creación, antes de arrancar.
- **No cubre:** un pipeline autorizado **ya comprometido** (supply-chain). Eso
  requiere firma de imágenes (Sigstore/cosign) y es **trabajo futuro**. Dilo con
  precisión: evita sobreafirmar.

## Instalación y uso

```bash
# 1) Instalar Kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# 2) AJUSTAR la allowlist de kyverno-identity-guard.yaml a tu clúster
#    (SA del desplegador real; conserva los SA de los controladores).
#    Sugerencia: empieza con validationFailureAction: Audit para observar,
#    luego cámbialo a Enforce.
kubectl apply -f kyverno-identity-guard.yaml
```

## Vector de prueba A2‴ (nuevo, medible)

```bash
# Impostor que INTENTA ponerse el label de identidad, como principal NO autorizado.
# Esperado: RECHAZADO en admisión (antes de crear el pod).
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nf-impostor-con-label
  namespace: 5g-cp
  labels:
    cib46-nf-type: core-nf   # intento de forjar identidad
spec:
  containers:
    - name: attacker
      image: nicolaka/netshoot:v0.13
      command: ["/bin/sh","-c","sleep infinity"]
EOF
# Resultado esperado: admission webhook "cib46-identity-guard" DENIED.
# Registra el veredicto como evidencia de A2‴ (tabla de resultados).
```

## Nota sobre pods hijos de Deployments

Cuando el desplegador autorizado crea un **Deployment** con el label, los pods
hijos los crea el `replicaset-controller` → por eso los SA de los controladores
están en la allowlist. El atacante, en cambio, aparece con **su propio** usuario
al crear directamente un Pod o Deployment → es denegado. Si tu RBAC ya impide al
atacante crear cargas en `5g-cp`, este control es **defensa en profundidad**; si
se la permite (modelo de pipeline comprometido parcial), es la barrera efectiva.

## Alternativa nativa (sin Kyverno)

Se puede implementar con una `ValidatingAdmissionPolicy` nativa (K8s ≥ 1.26 con
CEL) que, sobre CREATE de esas kinds en `5g-cp` con el label, deniegue si
`request.userInfo.username` no está en una lista permitida. Útil si no quieres
instalar Kyverno; la lógica y el alcance son idénticos.
