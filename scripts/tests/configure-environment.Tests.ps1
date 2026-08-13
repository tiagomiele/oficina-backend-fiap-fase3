Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'configure-environment.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    throw ($errors | Out-String)
}

foreach ($name in @('Assert-TerraformPlatform', 'Get-HcpApiStatusCode', 'Get-HcpApiErrorDetail', 'Invoke-HcpApi', 'Initialize-HcpWorkspace', 'Set-HcpWorkspaceVariable', 'Set-HcpVariableSetVariables', 'Set-AwsVariableSet', 'Set-LocalAwsCredentials', 'Get-TerraformOutputs', 'ConvertTo-HclList', 'Get-TerraformOutput', 'Get-KubernetesBackendUrl', 'Get-NewRelicLayerVersion')) {
    $functionAst = $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true) | Select-Object -First 1
    if ($null -eq $functionAst) {
        throw "Function not found: $name"
    }
    Invoke-Expression $functionAst.Extent.Text
}

$apiException = [InvalidOperationException]::new('HTTP 400')
$apiErrorRecord = [Management.Automation.ErrorRecord]::new(
    $apiException,
    'HcpApiFailure',
    [Management.Automation.ErrorCategory]::InvalidOperation,
    $null
)
$apiErrorRecord.ErrorDetails = [Management.Automation.ErrorDetails]::new('{"errors":[{"title":"invalid attribute","detail":"execution-mode is invalid","source":{"pointer":"/data/attributes/execution-mode"}}]}')
$apiErrorDetail = Get-HcpApiErrorDetail -ErrorRecord $apiErrorRecord
if ($apiErrorDetail -ne 'invalid attribute: execution-mode is invalid [/data/attributes/execution-mode]') {
    throw "HCP API error detail was not preserved: $apiErrorDetail"
}

function Invoke-RestMethod {
    throw $apiErrorRecord
}
$script:HcpHeaders = @{ Authorization = 'Bearer test' }
try {
    Invoke-HcpApi -Method PATCH -Path workspaces/ws-1 -Body @{ data = @{} } -Context 'atualizar o workspace teste'
    throw 'HCP API failure was not propagated.'
}
catch {
    $expectedMessage = 'Falha no HCP Terraform ao atualizar o workspace teste (PATCH /api/v2/workspaces/ws-1): invalid attribute: execution-mode is invalid [/data/attributes/execution-mode]'
    if ($_.Exception.Message -ne $expectedMessage) {
        throw "HCP API context was not preserved: $($_.Exception.Message)"
    }
}
Remove-Item Function:\Invoke-RestMethod

$script:newRelicLayersResponse = [pscustomobject]@{
    Layers = @(
        [pscustomobject]@{
            LayerName = 'NewRelicAgentJavaARM64-slim'
            LatestMatchingVersion = [pscustomobject]@{ Version = 8 }
        }
    )
}
function Invoke-RestMethod {
    $script:newRelicLayersResponse
}
if ((Get-NewRelicLayerVersion) -ne 8) {
    throw 'Latest New Relic Java ARM64 slim layer was not selected.'
}
$script:newRelicLayersResponse = [pscustomobject]@{ Layers = @() }
try {
    Get-NewRelicLayerVersion
    throw 'Missing New Relic layer must fail.'
}
catch {
    if ($_.Exception.Message -notlike 'A camada NewRelicAgentJavaARM64-slim não foi encontrada*') {
        throw
    }
}
Remove-Item Function:\Invoke-RestMethod

$singleItemHclList = ConvertTo-HclList -Values @('sg-00672ffa5d6c0fb23')
if ($singleItemHclList -ne '["sg-00672ffa5d6c0fb23"]') {
    throw "Single-item HCL list was serialized incorrectly: $singleItemHclList"
}
$multipleItemHclList = ConvertTo-HclList -Values @('subnet-a', 'subnet-b')
if ($multipleItemHclList -ne '["subnet-a","subnet-b"]') {
    throw "Multiple-item HCL list was serialized incorrectly: $multipleItemHclList"
}

if ($null -ne (Get-TerraformOutput -Outputs $null -Name vpc_id)) {
    throw 'Null Terraform outputs must return null.'
}
$emptyOutputs = '{}' | ConvertFrom-Json
if ($null -ne (Get-TerraformOutput -Outputs $emptyOutputs -Name vpc_id)) {
    throw 'Missing Terraform output must return null.'
}
$partialOutputs = '{"vpc_id":{"sensitive":false}}' | ConvertFrom-Json
if ($null -ne (Get-TerraformOutput -Outputs $partialOutputs -Name vpc_id)) {
    throw 'Terraform output without value must return null.'
}
$completeOutputs = '{"vpc_id":{"sensitive":false,"value":"vpc-123"}}' | ConvertFrom-Json
$vpcOutput = Get-TerraformOutput -Outputs $completeOutputs -Name vpc_id
if ($null -eq $vpcOutput -or $vpcOutput.value -ne 'vpc-123') {
    throw 'Existing Terraform output was not returned.'
}

$ValidateOnly = $false
$script:awsCalls = @()
function aws {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

    $script:awsCalls += , @($Arguments)
    if ($Arguments -contains 'get-caller-identity') {
        '{"Account":"123456789012"}'
    }
    $global:LASTEXITCODE = 0
}
$testCredentials = @{
    AWS_ACCESS_KEY_ID     = 'test-access-key'
    AWS_SECRET_ACCESS_KEY = 'test-secret-key'
    AWS_SESSION_TOKEN     = 'test-session-token'
}
Set-LocalAwsCredentials -Credentials $testCredentials
if ($script:awsCalls.Count -ne 5) {
    throw 'AWS credentials must configure four values and validate STS once.'
}
if ($ErrorActionPreference -ne 'Stop') {
    throw 'AWS credential setup did not restore ErrorActionPreference.'
}

$script:ConfigurationIssues = [Collections.Generic.List[string]]::new()
$TerraformOrganization = 'test-organization'
$env:TF_CLOUD_ORGANIZATION = 'original-organization'
$env:TF_WORKSPACE = 'original-workspace'
$script:terraformInitExitCode = 1
$script:terraformOutputExitCode = 1
$script:terraformOutput = '{}'
$script:terraformOutputError = 'Outputs unavailable.'
$script:terraformPlatform = 'linux_amd64'
function terraform {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

    if ($Arguments -contains 'version') {
        "{`"terraform_version`":`"1.10.0`",`"platform`":`"$script:terraformPlatform`"}"
        $global:LASTEXITCODE = 0
        return
    }

    if ($Arguments -contains 'init') {
        if ($script:terraformInitExitCode -ne 0) {
            Write-Error 'Provider checksum mismatch.'
        }
        else {
            'Terraform initialized.'
        }
        $global:LASTEXITCODE = $script:terraformInitExitCode
        return
    }

    if ($script:terraformOutputExitCode -ne 0) {
        Write-Error $script:terraformOutputError
    }
    else {
        $script:terraformOutput
    }
    $global:LASTEXITCODE = $script:terraformOutputExitCode
}

$originalOperatingSystem = $env:OS
try {
    $env:OS = 'Windows_NT'
    $script:terraformPlatform = 'windows_386'
    try {
        Assert-TerraformPlatform
        throw '32-bit Terraform must be rejected on Windows.'
    }
    catch {
        if ($_.Exception.Message -notlike 'Terraform incompatível: plataforma windows_386*') {
            throw
        }
    }
    $script:terraformPlatform = 'windows_amd64'
    Assert-TerraformPlatform
}
finally {
    $env:OS = $originalOperatingSystem
    $script:terraformPlatform = 'linux_amd64'
}

if ($null -ne (Get-TerraformOutputs -RepositoryPath repository -WorkspaceName target-workspace)) {
    throw 'Failed Terraform initialization must return null.'
}
if ($script:ConfigurationIssues.Count -ne 1) {
    throw 'Failed Terraform initialization must register a blocking issue.'
}
if ($ErrorActionPreference -ne 'Stop') {
    throw 'Terraform output lookup did not restore ErrorActionPreference.'
}
if ($env:TF_CLOUD_ORGANIZATION -ne 'original-organization' -or $env:TF_WORKSPACE -ne 'original-workspace') {
    throw 'Terraform output lookup did not restore the original environment.'
}

$script:ConfigurationIssues.Clear()
$script:terraformInitExitCode = 0
$script:terraformOutputExitCode = 1
if ($null -ne (Get-TerraformOutputs -RepositoryPath repository -WorkspaceName target-workspace)) {
    throw 'Failed Terraform output must return null.'
}
if ($script:ConfigurationIssues.Count -ne 1 -or $script:ConfigurationIssues[0] -notlike '*Outputs unavailable.*') {
    throw 'Failed Terraform output must preserve the command detail.'
}

$script:ConfigurationIssues.Clear()
$script:terraformOutputError = 'Error: could not read state version outputs: resource not found'
if ($null -ne (Get-TerraformOutputs -RepositoryPath repository -WorkspaceName empty-workspace)) {
    throw 'Workspace without state must return null.'
}
if ($script:ConfigurationIssues.Count -ne 0) {
    throw 'Workspace without state must not register a blocking issue.'
}

$script:terraformOutputExitCode = 0
$script:terraformOutput = '{"api_base_url":{"value":"https://example.com"}}'
$terraformOutputs = Get-TerraformOutputs -RepositoryPath repository -WorkspaceName target-workspace
if ($terraformOutputs.api_base_url.value -ne 'https://example.com') {
    throw 'Valid Terraform outputs were not parsed.'
}

$script:awsExitCode = 1
$script:kubectlExitCode = 1
$script:loadBalancerHostname = $null
function aws {
    if ($script:awsExitCode -ne 0) {
        Write-Error 'EKS cluster was not found.'
    }
    $global:LASTEXITCODE = $script:awsExitCode
}
function kubectl {
    if ($script:kubectlExitCode -ne 0) {
        Write-Error 'Kubernetes service was not found.'
    }
    else {
        $script:loadBalancerHostname
    }
    $global:LASTEXITCODE = $script:kubectlExitCode
}

if ($null -ne (Get-KubernetesBackendUrl -EnvironmentName homolog -ClusterName oficina-homolog)) {
    throw 'Missing EKS cluster must return null.'
}
$script:awsExitCode = 0
if ($null -ne (Get-KubernetesBackendUrl -EnvironmentName homolog -ClusterName oficina-homolog)) {
    throw 'Missing Kubernetes service must return null.'
}
$script:kubectlExitCode = 0
$script:loadBalancerHostname = 'backend.example.com'
$backendUrl = Get-KubernetesBackendUrl -EnvironmentName homolog -ClusterName oficina-homolog
if ($backendUrl -ne 'http://backend.example.com') {
    throw 'Existing LoadBalancer hostname was not returned.'
}
if ($ErrorActionPreference -ne 'Stop') {
    throw 'ErrorActionPreference was not restored.'
}

$script:requests = @()
$script:existingVariables = @()
$script:existingSets = @()
function Invoke-HcpApi {
    param([string]$Method, [string]$Path, [object]$Body, [string]$Context)

    if ($Method -eq 'GET') {
        if ($Path -like 'organizations/*/varsets*') {
            return @{ data = $script:existingSets }
        }
        return @{ data = $script:existingVariables }
    }
    $script:requests += [pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body; Context = $Context }
    if ($null -eq $Body) {
        return @{}
    }
    @{ data = $Body.data }
}
function Get-HcpWorkspaceVariables {
    param([string]$WorkspaceId)

    $script:existingVariables
}

$workspace = [pscustomobject]@{
    id         = 'ws-1'
    attributes = [pscustomobject]@{ name = 'workspace-1' }
}
$script:existingVariables = @([pscustomobject]@{
    id         = 'var-1'
    attributes = [pscustomobject]@{ key = 'TOKEN'; category = 'terraform'; sensitive = $true }
})
Set-HcpWorkspaceVariable -Workspace $workspace -Key TOKEN -Value updated -Sensitive $true
$patch = $script:requests | Where-Object Method -eq PATCH | Select-Object -First 1
if ($null -eq $patch) {
    throw 'Same-sensitivity workspace variable was not patched.'
}
if (@($patch.Body.data.attributes.Keys).Count -ne 1 -or -not $patch.Body.data.attributes.ContainsKey('value')) {
    throw 'Sensitive workspace PATCH must update only value.'
}

$script:requests = @()
Set-HcpWorkspaceVariable -Workspace $workspace -Key TOKEN -Value readable -Sensitive $false
if (@($script:requests | Where-Object Method -eq DELETE).Count -ne 1) {
    throw 'Changed-sensitivity workspace variable was not deleted.'
}
if (@($script:requests | Where-Object Method -eq POST).Count -ne 1) {
    throw 'Changed-sensitivity workspace variable was not recreated.'
}
if (@($script:requests | Where-Object Method -eq PATCH).Count -ne 0) {
    throw 'Changed-sensitivity workspace variable must not be patched.'
}

$definition = @{
    type       = 'vars'
    attributes = @{
        key       = 'AWS_SESSION_TOKEN'
        value     = 'updated'
        category  = 'env'
        hcl       = $false
        sensitive = $true
    }
}
$script:requests = @()
$script:existingVariables = @([pscustomobject]@{
    id         = 'varset-var-1'
    attributes = [pscustomobject]@{ key = 'AWS_SESSION_TOKEN'; category = 'env'; sensitive = $true }
})
Set-HcpVariableSetVariables -VariableSetId varset-1 -Definitions @($definition)
$patch = $script:requests | Where-Object Method -eq PATCH | Select-Object -First 1
if ($null -eq $patch) {
    throw 'Same-sensitivity Variable Set variable was not patched.'
}
if (@($patch.Body.data.attributes.Keys).Count -ne 1 -or -not $patch.Body.data.attributes.ContainsKey('value')) {
    throw 'Sensitive Variable Set PATCH must update only value.'
}

$definition.attributes.sensitive = $false
$script:requests = @()
Set-HcpVariableSetVariables -VariableSetId varset-1 -Definitions @($definition)
if (@($script:requests | Where-Object Method -eq DELETE).Count -ne 1) {
    throw 'Changed-sensitivity Variable Set variable was not deleted.'
}
if (@($script:requests | Where-Object Method -eq POST).Count -ne 1) {
    throw 'Changed-sensitivity Variable Set variable was not recreated.'
}
if (@($script:requests | Where-Object Method -eq PATCH).Count -ne 0) {
    throw 'Changed-sensitivity Variable Set variable must not be patched.'
}

$script:existingWorkspace = [pscustomobject]@{
    id            = 'ws-existing'
    attributes    = [pscustomobject]@{
        name                = 'existing-workspace'
        'execution-mode'    = 'remote'
        'auto-apply'        = $false
        'working-directory' = ''
    }
    relationships = [pscustomobject]@{
        project = [pscustomobject]@{
            data = [pscustomobject]@{ id = 'prj-1' }
        }
    }
}
function Get-HcpWorkspace {
    param([string]$Name, [switch]$AllowMissing)

    $script:existingWorkspace
}
$script:requests = @()
$project = [pscustomobject]@{ id = 'prj-1' }
$result = Initialize-HcpWorkspace -Project $project -Name existing-workspace
if ($result.id -ne 'ws-existing' -or $script:requests.Count -ne 0) {
    throw 'Unchanged workspace must not be patched.'
}
$script:existingWorkspace.attributes.'auto-apply' = $true
$result = Initialize-HcpWorkspace -Project $project -Name existing-workspace
$workspacePatch = $script:requests | Where-Object Method -eq PATCH | Select-Object -First 1
if ($null -eq $workspacePatch -or $workspacePatch.Body.data.attributes.Count -ne 1 -or $workspacePatch.Body.data.attributes.'auto-apply' -ne $false) {
    throw 'Workspace PATCH must contain only changed attributes.'
}
if ($workspacePatch.Body.data.ContainsKey('relationships')) {
    throw 'Unchanged project relationship must not be sent in workspace PATCH.'
}

$script:requests = @()
$script:existingSets = @([pscustomobject]@{
    id         = 'varset-1'
    attributes = [pscustomobject]@{
        name        = 'aws-academy-credentials'
        description = 'Credenciais temporárias compartilhadas do AWS Academy. Gerenciado pelo script central.'
        global      = $false
        priority    = $false
    }
})
$script:existingVariables = @(
    [pscustomobject]@{ id = 'access'; attributes = [pscustomobject]@{ key = 'AWS_ACCESS_KEY_ID'; category = 'env'; sensitive = $true } },
    [pscustomobject]@{ id = 'secret'; attributes = [pscustomobject]@{ key = 'AWS_SECRET_ACCESS_KEY'; category = 'env'; sensitive = $true } },
    [pscustomobject]@{ id = 'session'; attributes = [pscustomobject]@{ key = 'AWS_SESSION_TOKEN'; category = 'env'; sensitive = $true } }
)
Set-AwsVariableSet -Workspaces @($workspace) -Credentials $testCredentials
$associationRequest = $script:requests | Where-Object Path -eq 'varsets/varset-1/relationships/workspaces'
if ($null -eq $associationRequest -or $associationRequest.Method -ne 'POST') {
    throw 'Existing Variable Set must use the workspace relationship endpoint.'
}
if (@($associationRequest.Body.data).Count -ne 1 -or $associationRequest.Body.data[0].id -ne 'ws-1' -or $associationRequest.Body.data[0].type -ne 'workspaces') {
    throw 'Variable Set workspace relationship payload is invalid.'
}
$metadataPatch = $script:requests | Where-Object { $_.Path -eq 'varsets/varset-1' -and $_.Method -eq 'PATCH' }
if ($null -ne $metadataPatch) {
    throw 'Unchanged Variable Set metadata must not be patched.'
}

Write-Host 'Environment automation tests passed.'
