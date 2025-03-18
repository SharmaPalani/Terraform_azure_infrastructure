terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.19.0"
    }
  }

  backend "azurerm" {
    resource_group_name = "devopsrg"
    storage_account_name = "terraforminfradevops"
    container_name = "blob"
    key = "terraform.tfstate"
  }
}

provider "azurerm" {
  # Configuration options
  features {}
}
resource "azurerm_resource_group" "RG" {
  name     = "RG"
  location = "canada central"
}
resource "azurerm_virtual_network" "Vnet" {
  name                = "myvnet"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  address_space       = ["10.10.0.0/16"]

}
resource "azurerm_subnet" "subnet" {
  name                 = "mysubnet"
  resource_group_name  = azurerm_resource_group.RG.name
  virtual_network_name = azurerm_virtual_network.Vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}
resource "azurerm_public_ip" "PublicIP" {
  name                = "MyPublicIP"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  allocation_method   = "Static"
}
resource "azurerm_network_interface" "NIC" {
  name                = "MyNIC"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  ip_configuration {
    name                          = "myvnicconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.PublicIP.id

  }
}
resource "azurerm_network_security_group" "Nsg" {
  name                = "MyNSG"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  security_rule {
    name                       = "Allow_ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow_tcp"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "Subnet_NSG_Association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.Nsg.id
}
resource "azurerm_linux_virtual_machine" "VM" {
  name                = "VM"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  admin_username      = "azureuser"
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
  size                  = "Standard_B1s"
  network_interface_ids = [azurerm_network_interface.NIC.id]
  os_disk {
    name                 = "mydisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  provisioner "local-exec" {
    command = "echo ${ azurerm_linux_virtual_machine.VM.public_ip_address } > public_ip.txt"
  }

}
resource "null_resource" "copy_file_azure" {
  provisioner "file" {
    source      = "apache-install.sh"
    destination = "/tmp/apache-install.sh"

  }
  provisioner "remote-exec" {
 
    inline = ["sudo chmod +x /tmp/apache-install.sh", 
    "sudo /tmp/apche-install.sh"]
  }
      connection {
      type        = "ssh"
      host        = azurerm_public_ip.PublicIP.ip_address
      user        = "azureuser"
      private_key = file("~/.ssh/id_rsa")
    }
  depends_on = [azurerm_linux_virtual_machine.VM]

}