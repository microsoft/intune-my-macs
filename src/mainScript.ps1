# Requires: PowerShell 7+
$ErrorActionPreference = 'Stop'

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
#>

# Choose what to run
$importPolicies   = $true
$importPackages   = $true
$importScripts    = $true
$importCompliance = $true  # new: compliance policies

# Initialize created object trackers per run
$createdPolicyIds = @()
$createdComplianceIds = @()
$createdScriptIds = @()
$createdAppIds = @()

# set policy prefix
$policyPrefix = "[intune-my-mac] "

# connect to Graph (add apps scope + groups for assignments)
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All,DeviceManagementApps.ReadWrite.All,Group.Read.All" -NoWelcome

# Resolve repo root, if we cannot resolve we should exit (script is in src/)
$repoRoot = $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction Continue}
$repoRoot = Split-Path -Parent $repoRoot
if (-not $repoRoot) { Write-Error "Failed to resolve repository root; aborting."; exit 1 }

# ===================== Overview =====================
# Imports macOS Intune Policies, Shell Scripts, and PKG Apps defined via per-item XML manifests.
# Features:
#   --prefix=VALUE          : Name prefix for all created objects
#   --remove-all            : Delete existing prefixed policies/scripts/apps
#   --assign-group="Name"   : Assign newly created objects to specified Entra group (required intent for apps)
#   --apps / --policies / --scripts : Scope the import to specific object types


function Get-DistributedManifests {
    param(
        [Parameter(Mandatory)] [string] $BasePath
    )
    $xmlFiles = Get-ChildItem -Path $BasePath -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | Where-Object {
        try {
            $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
            $content -match '<MacIntuneManifest'
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
        $settingsCountRaw = $lookup['SettingsCount']
        $settingsCount = 0
        [int]::TryParse($settingsCountRaw, [ref]$settingsCount) | Out-Null

    if ($env:IMM_DEBUG -eq '1') { Write-Host "DEBUG: Elements found -> Type='$type'; Name='$name'; Category='$category'; SourceFile='$filePath'" -ForegroundColor Magenta }

        $obj = [PSCustomObject]@{
            type        = $type
            name        = $name
            description = $description
            platform    = $platform
            category    = $category
            filePath    = $filePath
        }

    switch ($type) {
            'Policy' { $obj | Add-Member -NotePropertyName settingCount -NotePropertyValue $settingsCount -Force }
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
        }
        $items += $obj
    }
    return ,$items
}

function Test-DistributedManifest {
    param([array]$Items)
    $errors = 0
    foreach ($item in $Items) {
        switch ($item.type) {
            'Policy' {
                foreach ($req in 'name','filePath') {
                    if (-not $item.$req) { Write-Warning ("Policy missing {0}: {1}" -f $req, ($item | ConvertTo-Json -Compress)); $errors++ }
                }
            }
            'Script' {
                foreach ($req in 'name','filePath','runAsAccount','blockExecutionNotifications','executionFrequency','retryCount') {
                    if ($null -eq $item.$req -or ($item.$req -is [string] -and [string]::IsNullOrWhiteSpace($item.$req))) { Write-Warning ("Script missing {0}: {1}" -f $req, $item.name); $errors++ }
                }
            }
            'Package' {
                foreach ($req in 'name','filePath','primaryBundleId','primaryBundleVersion','publisher','minimumSupportedOperatingSystem','ignoreVersionDetection') {
                    if (-not $item.$req) { Write-Warning ("Package missing {0}: {1}" -f $req, $item.name); $errors++ }
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
    try {
        Import-Module $ModuleName -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Installing beta Graph module '$ModuleName'..." -ForegroundColor Yellow
        try {
            Install-Module $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Import-Module $ModuleName -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning ("Failed to install/import {0}: {1}" -f $ModuleName, $_.Exception.Message)
            return $false
        }
    }
    return [bool](Get-Command -Name New-MgBetaDeviceAppManagementMobileApp -ErrorAction SilentlyContinue)
}


# Parse CLI args for selective processing
$removeAll = $false
$assignGroupName = $null
$argsLower = $args | ForEach-Object { $_.ToLowerInvariant() }
if ($argsLower.Count -gt 0) {
    $importPolicies = $false; $importPackages = $false; $importScripts = $false; $importCompliance = $false
    if ($argsLower -contains '--apps' -or $argsLower -contains '--packages') { $importPackages = $true }
    if ($argsLower -contains '--config' -or $argsLower -contains '--policies') { $importPolicies = $true }
    if ($argsLower -contains '--compliance') { $importCompliance = $true }
    if ($argsLower -contains '--scripts') { $importScripts = $true }
    $showAllScripts = $false
    if ($argsLower -contains '--show-all-scripts') { $showAllScripts = $true }
    if ($argsLower -contains '--remove-all') { $removeAll = $true }
    # Support custom prefix via --prefix="Value "
    foreach ($arg in $args) {
        if ($arg -like '--prefix=*') {
            $policyPrefix = $arg.Substring(9)
            if ($policyPrefix -and ($policyPrefix[-1] -ne ' ')) { $policyPrefix += ' ' }
        }
        if ($arg -like '--assign-group=*') {
            $assignGroupName = $arg.Substring(15).Trim('"')
        }
    }
    if (-not ($importPolicies -or $importPackages -or $importScripts -or $importCompliance)) {
        Write-Warning "No valid selector provided (--apps/--packages, --config/--policies, --scripts). Defaulting to all."
        $importPolicies = $true; $importPackages = $true; $importScripts = $true; $importCompliance = $true
        $showAllScripts = $true
    } else {
        Write-Host ("Selection: configPolicies={0} compliance={1} packages={2} scripts={3} showAllScripts={4}" -f $importPolicies, $importCompliance, $importPackages, $importScripts, $showAllScripts) -ForegroundColor Cyan
    }
}

function Remove-IntunePrefixedContent {
    param(
        [string]$Prefix
    )
    if (-not $Prefix) { Write-Error "Prefix is empty; refusing to continue."; return }
    Write-Host "Scanning Intune for policies, compliance policies, scripts, and apps beginning with prefix: '$Prefix'" -ForegroundColor Cyan

    $escapedFilterPolicies    = [System.Uri]::EscapeDataString("startsWith(name,'$Prefix')")
    $escapedFilterCompliance  = [System.Uri]::EscapeDataString("startsWith(displayName,'$Prefix')")
    $escapedFilterScripts     = [System.Uri]::EscapeDataString("startsWith(displayName,'$Prefix')")
    $escapedFilterApps        = [System.Uri]::EscapeDataString("startsWith(displayName,'$Prefix')")

    $policies = @(); $compliancePolicies = @(); $scripts = @(); $apps = @()
    try { $policies = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=$escapedFilterPolicies&`$select=id,name").value } catch { Write-Warning "Failed to query configuration policies: $($_.Exception.Message)" }
    try {
        # Some Graph endpoints for compliance policies may reject startsWith filter (400). Try filtered first.
        $compliancePolicies = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$filter=$escapedFilterCompliance&`$select=id,displayName").value
    } catch {
        Write-Warning "Failed to query compliance policies with server-side filter (will fallback to client filtering): $($_.Exception.Message)"
        try {
            $allCompliance = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$select=id,displayName").value
            if ($allCompliance) {
                $compliancePolicies = $allCompliance | Where-Object { $_.displayName -and $_.displayName.StartsWith($Prefix) }
            }
        } catch {
            Write-Warning "Fallback compliance policies query failed: $($_.Exception.Message)"
        }
    }
    try { $scripts  = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?`$filter=$escapedFilterScripts&`$select=id,displayName").value } catch { Write-Warning "Failed to query device shell scripts: $($_.Exception.Message)" }
    try { $apps     = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=$escapedFilterApps&`$select=id,displayName").value } catch { Write-Warning "Failed to query mobile apps: $($_.Exception.Message)" }

    $pCount = ($policies | Measure-Object).Count
    $cCount = ($compliancePolicies | Measure-Object).Count
    $sCount = ($scripts  | Measure-Object).Count
    $aCount = ($apps     | Measure-Object).Count
    if (($pCount + $cCount + $sCount + $aCount) -eq 0) {
        Write-Host "No Intune objects found with prefix '$Prefix'. Nothing to remove." -ForegroundColor Yellow
        return
    }

    Write-Host ""; Write-Host "The following Intune objects would be deleted:" -ForegroundColor Yellow
    if ($pCount -gt 0) {
        Write-Host "Policies ($pCount):" -ForegroundColor Magenta
        $policies | ForEach-Object { Write-Host "  • $($_.name)  [$($_.id)]" }
    }
    if ($cCount -gt 0) {
        Write-Host "Compliance Policies ($cCount):" -ForegroundColor Magenta
        $compliancePolicies | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($sCount -gt 0) {
        Write-Host "Scripts ($sCount):" -ForegroundColor Magenta
        $scripts | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }
    if ($aCount -gt 0) {
        Write-Host "Apps ($aCount):" -ForegroundColor Magenta
        $apps | ForEach-Object { Write-Host "  • $($_.displayName)  [$($_.id)]" }
    }

    Write-Host "Summary: $pCount config policies, $cCount compliance policies, $sCount scripts, $aCount apps will be permanently removed." -ForegroundColor Cyan
    $confirmation = Read-Host -Prompt "Type YES to confirm deletion or anything else to cancel"
    if ($confirmation -ne 'YES') { Write-Host "Deletion aborted by user." -ForegroundColor Yellow; return }

    # Delete configuration policies
    foreach ($p in $policies) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)" | Out-Null
            Write-Host "Deleted policy: $($p.name)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete policy $($p.name): $($_.Exception.Message)" }
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
    foreach ($a in $apps) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($a.id)" | Out-Null
            Write-Host "Deleted app: $($a.displayName)" -ForegroundColor Green
        } catch { Write-Warning "Failed to delete app $($a.displayName): $($_.Exception.Message)" }
    }
    Write-Host "Deletion complete." -ForegroundColor Cyan
}

if ($removeAll) {
    Remove-IntunePrefixedContent -Prefix $policyPrefix
    return
}

function Get-GroupIdByName {
    param([Parameter(Mandatory)][string]$DisplayName)
    try {
        $filter = [System.Uri]::EscapeDataString("displayName eq '$DisplayName'")
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName"
    $groupResults = @()
    if ($resp.value) { $groupResults = $resp.value }
    if ($groupResults.Count -eq 0) { Write-Error "Group not found: $DisplayName"; return $null }
    if ($groupResults.Count -gt 1) { Write-Warning "Multiple groups matched '$DisplayName'; using first." }
    return $groupResults[0].id
    } catch { Write-Error "Failed to resolve group '$DisplayName': $($_.Exception.Message)"; return $null }
}

$distributedItems = Get-DistributedManifests -BasePath $repoRoot

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
        [int]$ChunkSizeMB = 8
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

    # Creating temp file name from Source File path
    $tempName = ([System.IO.Path]::GetFileNameWithoutExtension($SourceFile)) + [guid]::NewGuid().ToString() + "_temp.bin"
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($SourceFile), $tempName)
        $fileName = (Get-Item $SourceFile).Name

        #Creating Intune app body JSON data to pass to the service
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow
        $body = New-macOSAppBody -displayName $displayName -Publisher $Publisher -Description $Description -fileName $fileName -primaryBundleId $primaryBundleId -primaryBundleVersion $primaryBundleVersion -includedApps $includedApps -minimumSupportedOperatingSystem $minimumSupportedOperatingSystem -ignoreVersionDetection $ignoreVersionDetection -preInstallScriptPath $preInstallScriptPath -postInstallScriptPath $postInstallScriptPath 

        # Create the Intune application object in the service
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
        $mobileApp = New-MgBetaDeviceAppManagementMobileApp -BodyParameter $body
        $mobileAppId = $mobileApp.id

        # Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
        $ContentVersion = New-MgBetaDeviceAppManagementMobileAppAsMacOSPkgAppContentVersion -MobileAppId $mobileAppId -BodyParameter @{}
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
        $ContentVersionFile = New-MgBetaDeviceAppManagementMobileAppAsMacOSPkgAppContentVersionFile -MobileAppId $mobileAppId -MobileAppContentId $ContentVersionId -BodyParameter $ContentVersionFileBody
        $ContentVersionFileId = $ContentVersionFile.id

        # Get the file URI for the upload
        $fileUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$mobileAppId/microsoft.graph.macOSPkgApp/contentVersions/$contentVersionId/files/$contentVersionFileId"

        # Wait for the service to process the file upload request.
        Write-Host "Waiting for the service to process the file upload request..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "AzureStorageUriRequest"
        $sasUriRenewTime = $file.azureStorageUriExpirationDateTime.AddMinutes(-3)

        # Upload the content to Azure Storage.
        Write-Host "Uploading file to Azure Storage..." -f Yellow
    [UInt64]$BlockSizeMB = [UInt64]$ChunkSizeMB
    UploadFileToAzureStorage $file.azureStorageUri $sasUriRenewTime $tempFile $BlockSizeMB 

        Write-Host "Committing the file to the service..." -ForegroundColor Yellow
        Invoke-MgBetaCommitDeviceAppManagementMobileAppMicrosoftGraphMacOSPkgAppContentVersionFile -MobileAppId $mobileAppId -MobileAppContentId $ContentVersionId -MobileAppContentFileId $ContentVersionFileId -BodyParameter ($encryptionInfo | ConvertTo-Json)

        # Wait for the service to process the commit file request.
        Write-Host "Waiting for the service to process the file commit request..." -ForegroundColor Yellow
        $file = WaitForFileProcessing $fileUri "CommitFile"

        # Commit the app.
        Write-Host "Committing the content version..." -ForegroundColor Yellow
        $params = @{
            "@odata.type"           = "#microsoft.graph.macOSPkgApp"
            committedContentVersion = "1"
        }
        
        Update-MgBetaDeviceAppManagementMobileApp -MobileAppId $mobileAppId -BodyParameter $params

        # Wait for the service to process the commit app request.
        Write-Host "Waiting for the service to process the app commit request..." -ForegroundColor Yellow

        $AppCheckAttempts = 25
        while ($AppCheckAttempts -gt 0) {
            $AppCheckAttempts--
            $AppStatus = Get-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId
            if ($AppStatus.PublishingState -eq "published") {
                Write-Host "Application created successfully." -ForegroundColor Green
                break
            }
            Start-Sleep -Seconds 3
        }

        if ($AppStatus.PublishingState -ne "published" -and $AppStatus.PublishingState -ne "processing") {
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
        # In the event that the creation of the app record in Intune succeeded, but processing/file upload failed, you can remove the comment block around the code below to delete the app record.
        # This will allow you to re-run the script without having to manually delete the incomplete app record.
        # Note: This will only work if the app record was successfully created in Intune.

        <#
        if ($mobileAppId) {
            Write-Host "Removing the incomplete application record from Intune..." -ForegroundColor Yellow
            Remove-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId
        }
        #>
        Write-Error "Aborting with exception: $($_.Exception.ToString())"
        throw $_
    }
    finally {
        # Cleaning up temporary files and directories
        Remove-Item -Path "$tempFile" -Force -ErrorAction SilentlyContinue
    }
    try { return (Get-MgDeviceAppManagementMobileApp -MobileAppId $mobileAppId) } catch { }
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
function UploadFileToAzureStorage($sasUri, $sasUriRenewTime, $filepath, $blockSizeMB, $mobileAppId, $ContentVersionId, $ContentVersionFileId) {
    # Chunk size in MiB
    $chunkSizeInBytes = 1024 * 1024 * $blockSizeMB
        $fileUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$mobileAppId/microsoft.graph.macOSLobApp/contentVersions/$ContentVersionId/files/$ContentVersionFileId"    # Read the whole file and find the total chunks.
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
            Invoke-MgRenewDeviceAppManagementMobileAppMicrosoftGraphMacOSLobAppContentVersionFileUpload -MobileAppId $mobileAppId -MobileAppContentId $ContentVersionId -MobileAppContentFileId $ContentVersionFileId
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


# Enumerate policies
if ($importPolicies) {
    $createdPolicyIds = @()
    $policies = $distributedItems | Where-Object { $_.type -eq 'Policy' }

    Write-Host "Found $($policies.Count) policies:`n" -ForegroundColor Cyan

    foreach ($p in $policies) {
        $policyPath = Join-Path $repoRoot $p.filePath
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
                # Override JSON name with XML manifest <Name> to keep single source of truth
                if ($policyPrefix) {
                    $policyContent.name = $policyPrefix + $p.name
                } else {
                    $policyContent.name = $p.name
                }
            $policyContentJson = ConvertTo-Json -InputObject $policyContent -Depth 20

            # create policy with json content
            $policyImportResults = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Body $policyContentJson
            if ($policyImportResults) {
                Write-Host "  - Policy $($policyImportResults.name) imported successfully with ID: $($policyImportResults.id)" -ForegroundColor Green
                $createdPolicyIds += $policyImportResults.id
            } else {
                Write-Host "  - Policy import failed or returned no results." -ForegroundColor Red
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
        $compPath = Join-Path $repoRoot $c.filePath
        $exists = Test-Path -LiteralPath $compPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }
        $desc = $c.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0,137)+'...' }
        Write-Host "• $($c.name)" -ForegroundColor Yellow
        Write-Host "  - Path: $($c.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }
        if (-not $exists) { Write-Warning "Compliance JSON missing, skipping."; Write-Host ''; continue }
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
            $resp = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" -Body $body
            if ($resp -and $resp.id) {
                Write-Host "  - Compliance policy imported with ID: $($resp.id)" -ForegroundColor Green
                $createdComplianceIds += $resp.id
            } else {
                Write-Warning "  - Import returned no ID"
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
        $scriptPath = Join-Path $repoRoot $s.filePath
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
        if (-not $exists) { Write-Warning "Script file missing, skipping upload."; Write-Host ''; continue }
        try {
            $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($scriptContent))
            $displayName = $policyPrefix + $s.name
            $fileName = [IO.Path]::GetFileName($scriptPath)
            
            # Use deviceShellScripts for macOS shell scripts to appear in Devices > macOS > Scripts
            $body = @{ 
                '@odata.type' = '#microsoft.graph.deviceShellScript'
                displayName = $displayName
                description = $s.description
                scriptContent = $encoded
                fileName = $fileName
                runAsAccount = $s.runAsAccount
            }
            $json = $body | ConvertTo-Json -Depth 5
            $result = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts' -Body $json
            if ($result -and $result.id) { 
                Write-Host "  - Script $($result.displayName) imported with ID: $($result.id)" -ForegroundColor Green 
                $createdScriptIds += $result.id
            } else { 
                Write-Host "  - Script import failed (no ID)" -ForegroundColor Red 
            }
        } catch {
            Write-Error "Failed to import script '$($s.name)': $_"
        }
    }
    
    # Removed legacy verification block for simplicity
}

# Enumerate packages/apps
if ($importPackages) {
    $createdAppIds = @()
    $packages = $distributedItems | Where-Object { $_.type -in @('Package','App') }

    Write-Host "Found $($packages.Count) packages/apps:`n" -ForegroundColor Cyan

    foreach ($a in $packages) {
        $assetPath = Join-Path $repoRoot $a.filePath
        $exists = Test-Path -LiteralPath $assetPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }

        $desc = $a.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0, 137) + '...' }

        Write-Host "• $($a.name)" -ForegroundColor Yellow
        Write-Host "  - Category: $($a.category); Platform: $($a.platform)"
        Write-Host "  - Path: $($a.filePath) [$status]"
        if ($desc) { Write-Host "  - Desc: $desc" }
        Write-Host "  - preinstallscript: $($a.preinstallscript)"
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
        if ($a.preinstallscript) {
            $preinstallScript = Join-Path $repoRoot $a.preinstallscript
        } else {
            $preinstallScript = $null
        }

        # add postInstall script if needed
        if ($a.postInstallScript) {
            $postInstallScript = Join-Path $repoRoot $a.postInstallScript
        } else {
            $postInstallScript = $null
        }

    if (-not $exists) { Write-Warning "Package source file missing, skipping upload."; continue }
    if (-not (Test-BetaModule)) { Write-Warning "Required beta Graph module missing; skipping package upload."; continue }
    $appResult = Invoke-macOSLobAppUpload -SourceFile $assetPath `
            -displayName "$($displayName)" -Publisher "$($a.publisher)" -Description "$($desc)" `
            -primaryBundleId "$($a.primaryBundleId)" -primaryBundleVersion "$($a.primaryBundleVersion)" `
            -preInstallScriptPath $preinstallScript -postInstallScriptPath $postInstallScript `
            -includedApps $includedApps -minimumSupportedOperatingSystem $minimumSupportedOperatingSystem `
            -ignoreVersionDetection $ignoreVersionDetection -ChunkSizeMB 8
    if ($appResult -and $appResult.id) { $createdAppIds += $appResult.id } else { Write-Warning "Could not capture app ID for: $displayName" }

    }

}

# Perform assignments if requested
if ($assignGroupName) {
    Write-Host ""; Write-Host "Assignment requested for group: $assignGroupName" -ForegroundColor Cyan
    $groupId = Get-GroupIdByName -DisplayName $assignGroupName
    if ($groupId) {
        Write-Host "Resolved group '$assignGroupName' to ID $groupId" -ForegroundColor Green

    # Assign Configuration Policies via assignments resource
    foreach ($policyId in ($createdPolicyIds | Sort-Object -Unique)) {
            try {
                $assignBody = @{ assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) } | ConvertTo-Json -Depth 6
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$policyId/assign" -Body $assignBody | Out-Null
        Write-Host "Assigned policy $policyId to group" -ForegroundColor Green
        } catch { Write-Warning "Failed to assign policy ${policyId}: $($_.Exception.Message)" }
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
    } else {
        Write-Warning "Skipping assignments; group not resolved."
    }
}
