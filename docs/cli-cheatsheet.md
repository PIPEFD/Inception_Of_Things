# Hoja de comandos — Azure CLI y Terraform

Comandos para inspeccionar el estado real de la infraestructura sin pasar
por el Makefile. Útiles para depurar cuando algo no cuadra entre lo que
Terraform cree que existe y lo que hay de verdad en Azure.

Variables usadas abajo (ajusta si cambiaste los defaults):

```bash
RG=rg-iot-42
VM=vm-iot-host
LOCATION=swedencentral
TF_DIR=infra/terraform
```

## Azure CLI

### Sesión y suscripción

```bash
az account show --query "{sub:name, id:id}" -o table   # sesión activa
az account list -o table                               # todas las suscripciones disponibles
az account set --subscription "<nombre o id>"           # cambiar de suscripción
```

### Inventario de recursos

```bash
az group list -o table                                  # todos los resource groups
az resource list -g $RG -o table                        # todo lo que hay dentro de rg-iot-42
az resource list -g $RG --query "[].{name:name, type:type}" -o table
```

### La VM

```bash
az vm list -d -o table                                          # todas las VMs, con IP y estado
az vm show -g $RG -n $VM -d -o table                             # detalle de esta VM
az vm get-instance-view -g $RG -n $VM \
  --query "instanceView.statuses[].{code:code, message:displayStatus}" -o table
az vm start -g $RG -n $VM                                        # arrancar
az vm deallocate -g $RG -n $VM                                   # liberar cómputo (deja de facturar CPU)
az vm resize -g $RG -n $VM --size Standard_D4d_v4                # cambiar tamaño (VM debe estar deallocated)
```

### Cuota — antes de crear o redimensionar

```bash
az vm list-usage --location $LOCATION -o table
az vm list-usage --location $LOCATION \
  --query "[?contains(localName, 'Dv4') || contains(localName,'DDv4')]" -o table
az vm list-skus --location $LOCATION --size Standard_D --all -o table   # tamaños disponibles en la región
```

### Red — lo que expone el NSG hacia fuera

```bash
az network nsg list -g $RG -o table
az network nsg rule list -g $RG --nsg-name iot-nsg -o table
az network public-ip show -g $RG -n iot-public-ip --query ipAddress -o tsv
az network nic show -g $RG -n iot-nic --query "ipConfigurations[].privateIPAddress" -o tsv
```

### Coste

```bash
az consumption usage list --start-date $(date -v-7d +%F) --end-date $(date +%F) \
  --query "[?contains(instanceName, 'vm-iot-host')]" -o table   # macOS (date -v-7d)
# En Linux/WSL: date -d '7 days ago' +%F
az billing invoice list -o table                        # facturas (si la suscripción lo soporta)
```

### Logs y actividad — por qué falló algo

```bash
az monitor activity-log list -g $RG --max-events 20 -o table
az monitor activity-log list -g $RG --status Failed --max-events 10 -o table
```

### Destruir a mano (si Terraform pierde el estado)

```bash
az group delete -n $RG --yes --no-wait     # borra TODO el resource group, sin confirmar
```

## Terraform

### Estado

```bash
cd $TF_DIR
terraform state list                       # todos los recursos que Terraform cree gestionar
terraform state show azurerm_linux_virtual_machine.iot
terraform show                             # estado completo, legible
terraform show -json | jq .                # estado completo, para procesar
```

### Plan y diffs

```bash
terraform plan                             # qué cambiaría
terraform plan -out=tfplan                 # guardarlo para aplicar exactamente eso
terraform apply tfplan                     # aplicar el plan guardado (no el "actual" del momento)
terraform plan -destroy                    # qué borraría, sin borrar
terraform plan -target=azurerm_linux_virtual_machine.iot   # solo un recurso
```

### Outputs

```bash
terraform output                           # todos
terraform output -raw public_ip            # uno solo, sin comillas (lo que usa el Makefile)
terraform output -json | jq .              # para scripts
```

### Cuando el estado y la realidad no coinciden

```bash
terraform refresh                          # releer el estado real desde Azure (deprecado, usar plan -refresh-only)
terraform plan -refresh-only                # lo mismo, forma moderna: solo detecta drift, no lo corrige
terraform apply -refresh-only                # aplica la actualización del estado (sin cambiar infra)
terraform state rm <recurso>                 # que Terraform "olvide" un recurso sin borrarlo en Azure
terraform import <recurso> <id-de-azure>     # que Terraform "adopte" algo creado a mano
```

### Validación estática, sin tocar Azure

```bash
terraform fmt -check -diff                 # formato
terraform validate                         # sintaxis y referencias
terraform providers                        # qué providers usa y de dónde
terraform version                          # versión de terraform y del provider instalado
```

### Depuración

```bash
TF_LOG=DEBUG terraform apply               # log detallado a stderr
TF_LOG=DEBUG TF_LOG_PATH=tf.log terraform apply   # log detallado a fichero
```

## Combinados útiles

```bash
# Confirmar que la IP que ve el Makefile es la IP real de la VM
diff <(cd $TF_DIR && terraform output -raw public_ip) \
     <(az vm show -g $RG -n $VM -d --query publicIps -o tsv)

# ¿Cuánto lleva viva la VM? (para calcular coste aproximado a mano)
az vm show -g $RG -n $VM --query "timeCreated" -o tsv 2>/dev/null \
  || az resource show -g $RG -n $VM --resource-type Microsoft.Compute/virtualMachines \
       --query "createdTime" -o tsv
```
