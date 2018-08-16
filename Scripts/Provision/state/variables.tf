variable subscription_id {
  description = "ID of azure subscription"
}

variable tenant_id {
  description = "ID of AAD directory tenant"
}

variable client_id {
  description = "Application Id of terraform service principal"
}

variable client_secret {
  description = "Password of terraform service principal"
}

variable "resource_group_name" {
  default     = "terraform"
  description = "Name of resource group"
}
