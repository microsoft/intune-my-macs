```
  ___       _                        __  __           __  __                     
 |_ _|_ __ | |_ _   _ _ __   ___     |  \/  |_   _    |  \/  | __ _  ___ ___      
  | || '_ \| __| | | | '_ \ / _ \    | |\/| | | | |   | |\/| |/ _` |/ __/ __|     
  | || | | | |_| |_| | | | |  __/    | |  | | |_| |   | |  | | (_| | (__\__ \     
 |___|_| |_|\__|\__,_|_| |_|\___|    |_|  |_|\__, |   |_|  |_|\__,_|\___|___/     
                                             |___/                             
```

# 🚀 Intune My Macs

**Automate your Microsoft Intune macOS environment setup in minutes, not days.**

Built with ❤️ by the **Microsoft Intune Customer Experience Engineering team**, this toolkit deploys a set of macOS specific policies, compliance settings, scripts, and applications to your Intune tenant automatically.

Perfect for proof-of-concept deployments, demo environments, or jump-starting your macOS management journey.

---

## ⚡ Quick Start

Get up and running in 5 minutes:

### 1️⃣ Install Prerequisites

**On macOS:**
```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install PowerShell
brew install --cask powershell
```

**On Windows:**
```powershell
# Install PowerShell 7+ (optional but recommended)
winget install Microsoft.PowerShell
```

### 2️⃣ Clone the Repository

```bash
git clone https://github.com/microsoft/intune-my-macs.git
cd intune-my-macs
```

### 3️⃣ Run the Deployment Script

**Basic deployment (no assignments):**
```bash
pwsh ./mainScript.ps1
```

**Deploy and assign to a group:**
```bash
pwsh ./mainScript.ps1 --assign-group "Pilot Macs"
```

The script will:
- ✅ Authenticate to Microsoft Graph
- ✅ Install required PowerShell modules automatically
- ✅ Upload all policies, scripts, and applications
- ✅ Assign configurations to your specified group (optional)

---

## 📋 Dependencies

Before deploying, ensure your Intune tenant has the following configured:

### Required: Apple Push Notification Service (APNS) Certificate

**Critical:** macOS device management in Intune requires a valid APNS certificate. Without this, devices cannot enroll or receive policies.

**Setup Instructions:**
1. Sign in to [Microsoft Intune admin center](https://intune.microsoft.com)
2. Navigate to **Devices** > **Enrollment** > **Apple enrollment** > **Apple MDM Push certificate**
3. Follow the wizard to download a CSR and upload it to [Apple Push Certificates Portal](https://identity.apple.com/pushcert)
4. Download the certificate from Apple and upload it back to Intune

**Documentation:** [Get an Apple MDM push certificate](https://learn.microsoft.com/mem/intune/enrollment/apple-mdm-push-certificate-get)

### Microsoft Graph API Permissions

Your account needs one of the following:

**Option 1 - Specific Graph Permissions:**
- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementApps.ReadWrite.All`
- `DeviceManagementManagedDevices.ReadWrite.All`

**Option 2 - Intune RBAC Role:**
- Intune Administrator
- Policy and Profile Manager

The script will prompt for authentication on first run and install Microsoft Graph PowerShell SDK modules if missing.

### Optional: Microsoft Defender for Endpoint

If deploying Microsoft Defender for Endpoint (using `--mde` flag), you need:

1. **MDE License:** Microsoft Defender for Endpoint Plan 1/2, or Microsoft 365 E5/A5/G5
2. **Onboarding File:** Download your organization's unique onboarding configuration from the [Microsoft Defender Portal](https://security.microsoft.com)
   - Place it as: `mde/cfg-mde-001-onboarding.mobileconfig`
   - See [mde/README.md](mde/README.md) for detailed instructions

**Without the onboarding file, MDE deployment will fail.**

---

## 📦 What Gets Deployed

This repository includes **31 production-ready artifacts** across multiple categories:

### 🔒 Security Policies
- FileVault encryption configuration
- Firewall settings (stealth mode enabled)
- Gatekeeper security enforcement
- Guest account restrictions
- Login window security
- Screen saver idle time and security
- Declarative Device Management (DDM) passcode policy

### 📱 Device Configuration
- Microsoft Entra ID Platform SSO
- Managed Login Items
- Network Time Protocol (NTP) configuration
- Microsoft Office settings
- Device restrictions

### 🛡️ Compliance & Enrollment
- macOS compliance policy
- macOS enrollment restrictions

### 🌐 Secure Enterprise Browser
Three progressive Edge security configurations:
- **Level 1:** Basic security for standard corporate environments (22 settings)
- **Level 2:** Enhanced security for compliance requirements (33 settings)
- **Level 3:** High security for zero-trust environments (53 settings)

### 🔧 Shell Scripts
- Company Portal installation
- Microsoft Office default associations
- Escrow Buddy (FileVault key escrow)
- Device renaming automation
- Dock configuration

### 📦 Applications
- Swift Dialog v2.5.6
- Swift Dialog Onboarding (with Company Portal, Office, Edge, Copilot)
- macOS Compatibility Checker

### 🛡️ Microsoft Defender for Endpoint (Optional)
**Note:** Requires additional setup - see [mde/README.md](mde/README.md)
- Microsoft Defender installation script
- Defender settings catalog configuration
- Onboarding profile (you must provide your organization's onboarding file)

**To deploy MDE:** Use the `--mde` flag when running mainScript.ps1

### Custom Attributes
- macOS compatibility checker for hardware assessment

**Full documentation:** Run `tools/Generate-ConfigurationDocumentation.py` to generate a comprehensive Word document with all settings.

---

## 🛠️ Management Tools

Five PowerShell and Python utilities help you manage and analyze your Intune configurations:

| Tool | Purpose |
|------|---------|
| **Generate-ConfigurationDocumentation.py** | Generate professional Word documentation from all policies |
| **Export-MacOSConfigPolicies.ps1** | Export existing policies from Intune to JSON files |
| **Find-DuplicatePayloadSettings.ps1** | Detect duplicate or conflicting settings across policies |
| **Get-IntuneAgentProcessingOrder.ps1** | Show the order Intune Agent processes scripts and apps |
| **Get-MacOSGlobalAssignments.ps1** | Find policies assigned to "All Devices" or "All Users" |

**Detailed usage:** See [tools/README.md](tools/README.md) for complete documentation and examples.

---

## 📚 Repository Structure

```
intune-my-macs/
├── mainScript.ps1           # Main deployment automation script
├── configurations/          # Intune configuration policies and profiles
│   ├── intune/              # Device restrictions, compliance, security
│   ├── entra/               # Entra ID Platform SSO configuration
│   └── Secure Enterprise Browser/  # Three levels of Edge security
├── scripts/                 # Shell scripts deployed via Intune
│   └── intune/              # Device management automation scripts
├── apps/                    # .pkg installers and app deployment configs
├── mde/                     # Microsoft Defender for Endpoint configuration
├── custom attributes/       # Custom inventory attributes
└── tools/                   # Management and documentation utilities

```

Each configuration, script, and app includes:
- **JSON/mobileconfig file:** The actual policy or configuration
- **XML manifest:** Metadata including name, description, assignment instructions
- **README (where applicable):** Detailed documentation

---

## 🎯 Common Workflows

### Deploy Everything with Assignments

```bash
pwsh ./mainScript.ps1 --assign-group "Pilot Macs"
```

Uploads all configurations and assigns them to the specified Azure AD group.

### Generate Documentation

```bash
cd tools
python3 Generate-ConfigurationDocumentation.py
```

Creates `INTUNE-MY-MACS-DOCUMENTATION.docx` with a professional breakdown of all 31 artifacts and their settings.

### Find Duplicate Settings

```bash
cd tools
pwsh ./Find-DuplicatePayloadSettings.ps1
```

Identifies conflicts where the same setting has different values across multiple policies.

### Export Current Policies

```bash
cd tools
pwsh ./Export-MacOSConfigPolicies.ps1
```

Backs up your current Intune policies to JSON files for version control or migration.

### Check Global Assignments

```bash
cd tools
pwsh ./Get-MacOSGlobalAssignments.ps1
```

Lists all policies assigned to "All Devices" or "All Users" to audit overly broad assignments.

---

## 🔧 Customization

### Modify Policies Before Deployment

1. Edit the JSON or `.mobileconfig` files in `configurations/intune/`
2. Update the corresponding XML manifest if changing names
3. Run `mainScript.ps1` to deploy the updated configurations

### Add New Policies

1. Create the configuration file (JSON or `.mobileconfig`)
2. Create an XML manifest following the existing examples
3. Place both files in the appropriate directory
4. The main script will automatically detect and deploy them

### Change Assignment Strategy

Edit the XML manifest files to set assignment behavior:
```xml
<AssignmentType>Include</AssignmentType>  <!-- or Exclude, or none for manual -->
```

---

## 🚨 Troubleshooting

### Authentication Issues

**Error:** "Insufficient permissions"
- **Solution:** Verify your account has `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementApps.ReadWrite.All` permissions or an appropriate Intune role

### Module Installation Failures

**Error:** "Cannot install Microsoft.Graph modules"
- **Solution (macOS):** Run `pwsh` as your user (not sudo). Modules install to user profile
- **Solution (Windows):** Run `Install-Module Microsoft.Graph -Scope CurrentUser` manually

### Policies Not Appearing on Devices

**Error:** Devices aren't receiving configurations
- **Check 1:** Verify APNS certificate is valid (Intune admin center > Enrollment > Apple enrollment)
- **Check 2:** Confirm devices are enrolled and showing in Intune
- **Check 3:** Verify group assignment matches device membership
- **Check 4:** Check Intune device sync status (can take up to 8 hours initially, then ~1 hour)

### Script Execution Errors on macOS

**Error:** "Cannot be loaded because running scripts is disabled"
- **Solution:** PowerShell on macOS doesn't have execution policy restrictions. Ensure you're running `pwsh` (PowerShell 7+), not `powershell`

### Large File Upload Blocked

**Error:** Git push fails due to file size
- **Solution:** Use Git LFS for large PKG files or remove from history if already committed

---

## 🤝 Contributing

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

From the repository root, run `mainScript.ps1` (PowerShell 7 recommended):
```bash
pwsh ./mainScript.ps1 --assign-group "<group-display-name>" --mde
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

---

## 🤝 Contributing

Contributions are welcome! Whether you're fixing a bug, adding a new policy, or improving documentation, we appreciate your help.

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-policy`)
3. Commit your changes (`git commit -m 'Add amazing new policy'`)
4. Push to the branch (`git push origin feature/amazing-policy`)
5. Open a Pull Request

### Contribution Guidelines

- Follow existing naming conventions for files and manifests
- Test your changes in a dev/test tenant before submitting
- Update documentation (README, manifest files) for any new configurations
- Ensure policies follow Microsoft security best practices

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with questions.

**Contributor License Agreement (CLA):** Most contributions require you to agree to a CLA declaring that you have the right to grant us the rights to use your contribution. Visit [Contributor License Agreements](https://cla.opensource.microsoft.com) for details.

---

## 📞 Support

- **Issues:** Report bugs or request features via [GitHub Issues](https://github.com/microsoft/intune-my-macs/issues)
- **Discussions:** Ask questions in [GitHub Discussions](https://github.com/microsoft/intune-my-macs/discussions)
- **Documentation:** Check [Microsoft Intune documentation](https://learn.microsoft.com/mem/intune/) for platform guidance

**Note:** This is a community-driven project. For official Intune support, contact Microsoft Support through your tenant.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ™️ Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third-party's policies.

---

## 🌟 Acknowledgments

Built with ❤️ by the **Microsoft Intune Customer Experience Engineering team** to help IT professionals accelerate their macOS management journey.

Special thanks to the Intune community for feedback, testing, and contributions that make this project better every day.

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
