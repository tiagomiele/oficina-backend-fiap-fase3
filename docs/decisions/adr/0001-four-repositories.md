# ADR 0001 — Quatro repositórios independentes

- **Status:** aceito
- **Data:** 2026-05-24

## Decisão

A solução será mantida em quatro repositórios: autenticação serverless, infraestrutura Kubernetes, infraestrutura de banco e aplicação principal.

## Motivos

- requisito explícito da Fase 3;
- pipelines e ciclos de entrega independentes;
- separação de permissões e estados Terraform;
- menor acoplamento entre aplicação e infraestrutura;
- READMEs e responsabilidades mais fáceis de compreender.

## Regras

- nenhum submódulo Git será usado para simular monorepo;
- não haverá cópia de código compartilhado;
- contratos serão documentados e versionados;
- cada repositório terá PR obrigatório, CI e CD próprios;
- documentação global ficará no repositório da aplicação, com documentação específica em cada repositório.

## Consequências

Mudanças de contrato podem exigir PRs coordenados. A compatibilidade será preservada durante a ordem de deploy e registrada nas RFCs.
