variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type    = string
  default = "elasticsearch"
}

variable "cluster_size" {
  type    = number
  default = 3
}

variable "management_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "elastic_password" {
  type      = string
  default   = "Ch4ng3Me_Str0ng!"
  sensitive = true
}
