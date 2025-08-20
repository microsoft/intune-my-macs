# Requires: PowerShell 7+
$ErrorActionPreference = 'Stop'

#requires -module Microsoft.Graph.Beta.Devices.CorporateManagement
#requires -module Microsoft.Graph.Authentication

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
$importPolicies = $true
$importPackages = $true
$importScripts = $true

# set policy prefix
$policyPrefix = "[CK-import] "

# connect to Graph
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All" -NoWelcome

# Resolve repo root (script is in src/, manifest is at repo root)
$repoRoot = $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction Continue}
if (-not $repoRoot) { $repoRoot = "C:\temp\intune-my-macs"}

# set manifest path
$manifestPath = Join-Path $repoRoot 'manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Error "manifest.json not found at: $manifestPath"
    exit 1
}

# Load manifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

# Header
if ($manifest.metadata) {
    Write-Host "Manifest: $($manifest.metadata.title) v$($manifest.metadata.version) ($($manifest.metadata.lastUpdated))" -ForegroundColor Cyan
}

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

        #Check if minmumSupportedOperatingSystem is provided. If not, default to v10_13
        if ($minimumSupportedOperatingSystem -eq $null) {
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
    $fileUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$mobileAppId/microsoft.graph.macOSPkgApp/contentVersions/$ContentVersionId/files/$ContentVersionFileId"

    # Read the whole file and find the total chunks.
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
            Invoke-MgBetaRenewDeviceAppManagementMobileAppMicrosoftGraphMacOSPkgAppContentVersionFileUpload -MobileAppId $mobileAppId -MobileAppContentId $ContentVersionId -MobileAppContentFileId $ContentVersionFileId
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

    if ($preInstallScriptPath) {
        $body.preInstallScript = @{
            scriptContent = Convert-ScriptToBase64($preInstallScriptPath)
        }
    }
    else {
        $body.preInstallScript = $null
    }

    if ($postInstallScriptPath) {
        $body.postInstallScript = @{
            scriptContent = Convert-ScriptToBase64($postInstallScriptPath)
        }
    }
    else {
        $body.postInstallScript = $null
    }
    
    return $body
}


# Enumerate policies
if ($importPolicies) {
    $policies = @()
    if ($manifest.policies) {
        $policies = $manifest.policies | Where-Object { $_.type -eq 'Policy' }
    }

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
            $policyContent.name = $policyPrefix + $policyContent.name
            $policyContentJson = ConvertTo-Json -InputObject $policyContent -Depth 20

            # create policy with json content
            $policyImportResults = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Body $policyContentJson
            if ($policyImportResults) {
                Write-Host "  - Policy $($policyImportResults.name)imported successfully with ID: $($policyImportResults.id)" -ForegroundColor Green
            } else {
                Write-Host "  - Policy import failed or returned no results." -ForegroundColor Red
            }

        } catch {
            Write-Error "Failed to process policy '$($p.name)': $_"
        }
        Write-Host ""

    }
}

# Enumerate packages/apps
if ($importPackages) {
    $packages = @()
    if ($manifest.policies) {
        $packages = $manifest.policies | Where-Object { $_.type -in @('Package','App') }
    }

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
                "@odata.type" = "microsoft.graph.macOSIncludedApp"
                bundleId      = "$($a.primaryBundleId)"
                bundleVersion = "$($a.primaryBundleVersion)"
            }
        )

        # add preinstall script if needed
        if ($a.preinstallscript) {
            $preinstallScript = Get-Content -Path $a.preinstallscript -Raw
        } else {
            $preinstallScript = $null
        }

        # add postInstall script if needed
        if ($a.postInstallScript) {
            $postInstallScript = Get-Content -Path $a.postInstallScript -Raw
        } else {
            $postInstallScript = $null
        }

        Invoke-macOSLobAppUpload -SourceFile "c:\temp\Microsoft_Remote_Help_1.0.2501211_installer.pkg" `
        -displayName "$($displayName)" -Publisher "$($a.publisher)" -Description "$($desc)" `
        -primaryBundleId "$($a.primaryBundleId)" -primaryBundleVersion "$($a.primaryBundleVersion)" `
        -preInstallScriptPath $preinstallScript -postInstallScriptPath $postInstallScript `
        -includedApps $includedApps -minimumSupportedOperatingSystem $minimumSupportedOperatingSystem `
        -ignoreVersionDetection $ignoreVersionDetection -ChunkSizeMB 8
    }
}


# Enumerate scripts
if ($importScripts) {
    $scripts = @()
    if ($manifest.policies) {
        $scripts = $manifest.policies | Where-Object { $_.type -eq 'Script' }
    }

    Write-Host "Found $($scripts.Count) scripts:`n" -ForegroundColor Cyan

    foreach ($s in $scripts) {
        $scriptPath = Join-Path $repoRoot $s.filePath
        $exists = Test-Path -LiteralPath $scriptPath
        $status = if ($exists) { 'OK' } else { 'MISSING' }

        $desc = $s.description
        if ($null -ne $desc -and $desc.Length -gt 140) { $desc = $desc.Substring(0, 137) + '...' }

        Write-Host "• $($s.name)" -ForegroundColor Yellow
        Write-Host "  - Platform: $($s.platform); RequiresElevation: $($s.requiresElevation)"
        Write-Host "  - Intune: RunAsSignedInUser=$($s.runAsSignedInUser); HideNotifications=$($s.hideNotifications); Frequency='$($s.frequency)'; MaxRetries=$($s.maxRetries)"
        Write-Host "  - Path: $($s.filePath) [$status]"
        
        try {
            if ($desc) { Write-Host "  - Desc: $desc" }
            # Read the script content
            $ScriptContent = Get-Content -Path $s.filePath -Raw
            $EncodedScript = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ScriptContent))
            $scriptJson = @{
                displayName = $policyPrefix + $s.name
                description = $s.description
                scriptContent = $EncodedScript
                runAsAccount = $s.runAsAccount
                fileName = [System.IO.Path]::GetFileName($s.filePath)
                roleScopeTagIds = @("0")
                blockExecutionNotifications = $s.blockExecutionNotifications
                retryCount = $s.retryCount
                executionFrequency = $s.executionFrequency
            } | ConvertTo-Json -Depth 20

            $scriptImportResults = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts" -Body $scriptJson

            Write-Host "  - Script '$($scriptImportResults.displayName)' imported successfully." -ForegroundColor Green
        } catch {
            Write-Error "Failed to import script '$($s.name)': $_"
        }

        Write-Host ""
    }
}