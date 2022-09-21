

variable "resource_group_name" {
  type = map(any)
  default = {
    rgnameingest        = "rg-terraform-ingest"
    rgnameprocess       = "rg-terraform-process"
    nsgnamesubnetingest = "nsg-terraform-ingest"
    eventhubnamespace   = "ns-evh-terraform-edpppe"
    acceptanceEventHub  = "sbr.vcr.ppe"
  }
}



