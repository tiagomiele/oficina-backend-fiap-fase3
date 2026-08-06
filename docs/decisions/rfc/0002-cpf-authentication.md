# RFC 0002 — Autenticação por CPF

- **Status:** proposta para implementação
- **Data:** 2026-05-24

## Contexto

A Fase 3 exige uma função serverless que valide o CPF, consulte a existência e o status do cliente e devolva um JWT para APIs protegidas.

## Proposta

- endpoint público `POST /auth/cpf` no API Gateway;
- Lambda para normalização, validação e consulta do cliente;
- resposta genérica para CPF inválido, inexistente ou inativo;
- JWT curto, assinado com chave assimétrica e sem CPF completo;
- Lambda Authorizer para proteger rotas no API Gateway;
- validação adicional do token no backend;
- logs mascarados e telemetria sem dados pessoais.

## Segurança

Autenticar somente por CPF satisfaz o requisito acadêmico, mas CPF não é um segredo. O risco será registrado na documentação. Uma evolução futura recomendada é incluir segundo fator, código de uso único ou outra prova de posse.

## Claims iniciais

- `sub`: identificador técnico do cliente;
- `role`: `CLIENTE`;
- `iss`: serviço de autenticação da oficina;
- `aud`: API da oficina;
- `iat`, `exp` e `jti`.

## Consequências

- Lambda precisa de acesso privado e somente leitura aos dados necessários do cliente;
- aplicação e autorizador precisam compartilhar a chave pública e as regras de validação;
- rotação de chaves deve ser possível sem alterar código;
- mudanças incompatíveis exigem nova versão do contrato.
