variable "name" {
  description = "Nom de base des ressources, par exemple novasphere-dev-abc (minuscules, chiffres, tirets)"
  type        = string

  validation {
    # Le nom du target group est "<name>-web" et AWS limite les noms d'ALB / target group a 32 caracteres.
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.name))
    error_message = "name doit faire 3 a 24 caracteres : minuscules, chiffres et tirets, et commencer par une lettre."
  }
}

variable "vpc_id" {
  description = "Identifiant du VPC (module.vpc.vpc_id)"
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id doit ressembler a vpc-0123abcd."
  }
}

variable "public_subnet_ids" {
  description = "Subnets publics (un par zone de disponibilite) pour l'ALB et l'ASG (module.vpc.public_subnets)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "Il faut au moins 2 subnets publics, dans 2 zones de disponibilite differentes."
  }
}

variable "ami_id" {
  description = "Image (AMI) des instances, par exemple Debian 12"
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id doit ressembler a ami-0123abcd."
  }
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type doit ressembler a t3.micro."
  }
}

variable "min_size" {
  description = "Nombre minimum d'instances (le cahier des charges impose 2 au moins)"
  type        = number
  default     = 2

  validation {
    condition     = var.min_size >= 2
    error_message = "min_size doit etre >= 2 : une instance par zone, sinon plus de haute disponibilite."
  }
}

variable "max_size" {
  description = "Nombre maximum d'instances"
  type        = number
  default     = 4

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size doit etre superieur ou egal a min_size."
  }
}

variable "desired_capacity" {
  description = "Nombre d'instances voulu au demarrage"
  type        = number
  default     = 2

  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity doit etre compris entre min_size et max_size."
  }
}

variable "user_data" {
  description = "Script de demarrage (texte brut, le module l'encode en base64). Ne jamais y mettre de secret."
  type        = string

  validation {
    # Limite EC2 : 16 Ko pour le user_data avant encodage.
    condition     = length(var.user_data) > 0 && length(var.user_data) <= 16000
    error_message = "user_data ne doit pas etre vide et doit faire moins de 16000 caracteres."
  }
}

variable "instance_profile_name" {
  description = "Nom du profil d'instance IAM. Dans le Learner Lab : LabInstanceProfile (pas de creation de role possible)."
  type        = string
}

variable "root_device_name" {
  description = "Nom du disque racine de l'AMI (Debian 12 : /dev/xvda). A verifier avec : aws ec2 describe-images --image-ids <ami> --query 'Images[0].RootDeviceName'"
  type        = string
  default     = "/dev/xvda"
}

variable "root_volume_size" {
  description = "Taille du disque racine en Go (chiffre, type gp3)"
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "root_volume_size doit etre compris entre 8 et 100 Go (Debian 12 demande au moins 8 Go)."
  }
}

variable "health_check_path" {
  description = "Chemin interroge par le health check du target group"
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path doit commencer par /."
  }
}

variable "health_check_grace_period" {
  description = "Secondes pendant lesquelles l'ASG ignore le health check apres le lancement d'une instance (le temps que le bootstrap installe nginx)"
  type        = number
  default     = 180
}

variable "tags" {
  description = "Tags ajoutes aux instances, volumes et ressources du module (default_tags ne descend pas dans les instances lancees par l'ASG)"
  type        = map(string)
  default     = {}
}
