# 🚀 Intune My Macs

Automate a Microsoft Intune macOS proof-of-concept in minutes: policies, compliance, scripts, PKG apps, and optional Microsoft Defender for Endpoint (MDE) are deployed from a single script.

---

## Quick Start (≈5 min)

### 1. Install prerequisites
**macOS**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install --cask powershell
```

**Windows**
```powershell
winget install Microsoft.PowerShell
```

> PowerShell modules (Microsoft Graph) are installed on demand the first time you run the script.

### 2. Prepare your tenant.
- **MDM Authority:** determines how you manage your devices (cannot be none). [Learn how](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/mdm-authority-set).
- **APNS certificate:** Required for any macOS enrollment. [Learn how](https://learn.microsoft.com/mem/intune/enrollment/apple-mdm-push-certificate-get).
- **Permissions:** Use an Intune Administrator (or equivalent) or grant `DeviceManagementConfiguration.ReadWrite.All`, `DeviceManagementApps.ReadWrite.All`, `DeviceManagementManagedDevices.ReadWrite.All`.
- **Optional MDE:** Download your org-specific onboarding file before using `--mde` (see [`mde/README.md`](mde/README.md) for detailed steps).

### 3. Clone and run
```bash
git clone https://github.com/microsoft/intune-my-macs.git
cd intune-my-macs
# Preview (dry-run)
pwsh ./mainScript.ps1 --assign-group "Intune Mac Pilot"

# Push changes
pwsh ./mainScript.ps1 --assign-group "Intune Mac Pilot" --apply
```

> The script defaults to **dry-run mode**. Nothing is created until you add `--apply`.

### 4. Common flags
| Flag | Purpose |
|------|---------|
| `--apps`, `--config`, `--compliance`, `--scripts`, `--custom-attributes` | Limit the import scope to specific artifact types |
| `--assign-group "Name"` | Assign every created object to an Entra group |
| `--prefix "[custom]"` | Override the default naming prefix |
| `--mde` | Include the `mde/` content (requires onboarding file) |
| `--remove-all` | Delete previously created objects that use the current prefix |
| `--apply` | Actually create/update/delete Intune objects (otherwise it's a preview) |

---

## What gets deployed
- **Security & configuration policies:** FileVault, Firewall, Gatekeeper, guest restrictions, login window, screen saver, managed login items, NTP, Office, Declarative Device Management, and more.
- **Compliance & scripts:** macOS compliance policy, enrollment restrictions, device scripts (Company Portal install, Dock customization, Escrow Buddy, etc.).
- **Applications:** [Swift Dialog](https://github.com/swiftDialog/swiftDialog), Office 365, Teams, M365 Copilot, [Intune Log Watch](https://github.com/gilburns/IntuneLogWatch).
- **Custom attributes:** Hardware compatibility checks and other helpers.
- **Optional MDE:** Defender installer (see `mde/README.md`).

For the full artifact catalog and settings, see `INTUNE-MY-MACS-DOCUMENTATION.md` or generate a fresh Word doc with `tools/Generate-ConfigurationDocumentation.py`.

---

## Learn more
- [`INTUNE-MY-MACS-DOCUMENTATION.md`](INTUNE-MY-MACS-DOCUMENTATION.md) – overview of every artifact.
- [`mde/README.md`](mde/README.md) – Defender prerequisites and onboarding steps.
- [`tools/README.md`](tools/README.md) – Utilities such as documentation export, duplicate payload detection, and processing-order reports.

---

## Troubleshooting at a glance
- **Auth or permission errors:** Re-run `pwsh ./mainScript.ps1` after confirming the Graph permissions above; modules auto-install per user.
- **Devices not receiving policies:** Verify APNS, device enrollment, and group membership, then force a device sync.

---

Built with ❤️ by the **Microsoft Intune Customer Experience Engineering team**