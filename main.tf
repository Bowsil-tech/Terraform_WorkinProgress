# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}
 
 //Step 1
//Creation of RG 
resource "azurerm_resource_group" "rg-terraform" {
  name     = var.resource_group_name["rgnameingest"]
  location = "UAE North"

  tags = {
    env     = "dev"
    project = "edp1"
  }
}
//Step 2
//Creating NSG
resource "azurerm_network_security_group" "rg-terraformnsg" {
  name                = var.resource_group_name["nsgnamesubnetingest"]
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name

  tags = {
    env     = "dev"
    project = "edp1"
  }

}

//Step 3
//Creating Vnet & Single subnet 
resource "azurerm_virtual_network" "rg-terraform-vnet" {
  name                = "vnet-ppe-edp-uaenorth-terraform"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  address_space       = ["172.16.36.0/22"]
  dns_servers         = ["172.16.37.4", "172.16.37.5"]

  subnet {
    name           = "subnet-ppe-edp-uaenorth-ingestion-terraform"
    address_prefix = "172.16.36.0/25"
  }

  subnet {
    name           = "subnet-ppe-edp-uaenorth-ingestion-terraform-2"
    address_prefix = "172.16.36.128/25"
    security_group = azurerm_network_security_group.rg-terraformnsg.id
  }

  tags = {
    env     = "dev"
    project = "edp1"
  }
}
//Step 4
// Creation of namespace

resource "azurerm_eventhub_namespace" "eventhub-namespace" {
  name                = var.resource_group_name["eventhubnamespace"]
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  sku                 = "Standard"
  capacity            = 1

  tags = {
    env     = "dev"
    project = "edp1"
  }
}
//Step 5
//Creation of eventhub 

resource "azurerm_eventhub" "eventhub-name" {
  name                = var.resource_group_name["acceptanceEventHub"]
  namespace_name      = azurerm_eventhub_namespace.eventhub-namespace.name
  resource_group_name = azurerm_resource_group.rg-terraform.name
  partition_count     = 3
  message_retention   = 3

  capture_description {
    enabled  = true
    encoding = "Avro"

    destination {
      name = "EventHubArchive.AzureBlockBlob"

      archive_name_format = "eventhubstorage/{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = "ppeedp"
      storage_account_id  = "/subscriptions/e6f22469-d358-47bd-8baf-bdea4c63edbd/resourceGroups/rg-edp-data-storage-platform/providers/Microsoft.Storage/storageAccounts/stppeedp"
    }
  }
}




//172.16.37.0/22