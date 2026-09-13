# Decisiones de arquitectura

## ADR-001: Hipervisor remoto en Azure en vez de VirtualBox local

**Contexto.** El subject espera VMs gestionadas por Vagrant con VirtualBox
como ejemplo de provider. El equipo de desarrollo trabaja en ARM64 (Apple
Silicon), donde VirtualBox no tiene soporte.

**Opciones consideradas.**
- Emular x86_64 sobre ARM (QEMU sin aceleración): funcional pero
  extremadamente lento para levantar 2-3 VMs con K3s.
- UTM / VMware Fusion con soporte ARM nativo: no soporta virtualización
  anidada, que K3s con containerd puede necesitar según el runtime, y aleja
  el entorno del que verán los evaluadores en x86.
- Host remoto x86 con KVM, virtualización anidada, orquestado desde el
  portátil como cliente ligero: reproducible en cualquier arquitectura de
  cliente (macOS ARM/Intel, Linux, Windows+WSL2), porque el trabajo pesado
  ocurre en el host remoto.

**Decisión.** VM de Azure con virtualización anidada activada como host,
provisionada con Terraform y configurada con Ansible. El provider de Vagrant
pasa a ser `libvirt` en vez de `virtualbox`.

**Consecuencias.**
- El ejemplo de Vagrantfile del subject (con `modifyvm`, sintaxis de
  VirtualBox) no es aplicable directamente: hay que traducirlo a la sintaxis
  del provider `libvirt-vagrant`.
- Se añade una capa de infraestructura (Terraform) y una de configuración de
  host (Ansible) que el subject no pide pero que hacen falta para sostener
  esta elección — ver capas en `docs/arquitectura.md`.
- Coste y disponibilidad de Azure como dependencia externa del proyecto.

## ADR-002: Orden de roles de Ansible — kvm antes que vagrant

**Contexto.** El rol `vagrant` instala el plugin `vagrant-libvirt`, que se
compila en la propia máquina host.

**Decisión.** El rol `kvm` (que instala `libvirt-dev` y dependencias de
compilación) se ejecuta siempre antes que el rol `vagrant`.

**Consecuencias.** Si se invierte el orden, el playbook falla al compilar el
plugin, no siempre con un mensaje claro — hay que vigilar este orden en
cualquier refactor del Makefile o los playbooks.

## ADR-003: Tamaño de VM del host con virtualización anidada

**Contexto.** El host de Azure necesita exponer virtualización anidada (KVM
dentro de la VM) para correr las VMs de Vagrant encima.

**Decisión.** Usar series Dv3/Dv4/Dv5, Ev3/Ev4/Ev5 o Fsv2. Las series B están
descartadas explícitamente.

**Consecuencias — fallo silencioso conocido.** Con una serie B, la VM de
Azure se crea sin error, pero `kvm-ok` falla después al comprobar soporte de
virtualización anidada. Verificar el tamaño de la VM es el primer paso de
troubleshooting si `kvm-ok` falla.

## Notas de seguridad transversales

Al revisar cualquier cambio en este repo, el orden de prioridad es:

1. Secretos o IPs escritas a mano en el código versionado.
2. Fallos silenciosos (como el ADR-003 de arriba).
3. Superficie de red innecesaria.
4. Acoplamiento que impida a un tercero ejecutar el proyecto sin editar
   nada.

Restricción dura del subject: nada de secretos en el repositorio. El repo
público de p3 (y el de bonus si aplica) no debe contener nada de `infra/`.
