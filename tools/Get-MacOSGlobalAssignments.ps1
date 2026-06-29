<#!
.SYNOPSIS
Lists every macOS Intune object (configuration, compliance, scripts, custom attributes, apps) assigned to All Devices or All Users.

.DESCRIPTION
Queries Microsoft Graph (beta) for:
  * Settings Catalog configurationPolicies (platforms includes macOS)
  * Classic deviceConfigurations (odata type starts with #microsoft.graph.macOS) — includes macOSCustomConfiguration
  * deviceCompliancePolicies (#microsoft.graph.macOSCompliancePolicy)
  * deviceShellScripts (macOS-only endpoint)
  * deviceCustomAttributeShellScripts (macOS-only endpoint)
  * mobileApps with any #microsoft.graph.macOS* type (PKG, LOB, DMG, Office, Edge, Defender, MDATP)
For each object, retrieves its assignments and flags whether it is targeted to:
  - All Devices (allDevicesAssignmentTarget)
  - All Users (allLicensedUsersAssignmentTarget)
For any such global assignment it also reports whether an assignment filter is
applied (filter display name and include/exclude mode).
Outputs a table and (optionally) JSON/CSV.

.PARAMETER OutputJson
Also emit raw JSON array to stdout (after table).

.PARAMETER CsvPath
Optional path to write CSV export of results.

.EXAMPLE
./Get-MacOSGlobalAssignments.ps1

.EXAMPLE
./Get-MacOSGlobalAssignments.ps1 -OutputJson -CsvPath ./mac-global.csv

.NOTES
Requires Microsoft.Graph.Authentication (Connect-MgGraph) and sufficient Intune permissions (DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All).
#>
     
# Copyright (c) Microsoft Corporation.


param(
    [switch]$OutputJson,
    [string]$CsvPath,
    [switch]$Unassign,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Ensure-GraphConnection {
    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        Write-Error "Microsoft Graph PowerShell SDK not installed. Install-Module Microsoft.Graph -Scope CurrentUser"
        exit 1
    }
    try {
        $ctx = Get-MgContext -ErrorAction Stop
        if (-not $ctx) { throw 'No context' }
    } catch {
        Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor Cyan
        Connect-MgGraph -Scopes @(
            'DeviceManagementConfiguration.Read.All',
            'DeviceManagementApps.Read.All'
        ) | Out-Null
    }
}

function Get-GraphBatchResults {
    # Submits multiple GET list requests in a single Graph $batch round trip,
    # then drains any per-request nextLink pages (rare for small tenants).
    # $Requests: ordered/hashtable of id => version-relative URL (leading '/').
    param(
        [Parameter(Mandatory)] $Requests
    )
    $base = 'https://graph.microsoft.com/beta'
    $reqList = foreach ($id in $Requests.Keys) {
        @{ id = [string]$id; method = 'GET'; url = $Requests[$id] }
    }
    $body = @{ requests = @($reqList) } | ConvertTo-Json -Depth 5
    $resp = Invoke-MgGraphRequest -Method POST -Uri "$base/`$batch" -Body $body -ContentType 'application/json'

    $out = @{}
    foreach ($r in $resp.responses) {
        $items = [System.Collections.Generic.List[object]]::new()
        if ($r.status -ge 200 -and $r.status -lt 300 -and $r.body) {
            if ($r.body.value) { $items.AddRange([object[]]$r.body.value) }
            $next = $r.body.'@odata.nextLink'
            while ($next) {
                $page = Invoke-MgGraphRequest -Method GET -Uri $next
                if ($page.value) { $items.AddRange([object[]]$page.value) }
                $next = $page.'@odata.nextLink'
            }
        } elseif ($r.status -ge 400) {
            Write-Warning "Batch request '$($r.id)' failed (HTTP $($r.status)); results for that category may be incomplete."
        }
        $out[$r.id] = $items
    }
    return $out
}

function Get-FilterDisplay {
    param(
        $Target,
        [hashtable]$FilterLookup
    )
    $fid   = $Target.deviceAndAppManagementAssignmentFilterId
    $ftype = $Target.deviceAndAppManagementAssignmentFilterType
    if (-not $fid -or $fid -eq '00000000-0000-0000-0000-000000000000' -or -not $ftype -or $ftype -eq 'none') {
        return $null
    }
    $name = if ($FilterLookup.ContainsKey($fid)) { $FilterLookup[$fid] } else { $fid }
    return "$name ($ftype)"
}

function Get-GlobalAssignmentInfo {
    param(
        $Assignments,
        [hashtable]$FilterLookup
    )
    $isAllDevices = $false; $isAllUsers = $false
    $filters = New-Object System.Collections.Generic.HashSet[string]
    $intents = New-Object System.Collections.Generic.HashSet[string]
    foreach ($a in $Assignments) {
        $t = $a.target.'@odata.type'
        $isGlobal = $false
        if ($t -eq '#microsoft.graph.allDevicesAssignmentTarget') { $isAllDevices = $true; $isGlobal = $true }
        if ($t -eq '#microsoft.graph.allLicensedUsersAssignmentTarget') { $isAllUsers = $true; $isGlobal = $true }
        if ($isGlobal) {
            $f = Get-FilterDisplay -Target $a.target -FilterLookup $FilterLookup
            if ($f) { [void]$filters.Add($f) }
            if ($a.intent) { [void]$intents.Add([string]$a.intent) }
        }
    }
    return [pscustomobject]@{
        AllDevices = $isAllDevices
        AllUsers   = $isAllUsers
        Filter     = (($filters | Sort-Object) -join '; ')
        Intent     = (($intents | Sort-Object) -join ',')
    }
}

Ensure-GraphConnection

$betaBase = 'https://graph.microsoft.com/beta'

Write-Host 'Collecting macOS objects (single batched request)...' -ForegroundColor Cyan
$batch = Get-GraphBatchResults -Requests ([ordered]@{
    filters    = '/deviceManagement/assignmentFilters?$top=100'
    config     = '/deviceManagement/configurationPolicies?$top=100&$expand=assignments'
    devcfg     = '/deviceManagement/deviceConfigurations?$top=100&$expand=assignments'
    compliance = '/deviceManagement/deviceCompliancePolicies?$top=100&$expand=assignments'
    shell      = '/deviceManagement/deviceShellScripts?$top=100&$expand=assignments'
    customattr = '/deviceManagement/deviceCustomAttributeShellScripts?$top=100&$expand=assignments'
    apps       = '/deviceAppManagement/mobileApps?$top=100&$expand=assignments'
})

$filterLookup = @{}
foreach ($f in $batch['filters']) { if ($f.id) { $filterLookup[$f.id] = $f.displayName } }

$configPolicies     = $batch['config']     | Where-Object { $_.platforms -match 'macOS' }
$deviceConfigs      = $batch['devcfg']     | Where-Object { $_.'@odata.type' -like '#microsoft.graph.macOS*' }
$compliancePolicies = $batch['compliance'] | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.macOSCompliancePolicy' }
$deviceShellScripts = $batch['shell']
$customAttrScripts  = $batch['customattr']
$mobileApps         = $batch['apps']       | Where-Object { $_.'@odata.type' -like '#microsoft.graph.macOS*' }

$rows = @()

# Settings catalog policies assignments
foreach ($p in $configPolicies) {
    $info = Get-GlobalAssignmentInfo -Assignments $p.assignments -FilterLookup $filterLookup
    if ($info.AllDevices -or $info.AllUsers) {
        $rows += [pscustomobject]@{
            Type        = 'SettingsCatalogPolicy'
            Name        = $p.name
            Id          = $p.id
            AllDevices  = $info.AllDevices
            AllUsers    = $info.AllUsers
            Filter      = $info.Filter
            Intent      = ''
            Platforms   = ($p.platforms -join ',')
        }
    }
}

# Classic / custom device configurations
foreach ($c in $deviceConfigs) {
    $info = Get-GlobalAssignmentInfo -Assignments $c.assignments -FilterLookup $filterLookup
    if ($info.AllDevices -or $info.AllUsers) {
        $rows += [pscustomobject]@{
            Type       = 'DeviceConfiguration'
            Name       = $c.displayName
            Id         = $c.id
            AllDevices = $info.AllDevices
            AllUsers   = $info.AllUsers
            Filter     = $info.Filter
            Intent     = ''
            Platforms  = 'macOS'
        }
    }
}

# Compliance policies
foreach ($cp in $compliancePolicies) {
    $info = Get-GlobalAssignmentInfo -Assignments $cp.assignments -FilterLookup $filterLookup
    if ($info.AllDevices -or $info.AllUsers) {
        $rows += [pscustomobject]@{
            Type       = 'CompliancePolicy'
            Name       = $cp.displayName
            Id         = $cp.id
            AllDevices = $info.AllDevices
            AllUsers   = $info.AllUsers
            Filter     = $info.Filter
            Intent     = ''
            Platforms  = 'macOS'
        }
    }
}

# Shell scripts (assignments already expanded when possible)
foreach ($s in $deviceShellScripts) {
    # Invoke-MgGraphRequest returns a Hashtable; direct access on the key
    # works and yields $null when absent.
    $expandedAssignments = if ($s.assignments) { $s.assignments } else {
        try { (Invoke-MgGraphRequest -Method GET -Uri "$betaBase/deviceManagement/deviceShellScripts/$($s.id)/assignments").value }
        catch { @() }
    }
    $info = Get-GlobalAssignmentInfo -Assignments $expandedAssignments -FilterLookup $filterLookup
    if ($info.AllDevices -or $info.AllUsers) {
        $rows += [pscustomobject]@{
            Type       = 'ShellScript'
            Name       = $s.displayName
            Id         = $s.id
            AllDevices = $info.AllDevices
            AllUsers   = $info.AllUsers
            Filter     = $info.Filter
            Intent     = ''
            Platforms  = 'macOS'
        }
    }
}

# Custom attribute shell scripts (assignments already expanded when possible)
foreach ($ca in $customAttrScripts) {
    $expandedAssignments = if ($ca.assignments) { $ca.assignments } else {
        try { (Invoke-MgGraphRequest -Method GET -Uri "$betaBase/deviceManagement/deviceCustomAttributeShellScripts/$($ca.id)/assignments").value }
        catch { @() }
    }
    $info = Get-GlobalAssignmentInfo -Assignments $expandedAssignments -FilterLookup $filterLookup
    if ($info.AllDevices -or $info.AllUsers) {
        $rows += [pscustomobject]@{
            Type       = 'CustomAttribute'
            Name       = $ca.displayName
            Id         = $ca.id
            AllDevices = $info.AllDevices
            AllUsers   = $info.AllUsers
            Filter     = $info.Filter
            Intent     = ''
            Platforms  = 'macOS'
        }
    }
}

# macOS Apps
foreach ($app in $mobileApps) {
    $info = Get-GlobalAssignmentInfo -Assignments $app.assignments -FilterLookup $filterLookup
    if ($info.AllDevices -or $info.AllUsers) {
        $rows += [pscustomobject]@{
            Type       = 'macOSApp'
            Name       = $app.displayName
            Id         = $app.id
            AllDevices = $info.AllDevices
            AllUsers   = $info.AllUsers
            Filter     = $info.Filter
            Intent     = $info.Intent
            Platforms  = 'macOS'
        }
    }
}

if (-not $rows) {
    Write-Host 'No macOS objects assigned to All Devices or All Users.' -ForegroundColor Yellow
    return
}

# Highlight global assignments that have NO assignment filter applied (red).
# Format-Table is ANSI-aware in PowerShell 7.2+, so wrapping each cell value
# keeps column widths correct.
$esc = [char]27
$red = "$esc[31m"
$reset = "$esc[0m"
$display = $rows | Sort-Object Type, Name | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.Filter)) {
        $colored = [ordered]@{}
        foreach ($prop in $_.PSObject.Properties) {
            $colored[$prop.Name] = "$red$($prop.Value)$reset"
        }
        [pscustomobject]$colored
    } else {
        $_
    }
}
$display | Format-Table Type, Name, Id, AllDevices, AllUsers, Filter, Intent -AutoSize

if ($CsvPath) {
    try {
        $rows | Export-Csv -NoTypeInformation -Path $CsvPath -Encoding UTF8
        Write-Host "CSV written to $CsvPath" -ForegroundColor Green
    } catch { Write-Warning "Failed to write CSV: $($_.Exception.Message)" }
}

if ($OutputJson) {
    $rows | ConvertTo-Json -Depth 4
}

if ($Unassign) {
    Write-Host "\n-- Unassign mode: removing All Devices / All Users assignments --" -ForegroundColor Magenta
    if (-not $Force) {
        $resp = Read-Host "Type YES to continue (this will remove global assignments)"
        if ($resp -ne 'YES') { Write-Host 'Aborted.' -ForegroundColor Yellow; return }
    }

    foreach ($item in $rows) {
        switch ($item.Type) {
            'SettingsCatalogPolicy' {
                $id = $item.Id
                $assignUri = "$betaBase/deviceManagement/configurationPolicies/$id/assignments"
                $all = (Invoke-MgGraphRequest -Method GET -Uri $assignUri).value
                if (-not $all) { continue }
                $remaining = @()
                foreach ($a in $all) {
                    $t = $a.target.'@odata.type'
                    if ($t -in '#microsoft.graph.allDevicesAssignmentTarget','#microsoft.graph.allLicensedUsersAssignmentTarget') { continue }
                    $remaining += @{ target = $a.target }
                }
                $body = @{ assignments = $remaining } | ConvertTo-Json -Depth 6
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "$betaBase/deviceManagement/configurationPolicies/$id/assign" -Body $body | Out-Null
                    Write-Host "Removed global assignment(s) from SettingsCatalogPolicy $id" -ForegroundColor Green
                } catch { Write-Warning "Failed to update assignments for configurationPolicy $id : $($_.Exception.Message)" }
            }
            'DeviceConfiguration' {
                $id = $item.Id
                $assignUri = "$betaBase/deviceManagement/deviceConfigurations/$id/assignments"
                $all = (Invoke-MgGraphRequest -Method GET -Uri $assignUri).value
                if (-not $all) { continue }
                $remaining = @()
                foreach ($a in $all) {
                    $t = $a.target.'@odata.type'
                    if ($t -in '#microsoft.graph.allDevicesAssignmentTarget','#microsoft.graph.allLicensedUsersAssignmentTarget') { continue }
                    $remaining += @{ target = $a.target }
                }
                $body = @{ assignments = $remaining } | ConvertTo-Json -Depth 6
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "$betaBase/deviceManagement/deviceConfigurations/$id/assign" -Body $body | Out-Null
                    Write-Host "Removed global assignment(s) from DeviceConfiguration $id" -ForegroundColor Green
                } catch { Write-Warning "Failed to update assignments for deviceConfiguration $id : $($_.Exception.Message)" }
            }
            'macOSApp' {
                $id = $item.Id
                $assignUri = "$betaBase/deviceAppManagement/mobileApps/$id/assignments"
                $all = (Invoke-MgGraphRequest -Method GET -Uri $assignUri).value
                if (-not $all) { continue }
                $remaining = @()
                foreach ($a in $all) {
                    $t = $a.target.'@odata.type'
                    if ($t -in '#microsoft.graph.allDevicesAssignmentTarget','#microsoft.graph.allLicensedUsersAssignmentTarget') { continue }
                    $remaining += @{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        intent        = $a.intent
                        target        = $a.target
                    }
                }
                $body = @{ mobileAppAssignments = $remaining } | ConvertTo-Json -Depth 8
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "$betaBase/deviceAppManagement/mobileApps/$id/assign" -Body $body | Out-Null
                    Write-Host "Removed global assignment(s) from macOSApp $id" -ForegroundColor Green
                } catch { Write-Warning "Failed to update assignments for macOSApp $id : $($_.Exception.Message)" }
            }
            'ShellScript' {
                $id = $item.Id
                $assignUri = "$betaBase/deviceManagement/deviceShellScripts/$id/assignments"
                $all = @()
                try { $all = (Invoke-MgGraphRequest -Method GET -Uri $assignUri).value } catch { }
                if (-not $all) { continue }
                $remaining = @()
                foreach ($a in $all) {
                    $t = $a.target.'@odata.type'
                    if ($t -in '#microsoft.graph.allDevicesAssignmentTarget','#microsoft.graph.allLicensedUsersAssignmentTarget') { continue }
                    $remaining += @{
                        '@odata.type' = '#microsoft.graph.deviceManagementScriptAssignment'
                        target        = $a.target
                    }
                }
                $body = @{ deviceManagementScriptAssignments = $remaining } | ConvertTo-Json -Depth 6
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "$betaBase/deviceManagement/deviceShellScripts/$id/assign" -Body $body | Out-Null
                    Write-Host "Removed global assignment(s) from ShellScript $id" -ForegroundColor Green
                } catch { Write-Warning "Failed to update assignments for ShellScript $id : $($_.Exception.Message)" }
            }
            'CustomAttribute' {
                $id = $item.Id
                $assignUri = "$betaBase/deviceManagement/deviceCustomAttributeShellScripts/$id/assignments"
                $all = @()
                try { $all = (Invoke-MgGraphRequest -Method GET -Uri $assignUri).value } catch { }
                if (-not $all) { continue }
                $remaining = @()
                foreach ($a in $all) {
                    $t = $a.target.'@odata.type'
                    if ($t -in '#microsoft.graph.allDevicesAssignmentTarget','#microsoft.graph.allLicensedUsersAssignmentTarget') { continue }
                    $remaining += @{
                        '@odata.type' = '#microsoft.graph.deviceManagementScriptAssignment'
                        target        = $a.target
                    }
                }
                $body = @{ deviceManagementScriptAssignments = $remaining } | ConvertTo-Json -Depth 6
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "$betaBase/deviceManagement/deviceCustomAttributeShellScripts/$id/assign" -Body $body | Out-Null
                    Write-Host "Removed global assignment(s) from CustomAttribute $id" -ForegroundColor Green
                } catch { Write-Warning "Failed to update assignments for CustomAttribute $id : $($_.Exception.Message)" }
            }
            'CompliancePolicy' {
                $id = $item.Id
                $assignUri = "$betaBase/deviceManagement/deviceCompliancePolicies/$id/assignments"
                $all = (Invoke-MgGraphRequest -Method GET -Uri $assignUri).value
                if (-not $all) { continue }
                $remaining = @()
                foreach ($a in $all) {
                    $t = $a.target.'@odata.type'
                    if ($t -in '#microsoft.graph.allDevicesAssignmentTarget','#microsoft.graph.allLicensedUsersAssignmentTarget') { continue }
                    $remaining += @{
                        '@odata.type' = '#microsoft.graph.deviceCompliancePolicyAssignment'
                        target        = $a.target
                    }
                }
                $body = @{ assignments = $remaining } | ConvertTo-Json -Depth 6
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "$betaBase/deviceManagement/deviceCompliancePolicies/$id/assign" -Body $body | Out-Null
                    Write-Host "Removed global assignment(s) from CompliancePolicy $id" -ForegroundColor Green
                } catch { Write-Warning "Failed to update assignments for CompliancePolicy $id : $($_.Exception.Message)" }
            }
        }
    }
    Write-Host "Unassign operation complete." -ForegroundColor Magenta
}
