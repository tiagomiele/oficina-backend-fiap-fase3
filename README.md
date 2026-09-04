# Oficina Backend — Tech Challenge Fase 3

[![CI](https://github.com/tiagomiele/oficina-backend-fiap-fase3/actions/workflows/ci.yml/badge.svg)](https://github.com/tiagomiele/oficina-backend-fiap-fase3/actions/workflows/ci.yml)

API principal do sistema de gestão de oficina mecânica. A Fase 3 evolui a base da Fase 2 para autenticação serverless por CPF, API Gateway, infraestrutura dividida em repositórios independentes e observabilidade com New Relic.

## Responsabilidades

Este repositório contém somente a aplicação Spring Boot e os artefatos necessários para executá-la em Kubernetes:

- regras de negócio e fluxo das Ordens de Serviço;
- APIs administrativas, técnicas e de cliente;
- persistência e migrações Flyway;
- validação dos JWTs emitidos pelo serviço serverless;
- métricas, logs estruturados e instrumentação APM;
- publicação de notificações pelo contrato serverless;
- imagem Docker e deploy da aplicação no EKS com HPA, distribuição de pods e PDB.

A infraestrutura AWS, o banco gerenciado e a autenticação serverless pertencem a repositórios separados. O Terraform combinado da Fase 2 foi removido deste repositório e substituído por states e pipelines independentes.

## Arquitetura da solução

```mermaid
flowchart LR
    Client[Cliente ou operador] --> APIGW[API Gateway]
    APIGW --> Auth[Lambda de autenticação por CPF]
    Auth --> RDS[(RDS PostgreSQL)]
    APIGW --> App[Aplicação Spring Boot no EKS]
    App --> RDS
    App --> Notify[Lambda + SNS + SES]
    App --> NR[New Relic]
    Auth --> NR
    EKS[EKS e HPA] --> NR
```

### Repositórios

| Repositório | Responsabilidade |
|---|---|
| [oficina-backend-fiap-fase3](https://github.com/tiagomiele/oficina-backend-fiap-fase3) | Aplicação principal no Kubernetes |
| [oficina-auth-serverless-fiap-fase3](https://github.com/tiagomiele/oficina-auth-serverless-fiap-fase3) | Lambda, autenticação por CPF, JWT e API Gateway |
| [oficina-kubernetes-infra-fiap-fase3](https://github.com/tiagomiele/oficina-kubernetes-infra-fiap-fase3) | VPC, EKS, HPA e integração Kubernetes/New Relic |
| [oficina-database-infra-fiap-fase3](https://github.com/tiagomiele/oficina-database-infra-fiap-fase3) | RDS PostgreSQL e infraestrutura de dados |

## Tecnologias

- Java 21 e Spring Boot 3.3;
- PostgreSQL 16, JPA/Hibernate e Flyway;
- Spring Security e JWT;
- JUnit 5, RestAssured, ArchUnit e JaCoCo;
- Docker, Kubernetes, HPA, topology spread e PodDisruptionBudget;
- GitHub Actions e GHCR;
- New Relic APM e logs estruturados.

## Executar localmente

### Pré-requisitos

- Docker Desktop com Docker Compose;
- ou Java 21 e PostgreSQL 16.

### Docker Compose

```bash
docker compose up --build
```

Serviços locais:

- API: `http://localhost:8080`
- Swagger: `http://localhost:8080/swagger-ui/index.html`
- Healthcheck: `http://localhost:8080/actuator/health`
- Adminer: `http://localhost:8081`

### Obter tokens pelo Swagger

O Swagger reúne os fluxos de autenticação da plataforma:

- `POST /auth/cpf`: cliente autenticado no Auth Serverless pelo API Gateway;
- `POST /auth/login`: funcionário ou técnico autenticado no Backend por e-mail e senha;
- `POST /usuarios`: funcionário autenticado cadastra novos funcionários ou técnicos.

O perfil é determinado pelo cadastro, nunca pelo request de login. Configure `AUTH_BASE_URL` com a URL base do API Gateway para habilitar o `Try it out` de `/auth/cpf`; homologação e produção recebem esse valor automaticamente pelo GitHub Environment.

### Validar o projeto

```bash
./mvnw spotless:check
./mvnw verify
```

O `verify` executa testes unitários, testes de integração, ArchUnit e o gate de cobertura JaCoCo do domínio.

## Preparar homologação ou produção

Com os quatro repositórios clonados como diretórios irmãos, copie o bloco `[default]` do AWS Academy e execute:

```powershell
.\scripts\configure-environment.ps1 -Environment homolog
# ou
.\scripts\configure-environment.ps1 -Environment production
```

O script cria/configura o projeto e os oito workspaces HCP, renova AWS CLI, Variable Set e GitHub Environments, preserva secrets fora do Git e sincroniza outputs consultando diretamente o state atual pela API do HCP Terraform. No AWS Academy, omita `-EnableSesDelivery` e `-CreateSesIdentity`: a notificação permanece assíncrona, usa log técnico sem PII e não solicita nem persiste e-mail remetente. Em uma conta com identidade SES verificada, use `-EnableSesDelivery` e informe o remetente; acrescente `-CreateSesIdentity` somente se a role puder solicitar a verificação. A chave técnica é gerada e reutilizada automaticamente. Após o apply do RDS, use `-RequireBackendDeployReady` para exigir os outputs do EKS/RDS e confirmar `DEPLOY_ENABLED=true` antes do CD. Produção recebe por padrão RDS Multi-AZ, proteção contra exclusão e snapshot final; `-UseAwsAcademyDisposableProductionProfile` é um override explícito, sem HA, somente para demonstração descartável. O script não executa apply ou deploy. Consulte o [guia geral](docs/validation/general-project.md).

## Documentação

- [Índice da documentação](docs/README.md)
- [Arquitetura geral](docs/architecture/overview.md)
- [Limites dos repositórios](docs/architecture/repository-boundaries.md)
- [Fluxo de autenticação por CPF](docs/architecture/authentication-flow.md)
- [Sequência de abertura da Ordem de Serviço](docs/architecture/service-order-opening-flow.md)
- [Observabilidade com New Relic](docs/architecture/observability-new-relic.md)
- [Evolução do banco de dados](docs/architecture/database-evolution.md)
- [Migração da infraestrutura da Fase 2](docs/architecture/infrastructure-migration.md)
- [Contrato da API de autenticação](docs/contracts/authentication-api.yaml)
- [Guia geral de execução e validação do projeto](docs/validation/general-project.md)
- [Histórico de validação da Semana 1](docs/validation/week1.md)
- [Histórico de validação da Semana 2](docs/validation/week2.md)
- [Histórico de validação da Semana 3](docs/validation/week3.md)
- [Roadmap da Fase 3](docs/roadmap/phase3.md)
- [Documentação preservada da Fase 2](docs/fase2/README-fase2.md)

## Segurança e configuração

Segredos não devem ser versionados. Banco, JWT, New Relic, chave técnica da notificação e SMTP de contingência são configurados por variáveis de ambiente e GitHub Environments. O modo integrado usa `NOTIFICATION_ENDPOINT`, `NOTIFICATION_API_KEY` e `NOTIFICACAO_TIPO=serverless`. Consulte os documentos específicos antes de executar deploy.

## Contribuição

- não são permitidos commits diretos na `main`;
- toda mudança deve passar por Pull Request;
- o CI deve estar aprovado antes do merge;
- mudanças arquiteturais devem atualizar RFCs ou ADRs.
