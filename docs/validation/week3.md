# Validação completa da Semana 3

Este guia descreve, sem etapas implícitas, como validar a solução da Semana 3 no Windows com PowerShell, HCP Terraform e AWS Academy. Ele cobre os quatro repositórios, credenciais temporárias, infraestrutura, banco, backend, autenticação por CPF, API Gateway, Lambda Authorizer, JWT RSA, histórico da ordem de serviço e segurança.

## Antes de começar: escolha o tipo de validação

Existem dois níveis de validação:

1. **Validação sem provisionamento:** executa builds, testes e `terraform plan`. Não cria recursos AWS e pode ser concluída até as seções de plan de cada repositório.
2. **Validação completa na AWS:** executa `terraform apply`, cria recursos cobrados no saldo do Learner Lab, implanta o backend e testa os endpoints reais.

Os comandos `terraform plan` não criam recursos. Os comandos `terraform apply` criam ou alteram recursos e estão identificados como **ETAPA COM CUSTO**. Não execute um apply apenas para conferir o código.

## Regras obrigatórias

- trabalhe em `homolog`; não promova para `main` antes de terminar a validação;
- mantenha **Auto apply desativado** em todos os workspaces HCP Terraform;
- nunca versione arquivos `.pem`, credenciais AWS, senhas, tokens ou arquivos `.tfstate`;
- nunca publique CPF completo, JWT, senha ou chave privada nas evidências;
- as credenciais do AWS Academy expiram e precisam ser renovadas em cada nova sessão;
- use as três credenciais da mesma sessão: access key, secret key e session token;
- não misture credenciais antigas e novas.

---

## 1. Pré-requisitos locais

No PowerShell, confirme as ferramentas:

```powershell
git --version
terraform version
aws --version
java -version
docker version
kubectl version --client
openssl version
```

Requisitos:

- Git;
- Terraform `>= 1.6` e `< 2.0`;
- AWS CLI;
- Java 21;
- Docker Desktop em execução, necessário para o teste de integração com Testcontainers;
- kubectl compatível com Kubernetes 1.34;
- OpenSSL;
- acesso ao GitHub, HCP Terraform e AWS Academy Learner Lab.

Se `openssl` não for reconhecido, instale o OpenSSL antes de gerar as chaves. Não substitua a geração RSA por uma chave copiada da internet.

Confirme que os repositórios estão nestes diretórios ou adapte todos os caminhos deste guia:

```text
C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
C:\fiap-fase3\oficina-database-infra-fiap-fase3
C:\fiap-fase3\oficina-backend-fiap-fase3
C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
```

---

## 2. Atualizar a branch `homolog` dos quatro repositórios

Execute os comandos em cada repositório. Não use uma branch `devin/*` para a validação.

### 2.1 Kubernetes

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
git switch homolog
git pull --ff-only
git status --short
```

### 2.2 Banco

```powershell
Set-Location C:\fiap-fase3\oficina-database-infra-fiap-fase3
git switch homolog
git pull --ff-only
git status --short
```

### 2.3 Backend

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
git switch homolog
git pull --ff-only
git status --short
```

### 2.4 Autenticação

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
git switch homolog
git pull --ff-only
git status --short
```

Resultado esperado: os quatro comandos `git status --short` não exibem arquivos. Se houver alterações locais, não apague nem sobrescreva os arquivos; preserve o trabalho em outro local ou use um clone limpo.

---

## 3. Entender onde as credenciais AWS devem ser atualizadas

As credenciais temporárias precisam ser copiadas separadamente para cada local que acessará a AWS.

| Local | Quando atualizar |
|---|---|
| HCP `oficina-kubernetes-homolog` | antes de plan ou apply do EKS |
| HCP `oficina-database-homolog` | antes de plan ou apply do RDS |
| HCP `oficina-auth-homolog` | antes de plan ou apply da autenticação |
| GitHub Environment `homolog` do backend | antes do deploy no EKS |
| computador local | antes de executar AWS CLI ou kubectl |

Atualizar um workspace HCP não atualiza os demais. Atualizar o HCP também não atualiza o GitHub nem o computador local.

### 3.1 Obter credenciais novas no AWS Academy

1. Abra o AWS Academy Learner Lab.
2. Clique em **Start Lab**.
3. Aguarde o indicador da AWS ficar verde.
4. Clique em **AWS Details**.
5. Na seção **AWS CLI**, clique em **Show**.
6. Mantenha essa tela aberta somente durante a configuração.
7. Não envie uma captura dessa tela e não copie os valores para o repositório.

Os três valores necessários são:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
```

### 3.2 Atualizar um workspace HCP Terraform

Repita este procedimento no workspace que será usado naquele momento:

1. Acesse https://app.terraform.io/.
2. Abra a organização `oficina-fiap-soat-fase-2`.
3. Abra o projeto `soat-fase3`.
4. Abra o workspace desejado.
5. Clique em **Variables**.
6. Localize a seção **Environment variables**.
7. Edite `AWS_ACCESS_KEY_ID` e cole o valor novo.
8. Edite `AWS_SECRET_ACCESS_KEY` e cole o valor novo.
9. Edite `AWS_SESSION_TOKEN` e cole o valor novo.
10. Marque as três variáveis como **Sensitive**.
11. Salve cada alteração.
12. Confirme que não existe uma segunda variável com o mesmo nome.

Se uma variável não existir, clique em **Add variable**, escolha **Environment variable**, informe o nome exato, cole o valor e marque **Sensitive**.

### 3.3 Erro `ExpiredToken`

O erro abaixo não é problema do Terraform:

```text
ExpiredToken: The security token included in the request is expired
```

Correção:

1. inicie uma sessão nova do Learner Lab;
2. obtenha as três credenciais novas;
3. atualize as três variáveis no workspace que executou o run;
4. descarte o run com falha;
5. execute novamente `terraform plan`.

Não é necessário repetir `terraform init` depois de apenas renovar as credenciais.

### 3.4 Configurar as credenciais no computador local

Esta etapa só é necessária antes de usar AWS CLI ou kubectl.

1. Na tela **AWS Details → AWS CLI**, copie o bloco completo iniciado por `[default]`.
2. Abra este arquivo no Windows:

```text
C:\Users\SEU_USUARIO\.aws\credentials
```

3. Substitua o bloco `[default]` antigo pelo bloco novo.
4. Salve o arquivo.
5. Não coloque esse arquivo dentro de `C:\fiap-fase3`.
6. Valide:

```powershell
aws sts get-caller-identity
```

O campo `Account` deve mostrar a conta atual do Learner Lab. Um ARN contendo `assumed-role/LabRole` é esperado para a sessão; ele não substitui o ARN IAM usado pelo Terraform.

### 3.5 Variáveis do PowerShell não são permanentes

Variáveis como `$vpcId`, `$dbHost` e `$backendUrl` existem somente na janela atual do PowerShell. Se fechar a janela, recupere os valores depois que os recursos estiverem aplicados:

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-kubernetes-homolog'
terraform init -input=false
$vpcId = terraform output -raw vpc_id
$eksClusterName = terraform output -raw eks_cluster_name
$eksSecurityGroupId = terraform output -raw eks_cluster_security_group_id
$privateSubnetsJson = terraform output -json private_subnet_ids

Set-Location C:\fiap-fase3\oficina-database-infra-fiap-fase3
$env:TF_WORKSPACE = 'oficina-database-homolog'
terraform init -input=false
$dbHost = terraform output -raw database_endpoint
$dbPort = terraform output -raw database_port
$dbName = terraform output -raw database_name
$jdbcUrl = terraform output -raw jdbc_url
$authJdbcUrl = "$jdbcUrl`?sslmode=require"

$backendHost = kubectl get service oficina-app -n oficina-homolog -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
$backendUrl = "http://$backendHost"
```

Execute apenas os blocos correspondentes aos recursos que já foram criados. Senhas e tokens não são recuperados por esses comandos; mantenha-os no gerenciador de senhas.

---

## 4. Conferir os workspaces HCP Terraform

No projeto HCP `soat-fase3`, devem existir:

```text
oficina-kubernetes-homolog
oficina-kubernetes-production
oficina-database-homolog
oficina-database-production
oficina-auth-homolog
oficina-auth-production
```

Para criar um workspace ausente:

1. abra o projeto `soat-fase3`;
2. clique em **New workspace**;
3. escolha **CLI-driven workflow**;
4. informe exatamente o nome do workspace;
5. conclua a criação;
6. abra **Settings → General**;
7. selecione **Execution Mode: Remote**;
8. selecione **Apply Method: Manual apply**;
9. deixe **Auto apply** desativado;
10. deixe **Terraform Working Directory** vazio;
11. selecione uma versão Terraform `>= 1.6` e `< 2.0`;
12. salve.

Este guia usa somente os workspaces de homologação. Não configure nem aplique produção nesta validação.

---

## 5. Validar e, se autorizado, provisionar Kubernetes 1.34

### 5.1 Confirmar o código

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
Select-String -Path .\variables.tf -Pattern 'default\s+=\s+"1.34"'
Select-String -Path .\environments\homolog.tfvars.example -Pattern 'cluster_version\s+=\s+"1.34"'
terraform fmt -check -recursive
```

As duas buscas devem exibir `1.34` e a formatação deve terminar sem erro. A validação Terraform será executada depois do `init`, na seção 5.3.

### 5.2 Configurar as Terraform variables do workspace

Abra `oficina-kubernetes-homolog → Variables → Terraform variables` e confirme:

| Chave | Valor | HCL | Sensitive |
|---|---|---:|---:|
| `aws_region` | `us-west-2` | não | não |
| `environment` | `homolog` | não | não |
| `lab_role_arn` | `arn:aws:iam::269023862684:role/LabRole` | não | não |
| `cluster_version` | `1.34` | não | não |

As demais variáveis podem usar os defaults de `variables.tf`. O ARN deve começar com `arn:aws:`; `aws:iam::...` está incorreto.

Antes do plan, renove as três **Environment variables** conforme a seção 3.2.

### 5.3 Executar o plan

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-kubernetes-homolog'
terraform init -input=false
terraform validate -no-color
terraform plan -input=false -no-color
```

`terraform init` deve informar:

```text
HCP Terraform has been successfully initialized!
```

No primeiro plan, espere aproximadamente:

```text
Plan: 20 to add, 0 to change, 0 to destroy.
```

Confirme no plan:

- EKS e node group com versão `1.34`;
- uma VPC;
- duas subnets públicas e duas privadas;
- Internet Gateway e NAT Gateway;
- EKS managed node group;
- add-ons `vpc-cni`, `coredns` e `kube-proxy`;
- CloudWatch Logs;
- reutilização da `LabRole`;
- nenhuma IAM role nova;
- nenhuma EKS Access Entry;
- nenhuma exclusão inesperada.

Se o workspace já tiver sido aplicado, o resultado esperado pode ser `No changes`. Se aparecer qualquer recurso para destruir, pare e revise antes de continuar.

### 5.4 ETAPA COM CUSTO: aplicar Kubernetes

Esta etapa é obrigatória apenas para executar a aplicação na AWS. Ela consome saldo do Learner Lab.

1. confirme novamente que Auto apply está desativado;
2. confirme que o plan não destrói recursos;
3. mantenha o Learner Lab ativo;
4. execute:

```powershell
terraform apply
```

5. revise o novo plan remoto;
6. quando o Terraform perguntar, digite `yes` somente se decidiu provisionar;
7. aguarde `Apply complete`.

Não use `-auto-approve`.

### 5.5 Obter os outputs do Kubernetes

Após o apply:

```powershell
terraform output
$vpcId = terraform output -raw vpc_id
$eksClusterName = terraform output -raw eks_cluster_name
$eksSecurityGroupId = terraform output -raw eks_cluster_security_group_id
$privateSubnetsJson = terraform output -json private_subnet_ids

$vpcId
$eksClusterName
$eksSecurityGroupId
$privateSubnetsJson
```

Guarde esses valores sem alterá-los. Eles serão usados no RDS, backend e autenticação.

### 5.6 Configurar kubectl

Renove as credenciais locais conforme a seção 3.4 e execute:

```powershell
aws eks update-kubeconfig --region us-west-2 --name $eksClusterName
kubectl cluster-info
kubectl get nodes
```

Resultado esperado: o cluster responde e os nodes ficam `Ready`. Se aparecer `Unauthorized`, confirme que o computador está usando a sessão atual do Learner Lab e repita `aws sts get-caller-identity`.

---

## 6. Validar e, se autorizado, provisionar o RDS

O RDS depende dos outputs reais do Kubernetes. Não use IDs fictícios dos arquivos `*.tfvars.example`.

### 6.1 Configurar as variáveis do workspace do banco

Abra `oficina-database-homolog → Variables`.

Renove primeiro as três **Environment variables** AWS conforme a seção 3.2.

Cadastre estas **Terraform variables**:

| Chave | Valor | HCL | Sensitive |
|---|---|---:|---:|
| `aws_region` | `us-west-2` | não | não |
| `environment` | `homolog` | não | não |
| `vpc_id` | valor de `$vpcId` | não | não |
| `private_subnet_ids` | conteúdo de `$privateSubnetsJson` | sim | não |
| `allowed_security_group_ids` | `["VALOR_DE_$eksSecurityGroupId"]` | sim | não |
| `db_name` | `oficina` | não | não |
| `db_username` | `oficina_admin` | não | não |
| `db_password` | senha forte com pelo menos 16 caracteres | não | sim |
| `db_engine_version` | `16` | não | não |
| `db_instance_class` | `db.t3.micro` | não | não |
| `multi_az` | `false` | sim | não |
| `deletion_protection` | `false` | sim | não |
| `skip_final_snapshot` | `true` | sim | não |

Para `allowed_security_group_ids`, substitua o placeholder, por exemplo:

```hcl
["sg-0123456789abcdef0"]
```

Não marque strings simples como HCL. Marque listas e booleanos como HCL.

Guarde a senha do banco em um gerenciador de senhas. A mesma senha será configurada posteriormente no backend e na autenticação. Não grave a senha em arquivo `.tfvars`.

### 6.2 Executar o plan do banco

```powershell
Set-Location C:\fiap-fase3\oficina-database-infra-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-database-homolog'
terraform init -input=false
terraform fmt -check -recursive
terraform validate -no-color
terraform plan -input=false -no-color
```

Confirme:

- PostgreSQL 16;
- `db.t3.micro`;
- subnet group com as duas subnets privadas;
- security group permitindo PostgreSQL a partir do SG do EKS;
- banco não público;
- backup configurado;
- nenhuma exclusão inesperada.

### 6.3 ETAPA COM CUSTO: aplicar o RDS

Esta etapa é obrigatória apenas para executar a aplicação na AWS.

```powershell
terraform apply
```

Revise o plan e digite `yes` somente se decidiu provisionar. Não use `-auto-approve`. A criação do RDS pode demorar vários minutos.

### 6.4 Obter os outputs do banco

Após `Apply complete`:

```powershell
$dbHost = terraform output -raw database_endpoint
$dbPort = terraform output -raw database_port
$dbName = terraform output -raw database_name
$jdbcUrl = terraform output -raw jdbc_url

$dbHost
$dbPort
$dbName
$jdbcUrl
```

Para a autenticação, use SSL na URL:

```powershell
$authJdbcUrl = "$jdbcUrl`?sslmode=require"
$authJdbcUrl
```

Não inclua usuário ou senha na URL.

---

## 7. Gerar as chaves RSA de homologação

Crie as chaves fora dos repositórios:

```powershell
New-Item -ItemType Directory -Force C:\fiap-secrets\oficina-homolog
Set-Location C:\fiap-secrets\oficina-homolog
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt-private.pem
openssl rsa -pubout -in jwt-private.pem -out jwt-public.pem
Get-Item .\jwt-private.pem, .\jwt-public.pem
```

Confirme:

- `jwt-private.pem` começa com `-----BEGIN PRIVATE KEY-----`;
- `jwt-public.pem` começa com `-----BEGIN PUBLIC KEY-----`;
- os arquivos estão em `C:\fiap-secrets`, fora dos repositórios.

Regras:

- a Lambda de login recebe a chave privada e a pública;
- o Lambda Authorizer recebe a chave pública;
- o backend recebe somente a chave pública;
- produção deve usar outro par de chaves;
- não mostre a chave privada em prints ou vídeos.

---

## 8. Validar o backend localmente

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\mvnw.cmd -B -Dtest=ServerlessJwtVerifierTest,ArchitectureTest test
.\mvnw.cmd -B -Dtest=FluxoCompletoOsIntegrationTest test
.\mvnw.cmd -B -DskipTests package
```

Resultado esperado:

- `BUILD SUCCESS` nos três comandos;
- testes RSA e de arquitetura aprovados;
- teste de integração com PostgreSQL/Testcontainers aprovado;
- arquivo JAR gerado em `target`.

Esses testes verificam JWT administrativo HMAC, JWT de cliente RSA, propriedade da OS, histórico, duração, correlation ID e fluxo completo.

---

## 9. Validar e empacotar a autenticação localmente

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
.\mvnw.cmd -B clean verify spotless:check
Test-Path .\target\oficina-auth.jar
```

Resultado esperado:

- 3 testes aprovados;
- `BUILD SUCCESS`;
- `Test-Path` retorna `True`.

O JAR deve existir antes de plan ou apply da autenticação, porque o Terraform envia `target/oficina-auth.jar` ao HCP.

---

## 10. Verificar um RDS preexistente antes da migration V3

Se o RDS foi criado vazio na seção 6, não existem dados antigos e esta verificação prévia pode ser ignorada.

Se você reutilizou um banco que já contém clientes ou ordens de serviço, execute esta seção antes de implantar o backend.

### 10.1 Criar um cliente PostgreSQL temporário dentro do EKS

```powershell
kubectl create namespace oficina-homolog --dry-run=client -o yaml | kubectl apply -f -
kubectl run postgres-client -n oficina-homolog --image=postgres:16-alpine --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/postgres-client -n oficina-homolog --timeout=120s
kubectl exec -it postgres-client -n oficina-homolog -- psql -h $dbHost -p $dbPort -U oficina_admin -d oficina -W
```

O `psql` solicitará a senha do RDS. Digite-a no prompt; ela não aparecerá na tela.

### 10.2 Executar as consultas no prompt do psql

```sql
SELECT regexp_replace(documento, '[^0-9]', '', 'g') AS documento_normalizado,
       COUNT(*)
  FROM clientes
 GROUP BY regexp_replace(documento, '[^0-9]', '', 'g')
HAVING COUNT(*) > 1;

SELECT DISTINCT status FROM ordens_servico ORDER BY status;
```

A consulta de duplicidades deve retornar zero linhas. Os status devem pertencer a:

```text
RECEBIDA
EM_DIAGNOSTICO
AGUARDANDO_APROVACAO
EM_EXECUCAO
AGUARDANDO_PAGAMENTO
PAGA
ENTREGUE
CANCELADA
```

Saia e exclua o pod:

```sql
\q
```

```powershell
kubectl delete pod postgres-client -n oficina-homolog
```

Se houver duplicidade ou status desconhecido, pare. Corrija os dados de forma controlada antes do deploy; não altere a migration para contornar dados inválidos.

---

## 11. Configurar o GitHub Environment `homolog` do backend

Abra:

1. repositório `oficina-backend-fiap-fase3` no GitHub;
2. **Settings → Environments**;
3. abra ou crie o environment `homolog`.

### 11.1 Environment variables

Crie ou atualize:

| Nome | Valor |
|---|---|
| `AWS_REGION` | `us-west-2` |
| `EKS_CLUSTER_NAME` | valor de `$eksClusterName` |
| `APP_DB_URL` | valor de `$jdbcUrl` |
| `APP_DB_USER` | `oficina_admin` |
| `SERVERLESS_JWT_ISSUER` | `oficina-auth-serverless` |
| `SERVERLESS_JWT_AUDIENCE` | `oficina-backend` |

### 11.2 Environment secrets

Crie ou atualize:

| Nome | Origem |
|---|---|
| `AWS_ACCESS_KEY_ID` | sessão atual do Learner Lab |
| `AWS_SECRET_ACCESS_KEY` | sessão atual do Learner Lab |
| `AWS_SESSION_TOKEN` | sessão atual do Learner Lab |
| `APP_DB_PASSWORD` | mesma senha do workspace do RDS |
| `APP_JWT_SECRET` | segredo aleatório do JWT administrativo, com pelo menos 32 caracteres |
| `APP_ADMIN_PASSWORD` | senha forte escolhida para `admin@oficina.local` |
| `SERVERLESS_JWT_PUBLIC_KEY` | conteúdo completo de `jwt-public.pem` |

Para gerar um segredo HMAC aleatório no PowerShell:

```powershell
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 48
$rng.GetBytes($bytes)
[Convert]::ToBase64String($bytes)
$rng.Dispose()
```

Copie o resultado diretamente para `APP_JWT_SECRET` e não o salve no repositório.

Para copiar a chave pública:

```powershell
Get-Content C:\fiap-secrets\oficina-homolog\jwt-public.pem -Raw | Set-Clipboard
```

Cole o conteúdo completo em `SERVERLESS_JWT_PUBLIC_KEY`. Não use `jwt-private.pem` no backend.

As credenciais AWS do GitHub também expiram. Renove os três secrets sempre que iniciar uma nova sessão antes de executar a pipeline.

---

## 12. Publicar e implantar o backend

### 12.1 Confirmar acesso da imagem no GHCR

A pipeline publica a imagem em:

```text
ghcr.io/tiagomiele/oficina-backend-fiap-fase3
```

O Deployment não configura credenciais de pull. Portanto, confirme que o pacote GHCR pode ser lido pelo cluster:

1. abra o perfil/organização no GitHub;
2. abra **Packages**;
3. selecione o pacote `oficina-backend-fiap-fase3`;
4. abra **Package settings**;
5. confirme que a visibilidade permite pull sem autenticação pelo EKS;
6. para este projeto acadêmico, use visibilidade pública se não houver conteúdo proprietário na imagem.

Se a organização exigir pacote privado, será necessário configurar um `imagePullSecret` antes do deploy; não prossiga esperando que um cluster sem credencial baixe uma imagem privada.

### 12.2 Executar novamente a pipeline de homologação

O merge anterior pode ter executado quando AWS/EKS ainda não estavam configurados. Execute a pipeline novamente:

1. abra **Actions** no repositório do backend;
2. selecione o workflow **CD**;
3. clique em **Run workflow**;
4. no seletor de branch, escolha `homolog`;
5. clique em **Run workflow**;
6. aguarde o job `Docker build & push (GHCR)`;
7. aguarde o job `Deploy HOMOLOG`;
8. abra cada job e confirme que não foi ignorado por credenciais ausentes.

Resultado esperado:

- imagem publicada com tag do SHA e tag `homolog`;
- namespace `oficina-homolog` criado;
- ConfigMap `oficina-config` criado;
- Secret `oficina-secrets` criado;
- deployment com rollout concluído;
- smoke test `/actuator/health` aprovado.

Se aparecer `ExpiredToken`, renove os três secrets AWS no GitHub Environment e execute novamente o workflow.

### 12.3 Verificar o deployment pelo kubectl

Com as credenciais locais atuais:

```powershell
kubectl get pods,svc,hpa -n oficina-homolog
kubectl rollout status deployment/oficina-app -n oficina-homolog --timeout=180s
kubectl logs deployment/oficina-app -n oficina-homolog --tail=200
```

Os pods devem estar `Running` e `Ready`. Não copie logs contendo dados pessoais para evidências.

Se aparecer `ImagePullBackOff`, confirme a visibilidade do pacote GHCR. Se aparecer erro de conexão com PostgreSQL, confira `APP_DB_URL`, `APP_DB_USER`, `APP_DB_PASSWORD` e o security group do RDS.

---

## 13. Obter a URL do backend e validar a saúde

```powershell
$backendHost = kubectl get service oficina-app -n oficina-homolog -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
$backendHost
```

Se o valor estiver vazio, aguarde alguns minutos e repita. Não prossiga até existir um hostname.

```powershell
$backendUrl = "http://$backendHost"
$backendUrl
Invoke-RestMethod -Method Get -Uri "$backendUrl/actuator/health"
```

Resultado esperado:

```text
status : UP
```

Use a URL sem `/` no final.

---

## 14. Verificar a migration V3 no RDS

Crie um pod temporário:

```powershell
kubectl run postgres-client -n oficina-homolog --image=postgres:16-alpine --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/postgres-client -n oficina-homolog --timeout=120s
kubectl exec -it postgres-client -n oficina-homolog -- psql -h $dbHost -p $dbPort -U oficina_admin -d oficina -W
```

Digite a senha no prompt e execute:

```sql
SELECT version, description, success
  FROM flyway_schema_history
 ORDER BY installed_rank;

SELECT column_name
  FROM information_schema.columns
 WHERE table_name = 'clientes'
   AND column_name = 'documento_normalizado';

SELECT to_regclass('public.historico_status_ordem_servico');
```

Resultado esperado:

- versão `3` com `success = true`;
- coluna `documento_normalizado` existente;
- tabela `historico_status_ordem_servico` existente.

Saia e apague o pod:

```sql
\q
```

```powershell
kubectl delete pod postgres-client -n oficina-homolog
```

---

## 15. Preparar dados para o teste ponta a ponta

Os comandos desta seção cadastram ou reutilizam dois clientes, um veículo, um serviço e criam uma nova OS. Não use dados pessoais reais.

### 15.1 Fazer login administrativo diretamente no backend

```powershell
$adminPassword = Read-Host 'Digite APP_ADMIN_PASSWORD'
$adminBody = @{
  email = 'admin@oficina.local'
  senha = $adminPassword
} | ConvertTo-Json

$admin = Invoke-RestMethod -Method Post -Uri "$backendUrl/auth/login" -ContentType 'application/json' -Body $adminBody
$adminHeaders = @{ Authorization = "Bearer $($admin.accessToken)" }
$admin.papel
```

Resultado esperado: `FUNCIONARIO_DA_OFICINA`. Não imprima `$admin.accessToken`.

### 15.2 Criar ou reutilizar o cliente proprietário

```powershell
$cpfOwner = '52998224725'
$clientes = Invoke-RestMethod -Method Get -Uri "$backendUrl/clientes" -Headers $adminHeaders
$clienteOwner = $clientes | Where-Object { ($_.documento -replace '[^0-9]', '') -eq $cpfOwner } | Select-Object -First 1

if ($null -eq $clienteOwner) {
  $clienteOwner = Invoke-RestMethod -Method Post -Uri "$backendUrl/clientes" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
    nome = 'Cliente Validacao Semana 3'
    documento = $cpfOwner
    email = 'cliente.week3@teste.local'
    telefone = '11999999999'
  } | ConvertTo-Json)
}

$idClienteOwner = [long]$clienteOwner.idCliente
$idClienteOwner
```

### 15.3 Criar ou reutilizar um segundo cliente

```powershell
$cpfOther = '83574032714'
$clientes = Invoke-RestMethod -Method Get -Uri "$backendUrl/clientes" -Headers $adminHeaders
$clienteOther = $clientes | Where-Object { ($_.documento -replace '[^0-9]', '') -eq $cpfOther } | Select-Object -First 1

if ($null -eq $clienteOther) {
  $clienteOther = Invoke-RestMethod -Method Post -Uri "$backendUrl/clientes" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
    nome = 'Outro Cliente Validacao Semana 3'
    documento = $cpfOther
    email = 'outro.week3@teste.local'
    telefone = '11888888888'
  } | ConvertTo-Json)
}

$idClienteOther = [long]$clienteOther.idCliente
$idClienteOther
```

### 15.4 Criar ou reutilizar o veículo

```powershell
$placa = 'ABC1D23'
$veiculos = Invoke-RestMethod -Method Get -Uri "$backendUrl/veiculos" -Headers $adminHeaders
$veiculo = $veiculos | Where-Object { $_.placa -eq $placa } | Select-Object -First 1

if ($null -eq $veiculo) {
  $veiculo = Invoke-RestMethod -Method Post -Uri "$backendUrl/veiculos" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
    placa = $placa
    marca = 'Fiat'
    modelo = 'Uno'
    ano = 2020
    idCliente = $idClienteOwner
  } | ConvertTo-Json)
}
```

### 15.5 Criar ou reutilizar o serviço

```powershell
$servicos = Invoke-RestMethod -Method Get -Uri "$backendUrl/servicos" -Headers $adminHeaders
$servico = $servicos | Where-Object { $_.nome -eq 'Servico Validacao Semana 3' } | Select-Object -First 1

if ($null -eq $servico) {
  $servico = Invoke-RestMethod -Method Post -Uri "$backendUrl/servicos" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
    nome = 'Servico Validacao Semana 3'
    descricao = 'Servico criado para validacao ponta a ponta'
    precoBase = 150.00
  } | ConvertTo-Json)
}

$idServico = [long]$servico.idServico
$idServico
```

### 15.6 Criar a OS e levá-la até aprovação

```powershell
$os = Invoke-RestMethod -Method Post -Uri "$backendUrl/ordens-servico" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
  idCliente = $idClienteOwner
  placa = $placa
  descricaoProblema = 'Validacao ponta a ponta da Semana 3'
} | ConvertTo-Json)

$numeroOs = $os.numero
$numeroOs
```

O status inicial deve ser `RECEBIDA`.

```powershell
$os = Invoke-RestMethod -Method Post -Uri "$backendUrl/ordens-servico/$numeroOs/servicos" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
  idServicoSku = $idServico
  quantidade = 1
} | ConvertTo-Json)
$os.status

$os = Invoke-RestMethod -Method Post -Uri "$backendUrl/ordens-servico/$numeroOs/enviar-para-aprovacao" -Headers $adminHeaders
$os.status
```

Resultados esperados: `EM_DIAGNOSTICO` e depois `AGUARDANDO_APROVACAO`.

---

## 16. Configurar o workspace da autenticação

Abra `oficina-auth-homolog → Variables`.

### 16.1 Atualizar credenciais AWS

Renove `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` nas **Environment variables**, conforme a seção 3.2.

### 16.2 Cadastrar Terraform variables

| Chave | Valor | HCL | Sensitive |
|---|---|---:|---:|
| `aws_region` | `us-west-2` | não | não |
| `environment` | `homolog` | não | não |
| `lab_role_arn` | `arn:aws:iam::269023862684:role/LabRole` | não | não |
| `private_subnet_ids` | conteúdo de `$privateSubnetsJson` | sim | não |
| `lambda_security_group_id` | valor de `$eksSecurityGroupId` | não | não |
| `db_url` | valor de `$authJdbcUrl` | não | sim |
| `db_user` | `oficina_admin` | não | sim |
| `db_password` | mesma senha do RDS | não | sim |
| `jwt_private_key` | conteúdo completo de `jwt-private.pem` | não | sim |
| `jwt_public_key` | conteúdo completo de `jwt-public.pem` | não | não |
| `jwt_issuer` | `oficina-auth-serverless` | não | não |
| `jwt_audience` | `oficina-backend` | não | não |
| `jwt_ttl_seconds` | `900` | sim | não |
| `backend_base_url` | valor de `$backendUrl`, sem `/` final | não | não |

Para copiar as chaves:

```powershell
Get-Content C:\fiap-secrets\oficina-homolog\jwt-private.pem -Raw | Set-Clipboard
# Cole em jwt_private_key e depois limpe o clipboard.
Set-Clipboard -Value ''

Get-Content C:\fiap-secrets\oficina-homolog\jwt-public.pem -Raw | Set-Clipboard
# Cole em jwt_public_key.
Set-Clipboard -Value ''
```

Não coloque aspas adicionais ao redor do conteúdo PEM no formulário do HCP.

---

## 17. Plan e apply da autenticação

### 17.1 Recriar o JAR

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
.\mvnw.cmd -B -DskipTests package
Test-Path .\target\oficina-auth.jar
```

`Test-Path` deve retornar `True`.

### 17.2 Executar o plan

```powershell
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-auth-homolog'
terraform init -input=false
terraform fmt -check -recursive
terraform validate -no-color
terraform plan -input=false -no-color
```

Confirme:

- duas Lambdas Java 21 ARM64;
- Lambda de login dentro das subnets privadas;
- rota pública `POST /auth/cpf`;
- Lambda Authorizer;
- seis rotas de cliente protegidas;
- HTTP proxy para o backend;
- logs com retenção de 7 dias;
- uso da `LabRole` existente;
- nenhuma IAM role nova;
- nenhuma EKS Access Entry;
- nenhuma exclusão inesperada.

Se aparecer erro informando que `target/oficina-auth.jar` não existe, execute novamente a seção 17.1 na raiz do repositório e repita o plan.

### 17.3 ETAPA COM CUSTO: aplicar autenticação e API Gateway

```powershell
terraform apply
```

Revise o plan e digite `yes` somente se decidiu provisionar. Não use `-auto-approve`.

### 17.4 Obter as URLs

```powershell
$authUrl = terraform output -raw cpf_authentication_url
$apiBase = terraform output -raw api_base_url
$authUrl
$apiBase
```

Não prossiga se os outputs estiverem vazios.

---

## 18. Testar autenticação por CPF e JWT

### 18.1 CPF ativo

```powershell
$responseOwner = Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/json' -Body (@{
  cpf = $cpfOwner
} | ConvertTo-Json)

$tokenOwner = $responseOwner.accessToken
$responseOwner.tokenType
$responseOwner.expiresIn
[bool](-not [string]::IsNullOrWhiteSpace($tokenOwner))
```

Resultado esperado:

- `Bearer`;
- aproximadamente `900` segundos;
- `True` para token preenchido.

Não imprima `$tokenOwner`.

### 18.2 CPF inválido

```powershell
try {
  Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/json' -Body '{"cpf":"111.111.111-11"}'
} catch {
  $_.Exception.Response.StatusCode.value__
}
```

Resultado esperado: `401`, sem informar se o CPF existe.

### 18.3 Requisição sem CPF e JSON inválido

```powershell
try {
  Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/json' -Body '{}'
} catch {
  $_.Exception.Response.StatusCode.value__
}

try {
  Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/json' -Body '{json-invalido'
} catch {
  $_.Exception.Response.StatusCode.value__
}
```

Os dois resultados devem ser `400`.

### 18.4 Conferir claims sem enviar o token a terceiros

```powershell
function Decode-Base64Url([string]$value) {
  $value = $value.Replace('-', '+').Replace('_', '/')
  while ($value.Length % 4) { $value += '=' }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value))
}

$claims = Decode-Base64Url ($tokenOwner.Split('.')[1]) | ConvertFrom-Json
$claims | Select-Object sub, client_id, role, iss, aud, iat, exp, jti
```

Confirme:

- `sub` e `client_id` representam `$idClienteOwner`;
- `role` é `CLIENTE`;
- `iss` é `oficina-auth-serverless`;
- `aud` contém `oficina-backend`;
- `iat`, `exp` e `jti` existem;
- o CPF completo não aparece.

Não salve o token ou os claims completos em arquivos de evidência.

---

## 19. Testar Authorizer, propriedade e fluxo completo da OS

### 19.1 Chamada sem token

```powershell
try {
  Invoke-RestMethod -Method Get -Uri "$apiBase/consulta/ordens-servico/$numeroOs/status"
} catch {
  $_.Exception.Response.StatusCode.value__
}
```

Resultado esperado: `401` ou `403` no API Gateway.

### 19.2 Cliente proprietário consulta a OS

```powershell
$ownerHeaders = @{ Authorization = "Bearer $tokenOwner" }
Invoke-RestMethod -Method Get -Uri "$apiBase/consulta/ordens-servico/$numeroOs/status" -Headers $ownerHeaders
Invoke-RestMethod -Method Get -Uri "$apiBase/ordens-servico/$numeroOs/historico" -Headers $ownerHeaders
```

### 19.3 Outro cliente não pode consultar a OS

```powershell
$responseOther = Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/json' -Body (@{
  cpf = $cpfOther
} | ConvertTo-Json)
$tokenOther = $responseOther.accessToken

try {
  Invoke-RestMethod -Method Get -Uri "$apiBase/consulta/ordens-servico/$numeroOs/status" -Headers @{ Authorization = "Bearer $tokenOther" }
} catch {
  $_.Exception.Response.StatusCode.value__
}
```

Resultado esperado: `404`, sem revelar que a OS pertence ao primeiro cliente.

### 19.4 Proprietário aprova

```powershell
$os = Invoke-RestMethod -Method Post -Uri "$apiBase/ordens-servico/$numeroOs/aprovar" -Headers $ownerHeaders
$os.status
```

Resultado esperado: `EM_EXECUCAO`.

### 19.5 Administração conclui o reparo

```powershell
$os = Invoke-RestMethod -Method Post -Uri "$backendUrl/ordens-servico/$numeroOs/concluir-reparo" -Headers $adminHeaders
$os.status
```

Resultado esperado: `AGUARDANDO_PAGAMENTO`.

### 19.6 Proprietário confirma o pagamento

```powershell
$os = Invoke-RestMethod -Method Post -Uri "$apiBase/ordens-servico/$numeroOs/confirmar-pagamento" -Headers $ownerHeaders -ContentType 'application/json' -Body (@{
  comprovante = 'PIX-VALIDACAO-WEEK3'
} | ConvertTo-Json)
$os.status
```

Resultado esperado: `PAGA`.

### 19.7 Administração entrega o veículo

```powershell
$os = Invoke-RestMethod -Method Post -Uri "$backendUrl/ordens-servico/$numeroOs/entregar" -Headers $adminHeaders
$os.status
```

Resultado esperado: `ENTREGUE`.

### 19.8 Conferir o histórico final

```powershell
$historico = Invoke-RestMethod -Method Get -Uri "$apiBase/ordens-servico/$numeroOs/historico" -Headers $ownerHeaders
$historico | Format-Table status, entradaEm, saidaEm, duracaoMilisegundos, correlationId
```

Confirme:

- estados em ordem cronológica;
- sete estados no fluxo concluído;
- estados encerrados com `saidaEm` e `duracaoMilisegundos`;
- estado atual `ENTREGUE` sem `saidaEm`;
- correlation ID preenchido.

---

## 20. Confirmar que o JWT administrativo continua funcional

O login administrativo já foi usado para preparar os dados. Confirme também uma rota administrativa:

```powershell
Invoke-RestMethod -Method Get -Uri "$backendUrl/relatorios/os-por-status" -Headers $adminHeaders
```

Resultado esperado: HTTP `200`. Isso comprova que o JWT administrativo HMAC continua funcionando e não foi substituído pelo JWT RSA do cliente.

Ao terminar, remova senhas e tokens da memória da sessão:

```powershell
Remove-Variable adminPassword, adminBody, tokenOwner, tokenOther -ErrorAction SilentlyContinue
```

---

## 21. Conferir logs e segurança

### 21.1 CloudWatch

No AWS Console:

1. abra **CloudWatch → Log groups**;
2. abra `/aws/lambda/oficina-auth-homolog-login`;
3. abra `/aws/lambda/oficina-auth-homolog-authorizer`;
4. abra `/aws/apigateway/oficina-auth-homolog`;
5. pesquise pelos request IDs usados nos testes.

Confirme:

- request ID e resultado aparecem;
- CPF e token não aparecem;
- falhas de autenticação usam mensagem genérica;
- nenhum conteúdo de chave aparece.

### 21.2 Kubernetes

```powershell
kubectl logs deployment/oficina-app -n oficina-homolog --tail=300
kubectl get configmap oficina-config -n oficina-homolog -o yaml
kubectl get secret oficina-secrets -n oficina-homolog
```

Não execute `kubectl get secret oficina-secrets -o yaml`, pois isso expõe valores codificados que podem ser decodificados.

### 21.3 Repositórios

Em cada repositório:

```powershell
git status --short
git diff --check
git grep -n -I -E 'BEGIN PRIVATE KEY|AWS_SECRET_ACCESS_KEY=|DB_PASSWORD=|accessToken=' -- ':!docs/validation/week3.md'
```

Não deve existir chave privada, credencial ou token versionado.

---

## 22. Evidências que devem ser guardadas

Guarde evidências sanitizadas de:

- `homolog` atualizada nos quatro repositórios;
- workspaces com Manual apply e Auto apply desativado;
- plan do EKS mostrando Kubernetes 1.34;
- outputs do Kubernetes sem credenciais;
- plan do RDS;
- RDS disponível;
- CI local do backend e autenticação;
- pipeline CD aprovada;
- pods `Running` e rollout concluído;
- `/actuator/health` com `UP`;
- Flyway V3 com sucesso;
- plan da autenticação;
- Lambdas e API Gateway criados;
- CPF ativo retornando `200` sem mostrar CPF/token;
- CPF inválido retornando `401`;
- requisição inválida retornando `400`;
- chamada sem token negada;
- outro cliente recebendo `404`;
- fluxo da OS até `ENTREGUE`;
- histórico com duração e correlation ID;
- login administrativo funcional;
- CloudWatch sem CPF, token ou chave.

Não guarde prints de:

- AWS Details;
- variáveis sensíveis do HCP;
- secrets do GitHub;
- conteúdo de Kubernetes Secrets;
- JWT completo;
- chave privada;
- senha do banco ou do administrador.

---

## 23. Problemas comuns e correção

| Erro | Causa provável | Correção |
|---|---|---|
| `ExpiredToken` | sessão AWS Academy expirou | renove as três credenciais no local que executou a operação |
| `InvalidClientTokenId` | credenciais misturadas ou incorretas | copie novamente as três credenciais da mesma sessão |
| organização HCP não encontrada | placeholder ou nome incorreto | use `oficina-fiap-soat-fase-2` sem `<` e `>` |
| `-reconfigure` inválido | opção incompatível com `cloud {}` | execute `terraform init -input=false` sem `-reconfigure` |
| ARN da LabRole inválido | prefixo `arn:` ausente | use `arn:aws:iam::269023862684:role/LabRole` |
| JAR da Lambda não encontrado | autenticação não empacotada | execute `./mvnw.cmd -B -DskipTests package` na raiz do auth |
| kubectl `Unauthorized` | credencial local antiga | renove `~/.aws/credentials`, valide STS e atualize kubeconfig |
| `ImagePullBackOff` | pacote GHCR não legível | torne o pacote legível ou configure `imagePullSecret` |
| backend não conecta ao RDS | URL, senha ou security group incorreto | confira outputs, GitHub Environment e SG autorizado |
| Lambda não conecta ao RDS | subnet/SG/URL incorretos | confira `private_subnet_ids`, SG do EKS e `db_url` |
| migration V3 falha no índice único | documentos normalizados duplicados | corrija duplicidades antes do deploy |
| API Gateway retorna `401/403` com token válido | issuer, audience ou chave divergentes | use exatamente o mesmo par RSA, issuer e audience |
| propriedade retorna `404` | token pertence a outro cliente | comportamento esperado de segurança |
| LoadBalancer sem hostname | serviço ainda provisionando | aguarde e repita a consulta do service |

---

## 24. Encerramento e custos

Ao terminar a coleta de evidências:

1. não promova automaticamente para `main`;
2. revise os resultados da homologação;
3. decida separadamente sobre o PR `homolog → main`;
4. destrua os recursos se não forem mais necessários e se a entrega permitir;
5. faça destroy na ordem inversa: autenticação, banco e Kubernetes;
6. revise cada destroy antes de confirmar;
7. não use `-auto-approve`.

Os itens de New Relic APM, dashboards e alertas pertencem à Semana 4 e não são considerados aprovados por este roteiro da Semana 3.
