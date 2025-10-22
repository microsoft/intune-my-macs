```
  ___       _                        __  __           __  __                     
 |_ _|_ __ | |_ _   _ _ __   ___     |  \/  |_   _    |  \/  | __ _  ___ ___      
  | || '_ \| __| | | | '_ \ / _ \    | |\/| | | | |   | |\/| |/ _` |/ __/ __|     
  | || | | | |_| |_| | | | |  __/    | |  | | |_| |   | |  | | (_| | (__\__ \     
 |___|_| |_|\__|\__,_|_| |_|\___|    |_|  |_|\__, |   |_|  |_|\__,_|\___|___/     
                                             |___/                             
```

## 🚀 Automation for Intune + macOS Proof of Concept

**Intune My Macs** is a comprehensive automation project designed to streamline your Microsoft Intune environment setup for macOS proof of concept deployments. Built with ❤️ by the **Intune Customer Experience Engineering team**.

### 🎯 What This Project Does

This automation toolkit helps you:
- **Rapidly configure** your Intune environment for macOS device management
- **Streamline POC setup** with pre-configured policies and profiles
- **Reduce deployment time** from days to hours
- **Follow best practices** established by Microsoft's Intune engineering team

### 🛠️ Built For IT Professionals

Whether you're a seasoned IT administrator or just getting started with Intune, this project provides the building blocks to demonstrate the power of Microsoft Intune for macOS device management.

---

## 🧩 Getting Started

The project automates upload of macOS policies, compliance, scripts, PKG apps, and custom configuration profiles into Intune using Microsoft Graph.

### Prerequisites

Mac:
- macOS 13 or later (tested on macOS 14/15 and 26 "Tahoe")
- Homebrew (recommended)
- PowerShell 7+ (`brew install --cask powershell`)
- Microsoft Graph PowerShell SDK modules (installed on first run if missing)

Windows:
- Windows 10/11
- PowerShell 7+ (optional but recommended; Windows PowerShell 5.1 works for most functions except some UTF-8 handling)
- Microsoft Graph PowerShell SDK (`Install-Module Microsoft.Graph -Scope CurrentUser`)

General:
- Intune tenant + account with: DeviceManagementConfiguration.ReadWrite.All, DeviceManagementApps.ReadWrite.All (or equivalent role)
- An Azure AD (Entra ID) security group if you plan to use assignment (`--assign-group`)

### Clone the Repository

Mac (Terminal):
```
git clone https://github.com/microsoft/intune-my-macs.git
cd intune-my-macs
```

Windows (PowerShell):
```
git clone https://github.com/microsoft/intune-my-macs.git
Set-Location intune-my-macs
```

### (Optional) Remove Large Test Artifacts
If you accidentally add large `.pkg` test files, ensure they are excluded:
```
echo '*.pkg' >> .gitignore
```

### Run the Main Import Script

From the `src` directory run `mainScript.ps1` (PowerShell 7 recommended):
```
pwsh ./src/mainScript.ps1 --assign-group "<group-display-name>" --mde
```

Common switches:
- `--assign-group="GroupName"`   Assign newly created items to a group
- `--mde`                         Include Defender (MDE) manifests under `mde/`
- `--remove-all`                  Delete existing Intune objects with the current prefix before import
- `--prefix="[intune-my-macs] "`  Override the default naming prefix

### Adding or Updating Content
1. Place PKG files under `apps/` with accompanying XML manifest
2. Add scripts under `scripts/intune/` and create a matching XML manifest
3. Add configuration JSON (.json) under `configurations/intune/` and add an XML manifest pointing to it
4. For custom `.mobileconfig` profiles: set `Type` to `CustomConfig` in the manifest
5. Re-run the script; only new or changed items are created (idempotent design)

### Structure of a Manifest (Example: Script)
```
<MacIntuneManifest>
  <Type>Script</Type>
  <Name>10 - Company Portal Install</Name>
  <Description>Install Microsoft Company Portal via signed PKG.</Description>
  <Platform>macOS</Platform>
  <Category>Config</Category>
  <SourceFile>scripts/intune/10 - install-company-portal.zsh</SourceFile>
  <Script>
    <RunAsAccount>system</RunAsAccount>
    <ExecutionFrequency>PT0S</ExecutionFrequency>
    <RetryCount>3</RetryCount>
  </Script>
</MacIntuneManifest>
```

### Export Existing macOS Policies
Use the export tool to capture current settings catalog policies:
```
pwsh ./tools/Get-MacOSConfigPolicies.ps1
```

### List / Unassign Global Assignments
```
pwsh ./tools/Get-MacOSGlobalAssignments.ps1 -OutputJson
pwsh ./tools/Get-MacOSGlobalAssignments.ps1 -Unassign -Force
```

### Troubleshooting
- Missing modules: The script attempts to import Graph modules; install manually if needed.
- Large file push blocked: Remove the file from Git history (see earlier guidance) or use Git LFS if required.
- Custom config (mobileconfig) failing: Ensure `payloadName` and `payloadFileName` are present (already handled in latest script).
- Permissions errors: Verify account has correct Intune RBAC / Graph permissions.

### Next Steps
- Adjust manifests to match your naming standards
- Add more policies or scripts
- Integrate into a CI pipeline to seed demo tenants automatically

---

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
