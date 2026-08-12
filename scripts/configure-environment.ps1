[CmdletBinding()]
param(
    [ValidateSet('homolog', 'production')]
    [string]$Environment = 'homolog',
    [string]$RepositoriesRoot,
    [string]$TerraformOrganization = 'oficina-fiap-soat-fase-2',
    [string]$TerraformProject = 'soat-fase3',
    [string]$AwsCredentialsFile,
    [string]$SecretsRoot,
    [switch]$ConfigureNewRelic,
    [switch]$DisableObservability,
    [switch]$SkipGitHub,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ConfigurationIssues = [Collections.Generic.List[string]]::new()
if ($ConfigureNewRelic -and $DisableObservability) {
    throw 'Use somente um parâmetro: ConfigureNewRelic ou DisableObservability.'
}

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

function Assert-TerraformPlatform {
    $versionOutput = @(& terraform version -json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível identificar a plataforma do Terraform: $(($versionOutput | Select-Object -Last 3) -join ' ')"
    }

    try {
        $version = ($versionOutput -join [Environment]::NewLine) | ConvertFrom-Json
    }
    catch {
        throw 'O comando terraform version -json retornou uma resposta inválida.'
    }

    if ($env:OS -eq 'Windows_NT' -and [string]$version.platform -ne 'windows_amd64') {
        throw "Terraform incompatível: plataforma $($version.platform). Instale a edição Windows x64 (windows_amd64) antes de continuar."
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

function Get-HcpApiStatusCode {
    param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$ErrorRecord)

    $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
    if ($null -eq $responseProperty -or $null -eq $responseProperty.Value) {
        return $null
    }

    $statusCode = $responseProperty.Value.StatusCode
    if ($statusCode -is [int]) {
        return $statusCode
    }
    [int]$statusCode
}

function Get-HcpApiErrorDetail {
    param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$ErrorRecord)

    $errorDetailsProperty = $ErrorRecord.PSObject.Properties['ErrorDetails']
    $responseBody = if ($null -eq $errorDetailsProperty -or $null -eq $errorDetailsProperty.Value) {
        ''
    }
    else {
        [string]$errorDetailsProperty.Value.Message
    }
    $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
    if ([string]::IsNullOrWhiteSpace($responseBody) -and $null -ne $responseProperty -and $null -ne $responseProperty.Value) {
        try {
            $response = $responseProperty.Value
            $contentProperty = $response.PSObject.Properties['Content']
            if ($null -ne $contentProperty -and $null -ne $contentProperty.Value) {
                $responseBody = $contentProperty.Value.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            else {
                $responseStream = $response.GetResponseStream()
                if ($null -ne $responseStream) {
                    $reader = [IO.StreamReader]::new($responseStream)
                    try {
                        $responseBody = $reader.ReadToEnd()
                    }
                    finally {
                        $reader.Dispose()
                    }
                }
            }
        }
        catch {
            $responseBody = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($responseBody)) {
        return [string]$ErrorRecord.Exception.Message
    }

    try {
        $apiError = $responseBody | ConvertFrom-Json
        $errorItems = @($apiError.PSObject.Properties['errors'].Value)
        $details = @($errorItems | ForEach-Object {
            $source = $_.PSObject.Properties['source'].Value
            $pointerValue = if ($null -eq $source) { $null } else { $source.PSObject.Properties['pointer'].Value }
            $pointer = if ([string]::IsNullOrWhiteSpace($pointerValue)) { '' } else { " [$pointerValue]" }
            "$($_.title): $($_.detail)$pointer"
        })
        if ($details.Count -gt 0) {
            return $details -join '; '
        }
    }
    catch {
    }

    ($responseBody -replace '[\r\n]+', ' ').Trim()
}

function Invoke-HcpApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [string]$Context = 'executar requisição'
    )

    $parameters = @{
        Method      = $Method
        Uri         = "https://app.terraform.io/api/v2/$Path"
        Headers     = $script:HcpHeaders
        ContentType = 'application/vnd.api+json'
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    try {
        Invoke-RestMethod @parameters
    }
    catch {
        $statusCode = Get-HcpApiStatusCode -ErrorRecord $_
        $detail = Get-HcpApiErrorDetail -ErrorRecord $_
        $exception = [InvalidOperationException]::new(
            "Falha no HCP Terraform ao $Context ($Method /api/v2/$Path): $detail",
            $_.Exception
        )
        if ($null -ne $statusCode) {
            $exception.Data['HcpStatusCode'] = $statusCode
        }
        throw $exception
    }
}

function Get-HcpProject {
    $projects = @((Invoke-HcpApi -Method GET -Path "organizations/$TerraformOrganization/projects?page%5Bsize%5D=100" -Context 'consultar projetos').data)
    $projects | Where-Object { $_.attributes.name -eq $TerraformProject } | Select-Object -First 1
}

function Initialize-HcpProject {
    $project = Get-HcpProject
    if ($null -ne $project) {
        return $project
    }

    $body = @{
        data = @{
            type       = 'projects'
            attributes = @{
                name                     = $TerraformProject
                'default-execution-mode' = 'remote'
            }
        }
    }
    (Invoke-HcpApi -Method POST -Path "organizations/$TerraformOrganization/projects" -Body $body -Context "criar o projeto $TerraformProject").data
}

function Get-HcpWorkspace {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$AllowMissing
    )

    try {
        return (Invoke-HcpApi -Method GET -Path "organizations/$TerraformOrganization/workspaces/$Name" -Context "consultar o workspace $Name").data
    }
    catch {
        if ($AllowMissing -and $_.Exception.Data['HcpStatusCode'] -eq 404) {
            return $null
        }
        throw
    }
}

function Initialize-HcpWorkspace {
    param(
        [Parameter(Mandatory)][object]$Project,
        [Parameter(Mandatory)][string]$Name,
        [string]$WorkingDirectory = ''
    )

    $workspace = Get-HcpWorkspace -Name $Name -AllowMissing
    $desiredAttributes = @{
        'execution-mode'    = 'remote'
        'auto-apply'        = $false
        'working-directory' = $WorkingDirectory
    }
    if ($null -eq $workspace) {
        $desiredAttributes.name = $Name
        $body = @{
            data = @{
                type          = 'workspaces'
                attributes    = $desiredAttributes
                relationships = @{
                    project = @{ data = @{ type = 'projects'; id = $Project.id } }
                }
            }
        }
        return (Invoke-HcpApi -Method POST -Path "organizations/$TerraformOrganization/workspaces" -Body $body -Context "criar o workspace $Name").data
    }

    $changedAttributes = @{}
    if ([string]$workspace.attributes.'execution-mode' -ne 'remote') {
        $changedAttributes['execution-mode'] = 'remote'
    }
    if ([bool]$workspace.attributes.'auto-apply') {
        $changedAttributes['auto-apply'] = $false
    }
    if ([string]$workspace.attributes.'working-directory' -ne $WorkingDirectory) {
        $changedAttributes['working-directory'] = $WorkingDirectory
    }
    $currentProjectId = [string]$workspace.relationships.project.data.id
    $projectChanged = $currentProjectId -ne [string]$Project.id
    if ($changedAttributes.Count -eq 0 -and -not $projectChanged) {
        return $workspace
    }

    $data = @{
        type = 'workspaces'
        id   = $workspace.id
    }
    if ($changedAttributes.Count -gt 0) {
        $data.attributes = $changedAttributes
    }
    if ($projectChanged) {
        $data.relationships = @{
            project = @{ data = @{ type = 'projects'; id = $Project.id } }
        }
    }
    $body = @{ data = $data }
    (Invoke-HcpApi -Method PATCH -Path "workspaces/$($workspace.id)" -Body $body -Context "atualizar o workspace $Name").data
}

function Get-HcpWorkspaceVariables {
    param([Parameter(Mandatory)][string]$WorkspaceId)

    @((Invoke-HcpApi -Method GET -Path "workspaces/$WorkspaceId/vars?page%5Bsize%5D=100" -Context "consultar variáveis do workspace $WorkspaceId").data)
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
        Invoke-HcpApi -Method POST -Path "workspaces/$($Workspace.id)/vars" -Body $payload -Context "criar a variável $Key no workspace $($Workspace.attributes.name)" | Out-Null
        return
    }

    if ([bool]$existing.attributes.sensitive -ne $Sensitive) {
        foreach ($variable in $matchingVariables) {
            Invoke-HcpApi -Method DELETE -Path "workspaces/$($Workspace.id)/vars/$($variable.id)" -Context "recriar a variável $Key no workspace $($Workspace.attributes.name)" | Out-Null
        }
        Invoke-HcpApi -Method POST -Path "workspaces/$($Workspace.id)/vars" -Body $payload -Context "recriar a variável $Key no workspace $($Workspace.attributes.name)" | Out-Null
        return
    }

    $payload.data.id = $existing.id
    if ($Sensitive) {
        $payload.data.attributes = @{ value = $Value }
    }
    else {
        $payload.data.attributes.Remove('sensitive')
    }
    Invoke-HcpApi -Method PATCH -Path "workspaces/$($Workspace.id)/vars/$($existing.id)" -Body $payload -Context "atualizar a variável $Key no workspace $($Workspace.attributes.name)" | Out-Null
    foreach ($duplicateVariable in $matchingVariables | Select-Object -Skip 1) {
        Invoke-HcpApi -Method DELETE -Path "workspaces/$($Workspace.id)/vars/$($duplicateVariable.id)" -Context "remover duplicata da variável $Key no workspace $($Workspace.attributes.name)" | Out-Null
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
        Invoke-HcpApi -Method DELETE -Path "workspaces/$($Workspace.id)/vars/$($variable.id)" -Context "remover a variável $Key do workspace $($Workspace.attributes.name)" | Out-Null
    }
}

function Set-HcpVariableSetVariables {
    param(
        [Parameter(Mandatory)][string]$VariableSetId,
        [Parameter(Mandatory)][object[]]$Definitions
    )

    $existingVariables = @((Invoke-HcpApi -Method GET -Path "varsets/$VariableSetId/relationships/vars" -Context 'consultar variáveis do Variable Set AWS').data)
    foreach ($definition in $Definitions) {
        $matchingVariables = @($existingVariables | Where-Object {
            $_.attributes.key -eq $definition.attributes.key -and $_.attributes.category -eq $definition.attributes.category
        })
        $payload = @{ data = $definition }
        if ($matchingVariables.Count -eq 0) {
            Invoke-HcpApi -Method POST -Path "varsets/$VariableSetId/relationships/vars" -Body $payload -Context "criar $($definition.attributes.key) no Variable Set AWS" | Out-Null
            continue
        }

        $primaryVariable = $matchingVariables[0]
        if ([bool]$primaryVariable.attributes.sensitive -ne [bool]$definition.attributes.sensitive) {
            foreach ($variable in $matchingVariables) {
                Invoke-HcpApi -Method DELETE -Path "varsets/$VariableSetId/relationships/vars/$($variable.id)" -Context "recriar $($definition.attributes.key) no Variable Set AWS" | Out-Null
            }
            Invoke-HcpApi -Method POST -Path "varsets/$VariableSetId/relationships/vars" -Body $payload -Context "recriar $($definition.attributes.key) no Variable Set AWS" | Out-Null
            continue
        }

        $attributes = if ([bool]$definition.attributes.sensitive) {
            @{ value = $definition.attributes.value }
        }
        else {
            $definition.attributes.Clone()
        }
        $attributes.Remove('sensitive')
        $payload.data = @{
            type       = $definition.type
            id         = $primaryVariable.id
            attributes = $attributes
        }
        Invoke-HcpApi -Method PATCH -Path "varsets/$VariableSetId/relationships/vars/$($primaryVariable.id)" -Body $payload -Context "atualizar $($definition.attributes.key) no Variable Set AWS" | Out-Null
        foreach ($duplicateVariable in $matchingVariables | Select-Object -Skip 1) {
            Invoke-HcpApi -Method DELETE -Path "varsets/$VariableSetId/relationships/vars/$($duplicateVariable.id)" -Context "remover duplicata de $($definition.attributes.key) no Variable Set AWS" | Out-Null
        }
    }
}

function Set-AwsVariableSet {
    param(
        [Parameter(Mandatory)][object[]]$Workspaces,
        [Parameter(Mandatory)][hashtable]$Credentials
    )

    $name = 'aws-academy-credentials'
    $existingSets = @((Invoke-HcpApi -Method GET -Path "organizations/$TerraformOrganization/varsets?page%5Bsize%5D=100" -Context 'consultar Variable Sets').data)
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
        Invoke-HcpApi -Method POST -Path "organizations/$TerraformOrganization/varsets" -Body $payload -Context 'criar o Variable Set AWS' | Out-Null
        return
    }

    $primarySet = $matchingSets[0]
    $attributeChanges = @{}
    if ([string]$primarySet.attributes.description -ne [string]$payload.data.attributes.description) {
        $attributeChanges.description = $payload.data.attributes.description
    }
    if ([bool]$primarySet.attributes.global) {
        $attributeChanges.global = $false
    }
    if ([bool]$primarySet.attributes.priority) {
        $attributeChanges.priority = $false
    }
    if ($attributeChanges.Count -gt 0) {
        $metadataPayload = @{
            data = @{
                type       = 'varsets'
                id         = $primarySet.id
                attributes = $attributeChanges
            }
        }
        Invoke-HcpApi -Method PATCH -Path "varsets/$($primarySet.id)" -Body $metadataPayload -Context 'atualizar os metadados do Variable Set AWS' | Out-Null
    }
    $workspacePayload = @{ data = $workspaceRelationships }
    Invoke-HcpApi -Method POST -Path "varsets/$($primarySet.id)/relationships/workspaces" -Body $workspacePayload -Context 'associar o Variable Set AWS aos workspaces' | Out-Null
    Set-HcpVariableSetVariables -VariableSetId $primarySet.id -Definitions $variables
    foreach ($duplicateSet in $matchingSets | Select-Object -Skip 1) {
        Invoke-HcpApi -Method DELETE -Path "varsets/$($duplicateSet.id)" -Context 'remover Variable Set AWS duplicado' | Out-Null
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

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if (-not $ValidateOnly) {
            $configureCommands = @(
                @('configure', 'set', 'aws_access_key_id', $Credentials.AWS_ACCESS_KEY_ID),
                @('configure', 'set', 'aws_secret_access_key', $Credentials.AWS_SECRET_ACCESS_KEY),
                @('configure', 'set', 'aws_session_token', $Credentials.AWS_SESSION_TOKEN),
                @('configure', 'set', 'region', 'us-west-2')
            )
            foreach ($command in $configureCommands) {
                & aws @command 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "Falha ao executar: aws $($command[0..2] -join ' ')"
                }
            }
        }

        $identityOutput = @(& aws sts get-caller-identity --output json 2>&1)
        $identityExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($identityExitCode -ne 0) {
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
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $env:TF_CLOUD_ORGANIZATION = $TerraformOrganization
        $env:TF_WORKSPACE = $WorkspaceName
        $ErrorActionPreference = 'Continue'

        $initOutput = @(& terraform "-chdir=$RepositoryPath" init -input=false -lockfile=readonly 2>&1)
        $initExitCode = $LASTEXITCODE
        if ($initExitCode -ne 0) {
            $detail = ($initOutput | Select-Object -Last 3) -join ' '
            $message = "Não foi possível inicializar $WorkspaceName. Detalhe: $detail"
            $script:ConfigurationIssues.Add($message)
            Write-Warning "$message Corrija o repositório antes do plan/apply."
            return $null
        }
        $initOutput | Out-Host

        $output = @(& terraform "-chdir=$RepositoryPath" output -json 2>&1)
        $outputExitCode = $LASTEXITCODE
        if ($outputExitCode -ne 0) {
            $detail = ($output | Select-Object -Last 8) -join ' '
            $message = "Não foi possível ler os outputs do workspace $WorkspaceName. Detalhe: $detail"
            $script:ConfigurationIssues.Add($message)
            Write-Warning "$message Não execute plan/apply antes de corrigir essa leitura."
            return $null
        }

        try {
            ($output -join [Environment]::NewLine) | ConvertFrom-Json
        }
        catch {
            $message = "Workspace $WorkspaceName retornou outputs inválidos."
            $script:ConfigurationIssues.Add($message)
            Write-Warning "$message Não execute plan/apply antes de corrigir essa leitura."
            return $null
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $env:TF_CLOUD_ORGANIZATION = $previousOrganization
        $env:TF_WORKSPACE = $previousWorkspace
    }
}

function Get-TerraformOutput {
    param(
        [object]$Outputs,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Outputs) {
        return $null
    }
    $property = $Outputs.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }
    if ($null -eq $property.Value.PSObject.Properties['value']) {
        return $null
    }
    $property.Value
}

function Get-KubernetesBackendUrl {
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$ClusterName
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $awsExitCode = 1
    $kubectlExitCode = 1
    $hostname = $null
    try {
        $ErrorActionPreference = 'Continue'
        & aws eks update-kubeconfig --region us-west-2 --name $ClusterName 2>$null | Out-Null
        $awsExitCode = $LASTEXITCODE
        if ($awsExitCode -eq 0) {
            $namespace = "oficina-$EnvironmentName"
            $hostname = & kubectl get service oficina-app -n $namespace -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}' 2>$null
            $kubectlExitCode = $LASTEXITCODE
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($awsExitCode -ne 0 -or $kubectlExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($hostname)) {
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
    $SecretsRoot = if ($env:OS -eq 'Windows_NT') {
        'C:\fiap-secrets'
    }
    else {
        Join-Path $HOME '.oficina-secrets'
    }
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
Assert-TerraformPlatform
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
if ($ValidateOnly) {
    Invoke-HcpApi -Method GET -Path "organizations/$TerraformOrganization" | Out-Null
    $missingWorkspaces = @()
    foreach ($component in @('Kubernetes', 'Database', 'Auth', 'NewRelic')) {
        foreach ($targetEnvironment in @('homolog', 'production')) {
            $workspaceName = $WorkspaceNames[$component][$targetEnvironment]
            if ($null -eq (Get-HcpWorkspace -Name $workspaceName -AllowMissing)) {
                $missingWorkspaces += $workspaceName
            }
        }
    }
    if ($missingWorkspaces.Count -gt 0) {
        Write-Warning "Workspaces que serão criados na execução efetiva: $($missingWorkspaces -join ', ')"
    }
    Write-Host "Validação concluída para ${Environment}: ferramentas, repositórios, AWS STS, organização HCP Terraform e GitHub CLI estão acessíveis."
    Write-Host 'Nenhum arquivo de credencial, Variable Set, workspace ou GitHub Environment foi alterado.'
    return
}

Write-Host 'Sincronizando projeto e workspaces no HCP Terraform...'
$hcpProject = Initialize-HcpProject
foreach ($component in @('Kubernetes', 'Database', 'Auth', 'NewRelic')) {
    foreach ($targetEnvironment in @('homolog', 'production')) {
        $workspaceName = $WorkspaceNames[$component][$targetEnvironment]
        $workingDirectory = if ($component -eq 'NewRelic') { 'observability/newrelic' } else { '' }
        $workspace = Initialize-HcpWorkspace -Project $hcpProject -Name $workspaceName -WorkingDirectory $workingDirectory
        $hcpWorkspaces[$workspaceName] = $workspace
        if ($component -ne 'NewRelic') {
            $awsWorkspaces += $workspace
        }
    }
}
Write-Host 'Sincronizando credenciais temporárias no Variable Set compartilhado...'
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

Write-Host 'Sincronizando secrets permanentes dos workspaces...'
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
    Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name DEPLOY_ENABLED -Value 'false'
}

$kubernetesReady = $false
$databaseReady = $false
$kubernetesOutputs = Get-TerraformOutputs -RepositoryPath $repositoryPaths.Kubernetes -WorkspaceName $WorkspaceNames.Kubernetes[$Environment]
$vpcOutput = Get-TerraformOutput -Outputs $kubernetesOutputs -Name vpc_id
$privateSubnetsOutput = Get-TerraformOutput -Outputs $kubernetesOutputs -Name private_subnet_ids
$eksSecurityGroupOutput = Get-TerraformOutput -Outputs $kubernetesOutputs -Name eks_cluster_security_group_id
if ($null -ne $vpcOutput -and $null -ne $privateSubnetsOutput -and $null -ne $eksSecurityGroupOutput) {
    $vpcId = [string]$vpcOutput.value
    $privateSubnetIds = @($privateSubnetsOutput.value)
    $eksSecurityGroupId = [string]$eksSecurityGroupOutput.value
    $contextValues['vpcId'] = $vpcId
    $contextValues['privateSubnetIds'] = $privateSubnetIds
    $contextValues['eksSecurityGroupId'] = $eksSecurityGroupId

    Set-HcpWorkspaceVariable -Workspace $databaseWorkspace -Key vpc_id -Value $vpcId
    Set-HcpWorkspaceVariable -Workspace $databaseWorkspace -Key private_subnet_ids -Value ($privateSubnetIds | ConvertTo-Json -Compress) -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $databaseWorkspace -Key allowed_security_group_ids -Value (@($eksSecurityGroupId) | ConvertTo-Json -Compress) -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key private_subnet_ids -Value ($privateSubnetIds | ConvertTo-Json -Compress) -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key lambda_security_group_id -Value $eksSecurityGroupId
    $kubernetesReady = $true

    Write-Host 'Outputs do Kubernetes sincronizados automaticamente com banco e autenticação.'
}
else {
    Write-Warning 'Kubernetes ainda não possui todos os outputs. Reexecute este mesmo script após o apply do cluster.'
}

$databaseOutputs = Get-TerraformOutputs -RepositoryPath $repositoryPaths.Database -WorkspaceName $WorkspaceNames.Database[$Environment]
$jdbcOutput = Get-TerraformOutput -Outputs $databaseOutputs -Name jdbc_url
if ($null -ne $jdbcOutput) {
    $jdbcUrl = [string]$jdbcOutput.value
    $authJdbcUrl = "$jdbcUrl?sslmode=require"
    $contextValues['jdbcUrl'] = $jdbcUrl
    $databaseEndpointOutput = Get-TerraformOutput -Outputs $databaseOutputs -Name database_endpoint
    $databasePortOutput = Get-TerraformOutput -Outputs $databaseOutputs -Name database_port
    $databaseNameOutput = Get-TerraformOutput -Outputs $databaseOutputs -Name database_name
    if ($null -ne $databaseEndpointOutput) {
        $contextValues['dbHost'] = [string]$databaseEndpointOutput.value
    }
    if ($null -ne $databasePortOutput) {
        $contextValues['dbPort'] = [int]$databasePortOutput.value
    }
    if ($null -ne $databaseNameOutput) {
        $contextValues['dbName'] = [string]$databaseNameOutput.value
    }
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key db_url -Value $authJdbcUrl -Sensitive $true

    if (-not $SkipGitHub) {
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name APP_DB_URL -Value $jdbcUrl
    }
    $databaseReady = $true
    Write-Host 'Output do RDS sincronizado automaticamente com autenticação e backend.'
}
else {
    Write-Warning 'RDS ainda não possui output. Reexecute este mesmo script após o apply do banco.'
}

if (-not $SkipGitHub -and $kubernetesReady -and $databaseReady) {
    Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name DEPLOY_ENABLED -Value 'true'
    Write-Host 'Deploy do backend habilitado: outputs de EKS e RDS estão disponíveis.'
}

$backendUrl = if ($kubernetesReady) {
    Get-KubernetesBackendUrl -EnvironmentName $Environment -ClusterName $contextValues.eksClusterName
}
else {
    $null
}
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
$apiBaseOutput = Get-TerraformOutput -Outputs $authOutputs -Name api_base_url
if ($null -ne $apiBaseOutput) {
    $apiBaseUrl = [string]$apiBaseOutput.value
    $contextValues['apiBase'] = $apiBaseUrl
    $cpfAuthenticationOutput = Get-TerraformOutput -Outputs $authOutputs -Name cpf_authentication_url
    if ($null -ne $cpfAuthenticationOutput) {
        $contextValues['authUrl'] = [string]$cpfAuthenticationOutput.value
    }
    if (-not $SkipGitHub) {
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name API_GATEWAY_BASE_URL -Value $apiBaseUrl
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name AUTH_BASE_URL -Value $apiBaseUrl
    }
    Write-Host 'URL do API Gateway sincronizada automaticamente com o backend.'
}

if ($DisableObservability) {
    $newRelicWorkspace = $hcpWorkspaces[$WorkspaceNames.NewRelic[$Environment]]
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key observability_enabled -Value 'false' -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key synthetic_monitor_enabled -Value 'false' -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $newRelicWorkspace -Key notification_enabled -Value 'false' -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key newrelic_instrumentation_enabled -Value 'false' -Hcl $true
    Set-HcpWorkspaceVariable -Workspace $authWorkspace -Key newrelic_log_forwarding_enabled -Value 'false' -Hcl $true
    if (-not $SkipGitHub) {
        Set-GitHubVariable -Repository $RepositoryNames.Kubernetes -EnvironmentName $Environment -Name SYNTHETIC_MONITOR_ENABLED -Value 'false'
        Set-GitHubVariable -Repository $RepositoryNames.Backend -EnvironmentName $Environment -Name NEW_RELIC_ENABLED -Value 'false'
    }
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
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $newRelicLayerOutput = @(& aws lambda list-layer-versions --layer-name $newRelicLayerArn --query 'LayerVersions[0].Version' --output text 2>&1)
        $newRelicLayerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $newRelicLayerVersion = ($newRelicLayerOutput -join '').Trim()
    if ($newRelicLayerExitCode -ne 0 -or $newRelicLayerVersion -notmatch '^\d+$') {
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
if ($script:ConfigurationIssues.Count -gt 0) {
    Write-Warning "A configuração terminou com $($script:ConfigurationIssues.Count) pendência(s) técnica(s):"
    foreach ($issue in $script:ConfigurationIssues) {
        Write-Warning "- $issue"
    }
    throw 'Configuração incompleta. Corrija as pendências acima e reexecute este mesmo comando antes de qualquer plan/apply.'
}

Write-Host "Configuração automática concluída para $Environment."
Write-Host 'Credenciais AWS: computador local, HCP Terraform e GitHub Environments atualizados.'
Write-Host "Contexto não sensível salvo em $contextPath"
Write-Host 'Reexecute este mesmo comando após cada apply/deploy para sincronizar outputs recém-criados.'
