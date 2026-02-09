output "sumo_api_endpoint" {
  value = "${aws_apigatewayv2_api.sumo_api.api_endpoint}/alert"
}

output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}
