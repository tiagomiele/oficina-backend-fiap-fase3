# Limites dos repositórios

## 1. Aplicação principal

**Repositório:** `oficina-backend-fiap-fase3`

Responsável por domínio, casos de uso, APIs, persistência, Flyway, instrumentação APM, Docker e artefatos de implantação da aplicação.

Não deve provisionar VPC, EKS, RDS, Lambda ou API Gateway.

## 2. Autenticação serverless

**Repositório:** `oficina-auth-serverless-fiap-fase3`

Responsável por validação de CPF, consulta do cliente, emissão de JWT, Lambda Authorizer, API Gateway e deploy serverless.

Não contém regras da Ordem de Serviço nem migrações do banco da aplicação.

## 3. Infraestrutura Kubernetes

**Repositório:** `oficina-kubernetes-infra-fiap-fase3`

Responsável por VPC, subnets, EKS, node groups, autoscaling, Load Balancer, namespaces e integração Kubernetes do New Relic.

Não constrói a imagem da aplicação e não administra o schema do banco.

## 4. Infraestrutura do banco

**Repositório:** `oficina-database-infra-fiap-fase3`

Responsável por RDS, subnet group, security groups, parâmetros, backups e outputs de conexão sem credenciais.

As migrações Flyway permanecem na aplicação, que é proprietária do schema funcional.

## Integrações

| Origem | Destino | Contrato |
|---|---|---|
| API Gateway | Lambda de login | HTTP/OpenAPI |
| API Gateway | Lambda Authorizer | Evento de autorização AWS |
| API Gateway | aplicação EKS | HTTP/OpenAPI |
| Lambda | RDS | schema de leitura de cliente |
| aplicação | RDS | JPA/Flyway |
| pipelines | HCP Terraform | workspace e variáveis |
| aplicação/Lambda/EKS | New Relic | APM, logs, métricas e eventos |

## Compartilhamento de informações

Outputs não sensíveis podem ser consumidos por HCP Terraform Remote State ou AWS Systems Manager Parameter Store. Credenciais e chaves são fornecidas por GitHub Environments, HCP Terraform e Secrets Kubernetes; nunca por arquivos versionados.
