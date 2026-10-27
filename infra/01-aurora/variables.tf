variable "aws_region" {
  description = "Región del laboratorio; la guía usa us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI ya autenticado. No contiene credenciales."
  type        = string
  default     = "workshop"
}

variable "expected_account_id" {
  description = "ID de la cuenta del participante. Evita aplicar en otra cuenta por error."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Ingresá el ID de 12 dígitos de la cuenta del workshop."
  }
}

variable "workshop_name" {
  description = "Prefijo para identificar los recursos de este laboratorio."
  type        = string
  default     = "utn-dms"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.workshop_name)) && !strcontains(var.workshop_name, "--")
    error_message = "Usá entre 3 y 30 letras minúsculas, números o guiones; comenzá con una letra y evitá guiones dobles o finales."
  }
}

variable "aurora_engine_version" {
  description = "Versión PostgreSQL 16 disponible en la región y compatible con Serverless v2 y Data API."
  type        = string
  default     = "16.13"

  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.aurora_engine_version))
    error_message = "Esta etapa usa la familia aurora-postgresql16; especificá una versión 16.x."
  }
}
