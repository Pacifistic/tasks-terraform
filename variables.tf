variable "region" {
  default     = "us-east-2"
  description = "AWS region"
}

variable "db_password" {
  description = "RDS root user password"
  # sensitive   = true

  validation {
    condition = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters."
  }
}