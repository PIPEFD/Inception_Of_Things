#!/usr/bin/env bash
set -euo pipefail

# Crea las etiquetas e issues del proyecto IoT.
# Requiere: gh auth login, y estar dentro del repositorio.
#
# TODO: sustituye los responsables antes de ejecutar
A="usuario-a"
B="usuario-b"

# ─── Etiquetas ─────────────────────────────────────────────────
gh label create hito     --color 0E8A16 --description "Entregable con criterio de cierre" --force
gh label create infra    --color 1D76DB --description "Capas 1 y 2: Azure, Terraform, Ansible" --force
gh label create k8s      --color 5319E7 --description "Capa 3: K3s, K3d, Argo CD" --force
gh label create docs     --color FBCA04 --description "Memoria, diario y decisiones" --force
gh label create bloqueo  --color B60205 --description "Impide avanzar en otra tarea" --force

issue() {
  gh issue create --title "$1" --label "$2" --assignee "$3" --body "$4"
}

# ─── Semana 1 — Corte vertical ─────────────────────────────────
issue "H1 — Host de Azure operativo (manual)" "hito,infra" "$A" \
'**Objetivo**
Crear a mano la VM de Azure y verificar que soporta virtualización anidada.
Anotar cada comando: son el borrador del playbook de Ansible.

**Criterio de cierre**
`kvm-ok` en el host responde que la aceleración KVM está disponible.

**Ojo**
El tamaño debe ser de una serie con anidación (Dv3/Dv4/Dv5, Ev3/Ev4/Ev5, Fsv2).
Las series B se crean sin error y fallan después.'

issue "H1b — Stack de virtualización instalado a mano" "hito,infra" "$B" \
'**Objetivo**
libvirt, Vagrant y el plugin vagrant-libvirt funcionando en el host.

**Criterio de cierre**
`vagrant up` levanta una VM cualquiera dentro del host, y
`virsh list` y `docker info` responden sin sudo.

**Trampa conocida**
El plugin se compila al instalarse: requiere libvirt-dev, ruby-dev, gcc, make.
Los grupos libvirt/kvm/docker no surten efecto hasta reabrir sesión.'

# ─── Semana 2 — p1 ─────────────────────────────────────────────
issue "H2 — p1: clúster K3s de dos nodos" "hito,k8s" "$A" \
'**Objetivo**
Vagrantfile con dos VMs: K3s en modo server y en modo agent.

**Criterio de cierre**
Tras `vagrant destroy -f && vagrant up`, `kubectl get nodes -o wide`
muestra ambos nodos Ready con 192.168.56.110 y .111.

**Verificación cruzada**
La ejecuta y explica quien no la escribió.'

issue "H2b — Experimentos de resiliencia en p1" "k8s" "$B" \
'**Objetivo**
Romper cosas a propósito para entender el bucle de reconciliación.
Parar el agente, borrar un pod, medir tiempos de recuperación.

**Criterio de cierre**
Anotado en docs/diario.md qué pasó en cada caso y por qué.'

# ─── Semana 3 — p2 ─────────────────────────────────────────────
issue "H3 — p2: tres aplicaciones tras un Ingress" "hito,k8s" "$B" \
'**Objetivo**
Tres apps en K3s, la segunda con 3 réplicas, enrutadas por cabecera Host.

**Criterio de cierre**
`curl -H "Host: app1.com" 192.168.56.110` devuelve app1, app2.com devuelve app2,
y cualquier otra cabecera devuelve app3.

**Concepto a defender**
La app por defecto es la regla SIN campo host, no una tercera regla con nombre.'

# ─── Semana 4 — p3 ─────────────────────────────────────────────
issue "H4 — Repositorio público de GitOps" "hito,k8s" "$A" \
'**Objetivo**
Repositorio público separado, con el login de un miembro en el nombre,
conteniendo solo los manifiestos de la aplicación.

**Criterio de cierre**
El repo existe, es público y no contiene nada de infra/.'

issue "H4b — p3: K3d y Argo CD sincronizando" "hito,k8s" "$A" \
'**Objetivo**
K3d sobre Docker, namespaces argocd y dev, aplicación desplegada desde GitHub.

**Criterio de cierre**
Cambiar el tag v1 → v2 en el repo público y hacer push actualiza el pod
sin tocar el clúster. `curl` a la app devuelve la nueva versión.

**Nota**
p3 NO lleva Vagrantfile. Si aparece uno, algo se ha entendido mal.'

issue "H4c — Script de instalación para la defensa" "k8s" "$B" \
'**Objetivo**
El subject exige un script que instale Docker, K3d y todo lo necesario
durante la defensa.

**Criterio de cierre**
Ejecutado sobre un host limpio, deja p3 listo sin pasos manuales.'

# ─── Semana 5 — Automatización ─────────────────────────────────
issue "H5 — Terraform: la VM de Azure como código" "hito,infra" "$B" \
'**Objetivo**
Resource group, red, NSG (solo 22 y restringido), IP pública estática, VM.

**Criterio de cierre**
`terraform apply` desde cero produce un host donde `kvm-ok` pasa.
Ninguna IP ni secreto escrito a mano en el código.

**Decisión pendiente**
Estado local documentado o backend remoto en un storage account.'

issue "H5b — Ansible: aprovisionamiento del host" "hito,infra" "$A" \
'**Objetivo**
Roles common, kvm, vagrant, docker, k3s-tools. Idempotente.

**Criterio de cierre**
Ejecutado dos veces seguidas, la segunda no cambia nada.
El rol kvm falla explícitamente si la anidación no está disponible.

**Orden**
kvm antes que vagrant: el plugin necesita libvirt-dev para compilar.'

issue "H5c — Verificaciones del Makefile" "hito,infra" "$B" \
'**Objetivo**
Implementar check-host, p1-check, p2-check y p3-check.

**Criterio de cierre**
`make verify` pasa en verde sobre un despliegue recién creado,
y falla con un mensaje útil si algo no está.

**Por qué importa**
Escribir los checks obliga a definir qué significa exactamente
que cada parte funciona.'

# ─── Semanas 6-8 ───────────────────────────────────────────────
issue "H6 — Decisión sobre el bonus (GitLab)" "hito,infra" "$A" \
'**Objetivo**
Decidir con criterio si se aborda GitLab en local o se consolida.

**Criterio de cierre**
Decisión escrita en docs/decisiones.md con su razonamiento.

**Recordatorio**
El bonus solo se evalúa si la parte obligatoria está impecable.'

issue "H7 — Prueba de reproducibilidad cronometrada" "hito,infra" "$B" \
'**Objetivo**
`make rebuild` desde cero, sin intervención manual, con el tiempo medido.

**Criterio de cierre**
Tiempo anotado en el README. Cualquier paso que exija tocar el teclado
se convierte en un issue nuevo.'

issue "H8 — Ensayo de defensa en frío" "hito,docs" "$A" \
'**Objetivo**
Defensa completa con la máquina apagada al empezar: az vm start, túnel SSH,
las tres partes demostradas, preguntas conceptuales entre ambos.

**Criterio de cierre**
Ambos pueden explicar las tres partes sin ayuda del otro.'

echo "Issues creadas. Revisa: gh issue list"
