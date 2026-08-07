# Validação da Semana 2

## Escopo entregue

- VPC, rede e EKS no repositório Kubernetes;
- RDS PostgreSQL no repositório de banco;
- states HCP Terraform separados por repositório e ambiente;
- plan manual sem apply automático;
- remoção do Terraform combinado e do Postgres em Kubernetes da aplicação;
- deploy da aplicação ajustado para AWS Academy, EKS e RDS externos.

Nenhum recurso AWS é criado por esta validação estática.

## 1. Validar o repositório Kubernetes

```bash
cd oficina-kubernetes-infra-fiap-fase3
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

Confirme que existem:

```text
versions.tf
providers.tf
variables.tf
network.tf
eks.tf
outputs.tf
.terraform.lock.hcl
```

O código deve criar VPC, duas subnets públicas, duas privadas, Internet Gateway, NAT Gateway, EKS, managed node group e add-ons essenciais sem criar IAM roles.

## 2. Validar o repositório do banco

```bash
cd oficina-database-infra-fiap-fase3
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

Confirme que o RDS:

- não possui acesso público;
- utiliza armazenamento criptografado;
- exige duas subnets privadas;
- recebe conexões somente de security groups autorizados;
- não expõe usuário ou senha nos outputs.

## 3. Validar a separação da aplicação

```bash
cd oficina-backend-fiap-fase3
test ! -d infra
test ! -f .github/workflows/infra.yml
test ! -f k8s/postgres-deployment.yaml
test ! -f k8s/postgres-service.yaml
test ! -f k8s/postgres-pvc.yaml
test ! -f k8s/secret.yaml
bash -n k8s/deploy-aws-academy.sh
```

A pasta `k8s` deve conter somente os manifests da aplicação e scripts que recebem as configurações em tempo de execução.

## 4. Validar pipelines

Nos Pull Requests, confirme:

- `Repository validation` aprovado nos dois repositórios Terraform;
- `terraform fmt`, `init -backend=false` e `validate` aprovados;
- TFLint, Trivy e Gitleaks aprovados;
- os checks da aplicação principal aprovados.

O workflow `Terraform plan` deve ser manual. Não deve existir etapa `terraform apply` nos workflows dos repositórios de infraestrutura.

## 5. Preparar o plan real

Somente com a sessão do Learner Lab ativa:

1. configure os workspaces HCP Terraform de `homolog` e `production`;
2. desative Auto apply;
3. atualize `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`;
4. configure o ARN atual da `LabRole` no workspace Kubernetes;
5. execute primeiro o plan do Kubernetes;
6. após apply autorizado, copie os outputs de rede para o workspace do banco;
7. execute o plan do banco;
8. revise quantidade, custo e segurança dos recursos antes de solicitar apply.

## Critérios de aceite

- [ ] Terraform válido e formatado nos dois repositórios;
- [ ] lockfiles versionados e states ignorados;
- [ ] nenhum IAM role ou EKS Access Entry criado;
- [ ] RDS privado e criptografado;
- [ ] outputs entre repositórios documentados;
- [ ] Terraform legado removido da aplicação;
- [ ] Postgres e secrets de exemplo removidos do Kubernetes;
- [ ] CI aprovado nos três Pull Requests;
- [ ] nenhum apply executado sem autorização.
