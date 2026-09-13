SHELL := /bin/bash
.DEFAULT_GOAL := help

# ─── Configuración ─────────────────────────────────────────────
# TODO: ajusta a tu suscripción y región
RG          ?= rg-iot-42
LOCATION    ?= swedencentral
VM_NAME     ?= vm-iot-host
# Debe coincidir con admin_username en infra/terraform/variables.tf --
# antes estaba repetido a mano en 4 sitios distintos de este Makefile.
ADMIN_USER  ?= azureuser
SSH_KEY     ?= $(HOME)/.ssh/iot42_rsa
TF_DIR      ?= infra/terraform
ANSIBLE_DIR ?= infra/ansible
VAULT_PASS_FILE ?= $(HOME)/.iot42_vault_pass

# IP del host: se obtiene de la salida de Terraform, nunca se escribe a mano
HOST_IP = $(shell cd $(TF_DIR) && terraform output -raw public_ip 2>/dev/null)
SSH     = ssh -i $(SSH_KEY) -o StrictHostKeyChecking=accept-new $(ADMIN_USER)@$(HOST_IP)
REMOTE  = /home/$(ADMIN_USER)/iot

# .env (gitignored): credenciales del Service Principal de Azure, así
# terraform no depende de 'az login' interactivo de cada persona. Si no
# existe, estas variables quedan vacías y terraform sigue usando la sesión
# az normal -- .env es opcional, no obligatorio.
-include .env
export ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_TENANT_ID ARM_SUBSCRIPTION_ID
# También exportados para que Ansible los lea vía lookup('env', ...) en
# group_vars/iot_host.yml -- una sola fuente de verdad (este Makefile /
# .env), en vez de repetir "azureuser" otra vez dentro de Ansible.
export ADMIN_USER SSH_KEY

# ─── Sistema cliente ────────────────────────────────────────────
# Distingue macOS / WSL-Ubuntu / Ubuntu nativo. WSL se detecta aparte de
# Linux porque comparte kernel con Windows (uname -s da "Linux" en ambos)
# pero no tiene entorno gráfico propio: abrir un navegador, por ejemplo,
# necesita delegar en Windows en vez de xdg-open.
UNAME_S := $(shell uname -s)
IS_WSL  := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo 1)

ifeq ($(UNAME_S),Darwin)
  CLIENT_OS := macos
  OPEN_CMD  := open
else ifeq ($(IS_WSL),1)
  CLIENT_OS := wsl
  OPEN_CMD  := cmd.exe /c start
else
  CLIENT_OS := linux
  OPEN_CMD  := xdg-open
endif

# ─── Colores ─────────────────────────────────────────────────────
# Activos por defecto. Se desactivan con NO_COLOR=1 (convención de
# no-color.org), para CI o `make ... > log`.
#
# Nota: NO se puede detectar terminal con `$(shell test -t 1)` aquí — la
# función $(shell ...) de Make siempre captura la salida del comando por
# una tubería para leerla, así que ese test vería siempre una tubería y
# jamás una terminal, sin importar cómo se invoque `make` realmente.
ifdef NO_COLOR
  C_RESET  :=
  C_BOLD   :=
  C_RED    :=
  C_GREEN  :=
  C_YELLOW :=
  C_BLUE   :=
  C_CYAN   :=
else
  C_RESET  := \033[0m
  C_BOLD   := \033[1m
  C_RED    := \033[31m
  C_GREEN  := \033[32m
  C_YELLOW := \033[33m
  C_BLUE   := \033[34m
  C_CYAN   := \033[36m
endif

# Cabecera de sección: $(call log_section,texto). Es su propia línea de
# receta (lleva @ incluido), no se encadena con ; \ como los log_* de abajo.
define log_section
	@printf "\n$(C_BOLD)$(C_BLUE)▶ %s$(C_RESET)\n" "$(1)"
endef

# Indicadores de paso: $(1)=etiqueta $(2)=detalle. Sin @: se usan dentro de
# cadenas "; \" ya prefijadas por un @ en la primera línea de la receta
# (igual que check_version más abajo).
define log_ok
	printf "  $(C_GREEN)[OK]$(C_RESET)     %-18s %s\n" "$(1)" "$(2)"
endef
define log_fail
	printf "  $(C_RED)[FALTA]$(C_RESET)  %-18s %s\n" "$(1)" "$(2)"
endef

# Spinner para comandos silenciosos y lentos (az vm start/deallocate: 30s-2min
# sin salida). NO usar con terraform/ansible/vagrant: ahí el output en vivo
# es justo lo que hay que ver, taparlo sería el "fallo silencioso" que este
# proyecto evita a propósito (ver CLAUDE.md).
# $(1)=etiqueta mostrada  $(2)=comando a ejecutar. Es su propia línea de
# receta (lleva @ incluido).
define with_spinner
	@log=$$(mktemp); \
	( $(2) ) >"$$log" 2>&1 & \
	pid=$$!; \
	spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; i=0; \
	while kill -0 $$pid 2>/dev/null; do \
	  i=$$(( (i + 1) % $${#spin} )); \
	  printf "\r$(C_CYAN)%s$(C_RESET) %s" "$${spin:$$i:1}" "$(1)"; \
	  sleep 0.1; \
	done; \
	wait $$pid; status=$$?; \
	if [ $$status -eq 0 ]; then \
	  printf "\r$(C_GREEN)✔$(C_RESET) %s\n" "$(1)"; \
	else \
	  printf "\r$(C_RED)✘$(C_RESET) %s (falló, código %s)\n" "$(1)" "$$status"; \
	  cat "$$log"; \
	fi; \
	rm -f "$$log"; \
	exit $$status
endef
define log_warn
	printf "  $(C_YELLOW)[AVISO]$(C_RESET)  %-18s %s\n" "$(1)" "$(2)"
endef

.PHONY: help infra infra-plan inventory provision check-host \
        p1 p1-check p2 p2-check p3 p3-check verify \
        ssh tunnel start stop destroy clean rebuild

# ─── Ayuda ────────────────────────────────────────────────────
help: ## Muestra esta ayuda
	@printf "$(C_BOLD)Inception-of-Things — comandos disponibles$(C_RESET)\n"
	@awk ' \
	  BEGIN { FS = ":.*?## " } \
	  /^# ─── .* ───/ { \
	    line = $$0; gsub(/^# ─── /, "", line); gsub(/ *─*$$/, "", line); \
	    pending = line; next \
	  } \
	  /^[a-zA-Z0-9_-]+:.*?## / { \
	    if (pending != "") { \
	      printf "\n$(C_BOLD)$(C_BLUE)%s$(C_RESET)\n", pending; pending = "" \
	    } \
	    printf "  $(C_CYAN)%-14s$(C_RESET) %s\n", $$1, $$2 \
	  } \
	' $(MAKEFILE_LIST)

# ─── Guardas ───────────────────────────────────────────────────
require-host:
	@test -n "$(HOST_IP)" || { echo "No hay host. Ejecuta 'make infra' primero."; exit 1; }

# ─── Capa 1: infraestructura ───────────────────────────────────
infra-plan: ## Muestra el plan de Terraform sin aplicarlo
	cd $(TF_DIR) && terraform init -input=false && terraform plan

infra: ## Crea la VM Azure con virtualización anidada
	$(call log_section,Creando la VM en Azure)
	cd $(TF_DIR) && terraform init -input=false && terraform apply -auto-approve
	@echo "Host disponible en $(HOST_IP)"

inventory: require-host ## Genera el inventario de Ansible desde la salida de Terraform
	@# Solo la IP -- lo único realmente dinámico. Usuario/clave/intérprete
	@# viven en group_vars/iot_host.yml, expandidos desde el mismo entorno
	@# (ADMIN_USER/SSH_KEY) que usa este Makefile: una sola fuente de verdad.
	@printf '[iot_host]\n%s\n' "$(HOST_IP)" > $(ANSIBLE_DIR)/inventory.ini
	@printf "$(C_GREEN)Inventario escrito:$(C_RESET) %s (%s)\n" "$(ANSIBLE_DIR)/inventory.ini" "$(HOST_IP)"

# ─── Capa 2: aprovisionamiento del host ────────────────────────
provision: require-host inventory ## Instala KVM, Vagrant, Docker, kubectl y k3d
	$(call log_section,Aprovisionando el host)
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.ini site.yml --vault-password-file $(VAULT_PASS_FILE)

check-host: require-host ## Verifica que el host puede virtualizar y tiene las herramientas
	@# TODO: kvm-ok, vagrant --version, docker info, k3d version
	$(SSH) 'kvm-ok'

# ─── Capa 3: el proyecto ───────────────────────────────────────
p1: require-host ## Levanta el clúster de dos nodos (K3s server + agent)
	$(call log_section,p1: K3s server + agent)
	$(SSH) 'cd $(REMOTE)/p1 && vagrant up'

p1-check: require-host ## Comprueba que ambos nodos están Ready con las IPs correctas
	@# TODO: kubectl get nodes -o wide y validar 192.168.56.110/.111
	@echo "TODO: verificación p1"

p2: require-host ## Levanta el nodo único con las tres apps y el Ingress
	$(call log_section,p2: tres apps tras el Ingress)
	$(SSH) 'cd $(REMOTE)/p2 && vagrant up'

p2-check: require-host ## Verifica el enrutado por cabecera Host (app1, app2, default)
	@# TODO: curl -H "Host: app1.com" 192.168.56.110 y comprobar la respuesta
	@echo "TODO: verificación p2"

p3: require-host ## Crea el clúster k3d con Argo CD y la aplicación en dev
	$(call log_section,p3: K3d + Argo CD)
	$(SSH) 'cd $(REMOTE)/p3 && ./scripts/install.sh && ./scripts/deploy.sh'

p3-check: require-host ## Comprueba los namespaces y la versión desplegada
	@# TODO: kubectl get ns, kubectl get pods -n dev, curl a la app
	@echo "TODO: verificación p3"

verify: check-host p1-check p2-check p3-check ## Ejecuta todas las verificaciones
	$(call log_section,Verificación completa)
	@printf "$(C_GREEN)$(C_BOLD)Todo verificado.$(C_RESET)\n"

# ─── Operación ─────────────────────────────────────────────────
ssh: require-host ## Abre una sesión en el host
	$(SSH)

tunnel: require-host ## Túnel SSH para la interfaz de Argo CD (localhost:8080)
	@( sleep 1 && $(OPEN_CMD) http://localhost:8080 >/dev/null 2>&1 & )
	ssh -i $(SSH_KEY) -L 8080:localhost:8080 $(ADMIN_USER)@$(HOST_IP) -N

start: ## Arranca la VM (antes de una sesión de trabajo o la defensa)
	$(call with_spinner,Arrancando $(VM_NAME)...,az vm start -g $(RG) -n $(VM_NAME))

stop: ## Libera la VM para dejar de pagar cómputo
	$(call with_spinner,Deteniendo $(VM_NAME)...,az vm deallocate -g $(RG) -n $(VM_NAME))

destroy: ## Destruye toda la infraestructura (pide confirmación)
	@read -p "Esto borra la VM y todo su contenido. ¿Seguro? [escribe 'si'] " ok; \
	  [ "$$ok" = "si" ] || { echo "Cancelado."; exit 1; }
	$(call log_section,Destruyendo infraestructura)
	cd $(TF_DIR) && terraform destroy -auto-approve

rebuild: destroy infra provision verify ## Prueba de reproducibilidad completa desde cero
	$(call log_section,Reconstrucción completa)
	@printf "$(C_GREEN)$(C_BOLD)Reconstrucción terminada.$(C_RESET)\n"

# ─── Capa 0: puesta a punto del cliente ────────────────────────
# Herramientas sin versión mínima exigida: basta con que existan.
PLAIN_TOOLS := git ssh make

# Herramientas con versión mínima: fallos de sintaxis o de provider por una
# versión vieja son un fallo silencioso típico (funciona en tu máquina,
# falla en la del compañero o en la VM de la defensa).
TF_MIN  := 1.7.0
ANS_MIN := 2.15.0
AZ_MIN  := 2.60.0

.PHONY: doctor ssh-key login bootstrap vault-pass vault-edit vault-view

# $(1)=nombre mostrado  $(2)=versión mínima  $(3)=comando que imprime la versión instalada
define check_version
	ver=$$($(3) 2>/dev/null || echo "0.0.0"); \
	if [ -z "$$ver" ]; then ver="0.0.0"; fi; \
	if printf '%s\n%s\n' "$(2)" "$$ver" | sort -V | head -1 | grep -qx "$(2)"; then \
	  $(call log_ok,$(1),$$ver); \
	else \
	  printf "  $(C_RED)[FALLA]$(C_RESET)  %-18s %s (mínimo $(2))\n" "$(1)" "$$ver"; fail=1; \
	fi
endef

doctor: ## Verifica herramientas, versiones mínimas, clave SSH y sesión de Azure
	@fail=0; \
	printf "$(C_BOLD)Sistema cliente:$(C_RESET) %s\n" "$(CLIENT_OS)"; \
	printf "$(C_BOLD)Herramientas (solo presencia):$(C_RESET)\n"; \
	for t in $(PLAIN_TOOLS); do \
	  if command -v $$t >/dev/null 2>&1; then \
	    if [ "$$t" = "ssh" ]; then vflag="-V"; else vflag="--version"; fi; \
	    $(call log_ok,$$t,$$($$t $$vflag 2>&1 | head -1 | cut -c1-40)); \
	  else \
	    $(call log_fail,$$t,); fail=1; \
	  fi; \
	done; \
	printf "$(C_BOLD)Herramientas (con versión mínima):$(C_RESET)\n"; \
	if command -v terraform >/dev/null 2>&1; then \
	  $(call check_version,terraform,$(TF_MIN),terraform version -json | python3 -c "import sys; import json; print(json.load(sys.stdin)['terraform_version'])"); \
	else \
	  $(call log_fail,terraform,); fail=1; \
	fi; \
	if command -v ansible-playbook >/dev/null 2>&1; then \
	  $(call check_version,ansible-playbook,$(ANS_MIN),ansible-playbook --version < /dev/null 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	else \
	  $(call log_fail,ansible-playbook,); fail=1; \
	fi; \
	if command -v az >/dev/null 2>&1; then \
	  $(call check_version,az,$(AZ_MIN),az version -o json | python3 -c "import sys; import json; print(json.load(sys.stdin)['azure-cli'])"); \
	else \
	  $(call log_fail,az,); fail=1; \
	fi; \
	printf "$(C_BOLD)Clave SSH:$(C_RESET)\n"; \
	if [ -f "$(SSH_KEY)" ]; then \
	  perms=$$(stat -f "%Lp" "$(SSH_KEY)" 2>/dev/null || stat -c "%a" "$(SSH_KEY)"); \
	  if [ "$$perms" = "600" ]; then $(call log_ok,$(SSH_KEY),); \
	  else $(call log_warn,$(SSH_KEY),permisos $$perms (deben ser 600)); fail=1; fi; \
	else \
	  $(call log_fail,$(SSH_KEY),ejecuta 'make ssh-key'); fail=1; \
	fi; \
	printf "$(C_BOLD)Azure:$(C_RESET)\n"; \
	if az account show >/dev/null 2>&1; then \
	  $(call log_ok,suscripción,$$(az account show --query name -o tsv)); \
	else \
	  $(call log_fail,az login,ejecuta 'make login'); fail=1; \
	fi; \
	if [ $$fail -eq 0 ]; then printf "$(C_GREEN)$(C_BOLD)Cliente listo.$(C_RESET)\n"; \
	else printf "$(C_RED)$(C_BOLD)Faltan requisitos (ver arriba).$(C_RESET)\n"; exit 1; fi

# RSA y no ed25519: el provider azurerm de Terraform valida en el propio
# cliente que la clave de admin_ssh_key sea RSA y rechaza ed25519, aunque
# Azure sí lo acepta a nivel de API. No es cosa de versión del provider.
ssh-key: ## Genera la clave SSH del proyecto si no existe
	@if [ -f "$(SSH_KEY)" ]; then \
	  printf "$(C_YELLOW)Ya existe:$(C_RESET) %s\n" "$(SSH_KEY)"; \
	else \
	  mkdir -p $$(dirname $(SSH_KEY)); \
	  ssh-keygen -t rsa -b 4096 -f $(SSH_KEY) -C "iot-42" -N ""; \
	  chmod 600 $(SSH_KEY); \
	  printf "$(C_GREEN)Clave creada.$(C_RESET) La pública se pasa a Terraform, la privada NUNCA se versiona.\n"; \
	fi

login: ## Inicia sesión en Azure y muestra la suscripción activa
	@az account show >/dev/null 2>&1 || az login
	@az account show --query "{suscripcion:name, id:id}" -o table

vault-pass: ## Genera la contraseña del vault si no existe (fuera del repo)
	@if [ -f "$(VAULT_PASS_FILE)" ]; then \
	  printf "$(C_YELLOW)Ya existe:$(C_RESET) %s\n" "$(VAULT_PASS_FILE)"; \
	else \
	  openssl rand -base64 32 > "$(VAULT_PASS_FILE)"; \
	  chmod 600 "$(VAULT_PASS_FILE)"; \
	  printf "$(C_GREEN)Contraseña del vault creada.$(C_RESET) NUNCA se versiona.\n"; \
	fi

vault-edit: vault-pass ## Edita infra/ansible/group_vars/all/vault.yml cifrado
	cd $(ANSIBLE_DIR) && EDITOR=$${EDITOR:-vi} ansible-vault edit group_vars/all/vault.yml --vault-password-file $(VAULT_PASS_FILE)

vault-view: vault-pass ## Muestra el contenido descifrado (solo en tu terminal, no lo compartas)
	cd $(ANSIBLE_DIR) && ansible-vault view group_vars/all/vault.yml --vault-password-file $(VAULT_PASS_FILE)

bootstrap: ssh-key login doctor ## Deja el cliente listo desde cero
	$(call log_section,Cliente listo)
