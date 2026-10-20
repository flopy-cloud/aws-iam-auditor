variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "email" {
  description = "Email que recibe el reporte semanal"
  type        = string
  sensitive   = true
}

variable "max_key_age_days" {
  description = "Días máximos sin rotar una access key"
  type        = number
  default     = 90
}

# Lunes 09:00 hora Argentina = 12:00 UTC
variable "schedule" {
  description = "Cuándo corre la auditoría"
  type        = string
  default     = "cron(0 12 ? * MON *)"
}