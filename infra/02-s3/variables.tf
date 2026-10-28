variable "aws_region" {
  description = "Región del laboratorio; mantené la misma que Aurora."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region)) && length(var.aws_region) <= 20
    error_message = "Ingresá una región AWS válida; la guía usa us-east-1."
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
  description = "Prefijo del bucket. El nombre final incluye cuenta y región."
  type        = string
  default     = "utn-dms"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.workshop_name)) && !strcontains(var.workshop_name, "--")
    error_message = "Usá de 3 a 20 caracteres: letras minúsculas, números y guiones; empezá con una letra y evitá guiones dobles o finales."
  }
}
