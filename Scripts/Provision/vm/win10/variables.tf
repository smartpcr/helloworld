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

variable "prefix" {
  default = "xd"
}

variable "location" {
  default = "west us 2"
}

variable "admin_username" {
  default = "xd"
}

variable "admin_password" {
  description = "admin password for windows vm"
}

variable "sku" {
  default = "RS3-Pro"
}

variable "vm_size" {
  default = "Standard_E4s_v3"
}
