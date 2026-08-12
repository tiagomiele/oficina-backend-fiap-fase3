Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'configure-environment.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    throw ($errors | Out-String)
}

foreach ($name in @('Set-HcpWorkspaceVariable', 'Set-HcpVariableSetVariables', 'Set-LocalAwsCredentials', 'Get-TerraformOutputs', 'Get-TerraformOutput', 'Get-KubernetesBackendUrl')) {
    $functionAst = $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true) | Select-Object -First 1
    if ($null -eq $functionAst) {
        throw "Function not found: $name"
    }
    Invoke-Expression $functionAst.Extent.Text
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
function terraform {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

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
        Write-Error 'Outputs unavailable.'
    }
    else {
        $script:terraformOutput
    }
    $global:LASTEXITCODE = $script:terraformOutputExitCode
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

$script:terraformInitExitCode = 0
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
function Invoke-HcpApi {
    param([string]$Method, [string]$Path, [object]$Body)

    if ($Method -eq 'GET') {
        return @{ data = $script:existingVariables }
    }
    $script:requests += [pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body }
    @{}
}
function Get-HcpWorkspaceVariables {
    param([string]$WorkspaceId)

    $script:existingVariables
}

$workspace = [pscustomobject]@{ id = 'ws-1' }
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

Write-Host 'Environment automation tests passed.'
