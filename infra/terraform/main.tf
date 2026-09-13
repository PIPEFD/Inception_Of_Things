# Traducción a Terraform de la creación de VM que en cloud-1/bootstrap.yml
# se hacía con módulos azure.azcollection de Ansible. Mismo diseño de red
# (resource group, NSG mínimo, vnet, subnet, IP pública, NIC, VM), con dos
# diferencias deliberadas para este proyecto:
#   - vm_size por defecto en una serie con virtualización anidada (ADR-003).
#   - solo se abre el puerto 22: este host no sirve tráfico HTTP/HTTPS
#     directo, todo pasa por túnel SSH (ver target `tunnel` del Makefile).

resource "azurerm_resource_group" "iot" {
  name     = var.resource_group
  location = var.location
}

resource "azurerm_network_security_group" "iot" {
  name                = "iot-nsg"
  resource_group_name = azurerm_resource_group.iot.name
  location            = azurerm_resource_group.iot.location

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "iot" {
  name                = "iot-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.iot.location
  resource_group_name = azurerm_resource_group.iot.name
}

resource "azurerm_subnet" "iot" {
  name                 = "iot-subnet"
  resource_group_name  = azurerm_resource_group.iot.name
  virtual_network_name = azurerm_virtual_network.iot.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "iot" {
  subnet_id                 = azurerm_subnet.iot.id
  network_security_group_id = azurerm_network_security_group.iot.id
}

resource "azurerm_public_ip" "iot" {
  name                = "iot-public-ip"
  resource_group_name = azurerm_resource_group.iot.name
  location            = azurerm_resource_group.iot.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "iot" {
  name                = "iot-nic"
  resource_group_name = azurerm_resource_group.iot.name
  location            = azurerm_resource_group.iot.location

  ip_configuration {
    name                          = "default"
    subnet_id                     = azurerm_subnet.iot.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.iot.id
  }
}

resource "azurerm_linux_virtual_machine" "iot" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.iot.name
  location            = azurerm_resource_group.iot.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.iot.id]

  # Nunca contraseña: solo clave pública, generada localmente por
  # 'make ssh-key'. La privada nunca se versiona (ver .gitignore).
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  lifecycle {
    # vm_agent_platform_updates_enabled: atributo deprecado en el provider
    # que Azure gestiona por su cuenta tras crear la VM. Sin esto, cada
    # 'terraform plan' muestra un diff que no es drift real, solo ruido.
    ignore_changes = [vm_agent_platform_updates_enabled]
  }
}
