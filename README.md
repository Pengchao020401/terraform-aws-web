# terraform-aws-web

Module Terraform du projet NovaSphere : la partie « web » d'un environnement AWS.
Il crée un **Application Load Balancer** devant un **groupe d'auto-scaling** d'au moins 2 instances, réparties sur 2 zones.

Le module ne contient **aucun bloc `provider`** : la région et les `default_tags` sont configurés par l'environnement qui l'appelle.
Le VPC et les subnets ne sont pas créés ici : ils sont passés en entrée (ils viennent du module public `terraform-aws-modules/vpc/aws`).

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `aws_security_group.alb` | Accepte le port 80 depuis Internet. Ne sort que vers les instances. |
| `aws_security_group.web` | Accepte le port 80 **uniquement depuis le SG de l'ALB**. Aucun SSH. |
| `aws_lb.this` | ALB public sur les subnets publics (`drop_invalid_header_fields = true`). |
| `aws_lb_target_group.this` | Health check HTTP sur `/` (code 200). |
| `aws_lb_listener.http` | Écoute sur le port 80 et envoie vers le target group. |
| `aws_launch_template.this` | IMDSv2 obligatoire, disque racine gp3 chiffré, profil d'instance, `user_data`. |
| `aws_autoscaling_group.this` | `min_size >= 2`, `health_check_type = "ELB"`, instance refresh progressif. |

## Entrées

| Nom | Type | Défaut | Description |
|---|---|---|---|
| `name` | `string` | requis | Nom de base (3 à 24 caractères : minuscules, chiffres, tirets). |
| `vpc_id` | `string` | requis | VPC dans lequel créer les ressources. |
| `public_subnet_ids` | `list(string)` | requis | Au moins 2 subnets publics (2 zones). |
| `ami_id` | `string` | requis | AMI des instances (Debian 12 dans le projet). |
| `instance_type` | `string` | `"t3.micro"` | Type d'instance. |
| `min_size` | `number` | `2` | Minimum d'instances. **Validation : >= 2.** |
| `max_size` | `number` | `4` | Maximum. Validation : >= `min_size`. |
| `desired_capacity` | `number` | `2` | Valeur de départ. Validation : entre `min_size` et `max_size`. |
| `user_data` | `string` | requis | Script de démarrage en texte brut (jamais de secret dedans). |
| `instance_profile_name` | `string` | requis | Profil IAM des instances (`LabInstanceProfile` dans le Learner Lab). |
| `root_device_name` | `string` | `"/dev/xvda"` | Nom du disque racine de l'AMI. |
| `root_volume_size` | `number` | `8` | Taille du disque en Go (8 à 100). |
| `health_check_path` | `string` | `"/"` | Chemin du health check. |
| `health_check_grace_period` | `number` | `180` | Délai avant que l'ASG juge une instance, en secondes. |
| `tags` | `map(string)` | `{}` | Tags posés sur les instances et volumes. |

## Sorties

| Nom | Description |
|---|---|
| `alb_dns_name` | Nom DNS de l'ALB. |
| `alb_url` | `http://<dns de l'ALB>`, à ouvrir dans le navigateur. |
| `alb_arn` | ARN de l'ALB. |
| `target_group_arn` | ARN du target group. |
| `asg_name` | Nom de l'ASG. |
| `launch_template_id` | Identifiant du Launch Template. |
| `alb_security_group_id` | Security Group de l'ALB. |
| `web_security_group_id` | Security Group des instances. |

## Exemple d'utilisation

```hcl
module "web" {
  source = "git::https://github.com/Bristhis25/terraform-aws-web.git?ref=v1.0.0"

  name                  = "novasphere-dev-abc"
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnets
  ami_id                = data.aws_ami.debian.id
  instance_type         = "t3.micro"
  min_size              = 2
  max_size              = 4
  desired_capacity      = 2
  user_data             = templatefile("${path.module}/bootstrap.sh", { environment = "dev", region = "us-east-1" })
  instance_profile_name = "LabInstanceProfile"
  tags                  = { Project = "NovaSphere", Environment = "dev" }
}
```

## Versions

Une version = un tag Git (`v1.0.0`, `v1.1.0`, ...). **Un tag publié n'est jamais modifié** : pour changer le module, on publie un nouveau tag, puis on met à jour `?ref=` dans les environnements.

```bash
git tag -a v1.0.0 -m "Première version : ALB, target group, Launch Template IMDSv2, ASG"
git push origin v1.0.0
```

## Scan de sécurité (checkov)

`checkov -d .` : 39 contrôles réussis, 0 échec, 9 ignorés. Chaque exception est écrite dans `main.tf` avec sa raison (`#checkov:skip=...`) :
HTTP sans HTTPS (extension optionnelle), pas de protection contre la suppression (le Learner Lab impose un `destroy`), pas de logs d'accès ni de WAF (hors périmètre du socle), et un faux positif sur la règle « SG vers SG ».

## Limites connues

- Pas de HTTPS : le listener est sur le port 80, comme l'exige le cahier des charges.
- Les instances sont dans des subnets publics (pas de NAT Gateway, pour le coût). Elles ne sont joignables que par l'ALB grâce aux Security Groups.
- Le disque racine est `/dev/xvda` (Debian 12). Pour une autre AMI, vérifier `root_device_name`.
