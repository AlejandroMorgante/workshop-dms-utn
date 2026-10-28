variable "aws_region" {
  description = "Región del laboratorio; mantené la misma que Aurora."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "Usá us-east-1, igual que el stack DMS del laboratorio."
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
