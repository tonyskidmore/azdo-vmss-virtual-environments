variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "rg-ado-vmss-example"
}

variable "location" {
  description = "Azure Location of resource group"
  type        = string
  default     = "uksouth"
}
