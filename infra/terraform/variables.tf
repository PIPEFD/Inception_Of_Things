variable "resource_group" {
  description = "Nombre del resource group de Azure para el host de IoT."
  type        = string
  default     = "rg-iot-42"
}

variable "location" {
  description = "Región de Azure."
  type        = string
  default     = "swedencentral"
}

variable "vm_name" {
  description = "Nombre de la VM host."
  type        = string
  default     = "vm-iot-host"
}

variable "vm_size" {
  description = <<-EOT
    Tamaño de la VM. Debe soportar virtualización anidada: series
    Dv3/Dv4/Dv5, Ev3/Ev4/Ev5 o Fsv2. Las series B NO la soportan y fallan
    en silencio (la VM se crea bien, `kvm-ok` falla después). Ver ADR-003
    en docs/decisiones.md.
  EOT
  type        = string
  default     = "Standard_D2d_v4"
}

variable "admin_username" {
  description = "Usuario administrador de la VM (coincide con $(SSH) del Makefile)."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = <<-EOT
    Ruta a la clave pública SSH generada por 'make ssh-key'
    (~/.ssh/iot42_rsa.pub). Debe ser RSA: el provider azurerm valida esto
    en el cliente y rechaza ed25519, aunque Azure sí lo acepta a nivel de
    API.
  EOT
  type        = string
  default     = "~/.ssh/iot42_rsa.pub"
}
