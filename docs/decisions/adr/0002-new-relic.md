# ADR 0002 — New Relic para observabilidade

- **Status:** aceito
- **Data:** 2026-05-24

## Decisão

New Relic será a plataforma central de monitoramento e observabilidade.

## Escopo

- Java APM para a aplicação;
- integração Kubernetes pelo `nri-bundle`;
- integração da Lambda e do API Gateway;
- logs estruturados e correlacionados;
- eventos de negócio e dashboards NRQL;
- alertas de disponibilidade, desempenho e processamento de OS.

## Motivos

- atende diretamente ao requisito da Fase 3;
- combina APM, infraestrutura, logs, traces, dashboards e alertas;
- possui integração oficial com Java, EKS e Lambda;
- opera fora da conta temporária do AWS Academy.

## Consequências

- será necessária uma conta New Relic e uma license key;
- a chave deve permanecer em Secrets/GitHub Environments;
- custos e limites de ingestão precisam ser acompanhados;
- dados pessoais devem ser filtrados antes do envio.
