variable "rg_name" {
  default = "webvm-rg"
}

variable "location" {
  default = "East US"
}

variable "keyvault_name" {
  description = "Name of Azure Key Vault"
}

variable "kv_rg" {
  description = "Resource Group of the Key Vault"
}

variable "secret_name" {
  description = "Name of the secret containing the VM admin password"
}

variable "admin_username" {
  default = "adminuser"
}
