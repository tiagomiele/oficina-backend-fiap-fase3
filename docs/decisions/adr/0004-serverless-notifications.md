# ADR 0004 — Notificações assíncronas serverless

- **Status:** aceito
- **Data:** 2026-05-24

## Contexto

Mudanças de status da Ordem de Serviço precisam notificar o cliente sem acoplar o domínio ao SDK da AWS ou ao tempo de resposta de um provedor de e-mail.

## Decisão

O backend continuará dependendo somente de `NotificacaoGateway`. Em nuvem, o adaptador HTTP envia a solicitação a um endpoint técnico do API Gateway autenticado por uma chave exclusiva. A Lambda de ingresso valida o contrato e publica o evento no Amazon SNS. Uma segunda Lambda, assinante do tópico, envia o e-mail pelo Amazon SES. Falhas definitivas de invocação são direcionadas a uma fila DLQ.

Os modos `log` e `smtp` permanecem disponíveis para desenvolvimento e contingência local. O modo oficial dos ambientes integrados é `serverless`.

## Segurança

- a chave técnica fica em HCP Terraform e GitHub Environments como segredo;
- o endpoint rejeita chave ausente ou inválida com comparação em tempo constante;
- endereço, assunto e corpo não são registrados em logs;
- o payload possui limites de tamanho e validação de e-mail;
- o remetente SES precisa ser verificado antes da ativação do ambiente.

## Consequências

- a criação e a evolução da OS não dependem da entrega do e-mail;
- SNS fornece retry assíncrono e DLQ para falhas definitivas;
- SES pode exigir verificação do remetente e, no sandbox, também do destinatário;
- a entrega operacional depende do apply e da confirmação das identidades, ações externas a este código.
