# Requires: PowerShell 7+
$ErrorActionPreference = 'Stop'

<#
HOW TO RUN

Run from the repository root folder.

Basic help:
    pwsh ./mainScript.ps1 --help

Default behavior:
    - The script runs in dry-run mode unless you pass --apply.
    - Use --assign-group to assign newly created objects.
    - Only one platform is processed per run.
    - If --platform is not specified, macOS is used.

Common examples:
    # Preview all changes (dry-run)
    pwsh ./mainScript.ps1 --assign-group "Intune Mac Pilot"

    # Apply all changes
    pwsh ./mainScript.ps1 --assign-group "Intune Mac Pilot" --apply

    # Target a specific tenant
    pwsh ./mainScript.ps1 --tenant-id "12345678-1234-1234-1234-123456789012" --assign-group "Intune Mac Pilot" --apply

    # Target a specific platform
    pwsh ./mainScript.ps1 --platform "Windows" --apply

    # Limit scope
    pwsh ./mainScript.ps1 --config --apply
    pwsh ./mainScript.ps1 --scripts --custom-attributes --apply

    # Include MDE manifests under macOS/mde
    pwsh ./mainScript.ps1 --mde --apply

    # Remove all objects matching prefix (destructive)
    pwsh ./mainScript.ps1 --prefix "[intune-my-devices]" --remove-all --apply

    # Remove all objects for a specific platform (destructive)
    pwsh ./mainScript.ps1 --prefix "[intune-my-devices]" --remove-all --platform "Windows" --apply

Main flags:
    Scope selectors:
        --apps
        --config
        --compliance
        --scripts
        --custom-attributes
        --enrollment

    Optional features:
        --mde
        -mde
        --show-all-scripts

    Mutation/control:
        --apply
        --remove-all
        --skip-terminal-verification

    Value parameters (supports both --param value and --param=value):
        --prefix "[custom]"
        --assign-group "Name"
        --tenant-id "GUID"
        --names "Name 1,Name 2,Name 3"
        --platform "macOS|Windows|iOS|Android"

    Help:
        -h
        --help
#>

# Graph SDK modules will auto-load when needed
# #requires -module Microsoft.Graph.Beta.Devices.CorporateManagement
# #requires -module Microsoft.Graph.Authentication

<# region Authentication 
To authenticate, you'll use the Microsoft Graph PowerShell SDK. If you haven't already installed the SDK, see this guide:
https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0
The PowerShell SDK supports two types of authentication: delegated access, and app-only access.
For details on using delegated access, see this guide here:
https://learn.microsoft.com/powershell/microsoftgraph/get-started?view=graph-powershell-1.0
For details on using app-only access for unattended scenarmacOS, see Use app-only authentication with the Microsoft Graph PowerShell SDK:
https://learn.microsoft.com/powershell/microsoftgraph/app-only?view=graph-powershell-1.0&tabs=azure-portal
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#>

# Choose what to run
$importPolicies             = $true
$importPackages             = $true
$importScripts              = $true
$importCompliance           = $true  # new: compliance policies
$importCustomAttrs          = $true  # new: custom attributes
$importEnrollmentRestrictions = $true  # enrollment platform restrictions
$includeMde                 = $false # include macOS/mde/ folder content only if --mde specified
$applyChanges               = $false # require --apply to move beyond dry-run mode

# Initialize created object trackers per run
$createdPolicyIds = @()
$createdDeviceConfigIds = @()  # classic deviceConfigurations (e.g., macOSCustomConfiguration)
$createdPolicyDeviceConfigIds = @()  # policy payloads created in deviceConfigurations (e.g., Windows update rings)
$createdFeatureUpdateProfileIds = @()  # policies created in windowsFeatureUpdateProfiles
$createdComplianceIds = @()
$createdScriptIds = @()
$createdAppIds = @()
$createdCustomAttrIds = @()  # custom attributes
$createdEnrollmentRestrictionIds = @()  # enrollment restrictions
$createdObjects = @()

function Add-CreatedObject {
    param(
        [Parameter(Mandatory)] [string]$Platform,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Id
    )

    $normalizedPlatform = if ([string]::IsNullOrWhiteSpace($Platform)) { 'Unknown' } else { $Platform }
    $script:createdObjects += [PSCustomObject]@{
        platform = $normalizedPlatform
        type     = $Type
        name     = $Name
        id       = $Id
    }
}

function Show-CreatedObjectsSummary {
    param(
        [Parameter(Mandatory)] [array]$Objects
    )

    if (-not $Objects -or $Objects.Count -eq 0) {
        Write-Host "No objects were created in this run." -ForegroundColor Yellow
        return
    }

    $typeOrder = @('Policy','CustomConfig','Compliance','Script','CustomAttribute','EnrollmentRestriction','App')
    $typeLabels = @{
        Policy                = 'Policies'
        CustomConfig          = 'Custom Configs'
        Compliance            = 'Compliance Policies'
        Script                = 'Scripts'
        CustomAttribute       = 'Custom Attributes'
        EnrollmentRestriction = 'Enrollment Restrictions'
        App                   = 'Apps'
    }

    Write-Host ""
    Write-Host "Created objects summary (by platform):" -ForegroundColor Cyan

    foreach ($platformGroup in ($Objects | Group-Object platform | Sort-Object Name)) {
        Write-Host ""
        Write-Host ("{0}:" -f $platformGroup.Name) -ForegroundColor Cyan

        foreach ($type in $typeOrder) {
            $items = @($platformGroup.Group | Where-Object { $_.type -eq $type })
            if ($items.Count -eq 0) { continue }

            $label = $typeLabels[$type]
            Write-Host ("{0} ({1}):" -f $label, $items.Count) -ForegroundColor Magenta
            foreach ($item in ($items | Sort-Object name)) {
                Write-Host ("• {0} [{1}]" -f $item.name, $item.id)
            }
        }
    }
}

# set policy prefix (spacing appended automatically later)
$policyPrefix = "[intune-my-devices]"

# tenant ID (optional, can be specified via --tenant-id)
$tenantId = $null

# GUI-supplied manifest name filter (comma-separated, set via --names)
$filterNames = @()

# Target platform (defaults to macOS if not provided)
$selectedPlatform = 'macOS'

# Resolve repo root (script is now in repository root)
$repoRoot = $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction Continue}
if (-not $repoRoot) { Write-Error "Failed to resolve repository root; aborting."; exit 1 }

# Distributed manifests live under platform folders.
# Always include macOS when present; include Windows/iOS/Android only if folders exist.
$availablePlatformRoots = @{}
foreach ($platformFolder in @('macOS','Windows','iOS','Android')) {
    $candidateRoot = Join-Path $repoRoot $platformFolder
    if (Test-Path -LiteralPath $candidateRoot) {
        $availablePlatformRoots[$platformFolder] = $candidateRoot
    }
}
if ($availablePlatformRoots.Count -eq 0) {
    Write-Error "No platform folders found under repository root (expected one or more of: macOS, Windows, iOS, Android)."
    exit 1
}

# Active platform roots used for discovery/resolution (set after CLI parsing)
$platformRoots = @{}

$macOSRoot = $null

function Resolve-ArtifactPath {
    param(
        [Parameter(Mandatory)] [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $null }

    $normalized = $RelativePath.Trim().Replace('\\', '/')
    if ([System.IO.Path]::IsPathRooted($normalized)) {
        return $normalized
    }

    $candidatePrimary = Join-Path $repoRoot $normalized
    if (Test-Path -LiteralPath $candidatePrimary) {
        return $candidatePrimary
    }

    # Backward compatibility: manifests may still use platform-relative paths
    # like 'configurations/...', 'apps/...', 'scripts/...', etc.
    foreach ($platformRoot in $platformRoots.Values) {
        $platformFolderName = Split-Path -Path $platformRoot -Leaf
        if ($normalized -match "^(?:\./)?$([regex]::Escape($platformFolderName))/") {
            continue
        }
        $candidatePlatform = Join-Path $platformRoot $normalized
        if (Test-Path -LiteralPath $candidatePlatform) {
            return $candidatePlatform
        }
    }

    return $candidatePrimary
}

function Get-DefaultCreateGraphUri {
    param(
        [Parameter(Mandatory)] [string] $Type
    )

    switch ($Type) {
        'Policy'               { return 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' }
        'Compliance'           { return 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies' }
        'Script'               { return 'https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts' }
        'CustomAttribute'      { return 'https://graph.microsoft.com/beta/deviceManagement/deviceCustomAttributeShellScripts' }
        'CustomConfig'         { return 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations' }
        'EnrollmentRestriction'{ return 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations' }
        'Package'              { return 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' }
        'App'                  { return 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' }
        'LobApp'               { return 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' }
        default                { return $null }
    }
}

function Resolve-CreateGraphUri {
    param(
        [string] $ManifestCreateGraphUri,
        [Parameter(Mandatory)] [string] $Type
    )

    if (-not [string]::IsNullOrWhiteSpace($ManifestCreateGraphUri)) {
        return $ManifestCreateGraphUri.Trim()
    }

    return Get-DefaultCreateGraphUri -Type $Type
}


function Get-DistributedManifests {
    param(
        [Parameter(Mandatory)] [string] $BasePath
    )
    $xmlFiles = Get-ChildItem -Path $BasePath -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | Where-Object {
        try {
            $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
            $content -match '<(MacIntuneManifest|IntuneManifest)\b'
        } catch { $false }
    }
    $items = @()
    foreach ($file in $xmlFiles) {
        $content = $null; $xdoc = $null; $xmlRoot = $null
        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            if ($env:IMM_DEBUG -eq '1') { Write-Host "DEBUG: Loading XML '$($file.Name)' (length=$($content.Length))" -ForegroundColor DarkCyan }
            $xdoc = [System.Xml.Linq.XDocument]::Parse($content, [System.Xml.Linq.LoadOptions]::PreserveWhitespace)
            $xmlRoot = $xdoc.Root
            if ($env:IMM_DEBUG -eq '1') { Write-Host "DEBUG: Root object type: $([string]($xmlRoot.GetType().FullName))" -ForegroundColor DarkCyan; Write-Host "DEBUG: Root element name raw: '$($xmlRoot.Name)' local: '$($xmlRoot.Name.LocalName)'" -ForegroundColor DarkCyan }
            if (-not $xmlRoot) {
                Write-Warning "Skipping file (no root element): $($file.FullName)"
                continue
            }
        } catch {
            Write-Warning "Failed to parse XML: $($file.FullName) - $($_.Exception.Message)"
            continue
        }

        # Extract simple scalar elements
        $lookup = @{}
        foreach ($el in $xmlRoot.Elements()) { $lookup[$el.Name.LocalName] = $el.Value }

        $type = $lookup['Type']
        $name = $lookup['Name']
        $description = $lookup['Description']
        $platform = $lookup['Platform']; if (-not $platform) { $platform = 'macOS' }
        $category = $lookup['Category']
        $filePath = $lookup['SourceFile']
        $createGraphUriRaw = $lookup['CreateGraphUri']
        $settingsCountRaw = $lookup['SettingsCount']
        $settingsCount = 0
        [int]::TryParse($settingsCountRaw, [ref]$settingsCount) | Out-Null
        $createGraphUri = Resolve-CreateGraphUri -ManifestCreateGraphUri $createGraphUriRaw -Type $type

    if ($env:IMM_DEBUG -eq '1') { Write-Host "DEBUG: Elements found -> Type='$type'; Name='$name'; Category='$category'; SourceFile='$filePath'" -ForegroundColor Magenta }

        $obj = [PSCustomObject]@{
            type        = $type
            name        = $name
            description = $description
            platform    = $platform
            category    = $category
            filePath    = $filePath
            createGraphUri = $createGraphUri
        }

    switch ($type) {
            'Policy' { $obj | Add-Member -NotePropertyName settingCount -NotePropertyValue $settingsCount -Force }
            'EnrollmentRestriction' { $obj | Add-Member -NotePropertyName settingCount -NotePropertyValue $settingsCount -Force }
            'Script' {
        $scriptNode = $xmlRoot.Element('Script')
                if ($scriptNode) {
                    $runAs = ($scriptNode.Element('RunAsAccount')).Value
                    $blockExec = ($scriptNode.Element('BlockExecutionNotifications')).Value
                    $execFreq = ($scriptNode.Element('ExecutionFrequency')).Value
                    $retry = ($scriptNode.Element('RetryCount')).Value
                    if ($runAs) { $obj | Add-Member runAsAccount $runAs -Force }
                    if ($blockExec) { $obj | Add-Member blockExecutionNotifications ([bool]::Parse($blockExec)) -Force }
                    if ($execFreq) { $obj | Add-Member executionFrequency $execFreq -Force }
                    if ($retry) { $obj | Add-Member retryCount ([int]$retry) -Force }
                }
            }
            'CustomAttribute' {
        $customAttrNode = $xmlRoot.Element('CustomAttribute')
                if ($customAttrNode) {
                    $customAttrType = ($customAttrNode.Element('CustomAttributeType'))?.Value
                    if ($customAttrType) { $obj | Add-Member customAttributeType $customAttrType -Force }
                }
            }
            'Package' {
        $pkgNode = $xmlRoot.Element('Package')
                if ($pkgNode) {
                    foreach ($p in $pkgNode.Elements()) {
                        $propName = $p.Name.LocalName
                        $val = $p.Value
                        $mName = $propName.Substring(0,1).ToLower()+$propName.Substring(1)
                        $obj | Add-Member -NotePropertyName $mName -NotePropertyValue $val -Force
                    }
                    if (-not $obj.PSObject.Properties['fileName'] -and $obj.filePath) {
                        $obj | Add-Member -NotePropertyName fileName -NotePropertyValue ([IO.Path]::GetFileName($obj.filePath)) -Force
                    }
                }
            }
            'LobApp' {
        $pkgNode = $xmlRoot.Element('Package')
                if ($pkgNode) {
                    foreach ($p in $pkgNode.Elements()) {
                        $propName = $p.Name.LocalName
                        $val = $p.Value
                        $mName = $propName.Substring(0,1).ToLower()+$propName.Substring(1)
                        $obj | Add-Member -NotePropertyName $mName -NotePropertyValue $val -Force
                    }
                    if (-not $obj.PSObject.Properties['fileName'] -and $obj.filePath) {
                        $obj | Add-Member -NotePropertyName fileName -NotePropertyValue ([IO.Path]::GetFileName($obj.filePath)) -Force
                    }
                }
            }
        }
        $items += $obj
    }
    return ,$items
}

function Test-DistributedManifest {
    param([array]$Items)
    $errors = 0
    $createUriTypes = @('Policy','Compliance','Script','CustomAttribute','CustomConfig','EnrollmentRestriction','Package','App','LobApp')
    foreach ($item in $Items) {
        if (($createUriTypes -contains $item.type) -and [string]::IsNullOrWhiteSpace($item.createGraphUri)) {
            Write-Host ("{0} missing CreateGraphUri: {1}" -f $item.type, $item.name) -ForegroundColor Red
            $errors++
        }

        switch ($item.type) {
            'Policy' {
                foreach ($req in 'name','filePath') {
                    if (-not $item.$req) { Write-Host ("Policy missing {0}: {1}" -f $req, ($item | ConvertTo-Json -Compress)) -ForegroundColor Red; $errors++ }
                }
            }
            'Script' {
                foreach ($req in 'name','filePath','runAsAccount','blockExecutionNotifications','executionFrequency','retryCount') {
                    if ($null -eq $item.$req -or ($item.$req -is [string] -and [string]::IsNullOrWhiteSpace($item.$req))) { Write-Host ("Script missing {0}: {1}" -f $req, $item.name) -ForegroundColor Red; $errors++ }
                }
            }
            'Package' {
                foreach ($req in 'name','filePath','primaryBundleId','primaryBundleVersion','publisher','minimumSupportedOperatingSystem','ignoreVersionDetection') {
                    if (-not $item.$req) { Write-Host ("Package missing {0}: {1}" -f $req, $item.name) -ForegroundColor Red; $errors++ }
                }
                foreach ($opt in 'preInstallScript','postInstallScript') {
                    if ($item.PSObject.Properties.Name -contains $opt -and $item.$opt) {
                        $candidate = Resolve-ArtifactPath -RelativePath $item.$opt
                        if (-not (Test-Path -LiteralPath $candidate)) {
                            Write-Warning ("Package '{0}' references missing {1} file: {2}" -f $item.name, $opt, $item.$opt)
                        }
                    }
                }
            }
            'CustomAttribute' {
                foreach ($req in 'name','filePath','customAttributeType') {
                    if (-not $item.$req) { Write-Host ("CustomAttribute missing {0}: {1}" -f $req, $item.name) -ForegroundColor Red; $errors++ }
                }
                if ($item.filePath) {
                    $full = Resolve-ArtifactPath -RelativePath $item.filePath
                    if (-not (Test-Path -LiteralPath $full)) { Write-Warning ("CustomAttribute file missing: {0}" -f $item.filePath) }
                }
            }
            'CustomConfig' {
                foreach ($req in 'name','filePath') {
                    if (-not $item.$req) { Write-Host ("CustomConfig missing {0}: {1}" -f $req, $item.name) -ForegroundColor Red; $errors++ }
                }
                if ($item.filePath) {
                    $full = Resolve-ArtifactPath -RelativePath $item.filePath
                    if (-not (Test-Path -LiteralPath $full)) { Write-Warning ("CustomConfig file missing: {0}" -f $item.filePath) }
                }
            }
            'EnrollmentRestriction' {
                foreach ($req in 'name','filePath') {
                    if (-not $item.$req) { Write-Host ("EnrollmentRestriction missing {0}: {1}" -f $req, $item.name) -ForegroundColor Red; $errors++ }
                }
                if ($item.filePath) {
                    $full = Resolve-ArtifactPath -RelativePath $item.filePath
                    if (-not (Test-Path -LiteralPath $full)) { Write-Warning ("EnrollmentRestriction file missing: {0}" -f $item.filePath) }
                }
            }
        }
    }
    if ($errors -gt 0) { Write-Host "Validation completed with $errors issue(s)." -ForegroundColor Yellow } else { Write-Host "Validation passed with no issues." -ForegroundColor Green }
    $counts = $Items | Group-Object type | ForEach-Object { "{0}={1}" -f $_.Name, $_.Count } | Sort-Object
    Write-Host "Types summary: $(($counts -join ', '))" -ForegroundColor Cyan
}

function Test-BetaModule {
    param(
        [string]$ModuleName = 'Microsoft.Graph.Beta.Devices.CorporateManagement'
    )
    if (Get-Command -Name New-MgBetaDeviceAppManagementMobileApp -ErrorAction SilentlyContinue) { return $true }
    
    # Check if module is already loaded
    if (Get-Module -Name $ModuleName) {
        return $true
    }
    
    try {
        Import-Module $ModuleName -ErrorAction Stop -SkipEditionCheck | Out-Null
    } catch {
        Write-Host "Installing beta Graph module '$ModuleName'..." -ForegroundColor Yellow
        try {
            Install-Module $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Import-Module $ModuleName -ErrorAction Stop -SkipEditionCheck | Out-Null
        } catch {
            Write-Warning ("Failed to install/import {0}: {1}" -f $ModuleName, $_.Exception.Message)
            return $false
        }
    }
    return [bool](Get-Command -Name New-MgBetaDeviceAppManagementMobileApp -ErrorAction SilentlyContinue)
}

function Get-GroupIdByName {
    param([Parameter(Mandatory)][string]$DisplayName)
    try {
        $filter = [System.Uri]::EscapeDataString("displayName eq '$DisplayName'")
        $groupResults = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName"
        if ($resp.value) { $groupResults += $resp.value }
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            if ($resp.value) { $groupResults += $resp.value }
        }
        if ($groupResults.Count -eq 0) {
            Write-Host "✗ Could not find an Entra group named '$DisplayName'." -ForegroundColor Red
            return $null
        }
        if ($groupResults.Count -gt 1) { Write-Warning "Multiple groups matched '$DisplayName'; using first." }
        return $groupResults[0].id
    } catch {
        Write-Host "✗ Failed to resolve group '$DisplayName'.`n  $_" -ForegroundColor Red
        return $null
    }
}


# Parse CLI args for selective processing
$removeAll = $false
$assignGroupName = $null
$skipTerminalVerification = $false
$argsLower = $args | ForEach-Object { $_.ToLowerInvariant() }

# Check for help flag
if ($argsLower -contains '-h' -or $argsLower -contains '--help') {
    Write-Host "`nIntune My Devices Deployment Script" -ForegroundColor Cyan
    Write-Host "================================`n" -ForegroundColor Cyan
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  ./mainScript.ps1 [OPTIONS]`n"
    Write-Host "SCOPE SELECTORS (by default, all types are imported):" -ForegroundColor Yellow
    Write-Host "  --apps                Import only packages/applications"
    Write-Host "  --config              Import only configuration policies"
    Write-Host "  --compliance          Import only compliance policies"
    Write-Host "  --scripts             Import only shell scripts"
    Write-Host "  --custom-attributes   Import only custom attributes"
    Write-Host "  --enrollment          Import only enrollment restrictions`n"
    Write-Host "OPTIONAL FEATURES:" -ForegroundColor Yellow
    Write-Host "  --mde                 Include Microsoft Defender for Endpoint (macOS/mde/) folder content"
    Write-Host "  --show-all-scripts    Show all scripts during enumeration`n"
    Write-Host "MODIFICATION OPTIONS:" -ForegroundColor Yellow
    Write-Host "  --prefix `"VALUE`"      Set custom prefix for all created objects (default: '[intune-my-devices]')"
    Write-Host "  --assign-group `"NAME`" Assign newly created objects to specified Entra group"
    Write-Host "  --tenant-id `"GUID`"    Specify tenant ID for Microsoft Graph connection"
    Write-Host "  --apply               Actually create/update/delete Intune objects (default: dry-run preview)"
    Write-Host "  --remove-all          Delete all existing Intune objects with the configured prefix"
    Write-Host "  --platform `"VALUE`"    Target platform folder to deploy (macOS|Windows|iOS|Android). Default: macOS`n"
    Write-Host "HELP:" -ForegroundColor Yellow
    Write-Host "  -h, --help            Display this help message`n"
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  # Import everything with default prefix"
    Write-Host "  ./mainScript.ps1`n"
    Write-Host "  # Import only apps and assign to a group"
    Write-Host "  ./mainScript.ps1 --apps --assign-group `"All Managed Macs`"`n"
    Write-Host "  # Import config policies with custom prefix"
    Write-Host "  ./mainScript.ps1 --config --prefix `"[Production]`"`n"
    Write-Host "  # Connect to a specific tenant"
    Write-Host "  ./mainScript.ps1 --tenant-id `"12345678-1234-1234-1234-123456789012`"`n"
    Write-Host "  # Remove all objects with the default prefix"
    Write-Host "  ./mainScript.ps1 --remove-all`n"
    Write-Host "NOTE:" -ForegroundColor Yellow
    Write-Host "  This script defaults to DRY-RUN mode. Re-run with --apply to push changes to Intune."
    Write-Host "  If you specify any scope selector (--apps, --config, etc.), only those types will be imported."
    Write-Host "  If no selectors are provided, all types are imported by default.`n"
    return
}

if ($args.Count -gt 0) {
    $knownFlags = @('--apps','--config','--compliance','--scripts','--custom-attributes','--enrollment','--show-all-scripts','--remove-all','--mde','-mde','--apply','--prefix','--assign-group','--tenant-id','--names','--platform','--skip-terminal-verification','-h','--help')
    $valueFlags = @('--prefix','--assign-group','--tenant-id','--names','--platform')
    $unknownArgs = @(); $missingValueArgs = @()
    $idx = 0
    while ($idx -lt $args.Count) {
        $rawArg = $args[$idx]
        $normalized = $rawArg.ToLowerInvariant()
        $handled = $false

        if ($normalized -like '--prefix=*' -or $normalized -like '--assign-group=*' -or $normalized -like '--tenant-id=*' -or $normalized -like '--names=*' -or $normalized -like '--platform=*') {
            $handled = $true
        } elseif ($knownFlags -contains $normalized) {
            $handled = $true
            if ($valueFlags -contains $normalized -and $rawArg -notlike '--*=*') {
                if ($idx + 1 -lt $args.Count) {
                    $idx++  # skip the value token so it is not reprocessed
                } else {
                    $missingValueArgs += $rawArg
                }
            }
        }

        if (-not $handled) {
            $unknownArgs += $rawArg
        }
        $idx++
    }

    if ($unknownArgs.Count -gt 0 -or $missingValueArgs.Count -gt 0) {
        if ($unknownArgs.Count -gt 0) {
            Write-Host "Unknown option(s): $($unknownArgs -join ', ')." -ForegroundColor Red
        }
        if ($missingValueArgs.Count -gt 0) {
            Write-Host "Missing value for option(s): $($missingValueArgs -join ', ')." -ForegroundColor Red
        }
        Write-Host "Run ./mainScript.ps1 --help for usage." -ForegroundColor Yellow
        return
    }
}

if ($argsLower.Count -gt 0) {
    $importPolicies = $false; $importPackages = $false; $importScripts = $false; $importCompliance = $false; $importCustomAttrs = $false; $importEnrollmentRestrictions = $false
    if ($argsLower -contains '--apps') { $importPackages = $true }
    if ($argsLower -contains '--config') { $importPolicies = $true }
    if ($argsLower -contains '--compliance') { $importCompliance = $true }
    if ($argsLower -contains '--scripts' ) { $importScripts = $true }
    if ($argsLower -contains '--custom-attributes') { $importCustomAttrs = $true }
    if ($argsLower -contains '--enrollment') { $importEnrollmentRestrictions = $true }
    $showAllScripts = $false
    if ($argsLower -contains '--show-all-scripts') { $showAllScripts = $true }
    if ($argsLower -contains '--remove-all') { $removeAll = $true }
    if ($argsLower -contains '--skip-terminal-verification') { $skipTerminalVerification = $true }
    if ($argsLower -contains '--mde' -or $argsLower -contains '-mde') { $includeMde = $true }
    if ($argsLower -contains '--apply') { $applyChanges = $true }
    # Support both --param="Value" and --param "Value" forms
    for ($i = 0; $i -lt $args.Count; $i++) {
        $arg = $args[$i]

        # --prefix
        if ($arg -like '--prefix=*') {
            $value = $arg.Substring(9)
        } elseif ($arg -eq '--prefix' -and ($i + 1) -lt $args.Count) {
            $value = $args[$i + 1]
        } else {
            $value = $null
        }
        if ($null -ne $value) {
            $policyPrefix = $value.Trim('"')
        }

        # --assign-group
        if ($arg -like '--assign-group=*') {
            $value = $arg.Substring(15)
        } elseif ($arg -eq '--assign-group' -and ($i + 1) -lt $args.Count) {
            $value = $args[$i + 1]
        } else {
            $value = $null
        }
        if ($null -ne $value) {
            $assignGroupName = $value.Trim('"')
        }

        # --tenant-id
        if ($arg -like '--tenant-id=*') {
            $value = $arg.Substring(12)
        } elseif ($arg -eq '--tenant-id' -and ($i + 1) -lt $args.Count) {
            $value = $args[$i + 1]
        } else {
            $value = $null
        }
        if ($null -ne $value) {
            $tenantId = $value.Trim('"')
        }

        # --names  (GUI-supplied comma-separated manifest name filter)
        if ($arg -like '--names=*') {
            $value = $arg.Substring(8)
        } elseif ($arg -eq '--names' -and ($i + 1) -lt $args.Count) {
            $value = $args[$i + 1]
        } else {
            $value = $null
        }
        if ($null -ne $value) {
            $filterNames = $value.Trim('"') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }

        # --platform
        if ($arg -like '--platform=*') {
            $value = $arg.Substring(11)
        } elseif ($arg -eq '--platform' -and ($i + 1) -lt $args.Count) {
            $value = $args[$i + 1]
        } else {
            $value = $null
        }
        if ($null -ne $value) {
            $selectedPlatform = $value.Trim('"')
        }
    }
    if (-not ($importPolicies -or $importPackages -or $importScripts -or $importCompliance -or $importCustomAttrs -or $importEnrollmentRestrictions)) {
    Write-Warning "No valid selector provided (--apps, --config, --scripts, --custom-attributes, --enrollment). Defaulting to all."
        $importPolicies = $true; $importPackages = $true; $importScripts = $true; $importCompliance = $true; $importCustomAttrs = $true; $importEnrollmentRestrictions = $true
        $showAllScripts = $true
    } else {
        Write-Host ("Selection: configPolicies={0} compliance={1} packages={2} scripts={3} customAttributes={4} enrollmentRestrictions={5} showAllScripts={6} includeMde={7}" -f $importPolicies, $importCompliance, $importPackages, $importScripts, $importCustomAttrs, $importEnrollmentRestrictions, $showAllScripts, $includeMde) -ForegroundColor Cyan
    }
}

$platformMap = @{
    'macos'   = 'macOS'
    'windows' = 'Windows'
    'ios'     = 'iOS'
    'android' = 'Android'
}
$selectedPlatformKey = $selectedPlatform.ToLowerInvariant()
if (-not $platformMap.ContainsKey($selectedPlatformKey)) {
    Write-Error "Invalid --platform value '$selectedPlatform'. Valid values: macOS, Windows, iOS, Android."
    exit 1
}
$selectedPlatformCanonical = $platformMap[$selectedPlatformKey]
if (-not $availablePlatformRoots.ContainsKey($selectedPlatformCanonical)) {
    Write-Error "Selected platform folder '$selectedPlatformCanonical' does not exist in this repository."
    exit 1
}
$platformRoots = @{ $selectedPlatformCanonical = $availablePlatformRoots[$selectedPlatformCanonical] }
$macOSRoot = if ($selectedPlatformCanonical -eq 'macOS') { $availablePlatformRoots['macOS'] } else { $null }
Write-Host "Selected platform: $selectedPlatformCanonical" -ForegroundColor DarkGray

if ($policyPrefix -and ($policyPrefix[-1] -ne ' ')) {
    $policyPrefix += ' '
}

if ($applyChanges) {
    Write-Host "Mode: APPLY (Intune objects will be created/updated/deleted)." -ForegroundColor Green
} else {
    Write-Host "Mode: DRY-RUN (no changes will be made; pass --apply to commit)." -ForegroundColor Yellow
}

# Connect to Microsoft Graph (add apps scope + groups for assignments + scripts for shell scripts)
# Ensure Microsoft.Graph.Authentication module is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host "Microsoft Graph PowerShell SDK not found. Installing..." -ForegroundColor Yellow
    try {
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "Microsoft.Graph.Authentication installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "`nERROR: Failed to install Microsoft.Graph.Authentication module." -ForegroundColor Red
        Write-Host "Install it manually with:  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser" -ForegroundColor Yellow
        Write-Host "For details see: https://learn.microsoft.com/powershell/microsoftgraph/installation`n" -ForegroundColor Cyan
        exit 1
    }
}
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
} catch {
    Write-Host "`nERROR: Failed to load Microsoft.Graph.Authentication module." -ForegroundColor Red
    Write-Host "Try reinstalling:  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force" -ForegroundColor Yellow
    exit 1
}

$graphParams = @{
    Scopes = "DeviceManagementConfiguration.ReadWrite.All,DeviceManagementApps.ReadWrite.All,DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementScripts.ReadWrite.All,DeviceManagementServiceConfig.ReadWrite.All,Group.Read.All"
    NoWelcome = $true
}
if ($tenantId) {
    $graphParams['TenantId'] = $tenantId
    Write-Host "Connecting to Microsoft Graph with tenant ID: $tenantId" -ForegroundColor Cyan
}
Connect-MgGraph @graphParams

# Resolve the tenant ID we are actually connected to. This is used to substitute
# REPLACE_WITH_TENANT_ID placeholders in policy JSON (e.g. the OneDrive Known Folder
# Move silent opt-in) with the correct Entra tenant GUID before the policy is created.
$resolvedTenantId = $tenantId
if (-not $resolvedTenantId) {
    try { $resolvedTenantId = (Get-MgContext).TenantId } catch { $resolvedTenantId = $null }
}
if ($resolvedTenantId) {
    Write-Host "Resolved tenant ID for policy substitution: $resolvedTenantId" -ForegroundColor DarkGray
} else {
    Write-Warning "Could not resolve a tenant ID; policies using REPLACE_WITH_TENANT_ID will be skipped. Pass --tenant-id <GUID> to set it explicitly."
}

$resolvedGroupId = $null
if ($assignGroupName) {
    Write-Host "Validating assignment group '$assignGroupName'..." -ForegroundColor Cyan
    $resolvedGroupId = Get-GroupIdByName -DisplayName $assignGroupName
    if ($resolvedGroupId) {
        Write-Host "✓ Assignment group resolved (ID: $resolvedGroupId)." -ForegroundColor Green
    } else {
        Write-Host "No changes made because the group '$assignGroupName' does not exist (or you lack permission to read it)." -ForegroundColor Red
        Write-Host "Double-check the exact display name in Entra ID or rerun without --assign-group." -ForegroundColor Yellow
        return
    }
}

function Remove-IntunePrefixedContent {
    param(
        [string]$Prefix,
        [bool]$ApplyChanges = $false,
        [string]$Platform = 'macOS'
    )
    if (-not $Prefix) { Write-Error "Prefix is empty; refusing to continue."; return }
    Write-Host "Scanning Intune for $Platform artifacts beginning with prefix: '$Prefix'" -ForegroundColor Cyan

    if (-not $platformRoots.ContainsKey($Platform)) {
        Write-Error "Selected platform '$Platform' is not available in this repository."
        return
    }

    $platformManifestItems = @()
    foreach ($platformRoot in ($platformRoots.Values | Sort-Object)) {
        $platformManifestItems += Get-DistributedManifests -BasePath $platformRoot
    }
    if (-not $platformManifestItems -or $platformManifestItems.Count -eq 0) {
        Write-Warning "No manifests discovered for platform '$Platform'. Refusing to run --remove-all to avoid cross-platform deletions."
        return
    }

    $targetPolicyNames = @{}
    $targetDeviceConfigPolicyNames = @{}
    $targetFeatureUpdatePolicyNames = @{}
    $targetComplianceNames = @{}
    $targetCustomConfigNames = @{}
    $targetScriptNames = @{}
    $targetCustomAttributeNames = @{}
    $targetEnrollmentRestrictionNames = @{}
    $targetAppNames = @{}

    foreach ($m in $platformManifestItems) {
        $displayName = "$Prefix$($m.name)"
        switch ($m.type) {
            'Policy'               {
                if ($m.createGraphUri -and $m.createGraphUri -match '/deviceConfigurations(\?|$|/)') {
                    $targetDeviceConfigPolicyNames[$displayName] = $true
                } elseif ($m.createGraphUri -and $m.createGraphUri -match '/windowsFeatureUpdateProfiles(\?|$|/)') {
                    $targetFeatureUpdatePolicyNames[$displayName] = $true
                } else {
                    $targetPolicyNames[$displayName] = $true
                }
            }
            'Compliance'           { $targetComplianceNames[$displayName] = $true }
            'CustomConfig'         { $targetCustomConfigNames[$displayName] = $true }
            'Script'               { $targetScriptNames[$displayName] = $true }
            'CustomAttribute'      { $targetCustomAttributeNames[$displayName] = $true }
            'EnrollmentRestriction'{ $targetEnrollmentRestrictionNames[$displayName] = $true }
            'Package'              { $targetAppNames[$displayName] = $true }
            'App'                  { $targetAppNames[$displayName] = $true }
            'LobApp'               { $targetAppNames[$displayName] = $true }
        }
    }

    # Build OData filter string for macOS custom configuration deviceConfiguration lookup
    $escapedFilterDeviceConfigs  = [System.Uri]::EscapeDataString("startsWith(displayName,'$Prefix')")

    $policies = @(); $customConfigs = @(); $featureUpdatePolicies = @(); $compliancePolicies = @(); $enrollmentRestrictions = @(); $scripts = @(); $customAttrs = @(); $apps = @()
    
    # Configuration Policies - always use client-side filtering for reliability with special characters
    Write-Host "  Scanning configuration policies..." -ForegroundColor DarkGray -NoNewline
    try {
        $allPolicies = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name"
        $allPolicies += $resp.value
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            $allPolicies += $resp.value
        }
        if ($env:IMM_DEBUG -eq '1') {
            Write-Host "DEBUG: Retrieved $($allPolicies.Count) total policies for client-side filtering" -ForegroundColor DarkCyan
            Write-Host "DEBUG: Looking for prefix: '$Prefix' (length: $($Prefix.Length))" -ForegroundColor DarkCyan
        }
        if ($allPolicies) {
            $policies = $allPolicies | Where-Object {
                $_.name -and $_.name.StartsWith($Prefix) -and $targetPolicyNames.ContainsKey($_.name)
            }
            if ($env:IMM_DEBUG -eq '1') { Write-Host "DEBUG: Client-side filter matched $($policies.Count) policies with prefix '$Prefix'" -ForegroundColor DarkCyan }
        }
        Write-Host " done ($($allPolicies.Count) found)" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Failed to query configuration policies: $($_.Exception.Message)"
    }

    # Feature update policies live under windowsFeatureUpdateProfiles
    Write-Host "  Scanning feature update policies..." -ForegroundColor DarkGray -NoNewline
    try {
        $allFeatureUpdates = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles?`$select=id,displayName"
        if ($resp.value) { $allFeatureUpdates += $resp.value }
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            if ($resp.value) { $allFeatureUpdates += $resp.value }
        }
        if ($allFeatureUpdates) {
            $featureUpdatePolicies = $allFeatureUpdates | Where-Object {
                $_.displayName -and $_.displayName.StartsWith($Prefix) -and $targetFeatureUpdatePolicyNames.ContainsKey($_.displayName)
            }
        }
        Write-Host " done ($($allFeatureUpdates.Count) found)" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Failed to query feature update policies: $($_.Exception.Message)"
    }
    # Compliance Policies - use client-side filtering with pagination
    Write-Host "  Scanning compliance policies..." -ForegroundColor DarkGray -NoNewline
    try {
        $allCompliance = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$select=id,displayName"
        $allCompliance += $resp.value
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            $allCompliance += $resp.value
        }
        if ($allCompliance) {
            $compliancePolicies = $allCompliance | Where-Object {
                $_.displayName -and $_.displayName.StartsWith($Prefix) -and $targetComplianceNames.ContainsKey($_.displayName)
            }
        }
        Write-Host " done ($($allCompliance.Count) found)" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Failed to query compliance policies: $($_.Exception.Message)"
    }
    # macOS custom configuration (mobileconfig) live under deviceConfigurations with type macOSCustomConfiguration
    Write-Host "  Scanning custom configs (mobileconfig)..." -ForegroundColor DarkGray -NoNewline
    try {
        $dcUrl = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=$escapedFilterDeviceConfigs"
        $raw = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri $dcUrl
        if ($resp.value) { $raw += $resp.value }
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            if ($resp.value) { $raw += $resp.value }
        }
        if ($raw) {
            $customConfigs = $raw | Where-Object {
                $_.displayName -and $_.displayName.StartsWith($Prefix) -and (
                    $targetCustomConfigNames.ContainsKey($_.displayName) -or
                    $targetDeviceConfigPolicyNames.ContainsKey($_.displayName)
                )
            }
        }
        Write-Host " done" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Primary query for custom configs failed: $($_.Exception.Message) - attempting broad fallback"
        try {
            $raw = @(); $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
            if ($resp.value) { $raw += $resp.value }
            while ($resp.'@odata.nextLink') { $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'; if ($resp.value) { $raw += $resp.value } }
            if ($raw) {
                $customConfigs = $raw | Where-Object {
                    $_.displayName -and $_.displayName.StartsWith($Prefix) -and (
                        $targetCustomConfigNames.ContainsKey($_.displayName) -or
                        $targetDeviceConfigPolicyNames.ContainsKey($_.displayName)
                    )
                }
            }
        } catch { Write-Warning "Fallback deviceConfigurations query failed: $($_.Exception.Message)" }
    }
    
    # Scripts - use client-side filtering with pagination
    Write-Host "  Scanning scripts..." -ForegroundColor DarkGray -NoNewline
    try {
        $allScripts = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?`$select=id,displayName"
        $allScripts += $resp.value
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            $allScripts += $resp.value
        }
        if ($allScripts) {
            $scripts = $allScripts | Where-Object {
                $_.displayName -and $_.displayName.StartsWith($Prefix) -and $targetScriptNames.ContainsKey($_.displayName)
            }
        }
        Write-Host " done ($($allScripts.Count) found)" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Failed to query scripts: $($_.Exception.Message)"
    }
    
    # Custom Attributes - use client-side filtering with pagination
    Write-Host "  Scanning custom attributes..." -ForegroundColor DarkGray -NoNewline
    try {
        $allCustomAttrs = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCustomAttributeShellScripts?`$select=id,displayName"
        $allCustomAttrs += $resp.value
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            $allCustomAttrs += $resp.value
        }
        if ($allCustomAttrs) {
            $customAttrs = $allCustomAttrs | Where-Object {
                $_.displayName -and $_.displayName.StartsWith($Prefix) -and $targetCustomAttributeNames.ContainsKey($_.displayName)
            }
        }
        Write-Host " done ($($allCustomAttrs.Count) found)" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Failed to query custom attributes: $($_.Exception.Message)"
    }
    
    # Enrollment Restrictions - use client-side filtering with pagination
    Write-Host "  Scanning enrollment restrictions..." -ForegroundColor DarkGray -NoNewline
    try {
        $allEnrollRestrictions = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$select=id,displayName"
        $allEnrollRestrictions += $resp.value
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            $allEnrollRestrictions += $resp.value
        }
        if ($allEnrollRestrictions) {
            $enrollmentRestrictions = $allEnrollRestrictions | Where-Object {
                $_.displayName -and $_.displayName.StartsWith($Prefix) -and $targetEnrollmentRestrictionNames.ContainsKey($_.displayName)
            }
        }
        Write-Host " done ($($allEnrollRestrictions.Count) found)" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Failed to query enrollment restrictions: $($_.Exception.Message)"
    }
    
    # Apps - use client-side filtering with pagination
    Write-Host "  Scanning apps..." -ForegroundColor DarkGray -NoNewline
    try {
        $allApps = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$select=id,displayName"
        $allApps += $resp.value
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            $allApps += $resp.value
        }
        if ($allApps) {
            $apps = $allApps | Where-Object {
                $_.displayName -and $_.displayName.StartsWith($Prefix) -and $targetAppNames.ContainsKey($_.displayName)
            }
        }
        Write-Host " done ($($allApps.Count) found)" -ForegroundColor DarkGray
    } catch {
        Write-Host " failed" -ForegroundColor Red
        Write-Warning "Failed to query apps: $($_.Exception.Message)"
    }

    $pCount = ($policies | Measure-Object).Count
    $xCount = ($customConfigs | Measure-Object).Count
    $fuCount = ($featureUpdatePolicies | Measure-Object).Count
    $cCount = ($compliancePolicies | Measure-Object).Count
    $eCount = ($enrollmentRestrictions | Measure-Object).Count
    $sCount = ($scripts  | Measure-Object).Count
    $caCount = ($customAttrs | Measure-Object).Count
    $aCount = ($apps     | Measure-Object).Count
    if (($pCount + $xCount + $fuCount + $cCount + $eCount + $sCount + $caCount + $aCount) -eq 0) {
        Write-Host "No Intune objects found with prefix '$Prefix'. Nothing to remove." -ForegroundColor Yellow
        return
    }

    Write-Host ""; Write-Host "The following Intune objects would be deleted:" -ForegroundColor Yellow
    if ($pCount -gt 0) {
        Write-Host "Policies ($pCount):" -ForegroundColor Magenta
        $policies | ForEach-Object { Write-Host "  • $($_.name)  [$($_.id)]" }
    }
    if ($xCount -gt 0) {
        Write-Host "Custom Configs ($xCount):" -ForegroundColor Magenta
        $customConfigs | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($fuCount -gt 0) {
        Write-Host "Feature Update Policies ($fuCount):" -ForegroundColor Magenta
        $featureUpdatePolicies | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($cCount -gt 0) {
        Write-Host "Compliance Policies ($cCount):" -ForegroundColor Magenta
        $compliancePolicies | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($sCount -gt 0) {
        Write-Host "Scripts ($sCount):" -ForegroundColor Magenta
        $scripts | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($caCount -gt 0) {
        Write-Host "Custom Attributes ($caCount):" -ForegroundColor Magenta
        $customAttrs | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($eCount -gt 0) {
        Write-Host "Enrollment Restrictions ($eCount):" -ForegroundColor Magenta
        $enrollmentRestrictions | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($aCount -gt 0) {
        Write-Host "Apps ($aCount):" -ForegroundColor Magenta
        $apps | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }

    Write-Host "Summary: $pCount config policies, $xCount custom configs, $fuCount feature update policies, $cCount compliance policies, $eCount enrollment restrictions, $sCount scripts, $caCount custom attributes, $aCount apps will be permanently removed." -ForegroundColor Cyan

    if (-not $ApplyChanges) {
        Write-Host "[dry-run] Skipping deletion because --apply was not provided." -ForegroundColor Yellow
        return
    }

    if ($skipTerminalVerification) {
        Write-Host "Terminal confirmation skipped because the action was already confirmed by the GUI." -ForegroundColor DarkGray
    } else {
        $confirmation = Read-Host -Prompt "Type YES to confirm deletion or anything else to cancel"
        if ($confirmation -ne 'YES') { Write-Host "Deletion aborted by user." -ForegroundColor Yellow; return }
    }

    # Delete configuration policies
    foreach ($p in $policies) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)" | Out-Null
            Write-Host "Deleted policy: $($p.name)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete policy $($p.name): $($_.Exception.Message)" }
    }
    # Delete custom configs (deviceConfigurations)
    foreach ($cc in $customConfigs) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($cc.id)" | Out-Null
            Write-Host "Deleted custom config: $($cc.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete custom config $($cc.displayName): $($_.Exception.Message)" }
    }
    # Delete feature update policies
    foreach ($fu in $featureUpdatePolicies) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles/$($fu.id)" | Out-Null
            Write-Host "Deleted feature update policy: $($fu.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete feature update policy $($fu.displayName): $($_.Exception.Message)" }
    }
    # Delete compliance policies
    foreach ($cp in $compliancePolicies) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($cp.id)" | Out-Null
            Write-Host "Deleted compliance policy: $($cp.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete compliance policy $($cp.displayName): $($_.Exception.Message)" }
    }
    foreach ($s in $scripts) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts/$($s.id)" | Out-Null
            Write-Host "Deleted script: $($s.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete script $($s.displayName): $($_.Exception.Message)" }
    }
    foreach ($ca in $customAttrs) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCustomAttributeShellScripts/$($ca.id)" | Out-Null
            Write-Host "Deleted custom attribute: $($ca.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete custom attribute $($ca.displayName): $($_.Exception.Message)" }
    }
    foreach ($a in $apps) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($a.id)" | Out-Null
            Write-Host "Deleted app: $($a.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete app $($a.displayName): $($_.Exception.Message)" }
    }
    foreach ($er in $enrollmentRestrictions) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($er.id)" | Out-Null
            Write-Host "Deleted enrollment restriction: $($er.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete enrollment restriction $($er.displayName): $($_.Exception.Message)" }
    }
    Write-Host "Deletion complete." -ForegroundColor Cyan
}

if ($removeAll) {
    Remove-IntunePrefixedContent -Prefix $policyPrefix -ApplyChanges $applyChanges -Platform $selectedPlatformCanonical
    return
}

function Get-GroupIdByName {
    param([Parameter(Mandatory)][string]$DisplayName)
    try {
        $filter = [System.Uri]::EscapeDataString("displayName eq '$DisplayName'")
        $groupResults = @()
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName"
        if ($resp.value) { $groupResults += $resp.value }
        while ($resp.'@odata.nextLink') {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $resp.'@odata.nextLink'
            if ($resp.value) { $groupResults += $resp.value }
        }
        if ($groupResults.Count -eq 0) { Write-Error "Group not found: $DisplayName"; return $null }
        if ($groupResults.Count -gt 1) { Write-Warning "Multiple groups matched '$DisplayName'; using first." }
        return $groupResults[0].id
    } catch { Write-Error "Failed to resolve group '$DisplayName': $($_.Exception.Message)"; return $null }
}

$distributedItems = @()
foreach ($platformRoot in ($platformRoots.Values | Sort-Object)) {
    $distributedItems += Get-DistributedManifests -BasePath $platformRoot
}

# Enforce single-platform deployment per run.
$prePlatformFilterCount = $distributedItems.Count
$distributedItems = @($distributedItems | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.platform) -and $_.platform.Trim().ToLowerInvariant() -eq $selectedPlatformCanonical.ToLowerInvariant()
})
$platformFilteredOut = $prePlatformFilterCount - $distributedItems.Count
if ($platformFilteredOut -gt 0) {
    Write-Host "Excluded $platformFilteredOut manifest item(s) that do not match selected platform '$selectedPlatformCanonical'." -ForegroundColor DarkGray
}
if ($distributedItems.Count -eq 0) {
    Write-Error "No manifests found for selected platform '$selectedPlatformCanonical'."
    exit 1
}

# Always exclude 'exports/' folder content (output artifacts) regardless of switches
$preExportsCount = $distributedItems.Count
$distributedItems = $distributedItems | Where-Object { $_.filePath -notmatch '(^|/)exports/' }
$exportsRemoved = $preExportsCount - $distributedItems.Count
if ($exportsRemoved -gt 0) { Write-Host "Excluded $exportsRemoved manifest item(s) under exports/." -ForegroundColor DarkGray }

if (-not $includeMde) {
    $pre = $distributedItems.Count
    $distributedItems = $distributedItems | Where-Object { $_.filePath -notmatch '(^|/)(macOS/)?mde/' }
    $removed = $pre - $distributedItems.Count
    if ($removed -gt 0) { Write-Host "Excluded $removed macOS/mde/ manifest(s) (use --mde to include)." -ForegroundColor DarkGray }
} else {
    if (-not $macOSRoot) {
        Write-Error "--mde was specified but macOS folder was not found in the repository."
        exit 1
    }
    Write-Host "Including macOS/mde/ manifests (--mde specified)." -ForegroundColor DarkGray
    
    # Validate that the required MDE onboarding file exists
    $mdeOnboardingFile = Join-Path $macOSRoot "mde/cfg-mde-001-onboarding.mobileconfig"
    if (-not (Test-Path $mdeOnboardingFile)) {
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║  ERROR: Microsoft Defender for Endpoint onboarding file is missing!         ║" -ForegroundColor Red
        Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        Write-Host "The --mde flag requires the onboarding configuration file, but it was not found at:" -ForegroundColor Yellow
        Write-Host "  $mdeOnboardingFile" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "This file is organization-specific and must be downloaded from your Microsoft" -ForegroundColor Yellow
        Write-Host "Defender Portal. Each organization has a unique onboarding configuration." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To obtain your onboarding file:" -ForegroundColor White
        Write-Host "  1. Go to: https://security.microsoft.com" -ForegroundColor Cyan
        Write-Host "  2. Navigate to: Settings > Endpoints > Device management > Onboarding" -ForegroundColor Cyan
        Write-Host "  3. Select OS: macOS" -ForegroundColor Cyan
        Write-Host "  4. Select method: Mobile Device Management / Microsoft Intune" -ForegroundColor Cyan
        Write-Host "  5. Download the onboarding package" -ForegroundColor Cyan
        Write-Host "  6. Rename to: cfg-mde-001-onboarding.mobileconfig" -ForegroundColor Cyan
        Write-Host "  7. Place in: macOS/mde/ folder" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "For detailed instructions, see: macOS/mde/README.md" -ForegroundColor White
        Write-Host ""
        Write-Error "Deployment stopped. Cannot proceed without MDE onboarding file."
        exit 1
    }
    Write-Host "✓ MDE onboarding file found: cfg-mde-001-onboarding.mobileconfig" -ForegroundColor Green
}

# Apply GUI name filter if supplied via --names
if ($filterNames -and $filterNames.Count -gt 0) {
    $preName = $distributedItems.Count
    $distributedItems = $distributedItems | Where-Object { $filterNames -contains $_.name }
    Write-Host "GUI filter: limited to $($distributedItems.Count) of $preName manifests by name." -ForegroundColor DarkGray
}

if ($distributedItems.type -contains '' -or $distributedItems.type -contains $null) { Write-Error "One or more XML manifests invalid (missing Type)."; exit 1 }
Write-Host "Using distributed XML manifests ($($distributedItems.Count) items)." -ForegroundColor Cyan
Test-DistributedManifest -Items $distributedItems

function Invoke-macOSLobAppUpload() {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$SourceFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$displayName,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$Publisher,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String]$Description,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$primaryBundleId,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$primaryBundleVersion,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [hashtable[]]$includedApps,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]$minimumSupportedOperatingSystem,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [bool]$ignoreVersionDetection,
        [Parameter(Mandatory = $false)]
        [String]$preInstallScriptPath,
        [Parameter(Mandatory = $false)]
        [String]$postInstallScriptPath,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1,100)]
        [int]$ChunkSizeMB = 8,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$MobileAppsUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    )
    try {
        # Check if the file exists and has a .pkg extension (case-insensitive)
        if (!(Test-Path -LiteralPath $SourceFile) -or ([System.IO.Path]::GetExtension($SourceFile)).ToLowerInvariant() -ne '.pkg') {
            Write-Error "The provided path does not exist or is not a .pkg file."
            throw
        }
        
        # Warn if not connected to Microsoft Graph
        $mgContext = $null
        try { $mgContext = Get-MgContext -ErrorAction SilentlyContinue } catch {}
        if (-not $mgContext) {
            Write-Warning "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'DeviceManagementApps.ReadWrite.All' before running this function."
        }

        #Check if minimumSupportedOperatingSystem is provided. If not, default to v10_13
        if ($null -eq $minimumSupportedOperatingSystem) {
            $minimumSupportedOperatingSystem = @{ v10_13 = $true }
        }

    $mobileAppsBaseUri = $MobileAppsUri.TrimEnd('/')

    # Creating temp file name from Source File path
    $tempName = ([System.IO.Path]::GetFileNameWithoutExtension($SourceFile)) + [guid]::NewGuid().ToString() + "_temp.bin"
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($SourceFile), $tempName)
        $fileName = (Get-Item $SourceFile).Name

        #Creating Intune app body JSON data to pass to the service
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow
        $body = New-macOSAppBody -displayName $displayName -Publisher $Publisher -Description $Description -fileName $fileName -primaryBundleId $primaryBundleId -primaryBundleVersion $primaryBundleVersion -includedApps $includedApps -minimumSupportedOperatingSystem $minimumSupportedOperatingSystem -ignoreVersionDetection $ignoreVersionDetection -preInstallScriptPath $preInstallScriptPath -postInstallScriptPath $postInstallScriptPath 

        # Create the Intune application object in the service
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
        $mobileApp = Invoke-MgGraphRequest -Method POST -Uri $mobileAppsBaseUri -Body ($body | ConvertTo-Json -Depth 5) -ContentType "application/json"
        $mobileAppId = $mobileApp.id

        # Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
        $ContentVersion = Invoke-MgGraphRequest -Method POST -Uri "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSPkgApp/contentVersions" -Body '{}' -ContentType "application/json"
        $ContentVersionId = $ContentVersion.id

        # Encrypt file and get file information
        Write-Host "Encrypting the copy of file '$SourceFile'..." -ForegroundColor Yellow
        
        $encryptionInfo = EncryptFile $SourceFile $tempFile
        $Size = (Get-Item "$SourceFile").Length
        $EncrySize = (Get-Item "$tempFile").Length

        $ContentVersionFileBody = @{
            name          = $fileName
            size          = $Size
            sizeEncrypted = $EncrySize
            manifest      = $null
            isDependency  = $false
            "@odata.type" = "#microsoft.graph.mobileAppContentFile"
        }

        # Create a new file entry in Azure for the upload
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
        $ContentVersionFile = Invoke-MgGraphRequest -Method POST -Uri "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSPkgApp/contentVersions/$ContentVersionId/files" -Body ($ContentVersionFileBody | ConvertTo-Json) -ContentType "application/json"
        $ContentVersionFileId = $ContentVersionFile.id

        # Get the file URI for the upload
        $fileUri = "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSPkgApp/contentVersions/$contentVersionId/files/$contentVersionFileId"

        # Wait for the service to process the file upload request.
        Write-Host "Waiting for the service to process the file upload request..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "AzureStorageUriRequest"
        $sasUriRenewTime = $file.azureStorageUriExpirationDateTime.AddMinutes(-3)

        # Upload the content to Azure Storage.
        Write-Host "Uploading file to Azure Storage..." -f Yellow
    [UInt64]$BlockSizeMB = [UInt64]$ChunkSizeMB
    UploadFileToAzureStorage $file.azureStorageUri $sasUriRenewTime $tempFile $BlockSizeMB 

        Write-Host "Committing the file to the service..." -ForegroundColor Yellow
        $fileCommitUri = "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSPkgApp/contentVersions/$ContentVersionId/files/$ContentVersionFileId/commit"
        Invoke-MgGraphRequest -Method POST -Uri $fileCommitUri -Body ($encryptionInfo | ConvertTo-Json) -ContentType "application/json"

        # Wait for the service to process the commit file request.
        Write-Host "Waiting for the service to process the file commit request..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "CommitFile"

        # Commit the app.
        Write-Host "Committing the content version..." -ForegroundColor Yellow
        $params = @{
            "@odata.type"           = "#microsoft.graph.macOSPkgApp"
            committedContentVersion = "1"
        }
        
        Invoke-MgGraphRequest -Method PATCH -Uri "$mobileAppsBaseUri/$mobileAppId" -Body ($params | ConvertTo-Json) -ContentType "application/json"

        # Wait for the service to process the commit app request.
        Write-Host "Waiting for the service to process the app commit request..." -ForegroundColor Yellow

        $AppCheckAttempts = 25
        while ($AppCheckAttempts -gt 0) {
            $AppCheckAttempts--
            $AppStatus = Invoke-MgGraphRequest -Method GET -Uri "$mobileAppsBaseUri/$mobileAppId"
            if ($AppStatus.publishingState -eq "published") {
                Write-Host "Application created successfully." -ForegroundColor Green
                break
            }
            Start-Sleep -Seconds 3
        }

        if ($AppStatus.publishingState -ne "published" -and $AppStatus.publishingState -ne "processing") {
            Write-Host "Application '$displayName' has failed to upload to Intune." -ForegroundColor Red
            throw "Application '$displayName' has failed to upload to Intune."
        }
        else {
            Write-Host "Application '$displayName' has been successfully uploaded to Intune." -ForegroundColor Green
            $AppStatus | Format-List
        }
    }
    catch {
        Write-Host "Application '$displayName' has failed to upload to Intune." -ForegroundColor Red
        Write-Error "Aborting with exception: $($_.Exception.ToString())"
        throw $_
    }
    finally {
        Remove-Item -Path "$tempFile" -Force -ErrorAction SilentlyContinue
    }
    try { return (Invoke-MgGraphRequest -Method GET -Uri "$mobileAppsBaseUri/$mobileAppId") } catch { }
}

####################################################
# Function to upload a macOS Line of Business app (macOSLobApp) to Intune
# This uses the correct #microsoft.graph.macOSLobApp type with bundleId, buildNumber, childApps
function Invoke-MacOSLobAppUploadReal {
    param(
        [Parameter(Mandatory = $true)] [string]$SourceFile,
        [Parameter(Mandatory = $true)] [string]$displayName,
        [Parameter(Mandatory = $true)] [string]$Description,
        [Parameter(Mandatory = $true)] [string]$Publisher,
        [Parameter(Mandatory = $true)] [string]$BundleId,
        [Parameter(Mandatory = $true)] [string]$BuildNumber,
        [Parameter(Mandatory = $false)] [string]$VersionNumber = "",
        [Parameter(Mandatory = $false)] [hashtable]$MinimumSupportedOperatingSystem = @{ "v14_0" = $true },
        [Parameter(Mandatory = $false)] [bool]$IgnoreVersionDetection = $true,
        [Parameter(Mandatory = $false)] [bool]$InstallAsManaged = $true,
        [Parameter(Mandatory = $false)] [int64]$ChunkSizeMB = 6,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [string]$MobileAppsUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    )

    $mobileAppId = $null
    $mobileAppsBaseUri = $MobileAppsUri.TrimEnd('/')
    $tempFile = [System.IO.Path]::GetTempFileName()
    $fileName = [System.IO.Path]::GetFileName($SourceFile)

    try {
        # Build the macOSLobApp body
        $appBody = @{
            "@odata.type"                    = "#microsoft.graph.macOSLobApp"
            displayName                      = $displayName
            description                      = $Description
            publisher                        = $Publisher
            fileName                         = $fileName
            bundleId                         = $BundleId
            buildNumber                      = $BuildNumber
            versionNumber                    = $VersionNumber
            childApps                        = @(
                @{
                    bundleId      = $BundleId
                    buildNumber   = $BuildNumber
                    versionNumber = "0.0"
                }
            )
            installAsManaged                 = $InstallAsManaged
            ignoreVersionDetection           = $IgnoreVersionDetection
            minimumSupportedOperatingSystem  = $MinimumSupportedOperatingSystem
            md5Hash                          = @()
            md5HashChunkSize                 = 0
            isFeatured                       = $false
            categories                       = @()
            roleScopeTagIds                  = @()
            informationUrl                   = ""
            privacyInformationUrl            = ""
            developer                        = ""
            notes                            = ""
            owner                            = ""
        }

        Write-Host "Creating application in Intune: $displayName" -ForegroundColor Yellow
        $mobileApp = Invoke-MgGraphRequest -Method POST -Uri $mobileAppsBaseUri -Body ($appBody | ConvertTo-Json -Depth 5) -ContentType "application/json"
        $mobileAppId = $mobileApp.id
        Write-Host "App created with ID: $mobileAppId" -ForegroundColor Green

        # Create content version
        Write-Host "Creating content version..." -ForegroundColor Yellow
        $contentVersion = Invoke-MgGraphRequest -Method POST -Uri "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSLobApp/contentVersions" -Body '{}' -ContentType "application/json"
        $ContentVersionId = $contentVersion.id
        Write-Host "Content version ID: $ContentVersionId" -ForegroundColor Green

        # Encrypt the file
        Write-Host "Encrypting file..." -ForegroundColor Yellow
        $encryptionInfo = EncryptFile $SourceFile $tempFile
        $Size = (Get-Item $SourceFile).Length
        $EncrySize = (Get-Item $tempFile).Length

        # Create file entry in content version
        Write-Host "Creating file entry..." -ForegroundColor Yellow
        $fileBody = @{
            "@odata.type" = "#microsoft.graph.mobileAppContentFile"
            name          = $fileName
            size          = $Size
            sizeEncrypted = $EncrySize
            manifest      = $null
            isDependency  = $false
        }
        $fileResult = Invoke-MgGraphRequest -Method POST -Uri "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSLobApp/contentVersions/$ContentVersionId/files" -Body ($fileBody | ConvertTo-Json) -ContentType "application/json"
        $ContentVersionFileId = $fileResult.id
        Write-Host "File entry ID: $ContentVersionFileId" -ForegroundColor Green

        # Wait for Azure Storage URI
        Write-Host "Waiting for Azure Storage URI..." -ForegroundColor Yellow
        $fileUri = "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSLobApp/contentVersions/$ContentVersionId/files/$ContentVersionFileId"
        $file = WaitForFileProcessing $fileUri "AzureStorageUriRequest"
        $sasUriRenewTime = (Get-Date $file.azureStorageUriExpirationDateTime).AddMinutes(-3)

        # Upload file to Azure Storage
        Write-Host "Uploading file to Azure Storage..." -ForegroundColor Yellow
        [UInt64]$BlockSizeMB = [UInt64]$ChunkSizeMB
        UploadFileToAzureStorage $file.azureStorageUri $sasUriRenewTime $tempFile $BlockSizeMB $mobileAppId $ContentVersionId $ContentVersionFileId $mobileAppsBaseUri

        # Commit the file
        Write-Host "Committing the file..." -ForegroundColor Yellow
        Invoke-MgGraphRequest -Method POST -Uri "$fileUri/commit" -Body ($encryptionInfo | ConvertTo-Json) -ContentType "application/json"

        # Wait for the service to process the commit
        Write-Host "Waiting for file commit processing..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "CommitFile"

        # Commit the content version to the app
        Write-Host "Committing content version to app..." -ForegroundColor Yellow
        $commitBody = @{
            "@odata.type"           = "#microsoft.graph.macOSLobApp"
            committedContentVersion = "1"
        }
        Invoke-MgGraphRequest -Method PATCH -Uri "$mobileAppsBaseUri/$mobileAppId" -Body ($commitBody | ConvertTo-Json) -ContentType "application/json"

        # Wait for publish
        Write-Host "Waiting for app to be published..." -ForegroundColor Yellow
        $AppCheckAttempts = 25
        while ($AppCheckAttempts -gt 0) {
            $AppCheckAttempts--
            $AppStatus = Invoke-MgGraphRequest -Method GET -Uri "$mobileAppsBaseUri/$mobileAppId"
            if ($AppStatus.publishingState -eq "published") {
                Write-Host "Application created successfully." -ForegroundColor Green
                break
            }
            Start-Sleep -Seconds 3
        }

        if ($AppStatus.publishingState -ne "published" -and $AppStatus.publishingState -ne "processing") {
            Write-Host "Application '$displayName' has failed to upload to Intune." -ForegroundColor Red
            throw "Application '$displayName' has failed to upload to Intune."
        }
        else {
            Write-Host "Application '$displayName' has been successfully uploaded to Intune." -ForegroundColor Green
            $AppStatus | Format-List
        }
    }
    catch {
        Write-Host "Application '$displayName' has failed to upload to Intune." -ForegroundColor Red
        Write-Error "Aborting with exception: $($_.Exception.ToString())"
        throw $_
    }
    finally {
        Remove-Item -Path "$tempFile" -Force -ErrorAction SilentlyContinue
    }
    try { return (Invoke-MgGraphRequest -Method GET -Uri "$mobileAppsBaseUri/$mobileAppId") } catch { }
}

####################################################
# Function that uploads a source file chunk to the Intune Service SAS URI location.
function UploadAzureStorageChunk($sasUri, $id, $body) {
    $uri = "$sasUri&comp=block&blockid=$id"
    $request = "PUT $uri"

    $headers = @{
        "x-ms-blob-type" = "BlockBlob"
        "Content-Type"   = "application/octet-stream"
        "Connection"     = "Keep-Alive"
        "Content-Length" = $body.Length
        "Accept"         = "*/*"
    }

    try {
        Invoke-WebRequest -Headers $headers -Uri $uri -Method Put -Body $body -RetryIntervalSec 2 -MaximumRetryCount 300 
    }
    catch {
        Write-Host -ForegroundColor Red $request
        Write-Host -ForegroundColor Red $_.Exception.Message
        throw
    }
}

####################################################
# Function that takes all the chunk ids and joins them back together to recreate the file
function FinalizeAzureStorageUpload($sasUri, $ids) {
    $uri = "$sasUri&comp=blocklist"
    $request = "PUT $uri"

    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
    foreach ($id in $ids) {
        $xml += "<Latest>$id</Latest>"
    }
    $xml += '</BlockList>'

    if ($logRequestUris) { Write-Host $request; }
    if ($logContent) { Write-Host -ForegroundColor Gray $xml; }

    $headers = @{
        "Content-Type" = "text/plain"
    }

    try {
        Invoke-WebRequest $uri -Method Put -Body $xml -Headers $headers
    }
    catch {
        Write-Host -ForegroundColor Red $request
        Write-Host -ForegroundColor Red $_.Exception.Message
        throw
    }
}

####################################################
# Function that splits the source file into chunks and calls the upload to the Intune Service SAS URI location, and finalizes the upload
function UploadFileToAzureStorage($sasUri, $sasUriRenewTime, $filepath, $blockSizeMB, $mobileAppId, $ContentVersionId, $ContentVersionFileId, $mobileAppsUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps') {
    # Chunk size in MiB
    $chunkSizeInBytes = 1024 * 1024 * $blockSizeMB
        $mobileAppsBaseUri = $mobileAppsUri
        $mobileAppsBaseUri = $mobileAppsBaseUri.TrimEnd('/')
        $fileUri = "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSLobApp/contentVersions/$ContentVersionId/files/$ContentVersionFileId"    # Read the whole file and find the total chunks.
    $fileStream = [System.IO.File]::OpenRead($filepath)
    $chunks = [Math]::Ceiling($fileStream.Length / $chunkSizeInBytes)

    # Upload each chunk.
    $ids = New-Object System.Collections.ArrayList
    $cc = 1
    $chunk = 0
    while ($fileStream.Position -lt $fileStream.Length) {
        $id = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunk.ToString("0000")))
        $ids.Add($id) > $null

        $size = [Math]::Min($chunkSizeInBytes, $fileStream.Length - $fileStream.Position)
        $body = New-Object byte[] $size
        $fileStream.Read($body, 0, $size) > $null

    Write-Host "Uploading chunk $cc of $chunks" -ForegroundColor Cyan
        $cc++

        UploadAzureStorageChunk $sasUri $id $body | Out-Null
        $chunk++

        # Renew the SAS URI if it is about to expire.
        if ((Get-Date).ToUniversalTime() -ge $sasUriRenewTime) {
            Write-Host "Renewing the SAS URI for the file upload..." -ForegroundColor Yellow
            Invoke-MgGraphRequest -Method POST -Uri "$mobileAppsBaseUri/$mobileAppId/microsoft.graph.macOSLobApp/contentVersions/$ContentVersionId/files/$ContentVersionFileId/renewUpload" -ContentType "application/json"
            $file = WaitForFileProcessing $fileUri "AzureStorageUriRenewal"
            $sasUri = $file.azureStorageUri
            $sasUriRenewTime = $file.azureStorageUriExpirationDateTime.AddMinutes(-3)
            Write-Host "New SAS Uri renewal time: $sasUriRenewTime" -ForegroundColor Yellow
        }
    }

    $fileStream.Close()

    # Finalize the upload.
    Write-Host "Finalizing file upload..." -ForegroundColor Yellow
    FinalizeAzureStorageUpload $sasUri $ids | Out-Null
}

####################################################
# Function to generate encryption key
function GenerateKey {
    try {
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aesProvider = New-Object System.Security.Cryptography.AesCryptoServiceProvider
        $aesProvider.GenerateKey()
        $aesProvider.Key
    }
    finally {
        if ($null -ne $aesProvider) { $aesProvider.Dispose(); }
        if ($null -ne $aes) { $aes.Dispose(); }
    }
}

####################################################
# Function to generate HMAC key
function GenerateIV {
    try {
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.IV
    }
    finally {
        if ($null -ne $aes) { $aes.Dispose(); }
    }
}

####################################################
# Function to create the encrypted target file compute HMAC value, and return the HMAC value
function EncryptFileWithIV($sourceFile, $targetFile, $encryptionKey, $hmacKey, $initializationVector) {
    $bufferBlockSize = 1024 * 4
    $computedMac = $null

    try {
        $aes = [System.Security.Cryptography.Aes]::Create()
        $hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256
        $hmacSha256.Key = $hmacKey
        $hmacLength = $hmacSha256.HashSize / 8

        $buffer = New-Object byte[] $bufferBlockSize
        $bytesRead = 0

        $targetStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $targetStream.Write($buffer, 0, $hmacLength + $initializationVector.Length)

        try {
            $encryptor = $aes.CreateEncryptor($encryptionKey, $initializationVector)
            $sourceStream = [System.IO.File]::Open($sourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            $cryptoStream = New-Object System.Security.Cryptography.CryptoStream -ArgumentList @($targetStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)

            $targetStream = $null
            while (($bytesRead = $sourceStream.Read($buffer, 0, $bufferBlockSize)) -gt 0) {
                $cryptoStream.Write($buffer, 0, $bytesRead)
                $cryptoStream.Flush()
            }
            $cryptoStream.FlushFinalBlock()
        }
        finally {
            if ($null -ne $cryptoStream) { $cryptoStream.Dispose(); }
            if ($null -ne $sourceStream) { $sourceStream.Dispose(); }
            if ($null -ne $encryptor) { $encryptor.Dispose(); }
        }

        try {
            $finalStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
            $finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null
            $finalStream.Write($initializationVector, 0, $initializationVector.Length)
            $finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null
            $hmac = $hmacSha256.ComputeHash($finalStream)
            $computedMac = $hmac
            $finalStream.Seek(0, [System.IO.SeekOrigin]::Begin) > $null
            $finalStream.Write($hmac, 0, $hmac.Length)
        }
        finally {
            if ($null -ne $finalStream) { $finalStream.Dispose(); }
        }
    }
    finally {
        if ($null -ne $targetStream) { $targetStream.Dispose(); }
        if ($null -ne $aes) { $aes.Dispose(); }
    }

    $computedMac
}

####################################################
# Function to encrypt file and return encryption info
function EncryptFile($sourceFile, $targetFile) {
    $encryptionKey = GenerateKey
    $hmacKey = GenerateKey
    $initializationVector = GenerateIV

    # Create the encrypted target file and compute the HMAC value.
    $mac = EncryptFileWithIV $sourceFile $targetFile $encryptionKey $hmacKey $initializationVector

    # Compute the SHA256 hash of the source file and convert the result to bytes.
    $fileDigest = (Get-FileHash $sourceFile -Algorithm SHA256).Hash
    $fileDigestBytes = New-Object byte[] ($fileDigest.Length / 2)
    for ($i = 0; $i -lt $fileDigest.Length; $i += 2) {
        $fileDigestBytes[$i / 2] = [System.Convert]::ToByte($fileDigest.Substring($i, 2), 16)
    }

    # Return an object that will serialize correctly to the file commit Graph API.
    $encryptionInfo = @{}
    $encryptionInfo.encryptionKey = [System.Convert]::ToBase64String($encryptionKey)
    $encryptionInfo.macKey = [System.Convert]::ToBase64String($hmacKey)
    $encryptionInfo.initializationVector = [System.Convert]::ToBase64String($initializationVector)
    $encryptionInfo.mac = [System.Convert]::ToBase64String($mac)
    $encryptionInfo.profileIdentifier = "ProfileVersion1"
    $encryptionInfo.fileDigest = [System.Convert]::ToBase64String($fileDigestBytes)
    $encryptionInfo.fileDigestAlgorithm = "SHA256"

    $fileEncryptionInfo = @{}
    $fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo
    $fileEncryptionInfo
}

####################################################
# Function to wait for file processing to complete by polling the file upload state
function WaitForFileProcessing($fileUri, $stage) {
    $attempts = 120
    $waitTimeInSeconds = 2
    $successState = "$($stage)Success"
    $renewalSuccessState = "$($stage)RenewalSuccess"
    $renewalPendingState = "$($stage)RenewalPending"
    $pendingState = "$($stage)Pending"

    $file = $null
    while ($attempts -gt 0) {
        $file = Invoke-MgGraphRequest -Method GET -Uri $fileUri
        if ($file.uploadState -eq $successState -or $file.uploadState -eq $renewalSuccessState -or $file.uploadState -eq $renewalPendingState) {
            break
        }
        elseif ($file.uploadState -ne $pendingState -and $file.uploadState -ne $renewalPendingState) {
            throw "File upload state is not success: $($file.uploadState)"
        }

        Start-Sleep $waitTimeInSeconds
        $attempts--
    }

    if ($null -eq $file) {
        throw "File request did not complete in the allotted time."
    }
    $file
}

####################################################

#Function to encode the pre and post install scripts in base64
function Convert-ScriptToBase64($scriptPath) {
    if (-not $scriptPath) { return $null }
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script path not found: $scriptPath"
    }
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($script)
    $encoded = [System.Convert]::ToBase64String($bytes)
    return $encoded
}

####################################################
# Function to generate body for Intune mobileapp
function New-macOSAppBody() {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$displayName,
        [Parameter(Mandatory = $true)]
        [string]$Publisher,
        [Parameter(Mandatory = $false)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$fileName,
        [Parameter(Mandatory = $true)]
        [string]$primaryBundleId,
        [Parameter(Mandatory = $true)]
        [string]$primaryBundleVersion,
        [Parameter(Mandatory = $true)]
        [hashtable[]]$includedApps,
        [Parameter(Mandatory = $false)]
        [hashtable]$minimumSupportedOperatingSystem,
        [Parameter(Mandatory = $true)]
        [bool]$ignoreVersionDetection,
        [Parameter(Mandatory = $false)]
        [string]$preInstallScriptPath,
        [Parameter(Mandatory = $false)]
        [string]$postInstallScriptPath
    )

    $body = @{ "@odata.type" = "#microsoft.graph.macOSPkgApp" }
    $body.isFeatured = $false
    $body.categories = @()
    $body.displayName = $displayName
    $body.publisher = $publisher
    $body.description = $description
    $body.fileName = $fileName
    $body.informationUrl = ""
    $body.privacyInformationUrl = ""
    $body.developer = ""
    $body.notes = ""
    $body.owner = ""
    $body.primaryBundleId = $primaryBundleId
    $body.primaryBundleVersion = $primaryBundleVersion
    $body.includedApps = $includedApps
    $body.ignoreVersionDetection = $ignoreVersionDetection

    if ($null -eq $minimumSupportedOperatingSystem) {
        $body.minimumSupportedOperatingSystem = @{ v10_13 = $true }
    }
    else {
        $body.minimumSupportedOperatingSystem = $minimumSupportedOperatingSystem
    }

    # Only include scripts if they exist
    if ($preInstallScriptPath -and (Test-Path $preInstallScriptPath)) {
        $body.preInstallScript = @{
            scriptContent = Convert-ScriptToBase64($preInstallScriptPath)
        }
    }

    if ($postInstallScriptPath -and (Test-Path $postInstallScriptPath)) {
        $body.postInstallScript = @{
            scriptContent = Convert-ScriptToBase64($postInstallScriptPath)
        }
    }
    
    return $body
}

function Get-MissingReusableSettingIdsFromErrorMessage {
    param(
        [string]$Message
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { return @() }
    # Backend responses vary in spacing/casing; accept broader patterns.
    if ($Message -notmatch '(?i)Reusable\s+Settings\s+are\s+not\s+found') { return @() }

    $ids = [regex]::Matches($Message, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') |
        ForEach-Object { $_.Value } |
        Select-Object -Unique
    return @($ids)
}

function Remove-SettingsWithReusableReferenceIds {
    param(
        [Parameter(Mandatory)] [object]$PolicyObject,
        [Parameter(Mandatory)] [string[]]$ReferenceIds
    )

    $removed = 0
    $filtered = @()
    $settings = @($PolicyObject.settings)

    foreach ($setting in $settings) {
        $settingJson = ConvertTo-Json -InputObject $setting -Depth 30 -Compress
        $containsMissingId = $false
        foreach ($id in $ReferenceIds) {
            if ($settingJson -match [regex]::Escape($id)) {
                $containsMissingId = $true
                break
            }
        }

        if ($containsMissingId) {
            $removed++
        } else {
            $filtered += $setting
        }
    }

    $PolicyObject.settings = $filtered
    if ($PolicyObject.PSObject.Properties.Name -contains 'settingCount') {
        $PolicyObject.settingCount = @($filtered).Count
    }

    return [PSCustomObject]@{
        Policy  = $PolicyObject
        Removed = $removed
    }
}


# Enumerate policies
if ($importPolicies) {
    $createdPolicyIds = @()
    $createdPolicyDeviceConfigIds = @()
    $createdFeatureUpdateProfileIds = @()
    $policies = $distributedItems | Where-Object { $_.type -eq 'Policy' }

    Write-Host "Found $($policies.Count) policies:`n" -ForegroundColor Cyan

    foreach ($p in $policies) {
        $policyPath = Resolve-ArtifactPath -RelativePath $p.filePath
        $exists = Test-Path -LiteralPath $policyPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }

        $desc = $p.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0, 137) + '...' }

        Write-Host "• $($p.name)" -ForegroundColor Yellow
        Write-Host "  - Category: $($p.category); Platform: $($p.platform); Settings: $($p.settingCount)"
        Write-Host "  - Path: $($p.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }

        # import policy into Intune
        try {
            $policyContentJson = Get-Content -LiteralPath $policyPath -Raw
            $policyContent = ConvertFrom-Json -InputObject $policyContentJson -Depth 20
                # Override payload display name with XML manifest <Name> to keep a single source of truth.
                $resolvedPolicyName = if ($policyPrefix) { $policyPrefix + $p.name } else { $p.name }
                if ($policyContent.PSObject.Properties.Name -contains 'name') {
                    $policyContent.name = $resolvedPolicyName
                } elseif ($policyContent.PSObject.Properties.Name -contains 'displayName') {
                    $policyContent.displayName = $resolvedPolicyName
                } else {
                    $policyContent | Add-Member -NotePropertyName displayName -NotePropertyValue $resolvedPolicyName -Force
                }

                $policyDisplayName = if ($policyContent.PSObject.Properties.Name -contains 'name') {
                    $policyContent.name
                } elseif ($policyContent.PSObject.Properties.Name -contains 'displayName') {
                    $policyContent.displayName
                } else {
                    $resolvedPolicyName
                }

                $policyContentJson = ConvertTo-Json -InputObject $policyContent -Depth 20

                # Substitute the tenant ID placeholder with the tenant we are connected to.
                # Used by settings such as the OneDrive Known Folder Move silent opt-in, which
                # require the literal Entra tenant GUID. Intune-native tokens like {{mail}} are
                # intentionally left untouched - Intune resolves those per-user at deployment.
                if ($policyContentJson -match 'REPLACE_WITH_TENANT_ID') {
                    if ($resolvedTenantId) {
                        $policyContentJson = $policyContentJson.Replace('REPLACE_WITH_TENANT_ID', $resolvedTenantId)
                        Write-Host "  - Substituted REPLACE_WITH_TENANT_ID with tenant ID '$resolvedTenantId'." -ForegroundColor DarkGray
                    } else {
                        Write-Warning "Policy '$($p.name)' contains REPLACE_WITH_TENANT_ID but no tenant ID could be resolved; skipping it. Re-run with --tenant-id <GUID>."
                        Write-Host ""
                        continue
                    }
                }

            if (-not $applyChanges) {
                Write-Host "  - [dry-run] Would create configuration policy '$policyDisplayName'." -ForegroundColor DarkGray
            } else {
                # create policy with json content
                $policyImportResults = $null
                try {
                    $policyImportResults = Invoke-MgGraphRequest -Method POST -Uri $p.createGraphUri -Body $policyContentJson
                } catch {
                    $errorParts = @(
                        $_.ErrorDetails.Message,
                        $_.Exception.Message,
                        ($_ | Out-String)
                    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $errorMessage = ($errorParts -join "`n")
                    $missingReusableIds = Get-MissingReusableSettingIdsFromErrorMessage -Message $errorMessage

                    if (@($missingReusableIds).Count -gt 0) {
                        $retryPolicyObject = ConvertFrom-Json -InputObject $policyContentJson -Depth 30
                        $sanitized = Remove-SettingsWithReusableReferenceIds -PolicyObject $retryPolicyObject -ReferenceIds $missingReusableIds

                        if ($sanitized.Removed -gt 0) {
                            Write-Warning "  - Removed $($sanitized.Removed) setting(s) with missing reusable reference ID(s): $($missingReusableIds -join ', '). Retrying policy creation."
                            $retryJson = ConvertTo-Json -InputObject $sanitized.Policy -Depth 30
                            $policyImportResults = Invoke-MgGraphRequest -Method POST -Uri $p.createGraphUri -Body $retryJson
                        } else {
                            throw
                        }
                    } else {
                        throw
                    }
                }

                if ($policyImportResults) {
                    $resultName = if ($policyImportResults.PSObject.Properties.Name -contains 'name') {
                        $policyImportResults.name
                    } elseif ($policyImportResults.PSObject.Properties.Name -contains 'displayName') {
                        $policyImportResults.displayName
                    } else {
                        $policyDisplayName
                    }
                    Write-Host "  - Policy $resultName imported successfully with ID: $($policyImportResults.id)" -ForegroundColor Green
                    if ($p.createGraphUri -and $p.createGraphUri -match '/deviceConfigurations(\?|$|/)') {
                        # Some Windows policy payloads (for example update rings) are created in deviceConfigurations
                        # and must be assigned through the deviceConfigurations assignment endpoint.
                        $createdDeviceConfigIds += $policyImportResults.id
                        $createdPolicyDeviceConfigIds += $policyImportResults.id
                    } elseif ($p.createGraphUri -and $p.createGraphUri -match '/windowsFeatureUpdateProfiles(\?|$|/)') {
                        # Windows feature update profiles are created and assigned via windowsFeatureUpdateProfiles.
                        $createdFeatureUpdateProfileIds += $policyImportResults.id
                    } else {
                        $createdPolicyIds += $policyImportResults.id
                    }
                    Add-CreatedObject -Platform $p.platform -Type 'Policy' -Name $resultName -Id $policyImportResults.id
                } else {
                    Write-Host "  - Policy import failed or returned no results." -ForegroundColor Red
                }
            }

        } catch {
            Write-Error "Failed to process policy '$($p.name)': $_"
        }
        Write-Host ""

    }
}

# Enumerate compliance policies
if ($importCompliance) {
    $createdComplianceIds = @()
    $compliance = @()
    if ($distributedItems) { $compliance = $distributedItems | Where-Object { $_.type -eq 'Compliance' } }
    Write-Host "Found $($compliance.Count) compliance policies:`n" -ForegroundColor Cyan
    foreach ($c in $compliance) {
        $compPath = Resolve-ArtifactPath -RelativePath $c.filePath
        $exists = Test-Path -LiteralPath $compPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }
        $desc = $c.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0,137)+'...' }
        Write-Host "• $($c.name)" -ForegroundColor Yellow
        Write-Host "  - Path: $($c.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }
    if (-not $exists) { Write-Host "Compliance JSON missing, skipping." -ForegroundColor Red; Write-Host ''; continue }
        try {
            $json = Get-Content -LiteralPath $compPath -Raw | ConvertFrom-Json -Depth 15
            # Ensure required scheduledActionsForRule exists (Graph requires exactly one block action)
            if (-not $json.PSObject.Properties['scheduledActionsForRule'] -or -not $json.scheduledActionsForRule -or $json.scheduledActionsForRule.Count -eq 0) {
                $json.scheduledActionsForRule = @(
                    @{ ruleName = 'default'; scheduledActionConfigurations = @(
                        @{ actionType = 'block'; gracePeriodHours = 0; notificationTemplateId = $null }
                    ) }
                )
            } elseif ($json.scheduledActionsForRule.Count -gt 1) {
                # Simplify to first if multiple to satisfy 'one and only one' constraint
                $json.scheduledActionsForRule = @($json.scheduledActionsForRule[0])
                if (-not ($json.scheduledActionsForRule[0].scheduledActionConfigurations) -or $json.scheduledActionsForRule[0].scheduledActionConfigurations.Count -eq 0) {
                    $json.scheduledActionsForRule[0].scheduledActionConfigurations = @(
                        @{ actionType = 'block'; gracePeriodHours = 0; notificationTemplateId = $null }
                    )
                }
            } else {
                # Normalize existing single rule: ensure one block action present
                $cfgs = $json.scheduledActionsForRule[0].scheduledActionConfigurations
                if (-not $cfgs -or ($cfgs | Where-Object { $_.actionType -eq 'block' }).Count -eq 0) {
                    $json.scheduledActionsForRule[0].scheduledActionConfigurations = @(
                        @{ actionType = 'block'; gracePeriodHours = 0; notificationTemplateId = $null }
                    )
                } elseif ($cfgs.Count -gt 1) {
                    # Keep only first block action
                    $block = ($cfgs | Where-Object { $_.actionType -eq 'block' })[0]
                    $json.scheduledActionsForRule[0].scheduledActionConfigurations = @($block)
                }
                if (-not $json.scheduledActionsForRule[0].ruleName) { $json.scheduledActionsForRule[0].ruleName = 'default' }
            }
            # Name source of truth = XML manifest
            $json.displayName = $policyPrefix + $c.name
            $body = $json | ConvertTo-Json -Depth 20
            if (-not $applyChanges) {
                Write-Host "  - [dry-run] Would create compliance policy '$($json.displayName)'." -ForegroundColor DarkGray
            } else {
                $resp = Invoke-MgGraphRequest -Method POST -Uri $c.createGraphUri -Body $body
                if ($resp -and $resp.id) {
                    Write-Host "  - Compliance policy imported with ID: $($resp.id)" -ForegroundColor Green
                    $createdComplianceIds += $resp.id
                    $createdName = if ($resp.displayName) { $resp.displayName } else { $json.displayName }
                    Add-CreatedObject -Platform $c.platform -Type 'Compliance' -Name $createdName -Id $resp.id
                } else {
                    Write-Warning "  - Import returned no ID"
                }
            }
        } catch {
            Write-Error "Failed to import compliance policy '$($c.name)': $_"
        }
        Write-Host ""
    }
}

# Enumerate scripts
if ($importScripts) {
    $createdScriptIds = @()
    $scripts = $distributedItems | Where-Object { $_.type -eq 'Script' }
    Write-Host "Found $($scripts.Count) scripts:`n" -ForegroundColor Cyan
    foreach ($s in $scripts) {
        $scriptPath = Resolve-ArtifactPath -RelativePath $s.filePath
        $exists = Test-Path -LiteralPath $scriptPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }
        $desc = $s.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0,137)+'...' }
        Write-Host "• $($s.name)" -ForegroundColor Yellow
        Write-Host "  - Category: $($s.category); Platform: $($s.platform)"
        Write-Host "  - Path: $($s.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }
        Write-Host "  - runAsAccount: $($s.runAsAccount)"
        Write-Host "  - blockExecutionNotifications: $($s.blockExecutionNotifications)"
        Write-Host "  - executionFrequency: $($s.executionFrequency)"
        Write-Host "  - retryCount: $($s.retryCount)"
    if (-not $exists) { Write-Host "Script file missing, skipping upload." -ForegroundColor Red; Write-Host ''; continue }
        try {
            $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($scriptContent))
            $displayName = $policyPrefix + $s.name
            $fileName = [IO.Path]::GetFileName($scriptPath)
            
            # Use deviceShellScripts for macOS shell scripts to appear in Devices > macOS > Scripts
            $body = @{ 
                '@odata.type' = '#microsoft.graph.deviceShellScript'
                executionFrequency = $s.executionFrequency
                retryCount = $s.retryCount
                blockExecutionNotifications = $s.blockExecutionNotifications
                displayName = $displayName
                description = $s.description
                scriptContent = $encoded
                fileName = $fileName
                runAsAccount = $s.runAsAccount
            }
            $json = $body | ConvertTo-Json -Depth 5
            if (-not $applyChanges) {
                Write-Host "  - [dry-run] Would upload shell script '$displayName'." -ForegroundColor DarkGray
            } else {
                $result = Invoke-MgGraphRequest -Method POST -Uri $s.createGraphUri -Body $json -ContentType 'application/json'
                if ($result -and $result.id) { 
                    Write-Host "  - Script $($result.displayName) imported with ID: $($result.id)" -ForegroundColor Green 
                    $createdScriptIds += $result.id
                    Add-CreatedObject -Platform $s.platform -Type 'Script' -Name $result.displayName -Id $result.id
                } else { 
                    Write-Host "  - Script import failed (no ID)" -ForegroundColor Red 
                }
            }
        } catch {
            Write-Error "Failed to import script '$($s.name)': $_"
        }
    }
    
    # Removed legacy verification block for simplicity
}

# Enumerate custom attributes
if ($importCustomAttrs) {
    $createdCustomAttrIds = @()
    $customAttributes = $distributedItems | Where-Object { $_.type -eq 'CustomAttribute' }
    Write-Host "Found $($customAttributes.Count) custom attributes:`n" -ForegroundColor Cyan
    foreach ($ca in $customAttributes) {
        $scriptPath = Resolve-ArtifactPath -RelativePath $ca.filePath
        $exists = Test-Path -LiteralPath $scriptPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }
        $desc = $ca.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0,137)+'...' }
        Write-Host "• $($ca.name)" -ForegroundColor Yellow
        Write-Host "  - Category: $($ca.category); Platform: $($ca.platform)"
        Write-Host "  - Path: $($ca.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }
        Write-Host "  - customAttributeType: $($ca.customAttributeType)"
    if (-not $exists) { Write-Host "Custom attribute script file missing, skipping upload." -ForegroundColor Red; Write-Host ''; continue }
        try {
            $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($scriptContent))
            $displayName = $policyPrefix + $ca.name
            $fileName = [IO.Path]::GetFileName($scriptPath)
            
            # Use deviceCustomAttributeShellScripts for macOS custom attributes
            $body = @{ 
                displayName = $displayName
                description = $ca.description
                scriptContent = $encoded
                fileName = $fileName
                runAsAccount = 'system'  # Custom attributes always run as system
                customAttributeType = $ca.customAttributeType
            }
            $json = $body | ConvertTo-Json -Depth 5
            if (-not $applyChanges) {
                Write-Host "  - [dry-run] Would create custom attribute '$displayName'." -ForegroundColor DarkGray
            } else {
                $result = Invoke-MgGraphRequest -Method POST -Uri $ca.createGraphUri -Body $json
                if ($result -and $result.id) { 
                    Write-Host "  - Custom attribute $($result.displayName) imported with ID: $($result.id)" -ForegroundColor Green 
                    $createdCustomAttrIds += $result.id
                    Add-CreatedObject -Platform $ca.platform -Type 'CustomAttribute' -Name $result.displayName -Id $result.id
                } else { 
                    Write-Host "  - Custom attribute import failed (no ID)" -ForegroundColor Red 
                }
            }
        } catch {
            Write-Error "Failed to import custom attribute '$($ca.name)': $_"
        }
        Write-Host ""
    }
}

# Enumerate enrollment restrictions
if ($importEnrollmentRestrictions) {
    $createdEnrollmentRestrictionIds = @()
    $enrollmentRestrictions = @()
    if ($distributedItems) { $enrollmentRestrictions = $distributedItems | Where-Object { $_.type -eq 'EnrollmentRestriction' } }
    Write-Host "Found $($enrollmentRestrictions.Count) enrollment restriction(s):`n" -ForegroundColor Cyan
    foreach ($er in $enrollmentRestrictions) {
        $erPath = Resolve-ArtifactPath -RelativePath $er.filePath
        $exists = Test-Path -LiteralPath $erPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }
        $desc = $er.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0,137)+'...' }
        Write-Host "• $($er.name)" -ForegroundColor Yellow
        Write-Host "  - Category: $($er.category); Platform: $($er.platform)"
        Write-Host "  - Path: $($er.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }
        if (-not $exists) { Write-Host "  - Enrollment restriction JSON missing, skipping." -ForegroundColor Red; Write-Host ''; continue }
        try {
            $json = Get-Content -LiteralPath $erPath -Raw | ConvertFrom-Json -Depth 15
            $json.displayName = $policyPrefix + $er.name
            $body = $json | ConvertTo-Json -Depth 20
            if (-not $applyChanges) {
                Write-Host "  - [dry-run] Would create enrollment restriction '$($json.displayName)'." -ForegroundColor DarkGray
            } else {
                $resp = Invoke-MgGraphRequest -Method POST -Uri $er.createGraphUri -Body $body
                if ($resp -and $resp.id) {
                    Write-Host "  - Enrollment restriction imported with ID: $($resp.id)" -ForegroundColor Green
                    $createdEnrollmentRestrictionIds += $resp.id
                    $createdName = if ($resp.displayName) { $resp.displayName } else { $json.displayName }
                    Add-CreatedObject -Platform $er.platform -Type 'EnrollmentRestriction' -Name $createdName -Id $resp.id
                } else {
                    Write-Warning "  - Import returned no ID"
                }
            }
        } catch {
            Write-Error "Failed to import enrollment restriction '$($er.name)': $_"
        }
        Write-Host ""
    }
}

# Enumerate packages/apps
if ($importPackages) {
    $createdAppIds = @()

    # Download latest Company Portal installer if the manifest references it
    $cpManifestExists = $distributedItems | Where-Object { $_.type -in @('Package','App','LobApp') -and $_.filePath -in @('macOS/apps/CompanyPortal-Installer.pkg','apps/CompanyPortal-Installer.pkg') }
    if ($macOSRoot -and $cpManifestExists) {
        $cpPkgPath = Join-Path $macOSRoot "apps/CompanyPortal-Installer.pkg"
        if (Test-Path -LiteralPath $cpPkgPath) {
            Remove-Item -LiteralPath $cpPkgPath -Force
            Write-Host "Removed existing CompanyPortal-Installer.pkg" -ForegroundColor DarkGray
        }
        Write-Host "Downloading latest Company Portal installer..." -ForegroundColor Cyan
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=853070" -OutFile $cpPkgPath -UseBasicParsing
            $ProgressPreference = 'Continue'
            $cpSize = (Get-Item $cpPkgPath).Length / 1MB
            Write-Host ("✓ Downloaded CompanyPortal-Installer.pkg ({0:N1} MB)" -f $cpSize) -ForegroundColor Green

            # Extract version from pkg and update manifest XML
            $cpManifestPath = Join-Path $macOSRoot "apps/app-sys-001-company-portal.xml"
            if (Test-Path -LiteralPath $cpManifestPath) {
                $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "cp_pkg_extract_$([System.Guid]::NewGuid().ToString('N'))"
                try {
                    $null = & pkgutil --expand-full $cpPkgPath $tmpDir 2>&1
                    $infoPlist = Get-ChildItem -Path $tmpDir -Recurse -Filter "Info.plist" | Where-Object { $_.FullName -match "Company Portal\.app/Contents/Info\.plist" } | Select-Object -First 1
                    if ($infoPlist) {
                        $pkgVersion = & /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $infoPlist.FullName 2>$null
                        if ($pkgVersion) {
                            $pkgVersion = $pkgVersion.Trim()
                            [xml]$manifestXml = Get-Content $cpManifestPath -Raw
                            $manifestRoot = $manifestXml.DocumentElement
                            if ($manifestRoot -and $manifestRoot.Name -in @('MacIntuneManifest','IntuneManifest')) {
                                $packageNode = $manifestRoot.SelectSingleNode('Package')
                                if ($packageNode) {
                                    $bundleVersionNode = $packageNode.SelectSingleNode('PrimaryBundleVersion')
                                    if ($bundleVersionNode) {
                                        $bundleVersionNode.InnerText = $pkgVersion
                                        $manifestXml.Save($cpManifestPath)
                                        Write-Host "  Updated PrimaryBundleVersion to $pkgVersion" -ForegroundColor Green
                                    }
                                }
                            }
                        }
                    }
                } finally {
                    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
                }
            }
        } catch {
            Write-Warning "Failed to download Company Portal: $($_.Exception.Message)"
        }
    }

    $packages = $distributedItems | Where-Object { $_.type -in @('Package','App','LobApp') }

    Write-Host "Found $($packages.Count) packages/apps:`n" -ForegroundColor Cyan

    foreach ($a in $packages) {
        $assetPath = Resolve-ArtifactPath -RelativePath $a.filePath
        $exists = Test-Path -LiteralPath $assetPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }

        $desc = $a.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0, 137) + '...' }

        Write-Host "• $($a.name)" -ForegroundColor Yellow
        Write-Host "  - Category: $($a.category); Platform: $($a.platform)"
        Write-Host "  - Path: $($a.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }
        Write-Host "  - preInstallScript: $($a.preInstallScript)"
        Write-Host "  - postInstallScript: $($a.postInstallScript)"
        Write-Host "  - primaryBundleId: $($a.primaryBundleId)"
        Write-Host "  - primaryBundleVersion: $($a.primaryBundleVersion)"
        Write-Host "  - publisher: $($a.publisher)"
        Write-Host "  - minimumSupportedOperatingSystem: $($a.minimumSupportedOperatingSystem)"
        Write-Host "  - ignoreVersionDetection: $($a.ignoreVersionDetection)"

        Write-Host ""

    $displayName = $policyPrefix + $a.name

        # create hashtable for minimumSupportedOperatingSystem
        $minimumSupportedOperatingSystem = @{
            $($a.minimumSupportedOperatingSystem) = $true
        }

        if ($a.ignoreVersionDetection -eq "true") {
            $ignoreVersionDetection = $true
        } else {
            $ignoreVersionDetection = $false
        }

        $includedApps = @(
            @{
                "@odata.type" = "#microsoft.graph.macOSIncludedApp"
                bundleId      = "$($a.primaryBundleId)"
                bundleVersion = "$($a.primaryBundleVersion)"
            }
        )

        # add preinstall script if needed
        if ($a.preInstallScript) {
            $preinstallScript = Resolve-ArtifactPath -RelativePath $a.preInstallScript
            if (-not (Test-Path -LiteralPath $preinstallScript)) {
                Write-Warning "Pre-install script path not found: $($a.preInstallScript) (resolved: $preinstallScript). Will skip embedding."
                $preinstallScript = $null
            } else {
                Write-Host "  - Using pre-install script: $($a.preInstallScript)" -ForegroundColor DarkCyan
            }
        } else {
            $preinstallScript = $null
        }

        # add postInstall script if needed
        if ($a.postInstallScript) {
            $postInstallScript = Resolve-ArtifactPath -RelativePath $a.postInstallScript
            if (-not (Test-Path -LiteralPath $postInstallScript)) {
                Write-Warning "Post-install script path not found: $($a.postInstallScript) (resolved: $postInstallScript). Will skip embedding."
                $postInstallScript = $null
            } else {
                Write-Host "  - Using post-install script: $($a.postInstallScript)" -ForegroundColor DarkCyan
            }
        } else {
            $postInstallScript = $null
        }

    if (-not $exists) { Write-Host "Package source file missing, skipping upload." -ForegroundColor Red; continue }
    if (-not $applyChanges) {
        Write-Host "  - [dry-run] Would upload macOS app '$displayName'." -ForegroundColor DarkGray
        continue
    }
    if (-not (Test-BetaModule)) { Write-Host "Required beta Graph module missing; skipping package upload." -ForegroundColor Red; continue }

    if ($a.type -eq 'LobApp') {
        # Use macOSLobApp upload (correct Graph type)
        $installAsManaged = if ($a.installAsManaged -eq "true") { $true } else { $false }
        $appResult = Invoke-MacOSLobAppUploadReal -SourceFile $assetPath `
                -displayName "$($displayName)" -Publisher "$($a.publisher)" -Description "$($desc)" `
                -BundleId "$($a.primaryBundleId)" -BuildNumber "$($a.primaryBundleVersion)" `
                -MinimumSupportedOperatingSystem $minimumSupportedOperatingSystem `
        -IgnoreVersionDetection $ignoreVersionDetection -InstallAsManaged $installAsManaged -ChunkSizeMB 8 -MobileAppsUri $a.createGraphUri
    } else {
        # Use macOSPkgApp upload (existing behavior for Package/App types)
        $appResult = Invoke-macOSLobAppUpload -SourceFile $assetPath `
                -displayName "$($displayName)" -Publisher "$($a.publisher)" -Description "$($desc)" `
                -primaryBundleId "$($a.primaryBundleId)" -primaryBundleVersion "$($a.primaryBundleVersion)" `
                -preInstallScriptPath $preinstallScript -postInstallScriptPath $postInstallScript `
                -includedApps $includedApps -minimumSupportedOperatingSystem $minimumSupportedOperatingSystem `
        -ignoreVersionDetection $ignoreVersionDetection -ChunkSizeMB 8 -MobileAppsUri $a.createGraphUri
    }
    if ($appResult -and $appResult.id) {
        $createdAppIds += $appResult.id
        Add-CreatedObject -Platform $a.platform -Type 'App' -Name $displayName -Id $appResult.id
    } else {
        Write-Warning "Could not capture app ID for: $displayName"
    }

    }

}

# Enumerate custom macOS configuration profiles (mobileconfig)
if ($importPolicies) {
    $customConfigs = $distributedItems | Where-Object { $_.type -eq 'CustomConfig' }
    if ($customConfigs.Count -gt 0) {
        Write-Host "Found $($customConfigs.Count) custom macOS configuration profile(s):`n" -ForegroundColor Cyan
        foreach ($cc in $customConfigs) {
            $ccPath = Resolve-ArtifactPath -RelativePath $cc.filePath
            $exists = Test-Path -LiteralPath $ccPath
            $status = if ($exists) { 'OK' } else { 'MISSING' }
            Write-Host "• $($cc.name)" -ForegroundColor Yellow
            Write-Host "  - Path: $($cc.filePath) [$status]"
            if ($cc.description) { Write-Host "  - Desc: $($cc.description)" }
            if (-not $exists) { Write-Host "  - Skipping (file missing)." -ForegroundColor Red; Write-Host ''; continue }
            try {
                $raw = [System.IO.File]::ReadAllBytes($ccPath)
                $b64 = [Convert]::ToBase64String($raw)
                $displayName = $policyPrefix + $cc.name
                $payloadFileName = [IO.Path]::GetFileName($cc.filePath)
                $payloadName = $payloadFileName
                $bodyHash = @{ 
                    '@odata.type'    = '#microsoft.graph.macOSCustomConfiguration'
                    displayName      = $displayName
                    description      = $cc.description
                    payload          = $b64
                    payloadName      = $payloadName
                    payloadFileName  = $payloadFileName
                }
                $body = $bodyHash | ConvertTo-Json -Depth 6
                if (-not $applyChanges) {
                    Write-Host "  - [dry-run] Would create custom configuration '$displayName'." -ForegroundColor DarkGray
                } else {
                    $resp = Invoke-MgGraphRequest -Method POST -Uri $cc.createGraphUri -Body $body
                    if ($resp -and $resp.id) {
                        Write-Host "  - Custom configuration imported with ID: $($resp.id)" -ForegroundColor Green
                        $createdDeviceConfigIds += $resp.id
                        Add-CreatedObject -Platform $cc.platform -Type 'CustomConfig' -Name $displayName -Id $resp.id
                    } else {
                        Write-Warning "  - Import returned no ID"
                    }
                }
            } catch {
                $errMsg = $_.Exception.Message
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $errMsg = $_.ErrorDetails.Message }
                Write-Error "Failed to import custom configuration '$($cc.name)': $errMsg"
            }
            Write-Host ''
        }
    }
}

# Perform assignments if requested
if ($assignGroupName) {
    Write-Host ""; Write-Host "Assignment requested for group: $assignGroupName" -ForegroundColor Cyan
    $groupId = $resolvedGroupId
    if ($groupId) {
        Write-Host "Resolved group '$assignGroupName' to ID $groupId" -ForegroundColor Green
    } else {
        Write-Warning "Skipping assignments; group not resolved."
    }
    if (-not $applyChanges) {
        Write-Host "[dry-run] Assignments skipped. Rerun with --apply to deploy them." -ForegroundColor Yellow
    }
    if ($applyChanges -and $groupId) {

    # Assign Configuration Policies via assignments resource
    foreach ($policyId in ($createdPolicyIds | Sort-Object -Unique)) {
            try {
                $assignBody = @{ assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$policyId/assign" -Body $assignBody | Out-Null
        Write-Host "Assigned policy $policyId to group" -ForegroundColor Green
        } catch { Write-Warning "Failed to assign policy ${policyId}: $($_.Exception.Message)" }
        }

    # Assign classic custom configurations (deviceConfigurations)
    foreach ($devCfgId in ($createdDeviceConfigIds | Sort-Object -Unique)) {
        try {
            $assignBody = @{ assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$devCfgId/assign" -Body $assignBody | Out-Null
            if ($createdPolicyDeviceConfigIds -contains $devCfgId) {
                Write-Host "Assigned policy $devCfgId to group" -ForegroundColor Green
            } else {
                Write-Host "Assigned custom config $devCfgId to group" -ForegroundColor Green
            }
        } catch {
            if ($createdPolicyDeviceConfigIds -contains $devCfgId) {
                Write-Warning "Failed to assign policy ${devCfgId}: $($_.Exception.Message)"
            } else {
                Write-Warning "Failed to assign custom config ${devCfgId}: $($_.Exception.Message)"
            }
        }
    }

    # Assign feature update policies (windowsFeatureUpdateProfiles)
    foreach ($fuId in ($createdFeatureUpdateProfileIds | Sort-Object -Unique)) {
        try {
            $assignBody = @{ assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles/$fuId/assign" -Body $assignBody | Out-Null
            Write-Host "Assigned policy $fuId to group" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to assign policy ${fuId}: $($_.Exception.Message)"
        }
    }

    # Assign Compliance Policies (deviceCompliancePolicies)
    foreach ($compId in ($createdComplianceIds | Sort-Object -Unique)) {
        try {
        $assignBody = @{ assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$compId/assign" -Body $assignBody | Out-Null
    Write-Host "Assigned compliance policy $compId to group" -ForegroundColor Green
    } catch { Write-Warning "Failed to assign compliance policy ${compId}: $($_.Exception.Message)" }
    }

    # Assign Scripts (deviceShellScripts) via assignments
    foreach ($scriptId in ($createdScriptIds | Sort-Object -Unique)) {
            try {
                $assignBody = @{ deviceManagementScriptGroupAssignments = @(); deviceManagementScriptAssignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts/$scriptId/assign" -Body $assignBody | Out-Null
        Write-Host "Assigned script $scriptId to group" -ForegroundColor Green
        } catch { Write-Warning "Failed to assign script ${scriptId}: $($_.Exception.Message)" }
        }

    # Assign Custom Attributes only if custom attributes were imported this run
    if ($importCustomAttrs -and $createdCustomAttrIds.Count -gt 0) {
        foreach ($customAttrId in ($createdCustomAttrIds | Sort-Object -Unique)) {
                try {
                    # Try the same format as regular scripts for custom attributes
                    $assignBody = @{ deviceManagementScriptGroupAssignments = @(); deviceManagementScriptAssignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
                    if ($env:IMM_DEBUG -eq '1') { Write-Host "DEBUG: Custom attribute assignment body: $assignBody" -ForegroundColor DarkCyan }
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCustomAttributeShellScripts/$customAttrId/assign" -Body $assignBody | Out-Null
            Write-Host "Assigned custom attribute $customAttrId to group" -ForegroundColor Green
            } catch { 
                Write-Warning "Failed to assign custom attribute ${customAttrId}: $($_.Exception.Message)"
                if ($_.Exception.Response) {
                    try {
                        $errorDetails = $_.Exception.Response.Content.ReadAsStringAsync().Result
                        Write-Host "Error details: $errorDetails" -ForegroundColor Red
                    } catch {
                        Write-Host "Could not read error response details" -ForegroundColor Red
                    }
                }
            }
            }
    } else {
        Write-Host "Skipping custom attribute assignments (no custom attributes imported)." -ForegroundColor DarkGray
    }

        # Assign Apps only if packages were imported this run
        if ($importPackages -and $createdAppIds.Count -gt 0) {
            $uniqueAppIds = $createdAppIds | Sort-Object -Unique
            foreach ($appId in $uniqueAppIds) {
                try {
                    $assignBody = @{ mobileAppAssignments = @(@{ '@odata.type' = '#microsoft.graph.mobileAppAssignment'; intent = 'required'; target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 8
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/assign" -Body $assignBody | Out-Null
                    Write-Host "Assigned app $appId as required to group" -ForegroundColor Green
                } catch { Write-Warning "Failed to assign app ${appId}: $($_.Exception.Message)" }
            }
        } else {
            Write-Host "Skipping app assignments (no packages imported)." -ForegroundColor DarkGray
        }

        # Assign Enrollment Restrictions only if imported this run
        if ($importEnrollmentRestrictions -and $createdEnrollmentRestrictionIds.Count -gt 0) {
            foreach ($erId in ($createdEnrollmentRestrictionIds | Sort-Object -Unique)) {
                try {
                    $assignBody = @{ enrollmentConfigurationAssignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$erId/assign" -Body $assignBody | Out-Null
                    Write-Host "Assigned enrollment restriction $erId to group" -ForegroundColor Green
                } catch { Write-Warning "Failed to assign enrollment restriction ${erId}: $($_.Exception.Message)" }
            }
        } else {
            Write-Host "Skipping enrollment restriction assignments (none imported)." -ForegroundColor DarkGray
        }
    }
}

if ($applyChanges) {
    Show-CreatedObjectsSummary -Objects $createdObjects
}
