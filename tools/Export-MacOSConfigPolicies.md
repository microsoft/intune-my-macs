# Export-MacOSConfigPolicies.ps1

A PowerShell script to list and export macOS configuration policies from Microsoft Intune via Microsoft Graph.

## Overview

This script queries Microsoft Graph (beta) to retrieve all macOS-related configuration policies from your Intune tenant, including:

- **Classic Device Configurations** - Traditional macOS configuration profiles (e.g., `macOSCustomConfiguration`, `macOSDeviceFeaturesConfiguration`)
- **Settings Catalog Policies** - Modern settings catalog policies targeting the macOS platform

The script presents an indexed table of all discovered policies and optionally exports a selected policy to JSON for backup, documentation, or migration purposes.

## Requirements

- **PowerShell 7+** (cross-platform) or Windows PowerShell 5.1
- **Microsoft Graph PowerShell SDK** - Installed automatically if missing
- **Permissions** - `DeviceManagementConfiguration.Read.All` scope in Microsoft Graph

## Installation

No installation required. Ensure you have PowerShell and internet access. The script will install the Microsoft Graph module if needed.

## Usage

### Basic Usage

```powershell
# Navigate to the tools directory and run
pwsh ./Export-MacOSConfigPolicies.ps1
```

This will:

1. Connect to Microsoft Graph (prompts for authentication if needed)
2. Retrieve all macOS configuration policies
3. Display an indexed table
4. Prompt you to select a policy to export

### Parameters

| Parameter | Type | Default | Description |
| ----------- | ------ | --------- | ------------- |
| `-OutputFolder` | String | `./exports` | Destination folder for exported JSON files. Created automatically if missing. |
| `-SkipConnect` | Switch | `$false` | Skip the `Connect-MgGraph` call. Useful if you're already connected with the required scopes. |
| `-NoPrompt` | Switch | `$false` | Only list policies without prompting for export. |
| `-SelectId` | String | (none) | Directly export a specific policy by its ID without interactive selection. |

### Examples

#### List All macOS Policies (No Export)

```powershell
pwsh ./Export-MacOSConfigPolicies.ps1 -NoPrompt
```

Output:

```text
Index DisplayName                    Type                              Source  Id
----- -----------                    ----                              ------  --
    0 FileVault Policy               macOSEndpointProtection           Classic abc123...
    1 macOS Baseline                 SettingsCatalog                   Catalog def456...
    2 Custom Shell Script Settings   macOSCustomConfiguration          Classic ghi789...
```

#### Export a Specific Policy by ID

```powershell
pwsh ./Export-MacOSConfigPolicies.ps1 -SelectId "00000000-0000-0000-0000-000000000000"
```

#### Export to a Custom Folder

```powershell
pwsh ./Export-MacOSConfigPolicies.ps1 -OutputFolder "./backups/intune"
```

#### Skip Authentication (Already Connected)

```powershell
# If you've already run Connect-MgGraph with appropriate scopes
pwsh ./Export-MacOSConfigPolicies.ps1 -SkipConnect
```

## Output

### Console Output

The script displays a formatted table with:

- **Index** - Selection number for interactive export
- **DisplayName** - Policy name
- **Type** - Configuration type (e.g., `macOSEndpointProtection`, `SettingsCatalog`)
- **Source** - `Classic` or `Catalog`
- **Id** - Policy GUID

### Exported JSON

When a policy is exported, the script:

1. Creates the output folder if needed
2. Generates a filename: `{PolicyName}-{Timestamp}-{Id}.json`
3. Saves the complete policy object including:
   - All configuration settings
   - Metadata

Example output file: `FileVault_Policy-20240115-143022-abc12345-6789-0123-4567-890abcdef012.json`

### Return Object

After export, the script returns a summary object:

```powershell
ExportPath   : /path/to/exports/PolicyName-20240115-143022-abc123.json
Id           : abc12345-6789-0123-4567-890abcdef012
Name         : FileVault Policy
Source       : Classic
Type         : macOSEndpointProtection
SettingCount : 5  # Only for Settings Catalog policies
```

## Authentication

The script uses interactive authentication by default. On first run:

1. A browser window opens for Microsoft 365 sign-in
2. You authenticate with an account that has Intune admin permissions
3. The session is cached for subsequent runs

To use different authentication methods (certificates, managed identity, etc.), connect manually before running:

```powershell
# Example: Connect with specific tenant
Connect-MgGraph -TenantId "your-tenant-id" -Scopes "DeviceManagementConfiguration.Read.All"

# Then run with -SkipConnect
pwsh ./Export-MacOSConfigPolicies.ps1 -SkipConnect
```

## Common Use Cases

### Backup All Policies

```powershell
# Get list of all policy IDs
$policies = pwsh ./Export-MacOSConfigPolicies.ps1 -NoPrompt

# Export each one (in a loop or by selecting interactively)
```

### Document Current State

Use `-NoPrompt` to generate a quick inventory of all macOS policies in your tenant.

### Migration Preparation

Export policies to JSON before migrating to a new tenant or making significant changes.

## Troubleshooting

| Issue | Solution |
| ------- | ---------- |
| "No macOS configuration policies found" | Verify you're connected to the correct tenant and have policies configured |
| Authentication fails | Ensure your account has `DeviceManagementConfiguration.Read.All` permission |
| Module installation fails | Run PowerShell as administrator or use `-Scope CurrentUser` |
| Deeply nested settings truncated | Increase `-Depth` parameter in `ConvertTo-Json` (default is 20) |

## Related Tools

- [Find-DuplicatePayloadSettings.ps1](Find-DuplicatePayloadSettings.ps1) - Find duplicate settings across policies
- [Get-MacOSGlobalAssignments.ps1](Get-MacOSGlobalAssignments.ps1) - View policy assignments

## Notes

- This is a **read-only** operation; no changes are made to your Intune environment
- Uses the Microsoft Graph **beta** endpoint for full macOS policy support
- Settings Catalog exports include the `settings` expansion for complete data
