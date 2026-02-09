variable "region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "email_alert" {
  description = "Email for SNS alert subscription"
  type        = string
}
