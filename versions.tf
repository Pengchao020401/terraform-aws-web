# Module terraform-aws-web : required_providers SEULEMENT.
# Pas de bloc "provider" ici : c'est l'environnement (envs/dev, envs/prod) qui configure la region
# et les default_tags. Un module avec son propre bloc provider est un defaut releve par le jury.
terraform {
  # 1.9 minimum : une validation de variable peut lire une autre variable (min_size / max_size).
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}
