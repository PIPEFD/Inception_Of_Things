# CLAUDE.md

Contexto del proyecto Inception-of-Things (IoT) de 42.

## Cómo quiero que trabajes aquí

**No escribas el código evaluable por mí.** Las partes p1, p2, p3 y bonus son
un ejercicio de aprendizaje: si no puedo explicar cada línea en la defensa, no
sirve. Explica conceptos, revisa lo que escribo, señala errores y propón
alternativas — pero el Vagrantfile, los manifiestos y los scripts del subject
los escribo yo.

El andamiaje (Makefile, Terraform, Ansible, documentación) sí es territorio
compartido: ahí puedes proponer y escribir, siempre explicando el porqué.

Cuando revises algo, busca en este orden: secretos o IPs escritas a mano,
fallos silenciosos, superficie de red innecesaria, y acoplamiento que impida
que un tercero lo ejecute sin editar nada.

## Decisión de arquitectura

El equipo de desarrollo es ARM64 (Apple Silicon), donde VirtualBox no está
soportado. En vez de emular x86, el hipervisor vive en una VM de Azure con
virtualización anidada y el portátil queda reducido a un cliente ligero. Eso
hace el proyecto reproducible desde macOS ARM o Intel, Linux, o Windows+WSL2.

Consecuencia: el provider de Vagrant es `libvirt`, no VirtualBox. El ejemplo
del subject usa `modifyvm`, que es sintaxis de VirtualBox.

### Capas y contratos

| Capa | Qué es | Herramienta | Contrato |
|------|--------|-------------|----------|
| 0 | Cliente | git, ssh, az, terraform, ansible, make | Puede orquestar |
| 1 | Infraestructura | Terraform | Host x86 con KVM vía SSH |
| 2 | Host | Ansible | Puede ejecutar el subject |
| 3 | Proyecto | Vagrant, K3s, K3d, Argo CD | Entregables de 42 |

Detalle en `docs/arquitectura.md` y `docs/decisiones.md`.

## Restricciones duras

- **El tamaño de VM debe soportar virtualización anidada**: Dv3/Dv4/Dv5,
  Ev3/Ev4/Ev5, Fsv2. Las series B NO. Fallo silencioso: la VM se crea bien y
  `kvm-ok` falla después.
- **`p3` no lleva Vagrantfile.** Usa K3d, que son contenedores Docker sobre el
  host. Solo p1, p2 y bonus tienen VMs.
- **Los nombres `p1`, `p2`, `p3`, `bonus` son literales** y van en la raíz.
- **En p2, la app por defecto es la regla de Ingress SIN campo `host`**, no una
  tercera regla con nombre.
- **El orden de los roles de Ansible importa**: `kvm` antes que `vagrant`,
  porque el plugin vagrant-libvirt se compila y necesita `libvirt-dev`.
- **Nada de secretos en el repositorio.** El repo público de p3 no debe
  contener nada de `infra/`.

## Convenciones

- Ramas cortas: `feat/`, `fix/`, `docs/`. Merge a `main` cuando el criterio de
  cierre del hito se cumple. `main` siempre defendible.
- Commits que explican el porqué, no el qué, y referencian el issue.
- Un hito solo está cerrado si su criterio se cumple **tras destruir y
  reconstruir**. "Funciona ahora mismo" no cuenta.
- `docs/diario.md` se actualiza con cada problema resuelto: es la fuente
  principal de la memoria del RNCP7.

## Punto de entrada

`make help` lista todo. El orden es: `make bootstrap` (cliente) →
`make infra provision` (host) → `make p1 p2 p3` → `make verify`.
`make rebuild` es la prueba de reproducibilidad completa.

## Contexto de evaluación

Dos evaluaciones distintas con el mismo trabajo:

- **42**: se evalúan solo `p1`, `p2`, `p3`, `bonus`. Defensa en vivo, con
  preguntas conceptuales (K3s vs K3d, reconciliación, Ingress).
- **RNCP7 nivel 7**: se evalúa el criterio, no el código. Importan las
  decisiones justificadas, los problemas resueltos y la trazabilidad.

Proyecto en pareja: ambos deben poder explicar las tres partes. Al cerrar cada
hito, lo verifica y explica quien no lo escribió.
