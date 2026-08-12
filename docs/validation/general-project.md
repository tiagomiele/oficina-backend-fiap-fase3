# Guia geral de execução e validação do projeto

Este é o documento único para executar, validar e coletar evidências de toda a solução no Windows com PowerShell, HCP Terraform, AWS Academy e New Relic. Ele cobre os quatro repositórios, infraestrutura, banco, backend, autenticação serverless, fluxo completo da ordem de serviço, segurança, observabilidade, testes, rollback, limpeza, critérios acadêmicos, PDF e o roteiro do vídeo que será gravado pelo usuário.

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

Abra o **PowerShell como usuário normal**. Não use uma janela administrativa. Em uma máquina nova, instale as ferramentas abaixo com `winget`:

```powershell
winget install --id Git.Git -e
winget install --id Hashicorp.Terraform -e --architecture x64
winget install --id Amazon.AWSCLI -e
winget install --id EclipseAdoptium.Temurin.21.JDK -e
winget install --id Docker.DockerDesktop -e
winget install --id Kubernetes.kubectl -e
winget install --id Helm.Helm -e
winget install --id GitHub.cli -e
winget install --id OpenJS.NodeJS.LTS -e
winget install --id GrafanaLabs.k6 -e
```

Feche e abra o PowerShell após as instalações. Inicie o Docker Desktop, aguarde o ícone indicar que o engine está ativo e execute:

```powershell
git --version
terraform version
$TerraformInfo = terraform version -json | ConvertFrom-Json
if ($TerraformInfo.platform -ne 'windows_amd64') {
  throw "Terraform incompatível: $($TerraformInfo.platform). Instale Hashicorp.Terraform para Windows x64."
}
aws --version
java -version
docker version
kubectl version --client
helm version --short
gh --version
node --version
npm --version
k6 version

$OpenSsl = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if ([string]::IsNullOrWhiteSpace($OpenSsl)) {
  $OpenSsl = Join-Path $env:ProgramFiles 'Git\usr\bin\openssl.exe'
}
if (-not (Test-Path $OpenSsl)) { throw 'OpenSSL não encontrado. Reinstale o Git for Windows.' }
& $OpenSsl version
```

Critérios obrigatórios:

- Terraform `>= 1.6` e `< 2.0`, obrigatoriamente com plataforma `windows_amd64`;
- Java 21;
- Docker respondendo sem erro;
- `kubectl` compatível com Kubernetes 1.34;
- acesso de proprietário ou administrador aos quatro repositórios GitHub;
- permissão **Manage projects** e **Manage all workspaces** na organização HCP Terraform `oficina-fiap-soat-fase-2`;
- acesso ao AWS Academy Learner Lab;
- conta New Relic somente para as seções de observabilidade.

Não prossiga se algum comando falhar. O script usa o OpenSSL incluído no Git for Windows quando ele não está no `PATH`; nunca use uma chave copiada da internet.

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

### 2.5 Limpar somente o cache após trocar Terraform 32 bits por x64

Execute esta subseção apenas se `terraform version` mostrava `windows_386` e foi substituído por `windows_amd64`. Os diretórios `.terraform` contêm providers e metadados locais; o state permanece no HCP Terraform. Não remova nem altere `.terraform.lock.hcl`.

```powershell
$TerraformRepositories = @(
  'C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3',
  'C:\fiap-fase3\oficina-database-infra-fiap-fase3',
  'C:\fiap-fase3\oficina-auth-serverless-fiap-fase3'
)
foreach ($Repository in $TerraformRepositories) {
  $Cache = Join-Path $Repository '.terraform'
  if (Test-Path $Cache) {
    Remove-Item -Path $Cache -Recurse -Force
  }
}
```

---

## 3. Preparação automática dos ambientes

### 3.1 Configuração inicial única

No computador Windows, autentique uma única vez:

```powershell
terraform login
gh auth login --hostname github.com --git-protocol https --web
gh auth status --hostname github.com
```

No `terraform login`, confirme `yes`, abra o endereço exibido, gere o token solicitado e cole-o no PowerShell. No GitHub CLI, conclua a autorização no navegador usando a conta com acesso aos quatro repositórios.

Mantenha os quatro repositórios como irmãos em `C:\fiap-fase3`. O script central está no backend e nunca executa `terraform apply`, `terraform destroy`, Helm ou deploy.

Secrets estáveis são armazenados fora dos repositórios em `C:\fiap-secrets\oficina-<ambiente>`:

- senha do RDS, senha administrativa e secret HMAC em CLIXML protegido pelo usuário do Windows;
- par RSA em arquivos PEM locais;
- nenhum desses arquivos deve ser versionado, copiado para prints ou exibido em logs.

Na primeira execução de um ambiente, informe os valores atuais já usados pela infraestrutura. Pressione Enter para gerar um valor novo somente quando o ambiente ainda não tiver sido criado.

### 3.2 Renovar a sessão do AWS Academy uma única vez

1. inicie o Learner Lab e aguarde o indicador verde;
2. abra **AWS Details** e copie o bloco `[default]` completo para o clipboard, ou salve-o em um arquivo fora dos repositórios;
3. não copie outro texto até concluir os próximos dois comandos; ambos leem o mesmo bloco diretamente do clipboard;
4. valide acessos sem alterar arquivos, HCP ou GitHub:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog -ValidateOnly
```

5. execute para o ambiente desejado:

```powershell
.\scripts\configure-environment.ps1 -Environment homolog
```

Alternativa com arquivo, sem depender do clipboard:

```powershell
$CredentialsFile = "$HOME\Downloads\credentials"
.\scripts\configure-environment.ps1 `
  -Environment production `
  -AwsCredentialsFile $CredentialsFile `
  -ValidateOnly
.\scripts\configure-environment.ps1 `
  -Environment production `
  -AwsCredentialsFile $CredentialsFile
```

Você copia ou salva o bloco AWS uma única vez por sessão. O script valida `aws sts get-caller-identity`, salva os outputs não sensíveis em `environment-context.ps1` e atualiza automaticamente:

- o perfil local do AWS CLI;
- o projeto HCP `soat-fase3`, quando ainda não existir;
- os oito workspaces HCP de Kubernetes, banco, autenticação e New Relic para homologação e produção;
- execução remota, apply manual, Auto apply desativado e Working Directory correto dos workspaces;
- o Variable Set HCP `aws-academy-credentials`, associado aos seis workspaces AWS de homologação e produção;
- os secrets dos GitHub Environments `homolog` e `production` dos quatro repositórios;
- o token e as variáveis fixas dos GitHub Environments;
- secrets estáveis do ambiente selecionado;
- variáveis dinâmicas que já possuam outputs disponíveis.

Variáveis AWS diretas nos workspaces são removidas para não sobrescrever o Variable Set compartilhado. O ARN da `LabRole` é calculado pelos módulos com `aws_caller_identity`; ele não é mais cadastrado manualmente.

Considere a preparação aprovada somente quando o comando terminar com código zero e exibir `Configuração automática concluída para <ambiente>`. Avisos de que Kubernetes, RDS ou LoadBalancer ainda não possuem outputs são esperados antes da criação desses recursos. Falha de provider, inicialização ou leitura do state termina com `Configuração incompleta`; nesse caso, não execute plan/apply, corrija a pendência exibida e repita o mesmo script.

### 3.3 Sincronização idempotente de outputs

Reexecute o mesmo comando, sem copiar IDs, após cada marco:

```powershell
.\scripts\configure-environment.ps1 -Environment homolog
```

| Depois de | O script propaga |
|---|---|
| apply do Kubernetes | VPC, subnets privadas e security group para banco e autenticação |
| apply do RDS | URL JDBC e credenciais para autenticação e backend |
| deploy do backend | URL do LoadBalancer para autenticação, health check e backend |
| apply da autenticação | URL do API Gateway para o backend |

Se um output ainda não existir, o script emite aviso e preserva o restante da configuração. Ele não inventa IDs, não usa valores de uma sessão anterior e pode ser reexecutado com segurança.

O GitHub Environment do backend permanece com `DEPLOY_ENABLED=false` enquanto os outputs de EKS e RDS não estiverem disponíveis. Nesse estado, merges continuam validando e publicando a imagem, mas o job de deploy termina com aviso, sem falhar e sem tentar acessar o cluster. Quando ambos os states estiverem prontos, o mesmo script grava os valores reais e altera `DEPLOY_ENABLED=true` automaticamente.

### 3.4 New Relic

Na primeira preparação do New Relic para cada ambiente, use:

```powershell
.\scripts\configure-environment.ps1 -Environment homolog -ConfigureNewRelic
```

Não crie o workspace de New Relic manualmente: a execução efetiva do script cria `oficina-newrelic-homolog` e `oficina-newrelic-production` com Working Directory `observability/newrelic`. Account ID, API key e License key são solicitados somente na primeira configuração e reutilizados para homologação e produção a partir de `C:\fiap-secrets\shared`, sem impressão dos valores. A versão pública da camada Java ARM64 é descoberta automaticamente na AWS.

### 3.5 Limitação inevitável

As credenciais do Learner Lab expiram. A cada nova sessão, copie o novo bloco `[default]` e execute novamente um único comando. Não é necessário abrir individualmente nenhum workspace HCP ou GitHub Environment.

Quando comandos de validação deste guia precisarem de `$dbHost`, `$jdbcUrl`, `$backendUrl`, `$authUrl` ou outros outputs, carregue o contexto persistente:

```powershell
. C:\fiap-secrets\oficina-homolog\environment-context.ps1
```

---

## 4. Conferir a criação automática no HCP Terraform

Depois da primeira execução **sem** `-ValidateOnly`, abra o projeto HCP `soat-fase3` e confirme estes oito workspaces:

```text
oficina-kubernetes-homolog
oficina-kubernetes-production
oficina-database-homolog
oficina-database-production
oficina-auth-homolog
oficina-auth-production
oficina-newrelic-homolog
oficina-newrelic-production
```

Não crie variáveis pelo formulário. O script já configura execução remota, apply manual, Auto apply desativado e os Working Directories. Os seis workspaces AWS usam a raiz do respectivo repositório; os dois de New Relic usam `observability/newrelic`.

Se um workspace não aparecer, não prossiga. Reexecute o script sem `-ValidateOnly` e leia a mensagem de erro completa. Verifique se o token criado por `terraform login` possui acesso à organização `oficina-fiap-soat-fase-2`. Não substitua o workspace ausente por outro nome.

As seções 5 a 23 executam homologação. A sequência completa e parametrizada de produção está na seção 24.1 e só deve ser usada depois da homologação aprovada.

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

### 5.2 Configurar o workspace sem cadastro manual

Execute a seção 3.2. O script mantém apenas `environment=homolog` no workspace. Região, versão do EKS e demais valores econômicos vêm dos defaults versionados; a `LabRole` é derivada automaticamente da conta autenticada.

Não cadastre `lab_role_arn`, `private_subnet_ids` ou credenciais AWS diretamente no workspace Kubernetes. As credenciais vêm do Variable Set compartilhado, e as subnets são outputs do próprio módulo.

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

### 5.5 Validar e sincronizar os outputs

Após o apply:

```powershell
terraform output
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
```

Não copie VPC, subnet ou security group. O segundo comando lê os outputs do state e os grava nos workspaces dependentes. Não prossiga se `terraform output` estiver vazio.

### 5.6 Configurar kubectl

As credenciais locais já foram renovadas pela seção 3.2. Execute:

```powershell
. C:\fiap-secrets\oficina-homolog\environment-context.ps1
aws eks update-kubeconfig --region us-west-2 --name $eksClusterName
kubectl cluster-info
kubectl get nodes
```

Resultado esperado: o cluster responde e os nodes ficam `Ready`. Se aparecer `Unauthorized`, confirme que o computador está usando a sessão atual do Learner Lab e repita `aws sts get-caller-identity`.

---

## 6. Validar e, se autorizado, provisionar o RDS

O RDS depende dos outputs reais do Kubernetes. Não use IDs fictícios dos arquivos `*.tfvars.example`.

### 6.1 Sincronizar o workspace do banco

A seção 5.5 configura automaticamente `vpc_id`, `private_subnet_ids`, `allowed_security_group_ids`, `db_password` e `environment`.

Os valores fixos (`us-west-2`, PostgreSQL 16, `db.t3.micro`, nome e usuário do banco, `multi_az=false`, `deletion_protection=false` e `skip_final_snapshot=true`) são defaults versionados e não devem ser repetidos no HCP.

Esses defaults econômicos são adequados apenas ao AWS Academy. Em produção real use proteção contra exclusão, snapshot final, alta disponibilidade e dimensionamento compatível.

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

### 6.4 Validar e sincronizar os outputs do banco

Após `Apply complete`:

```powershell
terraform output
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
. C:\fiap-secrets\oficina-homolog\environment-context.ps1
```

Confirme que o contexto foi carregado antes de seguir:

```powershell
if ([string]::IsNullOrWhiteSpace($dbHost)) { throw 'dbHost ausente no contexto.' }
if ([int]$dbPort -le 0) { throw 'dbPort ausente no contexto.' }
if ([string]::IsNullOrWhiteSpace($jdbcUrl)) { throw 'jdbcUrl ausente no contexto.' }
```

O script adiciona `sslmode=require` somente para a autenticação, mantém usuário e senha fora da URL e atualiza o GitHub Environment do backend. Não copie o endpoint manualmente. Como os outputs do EKS já foram sincronizados na etapa anterior, essa execução também habilita `DEPLOY_ENABLED=true`; o próximo run do CD poderá acessar o cluster com valores reais.

---

## 7. Chaves RSA e secrets estáveis

O script da seção 3 cria ou reutiliza o par RSA e os secrets estáveis em `C:\fiap-secrets\oficina-<ambiente>`. Não execute geração manual nem copie conteúdo PEM para HCP ou GitHub.

Validação opcional, sem exibir a chave:

```powershell
openssl pkey -in C:\fiap-secrets\oficina-homolog\jwt-private.pem -check -noout
openssl pkey -pubin -in C:\fiap-secrets\oficina-homolog\jwt-public.pem -text -noout
```

Se já existe infraestrutura, informe os secrets atuais na primeira execução para evitar rotação acidental. Produção usa seu próprio diretório e par RSA.

---

## 8. Validar o backend localmente

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\mvnw.cmd -B clean spotless:check verify
```

Resultado esperado:

- `BUILD SUCCESS`;
- testes unitários, arquitetura, observabilidade, segurança e integração aprovados;
- cobertura JaCoCo aprovada;
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

- 42 testes aprovados;
- `BUILD SUCCESS`;
- `Test-Path` retorna `True`.

O JAR deve existir antes de plan ou apply da autenticação, porque o Terraform envia `target/oficina-auth.jar` ao HCP.

---

## 10. Verificar um RDS preexistente antes das migrations

Se o RDS foi criado vazio na seção 6, não existem dados antigos e esta verificação prévia pode ser ignorada.

Se você reutilizou um banco que já contém clientes ou ordens de serviço, execute esta seção antes de implantar o backend. Carregue novamente o contexto, mesmo que já tenha feito isso em outra seção:

```powershell
. C:\fiap-secrets\oficina-homolog\environment-context.ps1
if ([string]::IsNullOrWhiteSpace($dbHost)) { throw 'dbHost ausente. Reexecute o script central após o apply do RDS.' }
if ([int]$dbPort -le 0) { throw 'dbPort ausente. Reexecute o script central após o apply do RDS.' }
```

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

## 11. Configurar o GitHub Environment do backend

Nenhuma variável ou secret desta seção deve ser cadastrada manualmente. O comando da seção 3 configura os environments `homolog` e `production` e sincroniza, no ambiente selecionado:

- credenciais temporárias AWS;
- região e nome do cluster;
- URL, usuário e senha do banco;
- issuer, audience e chave pública RSA;
- secret HMAC administrativo e senha do administrador;
- URL do backend e do API Gateway quando seus outputs existirem;
- configuração New Relic quando `-ConfigureNewRelic` for usado.

Antes do deploy, reexecute:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
```

O backend recebe somente a chave pública RSA. A chave privada permanece no diretório local protegido e no workspace da autenticação.

---

## 12. Publicar e implantar o backend

### 12.1 Confirmar acesso da imagem no GHCR

A pipeline publica a imagem em:

```text
ghcr.io/tiagomiele/oficina-backend-fiap-fase3
```

O Deployment atual não possui `imagePullSecret`; portanto, esta entrega exige que o pacote GHCR seja público:

1. abra https://github.com/tiagomiele?tab=packages;
2. selecione `oficina-backend-fiap-fase3`;
3. abra **Package settings**;
4. em **Danger Zone → Change package visibility**, selecione **Public**;
5. confirme o nome do pacote quando solicitado;
6. abra uma janela anônima do navegador e confirme que a página do pacote pode ser acessada sem login.

Não prossiga com pacote privado: o manifesto versionado não suporta esse modo e o pod entrará em `ImagePullBackOff`. Não crie um token pessoal ou `imagePullSecret` fora do projeto apenas para contornar esta validação.

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

Use a URL sem `/` no final. Sincronize-a automaticamente:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
. C:\fiap-secrets\oficina-homolog\environment-context.ps1
```

---

## 14. Verificar as migrations e os índices no RDS

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

SELECT indexname
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND indexname IN (
     'idx_itens_orc_servico_sku',
     'idx_cc_nota_fornecedor',
     'idx_cc_tipo_data'
   )
 ORDER BY indexname;
```

Resultado esperado:

- versões `1` a `4` com `success = true`;
- coluna `documento_normalizado` existente;
- tabela `historico_status_ordem_servico` existente;
- índices `idx_itens_orc_servico_sku`, `idx_cc_nota_fornecedor` e `idx_cc_tipo_data` existentes.

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
$adminPasswordSecure = Read-Host 'Digite APP_ADMIN_PASSWORD' -AsSecureString
$adminPasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPasswordSecure)
try {
  $adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPasswordPointer)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminPasswordPointer)
}
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
    nome = 'Cliente Validacao projeto'
    documento = $cpfOwner
    email = 'cliente.projeto@teste.local'
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
    nome = 'Outro Cliente Validacao projeto'
    documento = $cpfOther
    email = 'outro.projeto@teste.local'
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
$servico = $servicos | Where-Object { $_.nome -eq 'Servico Validacao projeto' } | Select-Object -First 1

if ($null -eq $servico) {
  $servico = Invoke-RestMethod -Method Post -Uri "$backendUrl/servicos" -Headers $adminHeaders -ContentType 'application/json' -Body (@{
    nome = 'Servico Validacao projeto'
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
  descricaoProblema = 'Validacao ponta a ponta da projeto'
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

Não abra o formulário de variáveis para copiar outputs ou chaves. Reexecute o script central depois do Kubernetes, RDS e backend:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
```

Ele configura automaticamente:

- credenciais AWS pelo Variable Set compartilhado;
- `environment`;
- subnets privadas e security group a partir do Kubernetes;
- URL JDBC com `sslmode=require`, usuário e senha a partir do banco;
- par RSA do diretório seguro;
- URL do backend quando o LoadBalancer existir.

Região, issuer, audience e TTL usam defaults versionados. A `LabRole` é derivada da conta AWS autenticada e não existe mais como input manual.

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

Não prossiga se os outputs estiverem vazios. Em seguida, reexecute o script central para sincronizar a URL do API Gateway com o backend:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
```

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
Remove-Variable adminPassword, adminPasswordSecure, adminPasswordPointer, adminBody, tokenOwner, tokenOther -ErrorAction SilentlyContinue
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
git grep -n -I -E 'BEGIN PRIVATE KEY|AWS_SECRET_ACCESS_KEY=|DB_PASSWORD=|accessToken=' -- ':!docs/validation/projeto.md'
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
- Flyway até V4 com sucesso;
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
| CD informa que o deploy foi ignorado | `DEPLOY_ENABLED` está ausente ou `false` porque EKS/RDS ainda não possuem outputs | conclua os applies necessários e reexecute `configure-environment.ps1`; não cadastre a variável manualmente |
| CD mostra `Configure no GitHub Environment` | o deploy foi habilitado, mas algum valor obrigatório foi removido depois da sincronização | reexecute `configure-environment.ps1` para restaurar secrets e variáveis reais |
| `ExpiredToken` | sessão AWS Academy expirou | copie o novo bloco `[default]` e reexecute `configure-environment.ps1` uma vez |
| `InvalidClientTokenId` | credenciais misturadas ou incorretas | copie novamente as três credenciais da mesma sessão |
| organização HCP não encontrada | placeholder ou nome incorreto | use `oficina-fiap-soat-fase-2` sem `<` e `>` |
| HCP `422` com `Sensitive cannot be updated` | a variável sensível já existe e o HCP aceita somente a atualização do valor | use a versão atual do script e reexecute o mesmo comando; não apague nem recrie a variável manualmente |
| propriedade `vpc_id` ou outro output não encontrada | versão antiga do script tentou acessar um state ainda vazio ou parcial | atualize a branch, reexecute o script e aguarde o aviso de output ausente; não cadastre IDs manualmente |
| `aws.exe` falha em `eks update-kubeconfig` durante a preparação | versão antiga do script tentou consultar o LoadBalancer antes de o cluster existir | atualize a branch e reexecute; o script deve ignorar essa consulta até existirem outputs do EKS |
| `-reconfigure` inválido | opção incompatível com `cloud {}` | execute `terraform init -input=false` sem `-reconfigure` |
| JAR da Lambda não encontrado | autenticação não empacotada | execute `.\mvnw.cmd -B -DskipTests package` na raiz do auth |
| kubectl `Unauthorized` | credencial local antiga | reexecute o script central, valide STS e atualize kubeconfig |
| `ImagePullBackOff` | pacote GHCR privado | torne o pacote público conforme a seção 12.1 e execute novamente o CD |
| backend não conecta ao RDS | outputs ainda não sincronizados ou senha incorreta | reexecute o script central após o apply do RDS e confira o SG autorizado |
| Lambda não conecta ao RDS | outputs ainda não sincronizados | reexecute o script central após Kubernetes e RDS; não copie IDs manualmente |
| migration de documento normalizado falha no índice único | documentos normalizados duplicados | corrija duplicidades antes do deploy |
| API Gateway retorna `401/403` com token válido | issuer, audience ou chave divergentes | use exatamente o mesmo par RSA, issuer e audience |
| propriedade retorna `404` | token pertence a outro cliente | comportamento esperado de segurança |
| LoadBalancer sem hostname | serviço ainda provisionando | aguarde e repita a consulta do service |

### 23.1 Recuperação após reset do AWS Academy

Um reset pode excluir recursos AWS sem atualizar o state remoto. Não execute outro destroy e não remova recursos do state manualmente.

1. renove a sessão com o script central;
2. no repositório do componente, execute somente:

```powershell
terraform plan -refresh-only -input=false -no-color
```

3. se o plan mostrar exclusivamente `Drift detected (delete)` para recursos que o reset já removeu, execute `terraform apply -refresh-only`;
4. confirme que `terraform state list` ficou vazio;
5. gere um plan normal e prossiga somente se o resultado esperado for criação limpa, sem destroys;
6. depois de cada apply, reexecute o script central para propagar os novos IDs.

Os outputs de subnet do Kubernetes aceitam mapas vazios durante o refresh, evitando o `Invalid index` que antes bloqueava a reconciliação. Se o refresh mostrar qualquer recurso ainda existente, pare e revise antes de aplicar.

---

## 24. Regras de promoção e controle de custo

Estas regras se aplicam ao final de todas as seções deste guia; não destrua os recursos antes de validar New Relic, Newman, k6 e HPA:

1. não promova automaticamente para `main`;
2. revise os resultados da homologação;
3. decida separadamente sobre o PR `homolog → main`;
4. destrua os recursos somente após concluir as seções 25 a 40, se não forem mais necessários e se a entrega permitir;
5. siga a ordem detalhada de destroy da seção 37;
6. revise cada destroy antes de confirmar;
7. não use `-auto-approve`.

A validação só estará concluída após executar também as seções de observabilidade, segurança, carga, evidências e limpeza adicionadas abaixo.

### 24.1 Executar production depois da homologação aprovada

Não reutilize variáveis do PowerShell de homologação. Produção possui state, secrets, chaves RSA, namespace e URLs próprios. Antes de começar, confirme no GitHub que a branch `homolog` validada foi promovida por PR para `main` nos quatro repositórios. Não faça push direto para `main`.

Abra um PowerShell novo, inicie o Learner Lab e copie novamente o bloco `[default]` completo para o clipboard. Sem copiar outro texto, configure somente produção:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment production -ValidateOnly
.\scripts\configure-environment.ps1 -Environment production
. C:\fiap-secrets\oficina-production\environment-context.ps1
```

#### 24.1.1 Kubernetes de produção

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
git switch main
git pull --ff-only
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-kubernetes-production'
terraform init -input=false
terraform fmt -check -recursive
terraform validate -no-color
terraform plan -input=false -no-color
```

Pare se o plan contiver exclusões inesperadas. Após autorização de custo, execute `terraform apply`, revise novamente e digite `yes`. Em seguida:

```powershell
terraform output
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment production
```

#### 24.1.2 RDS de produção

```powershell
Set-Location C:\fiap-fase3\oficina-database-infra-fiap-fase3
git switch main
git pull --ff-only
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-database-production'
terraform init -input=false
terraform fmt -check -recursive
terraform validate -no-color
terraform plan -input=false -no-color
```

Após revisar e autorizar o custo, execute `terraform apply` e digite `yes`. Depois sincronize e carregue o contexto:

```powershell
terraform output
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment production
. C:\fiap-secrets\oficina-production\environment-context.ps1
```

#### 24.1.3 Backend de produção

No GitHub, abra **Actions → CD → Run workflow**, selecione `main` e execute. O workflow cria uma issue de aprovação. Confira SHA e imagem na issue e comente `approved`. Aguarde `Deploy PRODUÇÃO` e valide:

```powershell
aws eks update-kubeconfig --region us-west-2 --name oficina-production
kubectl get pods,svc,hpa -n oficina-production
kubectl rollout status deployment/oficina-app -n oficina-production --timeout=180s
$backendHost = $null
for ($attempt = 1; $attempt -le 30 -and [string]::IsNullOrWhiteSpace($backendHost); $attempt++) {
  $backendHost = kubectl get service oficina-app -n oficina-production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
  if ([string]::IsNullOrWhiteSpace($backendHost)) { Start-Sleep -Seconds 10 }
}
if ([string]::IsNullOrWhiteSpace($backendHost)) { throw 'LoadBalancer de produção sem hostname após cinco minutos.' }
Invoke-RestMethod -Method Get -Uri "http://$backendHost/actuator/health"
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment production
```

#### 24.1.4 Autenticação de produção

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
git switch main
git pull --ff-only
.\mvnw.cmd -B clean verify spotless:check
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-auth-production'
terraform init -input=false
terraform fmt -check -recursive
terraform validate -no-color
terraform plan -input=false -no-color
```

Após autorização, execute `terraform apply`, revise e digite `yes`. Depois:

```powershell
terraform output
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment production
. C:\fiap-secrets\oficina-production\environment-context.ps1
if ([string]::IsNullOrWhiteSpace($apiBase)) { throw 'API Gateway de produção ausente no contexto.' }
Invoke-RestMethod -Method Get -Uri "$backendUrl/actuator/health"
aws lambda get-function --function-name oficina-auth-production-login --query 'Configuration.[FunctionName,Runtime,Architectures]' --output table
aws lambda get-function --function-name oficina-auth-production-authorizer --query 'Configuration.[FunctionName,Runtime,Architectures]' --output table
aws apigatewayv2 get-apis --query "Items[?Name=='oficina-auth-production-http-api'].[Name,ApiEndpoint]" --output table
```

#### 24.1.5 Add-ons e observabilidade de produção

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment production -ConfigureNewRelic
```

Depois, no repositório Kubernetes, abra **Actions → Deploy → Run workflow**, selecione a branch `main`, `environment=production`, `apply_infrastructure=false`, `deploy_addons=true` e `apply_observability=true`. Aprove o GitHub Environment quando solicitado. Aguarde os três jobs e confirme `kubectl top nodes`, pods `nri-bundle` em `Running` e entidades de produção no New Relic. Não execute Newman, k6 nem cadastre dados sintéticos em produção; esses testes pertencem à homologação.

---

## 25. Configurar a conta e as chaves do New Relic

Esta configuração não cria recursos AWS. Dashboards, alertas e monitor sintético só são criados após `terraform apply` autorizado no workspace de observabilidade.

1. Em https://one.newrelic.com/, obtenha o **Account ID**, uma **User API key** e uma **License key**.
2. Não copie essas chaves para HCP ou GitHub. Execute o script; ele cria/configura os workspaces e distribui os valores por canais sensíveis:


```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog -ConfigureNewRelic
```

O script configura o workspace de observabilidade, a autenticação, o backend e o Kubernetes sem imprimir as chaves. Repita com `-Environment production` para manter secrets e nomes separados.

O monitor sintético permanece desativado enquanto a URL pública não existir. Quando o LoadBalancer responder, o script sincroniza `HEALTH_CHECK_URL` e ativa o monitor automaticamente.

## 26. Configurar os GitHub Environments para deploy controlado

O script central cria ou atualiza os environments `homolog` e `production` nos quatro repositórios e também `homolog-apply` e `production-apply` no repositório de autenticação. Ele inclui credenciais AWS, token HCP, nomes dos workspaces, variáveis fixas e valores dinâmicos disponíveis.

Não copie secrets ou IDs pelo formulário do GitHub. Reexecute:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
```

Permanece uma configuração humana única, pois ela é uma regra de governança e não um valor de aplicação:

1. habilite **Required reviewers** nos environments de apply criados pelo script;
2. limite produção à branch `main` e homologação à branch `homolog`.

`TF_APPLY_ENABLED=true` e `ENABLE_TERRAFORM_APPLY=true` são sincronizados pelo script, mas não removem os gates: o workflow continua exigindo disparo manual, confirmação textual e aprovação do environment. Não existe apply automático.

## 27. Configurar observabilidade do RDS

Não cadastre variáveis de observabilidade do RDS manualmente. O módulo já define exportação do log PostgreSQL, logs de conexão/desconexão, limite de consultas lentas em 1000 ms, Performance Insights desativado, Enhanced Monitoring desativado, `multi_az = false`, `deletion_protection = false` e `skip_final_snapshot = true`. O script central define a retenção de backup em 7 dias para homologação e 14 dias para produção.

Os logs registram conexões, desconexões e consultas lentas sem habilitar `log_statement` nem `log_parameter_max_length`; parâmetros, CPF e dados pessoais não devem ser enviados ao CloudWatch.

Execute apenas o plan:

```powershell
Set-Location C:\fiap-fase3\oficina-database-infra-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-database-homolog'
terraform init -input=false
terraform plan -input=false -no-color
```

Confirme no plan o log export `postgresql`, o parameter group e ausência de destruições. O apply continua sendo etapa com custo e requer autorização.

## 28. Instalar Metrics Server e New Relic no EKS

Execute esta seção somente depois do apply do EKS e com credenciais atuais do Learner Lab.

1. No GitHub, abra o repositório Kubernetes.
2. Vá a **Actions → Deploy**.
3. Clique em **Run workflow**.
4. Escolha a branch `homolog`.
5. Selecione `environment=homolog`.
6. Marque `apply_infrastructure=false`; o EKS já foi aplicado e validado na seção 5.
7. Marque `deploy_addons=true`.
8. Mantenha `apply_observability=false` até validar os add-ons.
9. Aprove o environment solicitado.

O workflow valida `aws sts get-caller-identity`, configura o kubeconfig e instala versões fixas do Metrics Server e `nri-bundle`. Resultado esperado:

```powershell
kubectl get deployment metrics-server -n kube-system
kubectl get pods -n newrelic
kubectl top nodes
kubectl top pods -n oficina-homolog
kubectl get hpa -n oficina-homolog
```

- Metrics Server e pods New Relic: `Running/Ready`;
- `kubectl top`: CPU e memória preenchidas;
- HPA: métricas preenchidas, não `<unknown>`.

Se houver `CrashLoopBackOff` no namespace `newrelic`, confira a License key no GitHub Environment e reexecute o deploy. Não imprima o Secret.

## 29. Aplicar dashboards, alertas e monitor sintético

Primeiro execute um plan sem apply:

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3\observability\newrelic
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-newrelic-homolog'
terraform init -input=false
terraform plan -input=false -no-color
```

Confirme que o plan cria:

- dashboard com páginas Negócio, Aplicação, Kubernetes e Serverless/API Gateway;
- política de alertas;
- condições de healthcheck, erro, P95, falha de OS, integração, pod, reinício, CPU, memória, HPA, Lambda e ausência de telemetria;
- nenhum recurso AWS;
- nenhum monitor sintético enquanto `synthetic_monitor_enabled=false`.

Depois do backend publicar `$backendUrl`, não altere o workspace manualmente. Reexecute:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog -ConfigureNewRelic
```

O script grava `health_check_url` e `synthetic_monitor_enabled=true`. Volte ao diretório `observability\newrelic`, execute um novo `terraform plan` e confirme que o monitor sintético será criado com a URL `/actuator/health`. Somente após revisar e autorizar, faça apply pelo workflow **Deploy** do Kubernetes com `apply_observability=true`. Não use `-auto-approve`.

No New Relic, abra **All capabilities → Dashboards** e procure `oficina-homolog`. Em **Alerts & AI → Alert conditions**, confira as 12 condições e os limiares de homologação.

## 30. Validar APM, logs e eventos de negócio

Após o deploy do backend com `NEW_RELIC_ENABLED=true`, gere o fluxo completo da OS descrito nas seções 15 a 20. Em seguida:

1. Abra **APM & Services** e selecione `oficina-backend-homolog`.
2. Confira throughput, duração, P95, erros e traces.
3. Abra **Logs** e filtre:

```text
application = 'oficina-backend' AND environment = 'homolog'
```

4. Pesquise pelo `requestId` retornado no header `X-Request-Id`.
5. Confirme correlação com `trace.id`/`span.id` e ausência de CPF, JWT, senha e e-mail.
6. Abra o **Query builder** e execute:

```sql
SELECT count(*) FROM OrdemServicoCriada WHERE environment = 'homolog' SINCE 1 hour ago
SELECT count(*) FROM OrdemServicoStatusAlterado WHERE environment = 'homolog' FACET statusAnterior, novoStatus SINCE 1 hour ago
SELECT average(duracaoMilissegundos) / 1000 FROM OrdemServicoStatusAlterado WHERE environment = 'homolog' FACET statusAnterior SINCE 1 hour ago
SELECT count(*) FROM OrdemServicoProcessamentoFalhou WHERE environment = 'homolog' SINCE 1 hour ago
SELECT count(*) FROM IntegracaoExternaFalhou WHERE environment = 'homolog' SINCE 1 hour ago
```

Criação e transições devem aparecer depois do fluxo. Eventos de falha podem ficar zerados se nenhuma falha controlada ocorreu; não provoque indisponibilidade real apenas para produzir evidência.

## 31. Validar Lambda, Authorizer e API Gateway no New Relic

Não configure variáveis manualmente no workspace `oficina-auth-homolog`. Antes do plan da autenticação, execute:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog -ConfigureNewRelic
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-auth-homolog'
terraform init -input=false
terraform plan -input=false -no-color
```

O script descobre automaticamente a versão atual da layer oficial `NewRelicAgentJavaARM64-slim` em `us-west-2`, grava Account ID, License key e flags de instrumentação no workspace. Confirme no plan que as duas Lambdas continuam Java 21 ARM64, reutilizam `LabRole`, recebem as layers do New Relic e não criam IAM roles.

Depois do apply autorizado e dos testes de CPF/Authorizer:

- confira invocações, duração, erros e cold starts das funções `login` e `authorizer`;
- confira latência, integração, 4xx e 5xx do API Gateway;
- pesquise `requestId`, `traceId` e `spanId`;
- confirme que CPF, body, Authorization e JWT não aparecem.

## 32. Executar Newman — fluxo funcional e segurança

O caminho recomendado não exige arquivo local nem cópia de secrets:

1. abra o repositório backend no GitHub;
2. acesse **Actions → Validacao E2E → Run workflow**;
3. selecione a branch `homolog`;
4. escolha `environment=homolog`;
5. deixe `run_load_test=false` nesta primeira execução;
6. execute e aguarde o job `Postman/Newman (homolog)`;
7. baixe o artifact `newman-homolog-<run-id>` e confirme zero falhas.

O workflow recebe URLs e senha administrativa diretamente do GitHub Environment configurado pelo script central; nenhum token é impresso ou armazenado em arquivo local.

Para repetir localmente, use parâmetros explícitos e entrada de senha oculta:

```powershell
npm install --global newman@6.2.1 --ignore-scripts
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
. C:\fiap-secrets\oficina-homolog\environment-context.ps1
$adminSecure = Read-Host 'Digite APP_ADMIN_PASSWORD' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminSecure)
try { $adminPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
newman run .\tests\postman\oficina-weeks4-5.postman_collection.json `
  --env-var "backendBaseUrl=$backendUrl" `
  --env-var "apiGatewayBaseUrl=$apiBase" `
  --env-var "authBaseUrl=$apiBase" `
  --env-var 'adminEmail=admin@oficina.local' `
  --env-var "adminPassword=$adminPlain" `
  --reporters cli,junit `
  --reporter-junit-export .\target\newman-results.xml `
  --timeout-request 15000 `
  --bail
Remove-Variable adminPlain, adminSecure, pointer -ErrorAction SilentlyContinue
```

Resultado esperado: zero assertions com falha.

## 33. Executar k6 — carga controlada

Instale k6 e execute apenas em homologação, nunca durante outra turma usando o laboratório:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
$env:BACKEND_BASE_URL = $backendUrl
$env:API_GATEWAY_BASE_URL = $apiBase
$env:OWNER_TOKEN = $tokenOwner
$env:NUMERO_OS = $numeroOs
k6 run .\tests\k6\smoke-load.js
```

Resultado esperado:

- falhas HTTP abaixo de 1%;
- P95 geral abaixo de 1000 ms;
- P95 protegido abaixo de 1500 ms.

Se o ambiente estiver instável ou o saldo do Learner Lab estiver baixo, pare o teste. Não aumente usuários/duração para demonstrar escalabilidade.

## 34. Validar HPA

Durante o k6, em outro PowerShell:

```powershell
kubectl get hpa -n oficina-homolog --watch
kubectl get pods -n oficina-homolog -w
```

Confirme que métricas existem e que réplicas podem crescer até o máximo configurado. Após encerrar a carga, aguarde a redução. No New Relic, confira CPU, memória, desired/available replicas, HPA e reinícios.

Não force CPU artificialmente nem altere o máximo do HPA durante a validação.

## 35. Testes de segurança obrigatórios

Guarde resultados sanitizados de:

- CPF inválido: `401` genérico;
- JSON inválido: `400`;
- rota protegida sem token: `401/403`;
- JWT adulterado: `401/403`;
- cliente diferente consultando OS: `404`;
- request ID malicioso substituído por UUID seguro;
- logs sem CPF, token, senha, e-mail ou body;
- Secrets fora do Git e criados apenas durante deploy;
- RDS privado, SSL, criptografia e acesso somente pelos security groups autorizados;
- containers `runAsNonRoot`, filesystem somente leitura, sem privilege escalation e sem capabilities Linux.

Não coloque tokens ou dados sensíveis nos relatórios. Use apenas clientes sintéticos.

## 36. Rollback e troubleshooting

### Backend

```powershell
kubectl rollout history deployment/oficina-app -n oficina-homolog
kubectl rollout undo deployment/oficina-app -n oficina-homolog
kubectl rollout status deployment/oficina-app -n oficina-homolog --timeout=180s
```

### Add-ons

```powershell
helm history newrelic-bundle -n newrelic
[int]$newRelicRevision = Read-Host 'Digite a revisão anterior do newrelic-bundle'
if ($newRelicRevision -le 0) { throw 'Revisão inválida.' }
helm rollback newrelic-bundle $newRelicRevision -n newrelic --wait

helm history metrics-server -n kube-system
[int]$metricsRevision = Read-Host 'Digite a revisão anterior do metrics-server'
if ($metricsRevision -le 0) { throw 'Revisão inválida.' }
helm rollback metrics-server $metricsRevision -n kube-system --wait
```

### Observabilidade

Desative a instrumentação e os monitores pelo script, sem editar HCP/GitHub:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog -DisableObservability
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3\observability\newrelic
$env:TF_WORKSPACE = 'oficina-newrelic-homolog'
terraform init -input=false
terraform plan -input=false -no-color
```

Revise o plan. Se ele contiver somente a desativação esperada, execute `terraform apply`, revise novamente e digite `yes`. O script mantém as chaves armazenadas com segurança para uma futura reativação; ele apenas desliga as flags. Não apague dashboards à mão se eles são gerenciados pelo Terraform.

### Erros frequentes

| Erro | Ação |
|---|---|
| `ExpiredToken` | reinicie o Learner Lab e atualize as três credenciais juntas no executor correto |
| `kubectl Unauthorized` | valide STS e execute novamente `aws eks update-kubeconfig` |
| HPA `<unknown>` | valide Metrics Server e `resources.requests` do Deployment |
| sem dados Kubernetes | confira cluster name, namespace `oficina-homolog` e pods do `nri-bundle` |
| sem APM | confira License key, `NEW_RELIC_ENABLED`, app name e logs do agente |
| logs duplicados | mantenha forwarding do agente Java desativado; use o coletor Kubernetes |
| sem eventos de negócio | confira `OFICINA_OBSERVABILITY_NEW_RELIC_ENABLED=true` e faça uma nova transição de OS |
| Lambda sem telemetria | confira layers ARM64, License key e variáveis New Relic |
| dashboard vazio | confira nomes exatos da aplicação, cluster, namespace, Lambdas e API Gateway |

## 37. Limpeza e controle de custo

Depois de coletar as evidências, abra um PowerShell novo. Os comandos abaixo são para homologação; para produção substitua `homolog` por `production` somente depois de confirmar o ambiente.

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\scripts\configure-environment.ps1 -Environment homolog
. C:\fiap-secrets\oficina-homolog\environment-context.ps1
aws sts get-caller-identity
```

Não continue se o STS falhar ou se a conta retornada não for a conta atual do Learner Lab.

### 37.1 Destruir autenticação/API Gateway

```powershell
Set-Location C:\fiap-fase3\oficina-auth-serverless-fiap-fase3
$env:TF_CLOUD_ORGANIZATION = 'oficina-fiap-soat-fase-2'
$env:TF_WORKSPACE = 'oficina-auth-homolog'
terraform init -input=false
terraform plan -destroy -input=false -no-color
terraform destroy
```

Revise o plan e digite `yes`. Confirme que Lambdas e API Gateway foram removidos.

### 37.2 Destruir observabilidade gerenciada pelo Terraform

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3\observability\newrelic
$env:TF_WORKSPACE = 'oficina-newrelic-homolog'
terraform init -input=false
terraform plan -destroy -input=false -no-color
terraform destroy
```

Isso remove dashboards, alertas e monitor sintético; não remove o EKS.

### 37.3 Remover backend e add-ons antes do EKS

```powershell
aws eks update-kubeconfig --region us-west-2 --name oficina-homolog
kubectl delete namespace oficina-homolog --wait=true --timeout=300s
helm uninstall newrelic-bundle -n newrelic --wait
helm uninstall metrics-server -n kube-system --wait
kubectl delete namespace newrelic --wait=true --timeout=180s
kubectl get service --all-namespaces
```

Aceite `not found` somente quando o recurso já estiver ausente. Não prossiga enquanto existir um Service `LoadBalancer` da aplicação.

### 37.4 Destruir RDS

```powershell
Set-Location C:\fiap-fase3\oficina-database-infra-fiap-fase3
$env:TF_WORKSPACE = 'oficina-database-homolog'
terraform init -input=false
terraform plan -destroy -input=false -no-color
terraform destroy
```

Revise e digite `yes`. Aguarde até o RDS desaparecer do console AWS.

### 37.5 Destruir EKS e rede por último

```powershell
Set-Location C:\fiap-fase3\oficina-kubernetes-infra-fiap-fase3
$env:TF_WORKSPACE = 'oficina-kubernetes-homolog'
terraform init -input=false
terraform plan -destroy -input=false -no-color
terraform destroy
terraform state list
```

O último comando deve ficar vazio. Confirme no console AWS que EKS, node group, NAT Gateway, LoadBalancer, subnets e VPC foram removidos. Não use `-auto-approve` em nenhuma etapa.

## 38. Checklist de evidências e critérios do trabalho

### Arquitetura e entrega

- [ ] quatro repositórios separados, sem monorepo;
- [ ] branches `homolog` validadas antes de `main`;
- [ ] diagramas da arquitetura, observabilidade e modelo ER;
- [ ] HCP Terraform com estados e workspaces separados;
- [ ] CI em PR/push e deploy com aprovação explícita;
- [ ] AWS Academy/LabRole sem criação de IAM role.

### Funcionalidade e segurança

- [ ] autenticação por CPF e JWT RSA;
- [ ] Authorizer e isolamento por proprietário;
- [ ] fluxo completo da OS e histórico;
- [ ] testes de token ausente, inválido e adulterado;
- [ ] logs sem PII/segredos;
- [ ] RDS privado, criptografado e com SSL.

### Escalabilidade e observabilidade

- [ ] EKS 1.34, Metrics Server e HPA;
- [ ] APM do backend;
- [ ] telemetria Lambda/API Gateway;
- [ ] logs JSON correlacionados;
- [ ] eventos de negócio;
- [ ] dashboards de negócio, aplicação, Kubernetes e serverless;
- [ ] alertas configuráveis por ambiente;
- [ ] logs PostgreSQL no CloudWatch;
- [ ] Newman e k6 aprovados.

### Evidências proibidas

- [ ] nenhum print das credenciais do AWS Academy;
- [ ] nenhum secret do GitHub/HCP/Kubernetes exposto;
- [ ] nenhum CPF, JWT, senha ou chave privada;
- [ ] nenhum `.tfstate`, `.env` ou `.pem` versionado.

## 39. Roteiro do vídeo a ser gravado pelo usuário

O usuário grava o vídeo somente depois da validação geral. Sequência recomendada:

1. apresentar os quatro repositórios e a arquitetura distribuída;
2. mostrar CI aprovado e branches `homolog`;
3. mostrar workspaces HCP separados e Auto apply desativado, sem abrir variáveis sensíveis;
4. mostrar EKS 1.34, nodes, pods, Services e HPA;
5. mostrar RDS privado e logs exportados, ocultando endpoint e credenciais se necessário;
6. executar healthcheck;
7. demonstrar login administrativo e criação dos dados sintéticos;
8. autenticar cliente por CPF sem exibir o CPF completo ou token;
9. demonstrar Authorizer, isolamento e fluxo da OS;
10. mostrar histórico;
11. mostrar APM, logs correlacionados e eventos;
12. mostrar as quatro páginas do dashboard e alertas;
13. mostrar Metrics Server/HPA e resumo do k6;
14. mostrar resumo do Newman e dos testes de segurança;
15. finalizar com rollback, limpeza e critérios atendidos.

Antes de gravar, feche telas de secrets, limpe clipboard e terminal, e use tarjas quando qualquer identificador sensível puder aparecer.

## 40. Estrutura recomendada do PDF final

1. Capa e identificação do grupo;
2. objetivo e contexto de expansão da oficina;
3. arquitetura geral e justificativa dos quatro repositórios;
4. segurança e autenticação;
5. infraestrutura AWS/EKS/RDS e HCP Terraform;
6. CI/CD e estratégia de ambientes;
7. observabilidade New Relic;
8. modelo ER, constraints e índices;
9. execução funcional e fluxo da OS;
10. testes unitários, integração, segurança, Newman e k6;
11. escalabilidade/HPA;
12. dashboards, alertas e evidências;
13. custo, rollback e limpeza;
14. ADRs/RFCs e decisões arquiteturais;
15. conclusão e aderência aos critérios;
16. anexos com links dos repositórios, PRs, pipelines e vídeo.

Use prints sanitizados, legíveis e numerados. Cada evidência deve informar o critério comprovado, o ambiente, a data e o resultado esperado.
