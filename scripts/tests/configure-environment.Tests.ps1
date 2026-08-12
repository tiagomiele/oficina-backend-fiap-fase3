Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'configure-environment.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    throw ($errors | Out-String)
}

foreach ($name in @('Set-HcpWorkspaceVariable', 'Set-HcpVariableSetVariables')) {
    $functionAst = $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true) | Select-Object -First 1
    if ($null -eq $functionAst) {
        throw "Function not found: $name"
    }
    Invoke-Expression $functionAst.Extent.Text
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

Write-Host 'HCP variable sensitivity tests passed.'
