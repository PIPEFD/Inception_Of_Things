output "public_ip" {
  description = "IP pública del host. Leída por el Makefile ($(HOST_IP)) vía 'terraform output -raw public_ip'."
  value       = azurerm_public_ip.iot.ip_address
}

output "admin_username" {
  value = var.admin_username
}
