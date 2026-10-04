# Makefile — automatización de extremo a extremo del testbed CIB46.
# Objetivo: recrear el entorno y ejecutar el experimento con comandos cortos.
# Cada objetivo es idempotente (delega en los scripts de bootstrap/).

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---- Infraestructura (Ansible = recomendado; bash = respaldo) --------------
.PHONY: ansible-up
ansible-up: ## Despliega con Ansible (recomendado). Corre en ansible/
	cd ansible && ansible-playbook site.yml

.PHONY: up
up: ## Despliega con bash (respaldo): k3s -> Cilium -> ... -> C0
	bash bootstrap/bootstrap.sh

.PHONY: up-no-spire
up-no-spire: ## Igual que 'up' pero omite SPIRE (no afecta métricas C0-C3)
	bash bootstrap/bootstrap.sh --skip-spire

.PHONY: prereqs
prereqs: ## Verifica prerrequisitos del host
	bash bootstrap/00-prereqs.sh

# ---- Condiciones experimentales --------------------------------------------
.PHONY: c0 c1 c2 c3
c0: ## Transición a C0 (baseline)
	cd cilium-policies && bash transition-to-c0.sh
c1: ## Transición a C1 (microsegmentación L3/L4)
	cd cilium-policies && bash transition-to-c1.sh
c2: ## Transición a C2 (identidad de workload)
	cd cilium-policies && bash transition-to-c2.sh
c3: ## Transición a C3 (autorización L7 por rol)
	cd cilium-policies && bash transition-to-c3.sh

.PHONY: condition
condition: ## Transición declarativa con Kustomize (uso: make condition C=c1)
	kubectl delete ciliumnetworkpolicy -A -l cib46.io/managed=true 2>/dev/null || true
	kustomize build --load-restrictor=LoadRestrictionsNone cilium-policies/conditions/$(C) | kubectl apply -f -

# ---- Verificación (RM-01: plano de control, no ICMP) -----------------------
.PHONY: smoke
smoke: ## Prueba de humo del plano de control (uso: make smoke C=C1)
	bash bootstrap/checks/smoke-control-plane.sh $(C)

# ---- Análisis (RM-03/07: efecto congruente + ómnibus/post-hoc) -------------
.PHONY: analyze-latency
analyze-latency: ## Ómnibus + post-hoc de latencia (uso: make analyze-latency CSV=archivo.csv)
	python3 bootstrap/analysis/omnibus_posthoc.py $(CSV) latency_ms condicion

.PHONY: analyze-effect
analyze-effect: ## Tamaños de efecto por rangos (uso: make analyze-effect CSV=.. COL=..)
	python3 bootstrap/analysis/effect_sizes.py $(CSV) $(COL) condicion

# ---- Utilidades -------------------------------------------------------------
.PHONY: lint
lint: ## Chequeo de sintaxis de todos los scripts bash
	@for f in bootstrap/*.sh bootstrap/checks/*.sh cilium-policies/*.sh \
	          attack-scripts/*.sh monitoring/*.sh helm-values/*.sh \
	          cilium-policies/c2/*.sh; do bash -n "$$f" && echo "ok  $$f"; done

.PHONY: status
status: ## Estado rápido del testbed
	kubectl get pods -A | grep -E '5g-|cilium|multus|spire|metrics' || true
	kubectl get ciliumnetworkpolicies -A || true

.PHONY: help
help: ## Muestra esta ayuda
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	 awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
