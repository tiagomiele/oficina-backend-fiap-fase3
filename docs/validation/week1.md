# Validação da Semana 1

Este guia valida os artefatos de arquitetura e governança entregues na Semana 1 da Fase 3.

## 1. Escopo validado

A Semana 1 entrega:

- quatro repositórios independentes;
- responsabilidades e limites documentados;
- READMEs concisos e documentação detalhada em `/docs`;
- contrato OpenAPI inicial da autenticação por CPF;
- RFCs, ADRs, diagramas e roadmap;
- estratégia para AWS Academy e New Relic;
- workflows iniciais de CI e detecção de segredos.

Ainda não fazem parte desta etapa:

- Lambda de autenticação;
- API Gateway e Lambda Authorizer;
- endpoint funcional `POST /auth/cpf`;
- Terraform do EKS ou RDS;
- recursos provisionados na AWS;
- integração ativa com New Relic;
- histórico de status da Ordem de Serviço.

A separação física do Terraform legado da Fase 2 será realizada na Semana 2. Nesta etapa foram definidos os limites e criados os repositórios de destino; os arquivos antigos em `oficina-backend-fiap-fase3/infra` não devem receber evoluções da Fase 3.

> O Swagger local em `http://localhost:8080/swagger-ui/index.html` documenta apenas a aplicação Spring Boot. O `POST /auth/cpf` está definido como contrato, mas será implementado no serviço serverless e exposto pelo API Gateway na Semana 3.

## 2. Pré-requisitos

Para a validação completa, utilize:

- Git;
- acesso aos quatro repositórios privados no GitHub;
- PowerShell 7 ou Windows PowerShell;
- Java 21 para a validação opcional da aplicação;
- Docker Desktop para o smoke test opcional;
- Python 3 com PyYAML para validar os arquivos YAML.

Instale somente o validador YAML, se necessário:

```powershell
py -m pip install pyyaml
```

## 3. Conferir os Pull Requests e o CI

Abra os quatro Pull Requests:

1. [Aplicação principal](https://github.com/tiagomiele/oficina-backend-fiap-fase3/pull/1)
2. [Autenticação serverless](https://github.com/tiagomiele/oficina-auth-serverless-fiap-fase3/pull/1)
3. [Infraestrutura Kubernetes](https://github.com/tiagomiele/oficina-kubernetes-infra-fiap-fase3/pull/1)
4. [Infraestrutura do banco](https://github.com/tiagomiele/oficina-database-infra-fiap-fase3/pull/1)

Resultado esperado:

- os quatro PRs estão sem conflitos;
- a aplicação possui três checks aprovados: build/testes/cobertura, SBOM e Trivy;
- cada novo repositório possui o check `Repository validation` aprovado;
- não existem checks com falha ou pendentes.

Com GitHub CLI, a mesma conferência pode ser feita com:

```powershell
gh pr checks 1 --repo tiagomiele/oficina-backend-fiap-fase3
gh pr checks 1 --repo tiagomiele/oficina-auth-serverless-fiap-fase3
gh pr checks 1 --repo tiagomiele/oficina-kubernetes-infra-fiap-fase3
gh pr checks 1 --repo tiagomiele/oficina-database-infra-fiap-fase3
```

## 4. Preparar os repositórios localmente

Crie uma pasta de trabalho:

```powershell
New-Item -ItemType Directory -Force C:\fiap-fase3
Set-Location C:\fiap-fase3
```

Clone os quatro repositórios, caso ainda não estejam no computador:

```powershell
git clone https://github.com/tiagomiele/oficina-backend-fiap-fase3.git
git clone https://github.com/tiagomiele/oficina-auth-serverless-fiap-fase3.git
git clone https://github.com/tiagomiele/oficina-kubernetes-infra-fiap-fase3.git
git clone https://github.com/tiagomiele/oficina-database-infra-fiap-fase3.git
```

### Antes do merge dos PRs

Use as branches dos Pull Requests:

```powershell
git -C .\oficina-backend-fiap-fase3 fetch origin devin/1786058029-week1-architecture
git -C .\oficina-backend-fiap-fase3 switch devin/1786058029-week1-architecture

$reposNovos = @(
  'oficina-auth-serverless-fiap-fase3',
  'oficina-kubernetes-infra-fiap-fase3',
  'oficina-database-infra-fiap-fase3'
)

foreach ($repo in $reposNovos) {
  git -C ".\$repo" fetch origin devin/1786058915-week1-foundation
  git -C ".\$repo" switch devin/1786058915-week1-foundation
}
```

### Depois do merge dos PRs

Use a `main` atualizada:

```powershell
$repos = @(
  'oficina-backend-fiap-fase3',
  'oficina-auth-serverless-fiap-fase3',
  'oficina-kubernetes-infra-fiap-fase3',
  'oficina-database-infra-fiap-fase3'
)

foreach ($repo in $repos) {
  git -C ".\$repo" switch main
  git -C ".\$repo" pull --ff-only
}
```

## 5. Confirmar que não existe monorepo

Execute:

```powershell
$repos = @(
  'oficina-backend-fiap-fase3',
  'oficina-auth-serverless-fiap-fase3',
  'oficina-kubernetes-infra-fiap-fase3',
  'oficina-database-infra-fiap-fase3'
)

foreach ($repo in $repos) {
  git -C ".\$repo" rev-parse --show-toplevel
  git -C ".\$repo" remote get-url origin
}
```

Resultado esperado:

- quatro diretórios raiz diferentes;
- quatro origens GitHub diferentes;
- cada repositório possui seu próprio diretório `.git`;
- os novos repositórios de infraestrutura não contêm código da aplicação;
- o diretório legado `infra` da aplicação está identificado para migração na Semana 2, e não como infraestrutura definitiva da Fase 3.

## 6. Validar os arquivos obrigatórios

Na pasta `C:\fiap-fase3`, execute:

```powershell
$requiredFiles = @(
  'oficina-backend-fiap-fase3\README.md',
  'oficina-backend-fiap-fase3\docs\README.md',
  'oficina-backend-fiap-fase3\docs\architecture\overview.md',
  'oficina-backend-fiap-fase3\docs\architecture\repository-boundaries.md',
  'oficina-backend-fiap-fase3\docs\architecture\authentication-flow.md',
  'oficina-backend-fiap-fase3\docs\architecture\observability-new-relic.md',
  'oficina-backend-fiap-fase3\docs\architecture\database-evolution.md',
  'oficina-backend-fiap-fase3\docs\contracts\authentication-api.yaml',
  'oficina-backend-fiap-fase3\docs\decisions\rfc\0001-aws-academy-and-environments.md',
  'oficina-backend-fiap-fase3\docs\decisions\rfc\0002-cpf-authentication.md',
  'oficina-backend-fiap-fase3\docs\decisions\adr\0001-four-repositories.md',
  'oficina-backend-fiap-fase3\docs\decisions\adr\0002-new-relic.md',
  'oficina-backend-fiap-fase3\docs\decisions\adr\0003-jwt-signing.md',
  'oficina-backend-fiap-fase3\docs\roadmap\phase3.md',
  'oficina-backend-fiap-fase3\docs\validation\week1.md',
  'oficina-auth-serverless-fiap-fase3\docs\architecture.md',
  'oficina-auth-serverless-fiap-fase3\docs\security.md',
  'oficina-auth-serverless-fiap-fase3\docs\deployment.md',
  'oficina-auth-serverless-fiap-fase3\.github\workflows\ci.yml',
  'oficina-kubernetes-infra-fiap-fase3\docs\architecture.md',
  'oficina-kubernetes-infra-fiap-fase3\docs\aws-academy.md',
  'oficina-kubernetes-infra-fiap-fase3\docs\new-relic.md',
  'oficina-kubernetes-infra-fiap-fase3\.github\workflows\ci.yml',
  'oficina-database-infra-fiap-fase3\docs\architecture.md',
  'oficina-database-infra-fiap-fase3\docs\aws-academy.md',
  'oficina-database-infra-fiap-fase3\docs\data-model.md',
  'oficina-database-infra-fiap-fase3\.github\workflows\ci.yml'
)

$missingFiles = $requiredFiles | Where-Object { -not (Test-Path $_) }

if ($missingFiles) {
  $missingFiles
  throw 'Existem arquivos obrigatórios ausentes.'
}

Write-Host 'Arquivos obrigatórios encontrados.'
```

## 7. Validar YAML e o contrato de autenticação

Execute na pasta `C:\fiap-fase3`:

```powershell
@'
from pathlib import Path
import yaml

root = Path.cwd()
files = [
    root / 'oficina-backend-fiap-fase3/.github/workflows/ci.yml',
    root / 'oficina-backend-fiap-fase3/docs/contracts/authentication-api.yaml',
    root / 'oficina-auth-serverless-fiap-fase3/.github/workflows/ci.yml',
    root / 'oficina-kubernetes-infra-fiap-fase3/.github/workflows/ci.yml',
    root / 'oficina-database-infra-fiap-fase3/.github/workflows/ci.yml',
]

for file in files:
    with file.open(encoding='utf-8') as stream:
        yaml.safe_load(stream)

contract = yaml.safe_load(
    (root / 'oficina-backend-fiap-fase3/docs/contracts/authentication-api.yaml')
    .read_text(encoding='utf-8')
)

assert contract['openapi'] == '3.0.3'
assert '/auth/cpf' in contract['paths']
assert 'post' in contract['paths']['/auth/cpf']
assert contract['paths']['/auth/cpf']['post']['requestBody']['required'] is True
assert '200' in contract['paths']['/auth/cpf']['post']['responses']
assert '401' in contract['paths']['/auth/cpf']['post']['responses']

print('Workflows e contrato OpenAPI válidos.')
'@ | py -
```

Resultado esperado:

```text
Workflows e contrato OpenAPI válidos.
```

Essa validação confirma o contrato; ela não chama um endpoint funcional.

## 8. Validar os links locais da nova documentação

Execute:

```powershell
@'
from pathlib import Path
import re

root = Path.cwd()
backend = root / 'oficina-backend-fiap-fase3'
files = [backend / 'README.md', backend / 'docs/README.md']
for directory in ('architecture', 'decisions', 'roadmap', 'validation'):
    files.extend((backend / 'docs' / directory).rglob('*.md'))

for name in (
    'oficina-auth-serverless-fiap-fase3',
    'oficina-kubernetes-infra-fiap-fase3',
    'oficina-database-infra-fiap-fase3',
):
    files.extend((root / name).rglob('*.md'))

errors = []
for file in files:
    text = file.read_text(encoding='utf-8')
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', text):
        if target.startswith(('http://', 'https://', '#', 'mailto:')):
            continue
        path = target.split('#', 1)[0]
        if path and not (file.parent / path).resolve().exists():
            errors.append(f'{file.relative_to(root)} -> {target}')

if errors:
    print('\n'.join(errors))
    raise SystemExit('Foram encontrados links locais inválidos.')

print('Links locais válidos.')
'@ | py -
```

Resultado esperado:

```text
Links locais válidos.
```

## 9. Validar a aplicação principal

O CI já executa a validação completa. A repetição local é opcional para uma revisão exclusivamente documental.

Confirme o Java:

```powershell
java -version
```

A versão principal deve ser 21. Para executar a validação completa:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
.\mvnw.cmd -B verify
```

Resultado esperado:

- build concluído com sucesso;
- 120 testes aprovados;
- ArchUnit aprovado;
- gate de cobertura JaCoCo aprovado;
- JAR gerado em `target`.

### Spotless

O baseline importado da Fase 2 possui arquivos Java anteriores fora do padrão do Spotless. Como a Semana 1 não altera arquivos Java, essa pendência deve ser tratada separadamente e não invalida os artefatos documentais desta etapa.

## 10. Validar os workflows dos novos repositórios

### Autenticação serverless

O workflow deve:

- confirmar a presença do README e dos documentos de arquitetura, segurança e deploy;
- executar Gitleaks com histórico completo;
- possuir permissões somente de leitura.

### Kubernetes e banco

Os workflows devem:

- confirmar a documentação obrigatória;
- instalar Terraform com `hashicorp/setup-terraform`;
- executar `terraform fmt -check -recursive` quando existirem arquivos `.tf`;
- informar que o Terraform será incluído na Semana 2 quando não houver arquivos `.tf`;
- executar Gitleaks com histórico completo.

A aprovação do check `Repository validation` nos três PRs confirma essa etapa.

## 11. Validar que segredos e states não foram versionados

Na pasta `C:\fiap-fase3`, execute:

```powershell
$repos = @(
  'oficina-backend-fiap-fase3',
  'oficina-auth-serverless-fiap-fase3',
  'oficina-kubernetes-infra-fiap-fase3',
  'oficina-database-infra-fiap-fase3'
)

foreach ($repo in $repos) {
  $forbidden = git -C ".\$repo" ls-files | Where-Object {
    $_ -match '(^|/)\.env$|\.tfstate($|\.)|(^|/)credentials\.json$'
  }

  if ($forbidden) {
    Write-Host "Arquivos proibidos em $repo"
    $forbidden
    throw 'Arquivo sensível versionado.'
  }
}

Write-Host 'Nenhum arquivo de configuração sensível ou state foi versionado.'
```

Também confirme que o Gitleaks está aprovado nos PRs dos três novos repositórios.

O arquivo `.terraform.lock.hcl` não deve ser ignorado: ele deverá ser versionado quando os providers Terraform forem inicializados.

## 12. Validar a governança dos repositórios

Para cada repositório, acesse **Settings → Rules → Rulesets** ou **Settings → Branches** e confirme:

- Pull Request obrigatório para a `main`;
- ao menos uma aprovação antes do merge;
- checks de CI obrigatórios;
- branch atualizada antes do merge;
- proibição de force push e exclusão da `main`;
- administradores incluídos nas regras, quando permitido.

Confirme também a existência das branches:

- `main`;
- `homolog`.

> A proteção de branches e a criação de `homolog` são configurações administrativas do GitHub, não são criadas pelos arquivos dos PRs. Se estiverem ausentes, registre-as como pendência antes de iniciar a Semana 2.

## 13. Smoke test opcional da aplicação existente

A Semana 1 não altera o comportamento da aplicação. Se for necessário comprovar que a base da Fase 2 continua executando:

```powershell
Set-Location C:\fiap-fase3\oficina-backend-fiap-fase3
docker compose up --build -d
```

Valide:

```powershell
Invoke-RestMethod http://localhost:8080/actuator/health
Start-Process http://localhost:8080/swagger-ui/index.html
```

Resultado esperado:

- healthcheck com estado `UP`;
- Swagger da aplicação principal acessível;
- APIs existentes da Fase 2 documentadas;
- `POST /auth/cpf` ainda ausente, pois será implementado no serviço serverless.

Finalize:

```powershell
docker compose down
```

## 14. Critérios de aceite da Semana 1

A etapa pode ser aceita quando:

- [ ] os quatro PRs foram revisados e aprovados;
- [ ] todos os checks de CI estão aprovados;
- [ ] os quatro repositórios são independentes;
- [ ] os READMEs são concisos e apontam para `/docs`;
- [ ] arquitetura, limites, autenticação, banco e New Relic estão documentados;
- [ ] o contrato `POST /auth/cpf` é um OpenAPI válido;
- [ ] RFCs, ADRs e roadmap estão versionados;
- [ ] nenhum segredo, `.env` real ou Terraform state foi versionado;
- [ ] `.terraform.lock.hcl` poderá ser versionado;
- [ ] proteção da `main` e branch `homolog` foram confirmadas manualmente;
- [ ] não houve provisionamento antecipado de recursos da Semana 2.

## 15. Evidências recomendadas

Registre capturas ou exportações de:

1. cada PR aberto e sem conflitos;
2. checks aprovados nos quatro repositórios;
3. estrutura de arquivos de cada repositório;
4. contrato OpenAPI contendo `POST /auth/cpf`;
5. RFCs e ADRs no GitHub;
6. regras de proteção da `main`;
7. branch `homolog` de cada repositório;
8. resultado dos scripts locais de validação.
