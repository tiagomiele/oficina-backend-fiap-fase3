# ADR 0003 — JWT assinado e validado entre serviços

- **Status:** aceito
- **Data:** 2026-05-24

## Decisão

A Lambda emitirá JWT de curta duração com assinatura assimétrica. O autorizador e a aplicação validarão o token com a chave pública.

## Motivos

- a chave privada permanece somente no emissor;
- consumidores não conseguem emitir tokens;
- facilita rotação e separação de responsabilidades;
- permite defesa em profundidade no Gateway e no backend.

## Regras

- validar `iss`, `aud`, `exp`, algoritmo e assinatura;
- não aceitar algoritmo informado pelo cliente sem uma lista permitida;
- não incluir CPF completo ou credenciais no payload;
- armazenar a chave privada em serviço de segredos compatível com AWS Academy;
- expor a chave pública por configuração controlada ou endpoint JWKS.

## Consequências

A rotação precisa aceitar temporariamente a chave atual e a anterior. O desenho final dependerá das permissões disponíveis no laboratório.
