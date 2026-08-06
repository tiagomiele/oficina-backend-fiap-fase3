# RFC 0001 — AWS Academy e ambientes

- **Status:** aprovado
- **Data:** 2026-05-24

## Contexto

A Fase 3 exige API Gateway, Lambda, banco gerenciado, Kubernetes, Terraform e deploy automatizado. O projeto continuará usando AWS Academy Learner Lab.

## Proposta

- utilizar EKS, RDS PostgreSQL, API Gateway e Lambda;
- reutilizar a `LabRole` em vez de criar roles bloqueadas;
- manter estados independentes no HCP Terraform;
- representar homologação e produção por branches, GitHub Environments, nomes e estados separados;
- validar as credenciais temporárias antes de cada plan ou deploy;
- manter procedimentos reproduzíveis de criação e destruição;
- coletar evidências enquanto a sessão e os endpoints estiverem ativos.

## Consequências

- credenciais AWS precisam ser renovadas quando o laboratório reiniciar;
- pipelines podem falhar por sessão expirada mesmo sem erro no código;
- recursos não devem ser considerados permanentes;
- criação de IAM roles e algumas operações EKS podem estar bloqueadas;
- o cronograma deve reservar uma janela contínua para validação e gravação do vídeo.

## Alternativas rejeitadas

- conta AWS permanente: não será utilizada por decisão do projeto;
- outra nuvem: aumentaria o retrabalho e descartaria a experiência acumulada na Fase 2.
