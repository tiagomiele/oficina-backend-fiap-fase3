# Documentação da Fase 3

O README principal apresenta apenas o caminho rápido. Os detalhes técnicos e operacionais estão organizados nesta pasta.

## Arquitetura

- [Visão geral da solução](architecture/overview.md)
- [Responsabilidades dos repositórios](architecture/repository-boundaries.md)
- [Autenticação serverless por CPF](architecture/authentication-flow.md)
- [Observabilidade com New Relic](architecture/observability-new-relic.md)
- [Evolução do banco de dados](architecture/database-evolution.md)
- [Migração da infraestrutura da Fase 2](architecture/infrastructure-migration.md)

## Contratos

- [OpenAPI da autenticação](contracts/authentication-api.yaml)

## Decisões

### RFCs

- [RFC 0001 — AWS Academy e ambientes](decisions/rfc/0001-aws-academy-and-environments.md)
- [RFC 0002 — Autenticação por CPF](decisions/rfc/0002-cpf-authentication.md)

### ADRs

- [ADR 0001 — Quatro repositórios independentes](decisions/adr/0001-four-repositories.md)
- [ADR 0002 — New Relic](decisions/adr/0002-new-relic.md)
- [ADR 0003 — JWT assinado e validado entre serviços](decisions/adr/0003-jwt-signing.md)

## Validação

- [Guia geral de execução e validação do projeto](validation/general-project.md)
- [Histórico — Semana 1](validation/week1.md)
- [Histórico — Semana 2](validation/week2.md)
- [Histórico — Semana 3](validation/week3.md)

## Planejamento

- [Roadmap da Fase 3](roadmap/phase3.md)

## Histórico

- [Guia completo preservado da Fase 2](fase2/README-fase2.md)
- [Evidências da Fase 2](../docs-fase2/01-evidencias-fase-2/)
