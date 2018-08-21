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

variable "location" {
  type = "string"
  default = "west us 2"
}


variable "acr_resource_group_name" {
  type = "string"
}
variable "tags" {
  type = "map"

  default = {
    Environment = "dev"
    Responsible = "Xiaodong Li"
  }
}

variable "acr_name" {
  type = "string"
}

variable "acr_sku" {
  type    = "string"
  default = "Basic"
}
