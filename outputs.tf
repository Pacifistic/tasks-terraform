output "aws_webapp_public_ip" {
    value = aws_instance.webapp_instance.public_ip
}