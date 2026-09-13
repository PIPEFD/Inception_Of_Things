# Arquitectura

## Capas y contratos

| Capa | Qué es | Herramienta | Contrato |
|------|--------|-------------|----------|
| 0 | Cliente | git, ssh, az, terraform, ansible, make | Puede orquestar |
| 1 | Infraestructura | Terraform | Host x86 con KVM vía SSH |
| 2 | Host | Ansible | Puede ejecutar el subject |
| 3 | Proyecto | Vagrant, K3s, K3d, Argo CD | Entregables de 42 |

Razón de la capa 1 (detalle en `docs/decisiones.md`): el equipo es ARM64
(Apple Silicon), donde VirtualBox no está soportado. En vez de emular x86, el
hipervisor vive en una VM de Azure con virtualización anidada, y el portátil
queda reducido a un cliente ligero. El provider de Vagrant es `libvirt`, no
VirtualBox — el ejemplo del subject usa `modifyvm`, que es sintaxis de
VirtualBox y no aplica aquí.

## Estructura de entregables (capa 3)

Los nombres `p1`, `p2`, `p3`, `bonus` son literales y van en la raíz del
repo. Dentro de cada uno, el subject exige separar scripts de configuración:

```
p1/
├── Vagrantfile
├── scripts/     # provisioning, instalación de K3s, etc.
└── confs/       # manifiestos, ficheros de configuración
p2/
├── Vagrantfile
├── scripts/
└── confs/
p3/              # sin Vagrantfile: K3d sobre contenedores Docker del host
├── scripts/
└── confs/
bonus/           # opcional, solo se evalúa si p1+p2+p3 están impecables
├── scripts/
└── confs/
```

### p1 — K3s y Vagrant

- 2 VMs: `<login>S` (control-plane, K3s server) y `<login>SW` (K3s agent).
- IPs fijas en la interfaz primaria: `192.168.56.110` (S) y `192.168.56.111`
  (SW).
- SSH sin contraseña entre máquinas.
- Recursos mínimos: 1 CPU, 512–1024 MB RAM.
- Requiere `kubectl` instalado en las VMs.

### p2 — K3s y tres aplicaciones

- 1 sola VM, K3s en modo server.
- 3 apps expuestas por Ingress, enrutadas por `Host` header contra la IP
  `192.168.56.110`:
  - `Host: app1.com` → app1
  - `Host: app2.com` → app2 (3 réplicas)
  - cualquier otro Host (regla **sin** campo `host`, no una tercera regla
    con nombre) → app3 por defecto

### p3 — K3d y Argo CD

- Sin Vagrantfile: K3d = contenedores Docker sobre el host, no VMs.
- Requiere Docker instalado (documentar en un script de bootstrap).
- Dos namespaces: `argocd` y `dev`.
- App desplegada en `dev` por Argo CD desde un repo GitHub público propio
  (el nombre del repo debe incluir el login de un miembro del equipo).
- La app debe tener dos versiones (tags `v1` y `v2` en Docker Hub), y hay
  que poder cambiar de versión editando el repo Git y viendo el sync
  automático de Argo CD.

### bonus — GitLab

- GitLab corriendo localmente, namespace dedicado `gitlab`.
- Todo lo de p3 debe funcionar contra este GitLab local en vez de GitHub.
- Solo se evalúa si el resto del mandatory está impecable (criterio de
  cierre estricto: no solo "hecho", sino sin fallos).

## Punto de entrada

`make help` lista todo. Orden de ejecución:

```
make bootstrap        # capa 0: cliente
make infra provision  # capa 1+2: host remoto con KVM
make p1 p2 p3         # capa 3: entregables
make verify
```

`make rebuild` es la prueba de reproducibilidad completa: un hito solo está
cerrado si su criterio se cumple tras destruir y reconstruir.
