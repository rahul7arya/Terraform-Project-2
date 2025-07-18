output "vm_public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "image_id" {
  value = azurerm_image.custom_image.id
}
