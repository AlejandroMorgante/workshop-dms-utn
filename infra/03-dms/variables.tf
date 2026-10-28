variable "aws_region" {
  description = "Región del laboratorio; mantené la misma que Aurora."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "Esta etapa incluye el certificado y la configuración para us-east-1."
  }
}

variable "aws_profile" {
  description = "Perfil local de AWS CLI ya autenticado."
  type        = string
  default     = "workshop"
}

variable "expected_account_id" {
  description = "Cuenta del participante; el provider rechaza otra cuenta."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Ingresá el ID de 12 dígitos de la cuenta del workshop."
  }
}

variable "workshop_name" {
  description = "Prefijo para los recursos de DMS."
  type        = string
  default     = "utn-dms"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.workshop_name)) && !strcontains(var.workshop_name, "--")
    error_message = "Usá de 3 a 20 caracteres: letras minúsculas, números y guiones; empezá con una letra y evitá guiones dobles o finales."
  }
}

variable "source_credentials_ready" {
  description = "Habilitar después de ejecutar el asistente que prepara el usuario y su secreto."
  type        = bool
  default     = false
}

variable "create_dms_vpc_role" {
  description = "false si la cuenta ya tiene dms-vpc-role configurado."
  type        = bool
  default     = true
}

variable "create_dms_logs_role" {
  description = "false si la cuenta ya tiene dms-cloudwatch-logs-role configurado."
  type        = bool
  default     = true
}
