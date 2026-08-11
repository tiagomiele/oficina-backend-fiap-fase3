[CmdletBinding()]
param(
    [ValidateSet('homolog', 'production')]
    [string]$Environment = 'homolog',
    [string]$RepositoriesRoot,
    [string]$TerraformOrganization = 'oficina-fiap-soat-fase-2',
    [string]$AwsCredentialsFile,
    [string]$SecretsRoot,
    [switch]$ConfigureNewRelic,
    [switch]$SkipGitHub,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryNames = @{
    Kubernetes = 'oficina-kubernetes-infra-fiap-fase3'
    Database   = 'oficina-database-infra-fiap-fase3'
    Backend    = 'oficina-backend-fiap-fase3'
    Auth       = 'oficina-auth-serverless-fiap-fase3'
}
$GitHubOwner = 'tiagomiele'
$WorkspaceNames = @{
    Kubernetes = @{
        homolog    = 'oficina-kubernetes-homolog'
        production = 'oficina-kubernetes-production'
    }
    Database = @{
        homolog    = 'oficina-database-homolog'
        production = 'oficina-database-production'
    }
    Auth = @{
        homolog    = 'oficina-auth-homolog'
        production = 'oficina-auth-production'
    }
    NewRelic = @{
        homolog    = 'oficina-newrelic-homolog'
        production = 'oficina-newrelic-production'
    }
}

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatório não encontrado: $Name"
    }
}

function Resolve-OpenSslCommand {
    $command = Get-Command openssl -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $git) {
        $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
        $bundledOpenSsl = Join-Path $gitRoot 'usr\bin\openssl.exe'
        if (Test-Path $bundledOpenSsl) {
            return $bundledOpenSsl
        }
    }

    throw 'OpenSSL não encontrado no PATH nem na instalação do Git for Windows.'
}

function ConvertFrom-SecureText {
    param([Parameter(Mandatory)][Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-SecretText {
    param([Parameter(Mandatory)][string]$Prompt)

    ConvertFrom-SecureText (Read-Host $Prompt -AsSecureString)
}

function New-RandomSecret {
    $bytes = New-Object byte[] 36
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
    }
    finally {
        $random.Dispose()
    }

    ([Convert]::ToBase64String($bytes).TrimEnd('=') -replace '[+/]', 'A') + '!a9'
}

function Get-StoredValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Prompt
    )

    if (Test-Path $Path) {
        return (Get-Content $Path -Raw).Trim()
    }

    $value = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Prompt não foi informado."
    }
    New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
    Set-Content -Path $Path -Value $value -Encoding UTF8
    $value
}

function Get-StoredSecret {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$GenerateWhenEmpty,
        [string]$Directory = $script:SecretsDirectory
    )

    New-Item -ItemType Directory -Force $Directory | Out-Null
    $path = Join-Path $Directory "$Name.clixml"
    if (Test-Path $path) {
        return ConvertFrom-SecureText (Import-Clixml $path)
    }

    $promptText = $Prompt
    if ($GenerateWhenEmpty) {
        $promptText = "$Prompt (Enter vazio para gerar uma nova)"
    }
    $value = Read-SecretText $promptText
    if ([string]::IsNullOrWhiteSpace($value)) {
        if (-not $GenerateWhenEmpty) {
            throw "$Name não foi informado."
        }
        $value = New-RandomSecret
    }

    ConvertTo-SecureString $value -AsPlainText -Force | Export-Clixml $path
    $value
}

function Get-TerraformToken {
    if (-not [string]::IsNullOrWhiteSpace($env:TFC_TOKEN)) {
        return $env:TFC_TOKEN
    }

    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $paths += Join-Path $env:APPDATA 'terraform.d\credentials.tfrc.json'
    }
    $paths += Join-Path $HOME '.terraform.d/credentials.tfrc.json'

    foreach ($path in $paths | Select-Object -Unique) {
        if (-not (Test-Path $path)) {
            continue
        }

        $credentials = Get-Content $path -Raw | ConvertFrom-Json
        $hostCredentials = $credentials.credentials.'app.terraform.io'
        if ($null -ne $hostCredentials -and -not [string]::IsNullOrWhiteSpace($hostCredentials.token)) {
            return $hostCredentials.token
        }
    }

    throw 'Token do HCP Terraform não encontrado. Execute terraform login uma única vez.'
}

function Invoke-HcpApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )

    $parameters = @{
        Method      = $Method
        Uri         = "https://app.terraform.io/api/v2/$Path"
        Headers     = $script:HcpHeaders
        ContentType = 'application/vnd.api+json'
    }
    if ($null -ne $Body) {
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    Invoke-RestMethod @parameters
}

function Get-HcpWorkspace {
    param([Parameter(Mandatory)][string]$Name)

    (Invoke-HcpApi -Method GET -Path "organizations/$TerraformOrganization/workspaces/$Name").data
}

function Get-HcpWorkspaceVariables {
    param([Parameter(Mandatory)][string]$WorkspaceId)

    @((Invoke-HcpApi -Method GET -Path "workspaces/$WorkspaceId/vars?page%5Bsize%5D=100").data)
}

function Set-HcpWorkspaceVariable {
    param(
        [Parameter(Mandatory)][object]$Workspace,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('terraform', 'env')][string]$Category = 'terraform',
        [bool]$Hcl = $false,
        [bool]$Sensitive = $false,
        [string]$Description = 'Gerenciada por scripts/configure-environment.ps1'
    )

    $variables = Get-HcpWorkspaceVariables $Workspace.id
    $matchingVariables = @($variables | Where-Object {
        $_.attributes.key -eq $Key -and $_.attributes.category -eq $Category
    })
    $existing = $matchingVariables | Select-Object -First 1

    $payload = @{
        data = @{
            type       = 'vars'
            attributes = @{
                key         = $Key
                value       = $Value
                description = $Description
                category    = $Category
                hcl         = $Hcl
                sensitive   = $Sensitive
            }
        }
    }

    if ($null -eq $existing) {
        Invoke-HcpApi -Method POST -Path "workspaces/$($Workspace.id)/vars" -Body $payload | Out-Null
    }
    else {
        $payload.data.id = $existing.id
        Invoke-HcpApi -Method PATCH -Path "workspaces/$($Workspace.id)/vars/$($existing.id)" -Body $payload | Out-Null
        foreach ($duplicateVariable in $matchingVariables | Select-Object -Skip 1) {
            Invoke-HcpApi -Method DELETE -Path "workspaces/$($Workspace.id)/vars/$($duplicateVariable.id)" | Out-Null
        }
    }
}

function Remove-HcpWorkspaceVariable {
    param(
        [Parameter(Mandatory)][object]$Workspace,
        [Parameter(Mandatory)][string]$Key,
        [ValidateSet('terraform', 'env')][string]$Category = 'terraform'
    )

    $variables = Get-HcpWorkspaceVariables $Workspace.id
    foreach ($variable in $variables | Where-Object {
        $_.attributes.key -eq $Key -and $_.attributes.category -eq $Category
    }) {
        Invoke-HcpApi -Method DELETE -Path "workspaces/$($Workspace.id)/vars/$($variable.id)" | Out-Null
    }
}

function Set-HcpVariableSetVariables {
    param(
        [Parameter(Mandatory)][string]$VariableSetId,
        [Parameter(Mandatory)][object[]]$Definitions
    )

    $existingVariables = @((Invoke-HcpApi -Method GET -Path "varsets/$VariableSetId/relationships/vars").data)
    foreach ($definition in $Definitions) {
        $matchingVariables = @($existingVariables | Where-Object {
            $_.attributes.key -eq $definition.attributes.key -and $_.attributes.category -eq $definition.attributes.category
        })
        $payload = @{ data = $definition }
        if ($matchingVariables.Count -eq 0) {
            Invoke-HcpApi -Method POST -Path "varsets/$VariableSetId/relationships/vars" -Body $payload | Out-Null
            continue
        }

        $primaryVariable = $matchingVariables[0]
        $payload.data.id = $primaryVariable.id
        Invoke-HcpApi -Method PATCH -Path "varsets/$VariableSetId/relationships/vars/$($primaryVariable.id)" -Body $payload | Out-Null
        foreach ($duplicateVariable in $matchingVariables | Select-Object -Skip 1) {
            Invoke-HcpApi -Method DELETE -Path "varsets/$VariableSetId/relationships/vars/$($duplicateVariable.id)" | Out-Null
        }
    }
}

function Set-AwsVariableSet {
    param(
        [Parameter(Mandatory)][object[]]$Workspaces,
        [Parameter(Mandatory)][hashtable]$Credentials
    )

    $name = 'aws-academy-credentials'
    $existingSets = @((Invoke-HcpApi -Method GET -Path "organizations/$TerraformOrganization/varsets?page%5Bsize%5D=100").data)
    $matchingSets = @($existingSets | Where-Object { $_.attributes.name -eq $name })

    $workspaceRelationships = @($Workspaces | ForEach-Object {
        @{ type = 'workspaces'; id = $_.id }
    })
    $variables = @(
        @{
            type       = 'vars'
            attributes = @{
                key       = 'AWS_ACCESS_KEY_ID'
                value     = $Credentials.AWS_ACCESS_KEY_ID
                category  = 'env'
                hcl       = $false
                sensitive = $true
            }
        },
        @{
            type       = 'vars'
            attributes = @{
                key       = 'AWS_SECRET_ACCESS_KEY'
                value     = $Credentials.AWS_SECRET_ACCESS_KEY
                category  = 'env'
                hcl       = $false
                sensitive = $true
            }
        },
        @{
            type       = 'vars'
            attributes = @{
                key       = 'AWS_SESSION_TOKEN'
                value     = $Credentials.AWS_SESSION_TOKEN
                category  = 'env'
                hcl       = $false
                sensitive = $true
            }
        }
    )

    $payload = @{
        data = @{
            type          = 'varsets'
            attributes    = @{
                name        = $name
                description = 'Credenciais temporárias compartilhadas do AWS Academy. Gerenciado pelo script central.'
                global      = $false
                priority    = $false
            }
            relationships = @{
                workspaces = @{ data = $workspaceRelationships }
                vars       = @{ data = $variables }
            }
        }
    }

    if ($matchingSets.Count -eq 0) {
        $payload.data.relationships.parent = @{
            data = @{
                type = 'organizations'
                id   = $TerraformOrganization
            }
        }
        Invoke-HcpApi -Method POST -Path "organizations/$TerraformOrganization/varsets" -Body $payload | Out-Null
        return
    }

    $primarySet = $matchingSets[0]
    $payload.data.id = $primarySet.id
    $payload.data.relationships.Remove('vars')
    Invoke-HcpApi -Method PATCH -Path "varsets/$($primarySet.id)" -Body $payload | Out-Null
    Set-HcpVariableSetVariables -VariableSetId $primarySet.id -Definitions $variables
    foreach ($duplicateSet in $matchingSets | Select-Object -Skip 1) {
        Invoke-HcpApi -Method DELETE -Path "varsets/$($duplicateSet.id)" | Out-Null
    }
}

function Parse-AwsCredentials {
    param([Parameter(Mandatory)][string]$Content)

    $result = @{}
    foreach ($line in $Content -split "`r?`n") {
        if ($line -match '^\s*(aws_access_key_id|aws_secret_access_key|aws_session_token)\s*=\s*(.+?)\s*$') {
            $result[$matches[1].ToUpperInvariant()] = $matches[2]
        }
    }

    if ($result.Count -ne 3) {
        return $null
    }

    $result
}

function Get-AwsCredentials {
    $content = $null
    if (-not [string]::IsNullOrWhiteSpace($AwsCredentialsFile)) {
        if (-not (Test-Path $AwsCredentialsFile)) {
            throw "Arquivo de credenciais não encontrado: $AwsCredentialsFile"
        }
        $content = Get-Content $AwsCredentialsFile -Raw
    }
    else {
        try {
            $content = Get-Clipboard -Raw -ErrorAction Stop
        }
        catch {
            $content = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($content)) {
        $parsed = Parse-AwsCredentials $content
        if ($null -ne $parsed) {
            return $parsed
        }
    }

    @{
        AWS_ACCESS_KEY_ID     = Read-Host 'AWS_ACCESS_KEY_ID'
        AWS_SECRET_ACCESS_KEY = Read-SecretText 'AWS_SECRET_ACCESS_KEY'
        AWS_SESSION_TOKEN     = Read-SecretText 'AWS_SESSION_TOKEN'
    }
}

function Set-LocalAwsCredentials {
    param([Parameter(Mandatory)][hashtable]$Credentials)

    $env:AWS_ACCESS_KEY_ID = $Credentials.AWS_ACCESS_KEY_ID
    $env:AWS_SECRET_ACCESS_KEY = $Credentials.AWS_SECRET_ACCESS_KEY
    $env:AWS_SESSION_TOKEN = $Credentials.AWS_SESSION_TOKEN
    $env:AWS_DEFAULT_REGION = 'us-west-2'

    if (-not $ValidateOnly) {
        & aws configure set aws_access_key_id $Credentials.AWS_ACCESS_KEY_ID | Out-Null
        & aws configure set aws_secret_access_key $Credentials.AWS_SECRET_ACCESS_KEY | Out-Null
        & aws configure set aws_session_token $Credentials.AWS_SESSION_TOKEN | Out-Null
        & aws configure set region us-west-2 | Out-Null
    }

    $identityOutput = & aws sts get-caller-identity --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "As credenciais AWS não foram aceitas: $($identityOutput -join ' ')"
    }

    $identity = ($identityOutput -join [Environment]::NewLine) | ConvertFrom-Json
    Write-Host "AWS validada: conta $($identity.Account), sessão LabRole ativa."
}

function Invoke-Gh {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & gh @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no GitHub CLI: gh $($Arguments -join ' ')"
    }
}

function Initialize-GitHubEnvironment {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Name
    )

    Invoke-Gh @('api', '--method', 'PUT', "repos/$GitHubOwner/$Repository/environments/$Name", '--silent')
}

function Set-GitHubVariable {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    Invoke-Gh @('variable', 'set', $Name, '--body', $Value, '--repo', "$GitHubOwner/$Repository", '--env', $EnvironmentName)
}

function Set-GitHubSecret {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $Value | & gh secret set $Name --repo "$GitHubOwner/$Repository" --env $EnvironmentName
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao atualizar o secret $Name em $Repository/$EnvironmentName."
    }
}

function Get-TerraformOutputs {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$WorkspaceName
    )

    $previousOrganization = $env:TF_CLOUD_ORGANIZATION
    $previousWorkspace = $env:TF_WORKSPACE
    try {
        $env:TF_CLOUD_ORGANIZATION = $TerraformOrganization
        $env:TF_WORKSPACE = $WorkspaceName

        & terraform "-chdir=$RepositoryPath" init -input=false -lockfile=readonly | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Não foi possível inicializar $WorkspaceName. Os outputs serão sincronizados após o apply."
            return $null
        }

        $output = & terraform "-chdir=$RepositoryPath" output -json
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Workspace $WorkspaceName ainda não possui outputs disponíveis."
            return $null
        }

        ($output -join [Environment]::NewLine) | ConvertFrom-Json
    }
    finally {
        $env:TF_CLOUD_ORGANIZATION = $previousOrganization
        $env:TF_WORKSPACE = $previousWorkspace
    }
}

function Get-KubernetesBackendUrl {
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$ClusterName
    )

    & aws eks update-kubeconfig --region us-west-2 --name $ClusterName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $namespace = "oficina-$EnvironmentName"
    $hostname = & kubectl get service oficina-app -n $namespace -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($hostname)) {
        return $null
    }

    "http://$hostname"
}

function Write-EnvironmentContext {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Values,
        [Parameter(Mandatory)][string]$Path
    )

    $lines = foreach ($entry in $Values.GetEnumerator()) {
        if ($entry.Value -is [Array]) {
            $items = @($entry.Value | ForEach-Object { "'$(($_ -replace "'", "''"))'" })
            '$' + $entry.Key + ' = @(' + ($items -join ', ') + ')'
        }
        elseif ($entry.Value -is [ValueType] -and $entry.Value -isnot [string]) {
            '$' + $entry.Key + ' = ' + $entry.Value
        }
        else {
            '$' + $entry.Key + " = '$(($entry.Value -replace "'", "''"))'"
        }
    }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($RepositoriesRoot)) {
    $backendRoot = Split-Path $PSScriptRoot -Parent
    $RepositoriesRoot = Split-Path $backendRoot -Parent
}
if ([string]::IsNullOrWhiteSpace($SecretsRoot)) {
    $SecretsRoot = 'C:\fiap-secrets'
}
$script:SecretsDirectory = Join-Path $SecretsRoot "oficina-$Environment"
if (-not $ValidateOnly) {
    New-Item -ItemType Directory -Force $script:SecretsDirectory | Out-Null
}
$contextPath = Join-Path $script:SecretsDirectory 'environment-context.ps1'
$contextValues = [ordered]@{
    environment    = $Environment
    eksClusterName = "oficina-$Environment"
}

Assert-Command terraform
Assert-Command aws
Assert-Command kubectl
$script:OpenSslCommand = Resolve-OpenSslCommand
if (-not $SkipGitHub) {
    Assert-Command gh
    Invoke-Gh @('auth', 'status')
}

$repositoryPaths = @{}
foreach ($entry in $RepositoryNames.GetEnumerator()) {
    $path = Join-Path $RepositoriesRoot $entry.Value
    if (-not (Test-Path $path)) {
        throw "Repositório não encontrado: $path"
    }
    $repositoryPaths[$entry.Key] = $path
}

$credentials = Get-AwsCredentials
Set-LocalAwsCredentials $credentials

$terraformToken = Get-TerraformToken
$script:HcpHeaders = @{ Authorization = "Bearer $terraformToken" }

$hcpWorkspaces = @{}
$awsWorkspaces = @()
foreach ($component in @('Kubernetes', 'Database', 'Auth')) {
    foreach ($targetEnvironment in @('homolog', 'production')) {
        $workspaceName = $WorkspaceNames[$component][$targetEnvironment]
        $workspace = Get-HcpWorkspace $workspaceName
        $hcpWorkspaces[$workspaceName] = $workspace
        $awsWorkspaces += $workspace
    }
}
if ($ValidateOnly) {
    Write-Host "Validação concluída para ${Environment}: ferramentas, repositórios, AWS STS, HCP Terraform e GitHub CLI estão acessíveis."
    Write-Host 'Nenhum arquivo de credencial, Variable Set, workspace ou GitHub Environment foi alterado.'
    return
}
Set-AwsVariableSet -Workspaces $awsWorkspaces -Credentials $credentials
foreach ($workspace in $awsWorkspaces) {
    foreach ($key in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN')) {
        Remove-HcpWorkspaceVariable -Workspace $workspace -Key $key -Category env
    }
}

$redundantVariables = @{
    Kubernetes = @('aws_region', 'cluster_version', 'lab_role_arn')
    Database   = @('aws_region', 'db_name', 'db_username', 'db_engine_version', 'db_instance_class', 'multi_az', 'deletion_protection', 'skip_final_snapshot')
    Auth       = @('aws_region', 'lab_role_arn', 'jwt_issuer', 'jwt_audience', 'jwt_ttl_seconds')
}
foreach ($component in @('Kubernetes', 'Database', 'Auth')) {
    foreach ($targetEnvironment in @('homolog', 'production')) {
        $workspace = $hcpWorkspaces[$WorkspaceNames[$component][$targetEnvironment]]
        foreach ($key in $redundantVariables[$component]) {
            Remove-HcpWorkspaceVariable -Workspace $workspace -Key $key
        }
        Set-HcpWorkspaceVariable -Workspace $workspace -Key environment -Value $targetEnvironment
        if ($component -eq 'Database') {
            $backupRetentionDays = if ($targetEnvironment -eq 'production') { '14' } else { '7' }
            Set-HcpWorkspaceVariable -Workspace $workspace -Key backup_retention_days -Value $backupRetentionDays -Hcl $true
        }
    }
}

$dbPassword = Get-StoredSecret -Name 'database-password' -Prompt 'Senha atual do RDS' -GenerateWhenEmpty
$appJwtSecret = Get-StoredSecret -Name 'backend-jwt-secret' -Prompt 'Secret HMAC administrativo atual do backend' -GenerateWhenEmpty
$adminPassword = Get-StoredSecret -Name 'backend-admin-password' -Prompt 'Senha atual do administrador do backend' -GenerateWhenEmpty

$privateKeyPath = Join-Path $script:SecretsDirectory 'jwt-private.pem'
$publicKeyPath = Join-Path $script:SecretsDirectory 'jwt-public.pem'
if (-not (Test-Path $privateKeyPath) -or -not (Test-Path $publicKeyPath)) {
    & $script:OpenSslCommand genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out $privateKeyPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao gerar a chave privada RSA.'
    }
    & $script:OpenSslCommand rsa -pubout -in $privateKeyPath -out $publicKeyPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao gerar a chave pública RSA.'
    }
}
$jwtPrivateKey = Get-Content $privateKeyPath -Raw
$jwtPublicKey = Get-Content $publicKeyPath -Raw

$databaseWorkspace = $hcpWorkspaces[$WorkspaceNames.Database[$Environment]]
$authWorkspace = $hcpWorkspaces[$WorkspaceNames.Auth[$Environment]]
Set-HcpWorkspaceVariable -Workspace $databaseWorkspace -Key db_password -Value $dbPassword -Sensitive $true
Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key db_user -Value 'oficina_admin' -Sensitive $true
Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key db_password -Value $dbPassword -Sensitive $true
Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key jwt_private_key -Value $jwtPrivateKey -Sensitive $true
Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key jwt_public_key -Value $jwtPublicKey

if (-not $SkipGitHub) {
    foreach ($targetEnvironment in @('homolog', 'production')) {
        foreach ($repository in $RepositoryNames.Values) {
            Initialize-GitHubEnvironment -Repository $repository -Name $targetEnvironment
            Set-GitHubSecret -Repository $repository -EnvironmentName $targetEnvironment -Name AWS_ACCESS_KEY_ID -Value $credentials.AWS_ACCESS_KEY_ID
            Set-GitHubSecret -Repository $repository -EnvironmentName $targetEnvironment -Name AWS_SECRET_ACCESS_KEY -Value $credentials.AWS_SECRET_ACCESS_KEY
            Set-GitHubSecret -Repository $repository -EnvironmentName $targetEnvironment -Name AWS_SESSION_TOKEN -Value $credentials.AWS_SESSION_TOKEN
            Set-GitHubVariable -Repository $repository -EnvironmentName $targetEnvironment -Name AWS_REGION -Value 'us-west-2'
        }

        foreach ($component in @('Kubernetes', 'Database', 'Auth')) {
            $repository = $RepositoryNames[$component]
            Set-GitHubSecret -Repository $repository -EnvironmentName $targetEnvironment -Name TF_API_TOKEN -Value $terraformToken
            Set-GitHubVariable -Repository $repository -EnvironmentName $targetEnvironment -Name TF_CLOUD_ORGANIZATION -Value $TerraformOrganization
            Set-GitHubVariable -Repository $repository -EnvironmentName $targetEnvironment -Name TF_WORKSPACE_HOMOLOG -Value $WorkspaceNames[$component].homolog
            Set-GitHubVariable -Repository $repository -EnvironmentName $targetEnvironment -Name TF_WORKSPACE_PRODUCTION -Value $WorkspaceNames[$component].production
        }

        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $targetEnvironment -Name TF_WORKSPACE_OBSERVABILITY_HOMOLOG -Value $WorkspaceNames.NewRelic.homolog
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $targetEnvironment -Name TF_WORKSPACE_OBSERVABILITY_PRODUCTION -Value $WorkspaceNames.NewRelic.production
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $targetEnvironment -Name CLUSTER_NAME -Value "oficina-$targetEnvironment"
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $targetEnvironment -Name APP_NAMESPACE -Value "oficina-$targetEnvironment"
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $targetEnvironment -Name SYNTHETIC_MONITOR_ENABLED -Value 'false'
        Set-GitHubVariable -Repository $RepositoryNames.Database -EnvironmentName $targetEnvironment -Name ENABLE_TERRAFORM_APPLY -Value 'true'
        Set-GitHubVariable -Repository $RepositoryNames.Auth -EnvironmentName $targetEnvironment -Name TF_APPLY_ENABLED -Value 'true'

        $authApplyEnvironment = "$targetEnvironment-apply"
        Initialize-GitHubEnvironment -Repository $RepositoryNames.Auth -Name $authApplyEnvironment
        Set-GitHubSecret -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name AWS_ACCESS_KEY_ID -Value $credentials.AWS_ACCESS_KEY_ID
        Set-GitHubSecret -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name AWS_SECRET_ACCESS_KEY -Value $credentials.AWS_SECRET_ACCESS_KEY
        Set-GitHubSecret -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name AWS_SESSION_TOKEN -Value $credentials.AWS_SESSION_TOKEN
        Set-GitHubSecret -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name TF_API_TOKEN -Value $terraformToken
        Set-GitHubVariable -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name AWS_REGION -Value 'us-west-2'
        Set-GitHubVariable -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name TF_CLOUD_ORGANIZATION -Value $TerraformOrganization
        Set-GitHubVariable -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name TF_WORKSPACE_HOMOLOG -Value $WorkspaceNames.Auth.homolog
        Set-GitHubVariable -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name TF_WORKSPACE_PRODUCTION -Value $WorkspaceNames.Auth.production
        Set-GitHubVariable -Repository $RepositoryNames.Auth -EnvironmentName $authApplyEnvironment -Name TF_APPLY_ENABLED -Value 'true'

        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $targetEnvironment -Name EKS_CLUSTER_NAME -Value "oficina-$targetEnvironment"
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $targetEnvironment -Name APP_DB_USER -Value 'oficina_admin'
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $targetEnvironment -Name SERVERLESS_JWT_ISSUER -Value 'oficina-auth-serverless'
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $targetEnvironment -Name SERVERLESS_JWT_AUDIENCE -Value 'oficina-backend'
    }

    Set-GitHubSecret -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name APP_DB_PASSWORD -Value $dbPassword
    Set-GitHubSecret -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name APP_JWT_SECRET -Value $appJwtSecret
    Set-GitHubSecret -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name APP_ADMIN_PASSWORD -Value $adminPassword
    Set-GitHubSecret -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name SERVERLESS_JWT_PUBLIC_KEY -Value $jwtPublicKey
}

$kubernetesOutputs = Get-TerraformOutputs -RepositoryPath $repositoryPaths.Kubernetes -WorkspaceName $WorkspaceNames.Kubernetes[$Environment]
if ($null -ne $kubernetesOutputs -and
    $null -ne $kubernetesOutputs.vpc_id -and
    $null -ne $kubernetesOutputs.private_subnet_ids -and
    $null -ne $kubernetesOutputs.eks_cluster_security_group_id) {
    $vpcId = [string]$kubernetesOutputs.vpc_id.value
    $privateSubnetIds = @($kubernetesOutputs.private_subnet_ids.value)
    $eksSecurityGroupId = [string]$kubernetesOutputs.eks_cluster_security_group_id.value
    $contextValues['vpcId'] = $vpcId
    $contextValues['privateSubnetIds'] = $privateSubnetIds
    $contextValues['eksSecurityGroupId'] = $eksSecurityGroupId

    Set-HcpWorkspaceVariable -Workspace $databaseWorkspace -Key vpc_id -Value $vpcId
    Set-HcpWorkspaceVariable -Workspace $databaseWorkspace -Key private_subnet_ids -Value ($privateSubnetIds | ConvertTo-Json -Compress) -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $databaseWorkspace -Key allowed_security_group_ids -Value (@($eksSecurityGroupId) | ConvertTo-Json -Compress) -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key private_subnet_ids -Value ($privateSubnetIds | ConvertTo-Json -Compress) -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key lambda_security_group_id -Value $eksSecurityGroupId

    Write-Host 'Outputs do Kubernetes sincronizados automaticamente com banco e autenticação.'
}
else {
    Write-Warning 'Kubernetes ainda não possui todos os outputs. Reexecute este mesmo script após o apply do cluster.'
}

$databaseOutputs = Get-TerraformOutputs -RepositoryPath $repositoryPaths.Database -WorkspaceName $WorkspaceNames.Database[$Environment]
if ($null -ne $databaseOutputs -and $null -ne $databaseOutputs.jdbc_url) {
    $jdbcUrl = [string]$databaseOutputs.jdbc_url.value
    $authJdbcUrl = "$jdbcUrl?sslmode=require"
    $contextValues['jdbcUrl'] = $jdbcUrl
    if ($null -ne $databaseOutputs.database_endpoint) {
        $contextValues['dbHost'] = [string]$databaseOutputs.database_endpoint.value
    }
    if ($null -ne $databaseOutputs.database_port) {
        $contextValues['dbPort'] = [int]$databaseOutputs.database_port.value
    }
    if ($null -ne $databaseOutputs.database_name) {
        $contextValues['dbName'] = [string]$databaseOutputs.database_name.value
    }
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key db_url -Value $authJdbcUrl -Sensitive $true

    if (-not $SkipGitHub) {
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name APP_DB_URL -Value $jdbcUrl
    }
    Write-Host 'Output do RDS sincronizado automaticamente com autenticação e backend.'
}
else {
    Write-Warning 'RDS ainda não possui output. Reexecute este mesmo script após o apply do banco.'
}

$backendUrl = Get-KubernetesBackendUrl -EnvironmentName $Environment -ClusterName $contextValues.eksClusterName
if (-not [string]::IsNullOrWhiteSpace($backendUrl)) {
    $contextValues['backendUrl'] = $backendUrl
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key backend_base_url -Value $backendUrl
    if (-not $SkipGitHub) {
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name BACKEND_BASE_URL -Value $backendUrl
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name HEALTH_CHECK_URL -Value "$backendUrl/actuator/health"
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name SYNTHETIC_MONITOR_ENABLED -Value 'true'
    }
    $newRelicAccountPath = Join-Path (Join-Path $SecretsRoot 'shared') 'newrelic-account-id.txt'
    if (Test-Path $newRelicAccountPath) {
        $existingNewRelicWorkspace = Get-HcpWorkspace $WorkspaceNames.NewRelic[$Environment]
        Set-HcpWorkspaceVariable -Workspace $existingNewRelicWorkspace -Key health_check_url -Value "$backendUrl/actuator/health"
        Set-HcpWorkspaceVariable -Workspace $existingNewRelicWorkspace -Key synthetic_monitor_enabled -Value 'true' -Hcl $true
    }
    Write-Host 'URL do LoadBalancer sincronizada automaticamente.'
}
else {
    Write-Warning 'LoadBalancer do backend ainda não está disponível. Reexecute este mesmo script após o deploy do backend.'
}

$authOutputs = Get-TerraformOutputs -RepositoryPath $repositoryPaths.Auth -WorkspaceName $WorkspaceNames.Auth[$Environment]
if ($null -ne $authOutputs -and $null -ne $authOutputs.api_base_url) {
    $apiBaseUrl = [string]$authOutputs.api_base_url.value
    $contextValues['apiBase'] = $apiBaseUrl
    if ($null -ne $authOutputs.cpf_authentication_url) {
        $contextValues['authUrl'] = [string]$authOutputs.cpf_authentication_url.value
    }
    if (-not $SkipGitHub) {
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name API_GATEWAY_BASE_URL -Value $apiBaseUrl
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name AUTH_BASE_URL -Value $apiBaseUrl
    }
    Write-Host 'URL do API Gateway sincronizada automaticamente com o backend.'
}

if ($ConfigureNewRelic) {
    $sharedSecretsDirectory = Join-Path $SecretsRoot 'shared'
    $accountId = Get-StoredValue -Path (Join-Path $sharedSecretsDirectory 'newrelic-account-id.txt') -Prompt 'New Relic Account ID'
    if ($accountId -notmatch '^\d+$') {
        throw 'New Relic Account ID deve ser numérico.'
    }
    $apiKey = Get-StoredSecret -Name 'newrelic-api-key' -Prompt 'New Relic User API key' -Directory $sharedSecretsDirectory
    $licenseKey = Get-StoredSecret -Name 'newrelic-license-key' -Prompt 'New Relic License key' -Directory $sharedSecretsDirectory
    $newRelicWorkspace = Get-HcpWorkspace $WorkspaceNames.NewRelic[$Environment]
    $newRelicLayerArn = 'arn:aws:lambda:us-west-2:451483290750:layer:NewRelicAgentJavaARM64-slim'
    $newRelicLayerOutput = @(& aws lambda list-layer-versions --layer-name $newRelicLayerArn --query 'LayerVersions[0].Version' --output text 2>$null)
    $newRelicLayerVersion = ($newRelicLayerOutput -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $newRelicLayerVersion -notmatch '^\d+$') {
        throw 'Não foi possível descobrir a versão atual da camada Java ARM64 do New Relic em us-west-2.'
    }

    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key environment -Value $Environment
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key newrelic_account_id -Value $accountId -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key newrelic_api_key -Value $apiKey -Sensitive $true
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key observability_enabled -Value 'true' -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key cluster_name -Value "oficina-$Environment"
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key apm_application_name -Value "oficina-backend-$Environment"
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key kubernetes_namespace -Value "oficina-$Environment"
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key api_gateway_name -Value "oficina-auth-$Environment-http-api"
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key lambda_function_names -Value (@("oficina-auth-$Environment-login", "oficina-auth-$Environment-authorizer") | ConvertTo-Json -Compress) -Hcl $true
    $syntheticMonitorEnabled = if ([string]::IsNullOrWhiteSpace($backendUrl)) { 'false' } else { 'true' }
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key synthetic_monitor_enabled -Value $syntheticMonitorEnabled -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key notification_enabled -Value 'false' -Hcl $true
    if (-not [string]::IsNullOrWhiteSpace($backendUrl)) {
        Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key health_check_url -Value "$backendUrl/actuator/health"
    }

    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key newrelic_account_id -Value $accountId
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key newrelic_license_key -Value $licenseKey -Sensitive $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key newrelic_layer_version -Value $newRelicLayerVersion -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key newrelic_instrumentation_enabled -Value 'true' -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key newrelic_log_forwarding_enabled -Value 'true' -Hcl $true

    if (-not $SkipGitHub) {
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name NEW_RELIC_ACCOUNT_ID -Value $accountId
        Set-GitHubSecret -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name NEW_RELIC_API_KEY -Value $apiKey
        Set-GitHubSecret -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name NEW_RELIC_LICENSE_KEY -Value $licenseKey
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name SYNTHETIC_MONITOR_ENABLED -Value $syntheticMonitorEnabled
        if (-not [string]::IsNullOrWhiteSpace($backendUrl)) {
            Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name HEALTH_CHECK_URL -Value "$backendUrl/actuator/health"
        }
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name NEW_RELIC_ENABLED -Value 'true'
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name NEW_RELIC_APP_NAME -Value "oficina-backend-$Environment"
        Set-GitHubSecret -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name NEW_RELIC_LICENSE_KEY -Value $licenseKey
    }
}

Write-EnvironmentContext -Values $contextValues -Path $contextPath

Write-Host ''
Write-Host "Configuração automática concluída para $Environment."
Write-Host 'Credenciais AWS: computador local, HCP Terraform e GitHub Environments atualizados.'
Write-Host "Contexto não sensível salvo em $contextPath"
Write-Host 'Reexecute este mesmo comando após cada apply/deploy para sincronizar outputs recém-criados.'
