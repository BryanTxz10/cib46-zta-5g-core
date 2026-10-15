# CI/CD y roles de seguridad del despliegue

Automatización de la verificación del despliegue del testbed CIB46 mediante
GitHub Actions. El objetivo es que **nada que rompa el despliegue o introduzca
un secreto llegue a `main`**, en coherencia con el enfoque Zero Trust de la
investigación (desconfianza por defecto también en la cadena de CI/CD).

## Workflows

| Workflow | Archivo | Qué valida | Disparadores |
|---|---|---|---|
| **CI — Validación de despliegue** | `.github/workflows/ci.yml` | bash (shellcheck + `bash -n` + `make lint`), YAML (yamllint), Ansible (`--syntax-check` + ansible-lint), Kustomize (`build` de C0–C3), Python (`compileall` + ruff) | push, PR a `main`, manual |
| **Seguridad CI/CD** | `.github/workflows/security.yml` | Secretos (gitleaks), seguridad de los workflows (actionlint + zizmor), misconfiguraciones IaC/K8s (trivy, checkov, kube-linter) | push, PR a `main`, semanal (lunes 06:00 UTC), manual |

Réplica local del pipeline de CI:

```bash
make ci              # lint bash + yamllint + kustomize build C0-C3 + python
make kustomize-check # solo overlays de condición
```

## Roles de seguridad aplicados (hardening del pipeline)

Estos son los controles de seguridad exigidos a un CI/CD y cómo se cumplen:

1. **Mínimo privilegio del token.** Ambos workflows declaran
   `permissions: contents: read` a nivel global. El `GITHUB_TOKEN` no puede
   escribir en el repositorio, crear releases ni publicar paquetes.
2. **Acciones fijadas por SHA.** Toda `uses:` se referencia por su digest de
   commit inmutable (p. ej. `actions/checkout@11bd719…`), no por tag móvil.
   Evita ataques de reetiquetado en la cadena de suministro.
3. **Superficie de terceros mínima.** Las herramientas (gitleaks, trivy,
   kustomize, etc.) se descargan por **versión fijada** en pasos `run:` en vez
   de usar acciones de terceros no auditadas.
4. **Escaneo de secretos obligatorio.** `gitleaks` **bloquea** el merge si
   detecta credenciales. Las claves de laboratorio conocidas (IMSI/OPc de
   ejemplo de Open5GS/UERANSIM) están en una allowlist acotada
   (`.gitleaks.toml`) por ser valores públicos de test, no secretos reales.
5. **Seguridad de los propios workflows.** `actionlint` **bloquea** y `zizmor`
   audita patrones inseguros (inyección por `${{ }}`, permisos excesivos,
   checkout de referencias no confiables).
6. **Escaneo IaC/K8s informativo.** `trivy config`, `checkov` y `kube-linter`
   reportan misconfiguraciones. Son **no bloqueantes** porque el testbed usa a
   propósito contenedores privilegiados (TUN de UERANSIM), `--kubelet-insecure-tls`
   y kubeconfig modo 644: decisiones de laboratorio documentadas, no de producción.
7. **`concurrency` + `timeout-minutes`.** Cancelan ejecuciones obsoletas y
   acotan el tiempo de cada job (defensa frente a jobs colgados/abuso de minutos).
8. **Dependabot.** `.github/dependabot.yml` mantiene al día las acciones
   (por SHA) y las dependencias Python, aplicando parches de seguridad.
9. **Normalización de fin de línea.** `.gitattributes` fuerza **LF** en scripts
   y manifiestos: impide que un commit con CRLF desde Windows rompa los
   intérpretes bash (`#!/usr/bin/env bash` → "bad interpreter") en las VMs Ubuntu.

## Qué NO cubre el CI (requiere infraestructura)

El despliegue real (`make up` / `ansible-playbook site.yml`) necesita **3 nodos
Ubuntu 22.04** con k3s, SCTP y acceso SSH (ver `REPRODUCIBILITY.md`). El CI
valida la **corrección** de todo lo que se ejecuta (sintaxis, esquema, build),
pero no levanta el clúster 5G: eso se hace sobre las VMs del testbed.

## Protección de rama recomendada

Para que los controles sean efectivos, exigir en `main` (Settings → Branches):

- Requerir que pasen los checks: `lint-shell`, `lint-yaml`, `validate-ansible`,
  `validate-manifests`, `lint-python`, `secret-scan`, `actions-security`.
- Requerir PR con revisión antes de merge.
- Prohibir push directo a `main`.
