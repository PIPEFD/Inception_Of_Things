# Seguridad — vault, .env y claves

Qué protege cada mecanismo, dónde vive, y cómo operarlo. Ver también las
prioridades de revisión y la restricción dura "nada de secretos en el
repositorio" en `CLAUDE.md`.

## Resumen: qué vive dónde

| Qué | Dónde | En el repo? | Cómo se protege |
|---|---|---|---|
| Clave SSH del proyecto (`iot42_rsa`) | `~/.ssh/` | No | Fuera del repo por completo; `.gitignore` la cubre igualmente por si acaso |
| Contraseña del vault | `~/.iot42_vault_pass` | No | Fuera del repo, permisos `600` |
| Credenciales del Service Principal, tokens (Docker Hub, etc.) | `infra/ansible/group_vars/all/vault.yml` | **Sí, cifrado** | AES256 vía `ansible-vault` |
| Credenciales del SP para Terraform | `.env` (raíz del repo) | No | `.gitignore`; solo existe en tu máquina |
| Plantilla de `.env` sin valores | `.env.example` | Sí | No tiene secretos, solo nombres de variable |

Regla general: si algo puede identificar o dar acceso a un recurso real
(IP, credencial, token), o no va en el repo, o va cifrado. Nunca en texto
plano versionado — ni siquiera en una rama descartada (si pasa, hay que
rotar la credencial, no basta con un `git revert`).

## El vault (`ansible-vault`)

### Qué hay dentro

`infra/ansible/group_vars/all/vault.yml`, cifrado con AES256. Ansible lo
carga automáticamente en cualquier playbook que apunte a `iot_host`
(`group_vars/all/` aplica a todos los hosts) — por eso **todo** playbook
necesita la contraseña del vault para correr, aunque ninguna tarea use
esas variables todavía.

Contenido actual: `azure_sp_app_id`, `azure_sp_password`, `azure_sp_tenant`
(credenciales del Service Principal), y placeholders para
`dockerhub_username`/`dockerhub_token` (para cuando p3 use una imagen
propia en vez de la de Wil).

### Configurar la contraseña por primera vez

```bash
make vault-pass
```

Genera `~/.iot42_vault_pass` (32 bytes aleatorios en base64, `chmod 600`).
Si ya existe, no la toca — no hay riesgo de sobrescribir sin querer.

### Desbloquear (ver el contenido)

```bash
make vault-view
```

Descifra y muestra por pantalla, solo en tu terminal — nunca lo pegues en
un chat, PR, o log compartido (por eso `make provision` no imprime el
contenido, solo lo usa internamente).

### Desbloquear para editar

```bash
make vault-edit
```

Abre el vault descifrado en `$EDITOR` (o `vi` por defecto), y al guardar
lo vuelve a cifrar automáticamente. Nunca queda un `.yml` en texto plano
en disco durante el proceso — `ansible-vault edit` lo gestiona en un
fichero temporal que borra al terminar.

### "Bloquear" — no hace falta un comando

El vault **siempre está cifrado en disco** (`group_vars/all/vault.yml`).
No existe un estado "desbloqueado persistente": cada `vault-view`/
`vault-edit`/`provision` lo descifra solo en memoria para esa ejecución.
Si quieres estar seguro de que no quedó nada en texto plano después de
editar, comprueba la cabecera:

```bash
head -c 30 infra/ansible/group_vars/all/vault.yml
# debe empezar por: $ANSIBLE_VAULT;1.1;AES256
```

### Rotar la contraseña del vault

```bash
cd infra/ansible
ansible-vault rekey group_vars/all/vault.yml --vault-password-file ~/.iot42_vault_pass
```

Te pide la contraseña nueva interactivamente. Después, actualiza
`~/.iot42_vault_pass` con el mismo valor para que `make provision` siga
funcionando sin pedirla a mano.

### Si se pierde la contraseña

No hay recuperación (es cifrado real, no ofuscación). Hay que:
1. Rotar el Service Principal: `az ad sp credential reset --id <appId>`.
2. Reescribir `vault.yml` desde cero con las credenciales nuevas y una
   contraseña nueva.

## `.env` (credenciales de Terraform)

### Para qué sirve

Terraform's provider `azurerm` puede autenticarse de dos formas:
- `az login` interactivo (lo que usa `make login` — requiere que cada
  persona tenga su propia sesión).
- Variables de entorno `ARM_*` (Service Principal) — no interactivo,
  reproducible entre máquinas y personas.

`.env` guarda la segunda opción. Si existe, el Makefile lo carga
automáticamente (`-include .env` + `export`) antes de cualquier target de
Terraform. Si no existe, Terraform cae de vuelta a tu sesión `az` normal
— `.env` es opcional, no rompe nada si falta.

### Configurarlo

```bash
cp .env.example .env
```

Rellena `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`,
`ARM_SUBSCRIPTION_ID` con los valores del Service Principal (los mismos
que están cifrados en el vault, en `azure_sp_*` — es la misma credencial,
usada por dos herramientas distintas).

Si no tienes el Service Principal creado todavía:

```bash
az ad sp create-for-rbac --name "sp-iot-42-terraform" --role Contributor \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-iot-42"
```

Scoped **solo** al resource group del proyecto, nunca a toda la
suscripción — si esa credencial se filtra, el daño queda acotado.

### Verificar que está cargado

```bash
make -n infra | head -1   # no imprime valores, solo confirma que el target usa las vars
env | grep ^ARM_           # esto sí las imprime -- solo en tu terminal, nunca lo compartas
```

## Claves SSH

`make ssh-key` genera `~/.ssh/iot42_rsa` (RSA 4096 — no ed25519, el
provider `azurerm` de Terraform rechaza esa última, ver
`docs/decisiones.md`). Vive fuera del repo por completo; `.gitignore`
además bloquea el patrón `*_rsa`/`*_rsa.pub` por si acaso alguien la crea
sin querer dentro del proyecto.

## Onboarding de un compañero de equipo

1. `make bootstrap` (genera su propia clave SSH, hace `az login`).
2. Le pasas — por un canal fuera de Git (1Password, Signal...):
   - La contraseña del vault (para que la ponga en su propio
     `~/.iot42_vault_pass`, con `chmod 600`).
   - Las credenciales del Service Principal si va a usar `.env`.
3. `make vault-view` para confirmar que puede descifrar.
4. Su clave pública SSH necesita añadirse a `authorized_keys` en el host
   (o regenerar la VM con `ssh_public_key_path` apuntando a la suya) — el
   `main.tf` actual solo acepta una clave pública.

## Qué hacer si algo se filtra

1. **Rotar primero, investigar después.** Una credencial filtrada se
   asume comprometida en el momento en que sale del repo, aunque sea en
   una rama borrada o un commit reescrito con `--amend`/`force-push` —
   sigue accesible en el historial de GitHub una vez empujada.
2. Service Principal: `az ad sp credential reset --id <appId>`, actualizar
   `.env` y `vault.yml` con la contraseña nueva.
3. Clave SSH: `make ssh-key` no sobrescribe una existente — borra la vieja
   a mano primero, o corre `ssh-keygen` directo, y actualiza
   `ssh_public_key_path` en Terraform antes del siguiente `apply`.
4. Contraseña del vault: ver "Rotar la contraseña del vault" arriba.
5. Anotar el incidente en `docs/diario.md` — es la traza que pide el
   RNCP7.
