provider "azurerm" {
  features {}
}

# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

# 2. Virtual Network and Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-main"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-main"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 3. Public IP and NIC for standalone VM
resource "azurerm_public_ip" "pip" {
  name                = "vm-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

resource "azurerm_network_interface" "nic" {
  name                = "vm-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# 4. Get password from Azure Key Vault
data "azurerm_key_vault" "kv" {
  name                = var.keyvault_name
  resource_group_name = var.kv_rg
}

data "azurerm_key_vault_secret" "adminpass" {
  name         = var.secret_name
  key_vault_id = data.azurerm_key_vault.kv.id
}

# 5. Create initial VM (source for image)
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "source-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]
  size               = "Standard_B1s"
  admin_username     = var.admin_username
  admin_password     = data.azurerm_key_vault_secret.adminpass.value
  disable_password_authentication = false

  os_disk {
    name              = "vm-os-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install apache2 -y",
      "echo '<h1>Hello from Apache Rahul!</h1>' | sudo tee /var/www/html/index.html"
    ]

    connection {
      type     = "ssh"
      user     = var.admin_username
      password = data.azurerm_key_vault_secret.adminpass.value
      host     = azurerm_public_ip.pip.ip_address
    }
  }

  depends_on = [azurerm_public_ip.pip]
}

# 6. Generalize & Create Image
resource "azurerm_virtual_machine_extension" "deprovision" {
  name                 = "deprovision"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  settings = jsonencode({
    commandToExecute = "sudo waagent -deprovision+user --force && sudo shutdown -h now"
  })
}

resource "azurerm_image" "custom_image" {
  name                = "apache-image"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  source_virtual_machine_id = azurerm_linux_virtual_machine.vm.id

  depends_on = [azurerm_virtual_machine_extension.deprovision]
}

# 7. Get zones in region
data "azurerm_availability_zones" "zones" {
  location = var.location
}

# 8. VM Scale Set using image and zones
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "webscale"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard_B1s"
  instances           = length(data.azurerm_availability_zones.zones.names)
  admin_username      = var.admin_username
  admin_password      = data.azurerm_key_vault_secret.adminpass.value
  disable_password_authentication = false
  zones               = data.azurerm_availability_zones.zones.names

  source_image_id     = azurerm_image.custom_image.id

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "webnic"
    primary = true

    ip_configuration {
      name      = "ipconfig"
      subnet_id = azurerm_subnet.subnet.id
      primary   = true
    }
  }
}
