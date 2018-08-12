######################################################################################################
# VARIABLES 
######################################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}

variable "key_name" {
  default = "xiaodonglab"
}

variable "network_address_space" {
  default = "10.1.0.0/16"
}

variable "billing_code_tag" {}
variable "environment_tag" {}
variable "bucket_name" {}

variable "arm_subscription_id" {}
variable "arm_principal" {}
variable "arm_password" {}
variable "tenant_id" {}
variable "dns_zone_name" {}
variable "dns_resource_group" {}

variable "instance_count" {
  default = 2
}

variable "subnet_count" {
  default = 2
}

######################################################################################################
# PROVIDERS 
######################################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-east-1"
}

provider "azurerm" {
  subscription_id = "${var.arm_subscription_id}"
  client_id       = "${var.arm_principal}"
  client_secret   = "${var.arm_password}"
  tenant_id       = "${var.tenant_id}"
  alias           = "arm"
}

######################################################################################################
# DATA 
######################################################################################################
data "aws_availability_zones" "available" {}

######################################################################################################
# RESOURCES 
######################################################################################################

# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block = "${var.network_address_space}"

  tags = {
    Name        = "${var.environment_tag}"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name        = "${var.environment_tag}-igw"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}

resource "aws_subnet" "subnet" {
  count                   = "${var.subnet_count}"
  cidr_block              = "${cidrsubnet(var.network_address_space, 8, count.index + 1)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  map_public_ip_on_launch = "true"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"

  tags = {
    Name        = "${var.environment_tag}-subnet-${count.index + 1}"
    BillingCode = "${var.billing_code_tag}"
    Environment = "${var.environment_tag}"
  }
}
