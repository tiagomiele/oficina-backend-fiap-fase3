# Validação da Semana 3

Este guia valida a autenticação por CPF, JWT RSA, API Gateway, Lambda Authorizer, segurança do backend, histórico de status, imagem e pipeline. Os comandos de `plan` não criam recursos. Execute `terraform apply` somente quando houver autorização explícita e saldo no AWS Academy.

## 1. Ordem correta das branches

1. Faça merge dos PRs da Semana 3 em `homolog`.
2. Valide localmente, no HCP Terraform e em homologação.
3. Somente depois crie PR de `homolog` para `main`.

Não faça merge das branches de desenvolvimento diretamente em `main`.

## 2. Confirmar EKS 1.34 em `homolog`

No PowerShell:

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
git switch homolog
git pull --ff-only
Select-String -Path .\variables.tf -Pattern 'default\s+=\s+"1.34"'
Select-String -Path .\environments\homolog.tfvars.example -Pattern 'cluster_version\s+=\s+"1.34"'
```

Conecte o diretório ao workspace já criado:

```powershell
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-kubernetes-homolog'
terraform init -input=false
terraform plan -input=false -no-color
```

No plan, procure `version = "1.34"` no cluster e no node group. Não execute `apply` nesta etapa.

## 3. Criar os workspaces da autenticação

No projeto HCP Terraform `soat-fase3`, crie:

```text
oficina-auth-homolog
oficina-auth-production
```

Em cada workspace:

- Execution Mode: `Remote`;
- Apply Method: `Manual apply`;
- Auto apply: desativado;
- Terraform Working Directory: vazio;
- Terraform: versão `>= 1.6` e `< 2.0`.

## 4. Gerar as chaves RSA

Execute em uma pasta fora dos repositórios:

```powershell
New-Item -ItemType Directory -Force C:\fiap-secrets\oficina
Set-Location C:\fiap-secrets\oficina
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt-private.pem
openssl rsa -pubout -in jwt-private.pem -out jwt-public.pem
```

Regras:

- nunca copie os arquivos para um repositório;
- nunca versione as chaves;
- a Lambda recebe a chave privada e a pública;
- o backend recebe somente a chave pública;
- homologação e produção devem usar pares diferentes.

## 5. Compilar e testar a autenticação

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
git switch homolog
git pull --ff-only
.\mvnw.cmd -B clean verify spotless:check
Test-Path .\target\oficina-auth.jar
```

Resultado esperado:

- 3 testes aprovados;
- `BUILD SUCCESS`;
- `Test-Path` retorna `True`.

## 6. Configurar o workspace `oficina-auth-homolog`

Cadastre como Terraform variables:

| Chave | Exemplo/origem | Sensível |
|---|---|---|
| `aws_region` | `us-west-2` | não |
| `environment` | `homolog` | não |
| `lab_role_arn` | `arn:aws:iam::269023862684:role/LabRole` | não |
| `private_subnet_ids` | output do workspace Kubernetes | não |
| `lambda_security_group_id` | output `eks_cluster_security_group_id` | não |
| `db_url` | `jdbc:postgresql://<endpoint>:5432/oficina` | sim |
| `db_user` | usuário do RDS | sim |
| `db_password` | senha do RDS | sim |
| `jwt_private_key` | conteúdo de `jwt-private.pem` | sim |
| `jwt_public_key` | conteúdo de `jwt-public.pem` | sim |
| `jwt_issuer` | `oficina-auth-serverless` | não |
| `jwt_audience` | `oficina-backend` | não |
| `jwt_ttl_seconds` | `900` | não |
| `backend_base_url` | URL privada/pública do backend, sem `/` final | não |

Para obter os outputs do Kubernetes:

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-kubernetes-homolog'
terraform output private_subnet_ids
terraform output eks_cluster_security_group_id
```

O security group do EKS é reutilizado pela Lambda porque ele já deve estar autorizado no RDS. A autenticação não cria IAM role nem EKS Access Entry.

## 7. Validar o Terraform da autenticação

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-auth-homolog'
.\mvnw.cmd -B -DskipTests package
terraform init -input=false
terraform fmt -check -recursive
terraform validate -no-color
terraform plan -input=false -no-color
```

Confirme no plan:

- duas Lambdas Java 21 ARM64;
- rota pública `POST /auth/cpf`;
- Lambda Authorizer;
- somente as rotas de cliente protegidas;
- logs com retenção de 7 dias;
- uso da `LabRole` existente;
- nenhuma nova role IAM;
- nenhuma EKS Access Entry;
- nenhuma exclusão inesperada.

Não execute `terraform apply` apenas para validar o código.

## 8. Validar o backend localmente

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
git switch homolog
git pull --ff-only
.\mvnw.cmd -B -Dtest=ServerlessJwtVerifierTest,ArchitectureTest test
.\mvnw.cmd -B -Dtest=FluxoCompletoOsIntegrationTest test
.\mvnw.cmd -B -DskipTests package
```

Esses testes comprovam:

- assinatura RSA, issuer, audience, role e `client_id`;
- manutenção das regras de Clean Architecture;
- token administrativo HMAC ainda funcional;
- token de cliente RSA aceito;
- cliente não consegue consultar OS de outro cliente;
- histórico registra as transições com duração e correlation ID;
- fluxo completo da OS continua funcional.

## 9. Verificar a migration antes de usar um RDS existente

A migration `V3__autenticacao_cpf_e_historico_status.sql` normaliza documentos e cria o histórico. Antes do primeiro deploy, verifique duplicidades no PostgreSQL:

```sql
SELECT regexp_replace(documento, '[^0-9]', '', 'g') AS documento_normalizado,
       COUNT(*)
  FROM clientes
 GROUP BY regexp_replace(documento, '[^0-9]', '', 'g')
HAVING COUNT(*) > 1;
```

O resultado deve estar vazio. Verifique também os status existentes:

```sql
SELECT DISTINCT status FROM ordens_servico ORDER BY status;
```

Após iniciar o backend, confira:

```sql
SELECT version, description, success
  FROM flyway_schema_history
 ORDER BY installed_rank;

SELECT id_ordem_servico, status, entrada_em, saida_em,
       duracao_milisegundos, correlation_id
  FROM historico_status_ordem_servico
 ORDER BY id_ordem_servico, entrada_em;
```

A versão 3 deve estar aplicada com sucesso. Não altere manualmente a tabela de histórico.

## 10. Configurar o GitHub Environment do backend

Em `Settings → Environments → homolog`, configure:

### Variables

```text
AWS_REGION=us-west-2
EKS_CLUSTER_NAME=<output eks_cluster_name>
APP_DB_URL=jdbc:postgresql://<endpoint>:5432/oficina
APP_DB_USER=<usuario-rds>
SERVERLESS_JWT_ISSUER=oficina-auth-serverless
SERVERLESS_JWT_AUDIENCE=oficina-backend
```

### Secrets

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
APP_DB_PASSWORD
APP_JWT_SECRET
APP_ADMIN_PASSWORD
SERVERLESS_JWT_PUBLIC_KEY
```

`SERVERLESS_JWT_PUBLIC_KEY` deve conter exatamente o conteúdo de `jwt-public.pem`. Não use a chave privada no backend.

## 11. Validar imagem e pipeline

Após o merge do backend em `homolog`:

1. Abra `Actions → CD`.
2. Confirme o job `Docker build & push (GHCR)`.
3. Confirme que a imagem foi publicada com a tag do SHA e `homolog`.
4. Se AWS e EKS estiverem configurados, confirme `Deploy HOMOLOG` e o rollout.
5. Se as credenciais temporárias estiverem ausentes, o deploy deve ser ignorado com aviso, sem falhar o build da imagem.

A pipeline cria/atualiza `oficina-config` e `oficina-secrets`; a chave pública fica no Secret Kubernetes. O manifesto não contém chave ou senha.

Validação local opcional da imagem:

```powershell
docker build -t oficina-backend:week3 .
docker image inspect oficina-backend:week3
```

## 12. Ordem para uma validação real na AWS

Cada `apply` abaixo cria ou altera recursos cobrados. Execute somente quando autorizado:

1. revisar e, se autorizado, aplicar Kubernetes 1.34;
2. configurar o workspace do banco com os outputs da VPC e aplicar o RDS;
3. configurar os secrets do GitHub Environment;
4. implantar o backend em EKS e aguardar a migration V3;
5. obter a URL do LoadBalancer do backend;
6. preencher `backend_base_url` no workspace da autenticação;
7. revisar o plan da autenticação;
8. somente então aplicar Lambdas e API Gateway.

## 13. Testar autenticação por CPF

Obtenha a URL:

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-auth-homolog'
$authUrl = terraform output -raw cpf_authentication_url
```

CPF ativo, com ou sem máscara:

```powershell
$response = Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/json' -Body '{"cpf":"529.982.247-25"}'
$token = $response.accessToken
$response.tokenType
$response.expiresIn
```

Resultado esperado: `Bearer`, aproximadamente `900` segundos e token não vazio.

CPF inválido ou inexistente:

```powershell
try {
  Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/json' -Body '{"cpf":"111.111.111-11"}'
} catch {
  $_.Exception.Response.StatusCode.value__
}
```

Resultado esperado: `401`, sem informar se o CPF existe.

JSON inválido ou CPF ausente deve retornar `400`.

## 14. Conferir o JWT sem enviar o token a terceiros

```powershell
function Decode-Base64Url([string]$value) {
  $value = $value.Replace('-', '+').Replace('_', '/')
  while ($value.Length % 4) { $value += '=' }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value))
}

Decode-Base64Url ($token.Split('.')[1]) | ConvertFrom-Json | Format-List
```

Confirme:

- `sub` e `client_id` possuem o identificador do cliente;
- `role` é `CLIENTE`;
- `iss` é `oficina-auth-serverless`;
- `aud` contém `oficina-backend`;
- `iat`, `exp` e `jti` existem;
- o CPF completo não aparece.

Não publique o token nem a chave privada em evidências.

## 15. Testar Authorizer, backend e propriedade da OS

Use a URL base do API Gateway:

```powershell
$apiBase = terraform output -raw api_base_url
```

Sem token:

```powershell
try {
  Invoke-RestMethod -Method Get -Uri "$apiBase/consulta/ordens-servico/<OS>/status"
} catch {
  $_.Exception.Response.StatusCode.value__
}
```

Resultado esperado: `401` ou `403` no API Gateway.

Com token válido do proprietário:

```powershell
Invoke-RestMethod -Method Get -Uri "$apiBase/consulta/ordens-servico/<OS>/status" -Headers @{ Authorization = "Bearer $token" }
Invoke-RestMethod -Method Get -Uri "$apiBase/ordens-servico/<OS>/historico" -Headers @{ Authorization = "Bearer $token" }
```

O histórico deve estar em ordem cronológica. Estados encerrados devem possuir `saidaEm` e `duracaoMilisegundos`; o estado atual permanece sem saída.

Repita usando o token de outro cliente para a mesma OS. Resultado esperado: `404`, sem revelar que a OS pertence a outra pessoa.

## 16. Confirmar que o login administrativo continua funcional

Acesse diretamente o backend:

```powershell
$admin = Invoke-RestMethod -Method Post -Uri '<BACKEND_URL>/auth/login' -ContentType 'application/json' -Body '{"email":"admin@oficina.local","senha":"<SENHA>"}'
Invoke-RestMethod -Method Get -Uri '<BACKEND_URL>/relatorios/os-por-status' -Headers @{ Authorization = "Bearer $($admin.accessToken)" }
```

Resultado esperado: login `200` e rota administrativa autorizada. O API Gateway de cliente não substitui o JWT administrativo HMAC.

## 17. Verificações de segurança

Em cada repositório:

```powershell
git status --short
git diff --check
git grep -n -I -E 'BEGIN PRIVATE KEY|AWS_SECRET_ACCESS_KEY=|DB_PASSWORD=|accessToken=' -- ':!docs/validation/week3.md'
```

Confirme também no CloudWatch:

- logs de autenticação contêm request ID e resultado;
- CPF e token não aparecem;
- falhas de CPF usam mensagem genérica;
- chave privada existe somente nas variáveis sensíveis da Lambda/HCP.

## 18. O que não foi validado sem provisionamento

A implementação local e estática não comprova, sem `apply`:

- conectividade real Lambda → RDS;
- permissões de ENI da `LabRole`;
- invocação real do API Gateway e Authorizer;
- DNS/LoadBalancer do backend no EKS;
- publicação real da imagem e rollout;
- métricas New Relic, previstas para a Semana 4.

Esses itens devem ser marcados como pendentes até a execução autorizada em homologação.

## 19. Evidências finais

Guarde:

- plan do EKS mostrando Kubernetes 1.34;
- plan do RDS;
- plan da autenticação;
- CI aprovado nos dois PRs;
- imagem no GHCR;
- resposta `200` do CPF ativo e `401` do inválido, sem expor CPF/token;
- claims sanitizados do JWT;
- negação sem token e para cliente não proprietário;
- histórico da OS;
- login administrativo funcional;
- CloudWatch sem CPF ou token;
- confirmação de Auto Apply desativado em todos os workspaces.
