# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~>1.0.0"
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
//TODO: Move the variable value to variables tf
resource "azurerm_virtual_network" "rg-terraform-vnet" {
  name                = "vnet-ppe-edp-uaenorth-terraform"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  address_space       = ["172.16.36.0/22"]
  dns_servers         = ["172.16.37.4", "172.16.37.5"]

  # subnet {
  #   name           = "subnet-ppe-edp-uaenorth-ingestion-terraform"
  #   address_prefix = "172.16.36.0/25"
  # }

  # subnet {
  #   name           = "subnet-ppe-edp-uaenorth-ingestion-terraform-2"
  #   address_prefix = "172.16.36.128/25"
  #   security_group = azurerm_network_security_group.rg-terraformnsg.id
  # }

  tags = {
    env     = "dev"
    project = "edp1"
  }
}

// Creation of subnet seperatly 



resource "azurerm_subnet" "subnet_privateendpoint" {
  name                 = "subnet-ppe-edp-uaenorth-ingestion-terraform-private"
  resource_group_name  = azurerm_resource_group.rg-terraform.name
  virtual_network_name = azurerm_virtual_network.rg-terraform-vnet.name
  address_prefixes     = ["172.16.37.0/25"]
}





//Create NIC for VM

resource "azurerm_network_interface" "shirnic" {
  name                = "shir-nic"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet_privateendpoint.id
    private_ip_address_allocation = "Dynamic"
  }
}


//Step 4
// Creation of namespace
//TODO: Move the variable value to variables tf
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
//TODO: Move the variable value to variables tf
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

// Creation of Root key for Listen
//TODO: Move the variable value to variables tf
resource "azurerm_eventhub_namespace_authorization_rule" "this" {
  name                = "pnr_retrival_sharedkey"
  namespace_name      = azurerm_eventhub_namespace.eventhub-namespace.name
  resource_group_name = azurerm_resource_group.rg-terraform.name

  listen = true
  send   = false
  manage = false
}

//Output

output "namespace_id" {
  value = azurerm_eventhub_namespace_authorization_rule.this.id


}
output "primary_connection_string" {
  value     = azurerm_eventhub_namespace_authorization_rule.this.primary_connection_string
  sensitive = true
}

//Private Endpoint 

resource "azurerm_private_endpoint" "example" {
  name                = "pep-eventhub-terraform-endpoint"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  subnet_id           = azurerm_subnet.subnet_privateendpoint.id

  private_service_connection {
    name                           = "terraform-privateserviceconnection"
    private_connection_resource_id = azurerm_eventhub_namespace.eventhub-namespace.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }
}


// Create ADF

//ADF Paas Service 
//var.resource_group_name["rgname"]

resource "azurerm_data_factory" "adfterraform" {
  name                = "adf-edp-ppe-terraform"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
}





//Creation of VM

resource "azurerm_windows_virtual_machine" "shirvm" {
  name                = "adshirterraform"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  size                = "Standard_B2ms"
  admin_username      = "adminuser"
  admin_password      = "P@$$w0rd1234!"
  network_interface_ids = [
    azurerm_network_interface.shirnic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  tags = {
    env     = "dev"
    project = "edp1"
  }

}

// ADF SHIR


resource "azurerm_data_factory_integration_runtime_self_hosted" "adfterraform" {
  name            = "shirterraform"
  data_factory_id = azurerm_data_factory.adfterraform.id
}



output "primary_authorization_key_shir" {

  value     = azurerm_data_factory_integration_runtime_self_hosted.adfterraform.primary_authorization_key
  sensitive = false

}


// Private Endpoint for portal

resource "azurerm_private_endpoint" "adfprivateendpoint" {
  name                = "pep-adfendpoint-terraform-portal"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  subnet_id           = azurerm_subnet.subnet_privateendpoint.id

  private_service_connection {
    name                           = "terraform-privateserviceconnection-adf-portal"
    private_connection_resource_id = azurerm_data_factory.adfterraform.id
    subresource_names              = ["portal"]
    is_manual_connection           = false
  }


}


// Process RG 
//TODo Para, clean up


resource "azurerm_resource_group" "rg-process" {
  name     = var.resource_group_name["rgnameprocess"]
  location = "UAE North"

  tags = {
    env     = "dev"
    project = "edp1"
  }
}


// Create ADLS Gen2
resource "azurerm_storage_account" "storage" {
  name                     = "stppeedpterraform"
  resource_group_name      = azurerm_resource_group.rg-process.name
  location                 = azurerm_resource_group.rg-process.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = "true"
}

//Create Gen2 Container 
resource "azurerm_storage_data_lake_gen2_filesystem" "storageadls" {
  name               = "stppeedpterraform"
  storage_account_id = azurerm_storage_account.storage.id

}

//TODO: create private endpoint  ?????


//Private Endpoint for storage dfs

resource "azurerm_private_endpoint" "storagepep" {
  name                = "pep-storagepep-terraform-endpoint"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
  subnet_id           = azurerm_subnet.subnet_privateendpoint.id

  private_service_connection {
    name                           = "terraform-privateserviceconnection-storage"
    private_connection_resource_id = azurerm_storage_account.storage.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }
}





resource "azurerm_subnet" "subnet_privatedatabrick" {
  name                 = "subnet-ppe-edp-uaenorth-databrick-terraform-private"
  resource_group_name  = azurerm_resource_group.rg-terraform.name
  virtual_network_name = azurerm_virtual_network.rg-terraform-vnet.name
  address_prefixes     = ["172.16.37.128/25"]

  delegation {
    name = "delegationprivate"

   service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"
      ]
  }
}
}
resource "azurerm_subnet" "subnet_publicdatabrick" {
  name                 = "subnet-ppe-edp-uaenorth-databrick-terraform-public"
  resource_group_name  = azurerm_resource_group.rg-terraform.name
  virtual_network_name = azurerm_virtual_network.rg-terraform-vnet.name
  address_prefixes     = ["172.16.38.0/25"]
  delegation {
    name = "delegationpublic"

   service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"
      ]
  }
}
}


resource "azurerm_network_security_group" "public" {
  name                = "pubdb-nsg"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
}

resource "azurerm_subnet_network_security_group_association" "pubdbassociation" {
  subnet_id                 = azurerm_subnet.subnet_privatedatabrick.id
  network_security_group_id = azurerm_network_security_group.public.id
}


resource "azurerm_network_security_group" "private" {
  name                = "privatedb-nsg"
  location            = azurerm_resource_group.rg-terraform.location
  resource_group_name = azurerm_resource_group.rg-terraform.name
}

resource "azurerm_subnet_network_security_group_association" "privatedbbassociation" {
  subnet_id                 = azurerm_subnet.subnet_publicdatabrick.id
  network_security_group_id = azurerm_network_security_group.private.id
}



provider "databricks" {
  host = azurerm_databricks_workspace.dbworkspace.workspace_url
}

resource "azurerm_databricks_workspace" "dbworkspace" {
  name                        = var.databricks["dbname"]
  resource_group_name         = azurerm_resource_group.rg-terraform.name
  location                    = azurerm_resource_group.rg-terraform.location
  sku                         = "premium"
  managed_resource_group_name = "terraform-DBW-managed-without-lb"


  custom_parameters {
    no_public_ip        = true
    virtual_network_id  = azurerm_virtual_network.rg-terraform-vnet.id
    public_subnet_name  = azurerm_subnet.subnet_publicdatabrick.name
    private_subnet_name = azurerm_subnet.subnet_privatedatabrick.name

    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.pubdbassociation.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.privatedbbassociation.id
  }

   depends_on = [
     azurerm_subnet_network_security_group_association.privatedbbassociation ]

  tags = {
    Environment = "Production"
    Pricing     = "Standard"
  }
}



data "databricks_node_type" "smallest" {
  local_disk = true
  depends_on = [
    azurerm_databricks_workspace.dbworkspace
  ]
}
data "databricks_spark_version" "latest_lts" {
  long_term_support = true
  depends_on = [
    azurerm_databricks_workspace.dbworkspace
  ]
}
resource "databricks_cluster" "dbcselfservice" {
  cluster_name            = "Shared Autoscaling"
  spark_version           = data.databricks_spark_version.latest_lts.id
  node_type_id            = data.databricks_node_type.smallest.id
  autotermination_minutes = 20
  autoscale {
    min_workers = 1
    max_workers = 2
  }

  depends_on = [
    azurerm_databricks_workspace.dbworkspace
  ]
}
resource "databricks_group" "db-group" {
  display_name               = "adb-users-admin"
  allow_cluster_create       = true
  allow_instance_pool_create = true
  depends_on = [
    resource.azurerm_databricks_workspace.dbworkspace
  ]
}


//Subnet  for databricks


