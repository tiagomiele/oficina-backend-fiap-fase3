# Validação da Semana 2

Este guia valida a implementação da Semana 2 sem provisionar recursos e sem executar `terraform apply`.

## Entregas implementadas

| Entrega | Pull Request |
|---|---|
| VPC, rede, EKS e managed node group | [Kubernetes infra #2](https://github.com/tiagomiele/oficina-kubernetes-infra-fiap-fase3/pull/2) |
| RDS PostgreSQL e segurança do banco | [Database infra #2](https://github.com/tiagomiele/oficina-database-infra-fiap-fase3/pull/2) |
| Remoção da infraestrutura legada da aplicação | [Backend #4](https://github.com/tiagomiele/oficina-backend-fiap-fase3/pull/4) |

A validação está dividida em três níveis:

1. **estática:** formatação, sintaxe e estrutura, sem credenciais AWS;
2. **CI:** checks dos três Pull Requests;
3. **plan remoto:** consulta real à AWS, sem criar recursos.

## 1. Pré-requisitos no Windows

Instale:

- Git;
- Terraform `>= 1.6` e `< 2.0`;
- PowerShell 7 ou Windows PowerShell 5.1.

Valide:

```powershell
git --version
terraform version
```

Python, Java e Docker não são necessários para a validação estática desta etapa.

## 2. Selecionar a versão da Semana 2

Se os PRs ainda estiverem abertos, valide diretamente a branch deles:

```powershell
$root = 'C:\fiap-fase3'
$branch = 'devin/1786111008-week2-infrastructure'
$repositories = @(
  'oficina-backend-fiap-fase3',
  'oficina-kubernetes-infra-fiap-fase3',
  'oficina-database-infra-fiap-fase3'
)

foreach ($repository in $repositories) {
  $path = Join-Path $root $repository
  if (-not (Test-Path $path)) {
    throw "Repositório não encontrado: $path"
  }

  git -C $path fetch origin
  if ($LASTEXITCODE -ne 0) { throw "Falha no fetch de $repository" }

  git -C $path switch --detach "origin/$branch"
  if ($LASTEXITCODE -ne 0) { throw "Falha ao selecionar a branch de $repository" }
}
```

Se os PRs já estiverem integrados, substitua a linha do branch por:

```powershell
$branch = 'homolog'
```

O modo detached é usado apenas para leitura e validação; ele não publica alterações.

## 3. Validar o Terraform do Kubernetes

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
terraform fmt -check -recursive
if ($LASTEXITCODE -ne 0) { throw 'terraform fmt falhou no Kubernetes' }

terraform init -backend=false -input=false
if ($LASTEXITCODE -ne 0) { throw 'terraform init falhou no Kubernetes' }

terraform validate -no-color
if ($LASTEXITCODE -ne 0) { throw 'terraform validate falhou no Kubernetes' }
```

Resultado esperado:

```text
Success! The configuration is valid.
```

Confira os arquivos obrigatórios:

```powershell
$requiredFiles = @(
  'versions.tf',
  'providers.tf',
  'variables.tf',
  'network.tf',
  'eks.tf',
  'outputs.tf',
  '.terraform.lock.hcl',
  '.github\workflows\ci.yml',
  '.github\workflows\terraform-plan.yml',
  'environments\homolog.tfvars.example',
  'environments\production.tfvars.example'
)

$missingFiles = $requiredFiles | Where-Object { -not (Test-Path $_) }
if ($missingFiles) {
  $missingFiles
  throw 'Existem arquivos obrigatórios ausentes no repositório Kubernetes.'
}

Write-Host 'Estrutura Kubernetes encontrada.'
```

Confirme que o Terraform não tenta criar IAM roles ou EKS Access Entry:

```powershell
$forbiddenResources = Get-ChildItem -Filter '*.tf' |
  Select-String -Pattern 'resource\s+"aws_iam_|resource\s+"aws_eks_access_entry"'

if ($forbiddenResources) {
  $forbiddenResources
  throw 'Foi encontrada criação de IAM incompatível com o AWS Academy.'
}

Write-Host 'Nenhum recurso IAM ou EKS Access Entry encontrado.'
```

A implementação deve conter:

- uma VPC com DNS habilitado;
- duas subnets públicas e duas privadas em zonas distintas;
- Internet Gateway;
- um NAT Gateway, como compromisso de custo do Learner Lab;
- cluster EKS com logs do control plane;
- managed node group nas subnets privadas;
- VPC CNI, CoreDNS e kube-proxy;
- reutilização da `LabRole` no cluster e nos nodes;
- outputs de VPC, subnets, cluster e security group do EKS.

## 4. Validar o Terraform do banco

```powershell
Set-Location C:\fiap-fase3\oficina-database-infra-fiap-fase3
terraform fmt -check -recursive
if ($LASTEXITCODE -ne 0) { throw 'terraform fmt falhou no banco' }

terraform init -backend=false -input=false
if ($LASTEXITCODE -ne 0) { throw 'terraform init falhou no banco' }

terraform validate -no-color
if ($LASTEXITCODE -ne 0) { throw 'terraform validate falhou no banco' }
```

Resultado esperado:

```text
Success! The configuration is valid.
```

Confira os arquivos obrigatórios:

```powershell
$requiredFiles = @(
  'versions.tf',
  'providers.tf',
  'variables.tf',
  'main.tf',
  'outputs.tf',
  '.terraform.lock.hcl',
  '.github\workflows\ci.yml',
  '.github\workflows\terraform-plan.yml',
  'environments\homolog.tfvars.example',
  'environments\production.tfvars.example'
)

$missingFiles = $requiredFiles | Where-Object { -not (Test-Path $_) }
if ($missingFiles) {
  $missingFiles
  throw 'Existem arquivos obrigatórios ausentes no repositório do banco.'
}

Write-Host 'Estrutura do banco encontrada.'
```

Revise `main.tf` e confirme:

- RDS PostgreSQL 16;
- `publicly_accessible = false`;
- `storage_encrypted = true`;
- DB subnet group com subnets privadas;
- security group na porta 5432 restrito aos grupos autorizados;
- `rds.force_ssl = 1`;
- backups e janela de manutenção configurados;
- nenhuma senha presente nos outputs.

## 5. Validar a separação da aplicação

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3

$legacyPaths = @(
  'infra',
  '.github\workflows\infra.yml',
  'k8s\configmap.yaml',
  'k8s\secret.yaml',
  'k8s\postgres-deployment.yaml',
  'k8s\postgres-pvc.yaml',
  'k8s\postgres-service.yaml'
)

$unexpectedPaths = $legacyPaths | Where-Object { Test-Path $_ }
if ($unexpectedPaths) {
  $unexpectedPaths
  throw 'A infraestrutura legada ainda está presente na aplicação.'
}

Write-Host 'Terraform legado, Postgres local e secrets versionados foram removidos.'
```

Confirme que o deploy recebe a configuração externa:

```powershell
$requiredSettings = @(
  'EKS_CLUSTER_NAME',
  'APP_DB_URL',
  'APP_DB_USER',
  'APP_DB_PASSWORD',
  'APP_JWT_SECRET',
  'APP_ADMIN_PASSWORD'
)

$content = Get-Content '.github\workflows\deploy.yml' -Raw
$missingSettings = $requiredSettings | Where-Object { $content -notmatch [regex]::Escape($_) }
if ($missingSettings) {
  $missingSettings
  throw 'Existem configurações externas ausentes no workflow de deploy.'
}

Write-Host 'Deploy configurado para EKS e RDS externos.'
```

O backend não deve mais provisionar VPC, EKS ou RDS. A pasta `k8s` deve manter somente namespace, Deployment, Service, HPA e scripts de implantação da aplicação.

## 6. Confirmar que não existe apply automático

Execute nos dois repositórios Terraform:

```powershell
$terraformRepositories = @(
  'C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3',
  'C:\fiap-fase3\oficina-database-infra-fiap-fase3'
)

foreach ($repository in $terraformRepositories) {
  $applySteps = Get-ChildItem "$repository\.github\workflows\*.yml" |
    Select-String -Pattern 'terraform\s+apply'

  if ($applySteps) {
    $applySteps
    throw "Foi encontrado terraform apply automático em $repository"
  }
}

Write-Host 'Nenhum terraform apply encontrado nos workflows.'
```

## 7. Validar os Pull Requests e o CI

Abra:

- https://github.com/tiagomiele/oficina-kubernetes-infra-fiap-fase3/pull/2
- https://github.com/tiagomiele/oficina-database-infra-fiap-fase3/pull/2
- https://github.com/tiagomiele/oficina-backend-fiap-fase3/pull/4

Resultados esperados:

### Kubernetes e banco

```text
Repository validation: aprovado
```

Esse job executa:

- `terraform fmt -check -recursive`;
- `terraform init -backend=false`;
- `terraform validate`;
- TFLint;
- Trivy para configurações críticas;
- Gitleaks.

### Aplicação

```text
Build, test & coverage: aprovado
SBOM (CycloneDX) + Dependency-Track: aprovado
Trivy scan: aprovado
Trivy: aprovado
```

Confirme também que os três PRs apontam para `homolog` e não possuem conflitos.

## 8. Preparar os workspaces HCP Terraform

Crie quatro workspaces com execução remota e **Auto apply desativado**:

| Repositório | Homologação | Produção |
|---|---|---|
| Kubernetes | `oficina-kubernetes-homolog` | `oficina-kubernetes-production` |
| Banco | `oficina-database-homolog` | `oficina-database-production` |

Não reutilize o state combinado da Fase 2.

### Variáveis do workspace Kubernetes

Variáveis de ambiente sensíveis:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
```

Variáveis Terraform:

```hcl
aws_region  = "us-west-2"
environment = "homolog"
lab_role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/LabRole"
```

No workspace de produção, use:

```hcl
environment = "production"
```

### Variáveis do workspace do banco

Variáveis de ambiente sensíveis:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
```

Variáveis Terraform:

```hcl
aws_region                   = "us-west-2"
environment                  = "homolog"
vpc_id                       = "vpc-..."
private_subnet_ids           = ["subnet-...", "subnet-..."]
allowed_security_group_ids   = ["sg-..."]
db_password                  = "<senha-segura>"
```

Marque `private_subnet_ids` e `allowed_security_group_ids` como HCL. Marque `db_password` como sensível.

Os valores reais de rede só existirão depois de um apply autorizado do Kubernetes. Portanto, antes disso, valide o banco apenas estaticamente.

## 9. Configurar o workflow manual no GitHub

Nos repositórios Kubernetes e banco, crie os GitHub Environments `homolog` e `production`.

Em cada Environment, configure:

### Secret

```text
TF_API_TOKEN
```

### Variables

```text
TF_CLOUD_ORGANIZATION
TF_WORKSPACE_HOMOLOG
TF_WORKSPACE_PRODUCTION
```

Valores de workspace por repositório:

```text
Kubernetes:
TF_WORKSPACE_HOMOLOG=oficina-kubernetes-homolog
TF_WORKSPACE_PRODUCTION=oficina-kubernetes-production

Banco:
TF_WORKSPACE_HOMOLOG=oficina-database-homolog
TF_WORKSPACE_PRODUCTION=oficina-database-production
```

O workflow `workflow_dispatch` só aparece no GitHub Actions depois que seu arquivo existe na branch padrão `main`. No primeiro bootstrap, use uma destas opções:

1. integrar e promover o workflow até `main`, depois selecionar `homolog` em **Use workflow from**;
2. executar o primeiro plan pela CLI do Terraform, conforme a próxima seção.

## 10. Executar somente o plan do Kubernetes

Antes de qualquer execução real:

1. inicie o AWS Academy Learner Lab;
2. copie as credenciais em **AWS Details → AWS CLI → Show**;
3. atualize as três variáveis AWS no workspace HCP Terraform;
4. confirme o ARN da `LabRole`;
5. deixe **Auto apply** desativado.

### Opção A — GitHub Actions

Acesse:

```text
Actions → Terraform plan → Run workflow
```

Selecione:

```text
Use workflow from: homolog
environment: homolog
```

### Opção B — Terraform CLI para o primeiro bootstrap

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
terraform login app.terraform.io

$env:TF_CLOUD_ORGANIZATION = '<organizacao-hcp>'
$env:TF_WORKSPACE = 'oficina-kubernetes-homolog'

terraform init -input=false -lockfile=readonly
terraform plan -input=false -no-color
```

Resultado aproximado esperado:

```text
Plan: 20 to add, 0 to change, 0 to destroy.
```

A quantidade pode mudar se a AWS ou o provider adicionar recursos derivados, mas o plan deve conter VPC, rede, CloudWatch log group, EKS, node group e três add-ons. Não deve criar IAM roles nem EKS Access Entry.

**Pare após revisar o plan. Não confirme apply.**

## 11. Plan do banco após autorização futura

O plan real do banco depende destes outputs do Kubernetes:

```text
vpc_id
private_subnet_ids
eks_cluster_security_group_id
```

Depois de um apply do Kubernetes explicitamente autorizado:

1. copie os outputs para o workspace `oficina-database-homolog`;
2. use `eks_cluster_security_group_id` em `allowed_security_group_ids`;
3. atualize as credenciais temporárias AWS;
4. execute somente o plan do banco.

Resultado aproximado esperado:

```text
Plan: 4 to add, 0 to change, 0 to destroy.
```

Os quatro recursos Terraform são DB subnet group, security group, parameter group e instância RDS.

**Pare após revisar o plan. Não confirme apply.**

## 12. Critérios de aceite

- [ ] os três PRs apontam para `homolog`;
- [ ] todos os checks dos PRs estão aprovados;
- [ ] `terraform fmt`, `init -backend=false` e `validate` passam nos dois repositórios;
- [ ] lockfiles estão versionados e states estão ignorados;
- [ ] nenhum IAM role ou EKS Access Entry é criado;
- [ ] RDS é privado, criptografado e restrito por security group;
- [ ] outputs entre Kubernetes, banco e aplicação estão documentados;
- [ ] Terraform legado foi removido da aplicação;
- [ ] Postgres no cluster e secrets de exemplo foram removidos;
- [ ] nenhum workflow executa `terraform apply`;
- [ ] nenhum recurso AWS foi criado durante a validação estática;
- [ ] qualquer plan real foi revisado sem confirmar apply.

## 13. Voltar para `homolog`

Após validar uma branch de PR em modo detached:

```powershell
$root = 'C:\fiap-fase3'
$repositories = @(
  'oficina-backend-fiap-fase3',
  'oficina-kubernetes-infra-fiap-fase3',
  'oficina-database-infra-fiap-fase3'
)

foreach ($repository in $repositories) {
  git -C (Join-Path $root $repository) switch homolog
}
```

A validação da Semana 2 termina sem `terraform apply`. O provisionamento da AWS é uma etapa separada e exige autorização explícita.
