#!/usr/bin/env pwsh
<#
 .SYNOPSIS
  Lists all macOS configuration policies (classic + settings catalog) and optionally exports one to JSON.

 .DESCRIPTION
  Queries Microsoft Graph (beta) for:
    - Classic deviceConfigurations whose @odata.type begins with macOS
    - Settings catalog configurationPolicies where platforms includes macOS
  Presents an indexed table, prompts for a selection (unless -NoPrompt or -SelectId used),
  then exports the full object (with settings for catalog) to an output folder.

 .PARAMETER OutputFolder
  Destination folder for exported JSON (created if missing). Default: ./exports

 .PARAMETER SkipConnect
  If supplied, skips Connect-MgGraph (useful if already connected with required scopes).

 .PARAMETER NoPrompt
  Only list policies; do not prompt or export.

 .PARAMETER SelectId
  Directly export a specific policy Id without prompting.

 .EXAMPLE
  pwsh ./tools/Get-MacOSConfigPolicies.ps1

 .EXAMPLE
  pwsh ./tools/Get-MacOSConfigPolicies.ps1 -NoPrompt

 .EXAMPLE
  pwsh ./tools/Get-MacOSConfigPolicies.ps1 -SelectId "00000000-0000-0000-0000-000000000000"

 .NOTES
    Requires Microsoft Graph PowerShell SDK. Scopes: DeviceManagementConfiguration.Read.All
    Safe read-only operation. Increase -Depth in ConvertTo-Json if needed for deeply nested settings.
#>

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

param(
    [string]$OutputFolder = './exports',
    [switch]$SkipConnect,
    [switch]$NoPrompt,
    [string]$SelectId
)

$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Warn([string]$msg){ Write-Host $msg -ForegroundColor Yellow }
function Write-Err ([string]$msg){ Write-Host $msg -ForegroundColor Red }

if (-not $SkipConnect) {
    if (-not (Get-Module Microsoft.Graph -ListAvailable)) {
        Write-Info 'Installing Microsoft.Graph module (CurrentUser scope)...'
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
    }
    # Only connect if not already connected
    $ctx = $null
    try { $ctx = Get-MgContext -ErrorAction SilentlyContinue } catch {}
    if (-not $ctx -or -not $ctx.Account) {
        Write-Info 'Connecting to Microsoft Graph...'
        Connect-MgGraph -Scopes 'DeviceManagementConfiguration.Read.All' | Out-Null
    } else {
        Write-Info "Graph context already present for: $($ctx.Account)"
    }
}

function Invoke-PagedGraph {
    param([Parameter(Mandatory)][string]$Uri)
    $accum = @()
    $next = $Uri
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next
        if ($resp.value) { $accum += $resp.value }
        $next = $resp.'@odata.nextLink'
    }
    return $accum
}

Write-Info 'Retrieving classic macOS device configuration policies...'
$classicAll = Invoke-PagedGraph -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$top=200"
$classicMac = $classicAll | Where-Object { $_.'@odata.type' -like '#microsoft.graph.macOS*' }

Write-Info 'Retrieving settings catalog configuration policies (macOS)...'
$catalogAll = Invoke-PagedGraph -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$top=200"
$catalogMac = $catalogAll | Where-Object { ($_.platforms -eq 'macOS') -or ($_.platforms -like '*macOS*') }

$policies = @()
$policies += $classicMac | ForEach-Object {
    [pscustomobject]@{
        Id          = $_.id
        DisplayName = $_.displayName
        Type        = ($_."@odata.type" -replace '^#microsoft\\.graph\\.')
        Source      = 'Classic'
    }
}
$policies += $catalogMac | ForEach-Object {
    [pscustomobject]@{
        Id          = $_.id
        DisplayName = $_.name
        Type        = 'SettingsCatalog'
        Source      = 'Catalog'
    }
}

if (-not $policies) { Write-Warn 'No macOS configuration policies found.'; return }

$policies = $policies | Sort-Object Source, DisplayName

# Build indexed view
$indexed = $policies | ForEach-Object -Begin { $i = 0 } -Process {
    [pscustomobject]@{ Index=$i; DisplayName=$_.DisplayName; Type=$_.Type; Source=$_.Source; Id=$_.Id }; $i++ }

$indexed | Format-Table -AutoSize

if ($NoPrompt -and -not $SelectId) { return }

$selected = $null
if ($SelectId) {
    $selected = $policies | Where-Object { $_.Id -eq $SelectId }
    if (-not $selected) { Write-Err "Policy Id '$SelectId' not found."; return }
} else {
    while (-not $selected) {
        $inputVal = Read-Host "Enter Index to export (or 'q' to quit)"
        if ($inputVal -eq 'q') { return }
        if ($inputVal -match '^\d+$' -and [int]$inputVal -ge 0 -and [int]$inputVal -lt $indexed.Count) {
            $selected = $policies[[int]$inputVal]
        } else { Write-Warn 'Invalid selection.' }
    }
}

Write-Info "Selected: $($selected.DisplayName) [$($selected.Source)/$($selected.Type)]"

if ($selected.Source -eq 'Classic') {
    $full = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($selected.Id)"
} else {
    $full = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($selected.Id)?`$expand=settings"
}

if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$resolved = Resolve-Path -LiteralPath $OutputFolder
$safeName = ($selected.DisplayName -replace '[\\/:*?""<>|]', '_')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $resolved.Path "$safeName-$timestamp-$($selected.Id).json"

$full | ConvertTo-Json -Depth 20 | Out-File -FilePath $outFile -Encoding UTF8

Write-Info "Exported: $outFile"

[pscustomobject]@{
    ExportPath   = $outFile
    Id           = $selected.Id
    Name         = $selected.DisplayName
    Source       = $selected.Source
    Type         = $selected.Type
    SettingCount = if ($selected.Source -eq 'Catalog') { @($full.settings).Count } else { $null }
}
