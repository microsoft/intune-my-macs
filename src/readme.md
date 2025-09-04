## mainScript.ps1 – Intune macOS Automation

Automates importing and (optionally) assigning Intune artifacts for a macOS proof‑of‑concept environment:

Supported object types (current script version):
- Configuration Policies (deviceManagement/configurationPolicies)
- Compliance Policies (deviceCompliancePolicies)
- Shell Scripts (deviceShellScripts)
- macOS PKG Line‑of‑Business Apps (macOSPkgApp)

Deletion (prefix based) also covers: policies, compliance policies, scripts, apps.

---

### Prerequisites
1. PowerShell 7+ (pwsh)
2. Microsoft Graph PowerShell SDK (core authentication module installs automatically on first `Connect-MgGraph`):
	 - `Microsoft.Graph.Authentication`
	 - Beta device app management cmdlets are auto-installed on demand (module: `Microsoft.Graph.Beta.Devices.CorporateManagement`) when uploading macOS apps.
3. Intune / Graph permissions (delegated) granted at sign‑in:
	 - `DeviceManagementConfiguration.ReadWrite.All`
	 - `DeviceManagementApps.ReadWrite.All` (only required if importing apps)
	 - `Group.Read.All` (only required if assigning to groups)

### Authentication
The script calls:
```
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All,DeviceManagementApps.ReadWrite.All,Group.Read.All"
```
Consent once; subsequent runs reuse the token (until expiry). If you do not import apps or assign groups, you can safely ignore the extra scopes.

### Distributed XML Manifests
Each Intune object is described by an XML file containing a root `<MacIntuneManifest>` element with metadata. Example (script):
```xml
<MacIntuneManifest>
	<Type>Script</Type>
	<Name>Rename Device</Name>
	<Description>Standardize device name.</Description>
	<Platform>macOS</Platform>
	<Category>Device Setup</Category>
	<SourceFile>scripts/intune/device-rename.sh</SourceFile>
	<Script>
		<RunAsAccount>system</RunAsAccount>
		<BlockExecutionNotifications>false</BlockExecutionNotifications>
		<ExecutionFrequency>PT0H</ExecutionFrequency>
		<RetryCount>3</RetryCount>
	</Script>
</MacIntuneManifest>
```

Package / app manifests include a `<Package>` block with fields like `PrimaryBundleId`, `PrimaryBundleVersion`, `Publisher`, etc. Policies reference a JSON settings file via `<SourceFile>`.

### Naming & Prefix
All created objects are prefixed by default with:
```
[intune-my-mac] 
```
Override with `--prefix="[YourPrefix] "` (include quotes if spaces). A trailing space is auto‑added if omitted.

### Command Line Flags
| Flag | Purpose |
|------|---------|
| `--policies` or `--config` | Import only configuration policies |
| `--compliance` | Import only compliance policies |
| `--scripts` | Import only shell scripts |
| `--apps` or `--packages` | Import only macOS PKG apps |
| (no selector flags) | If none of the above are supplied, all types are imported |
| `--assign-group="Display Name"` | After creation, assign each created object to the specified Entra ID group |
| `--remove-all` | Delete ALL existing objects whose name starts with the current prefix (asks for `YES` confirmation) |
| `--prefix="Value "` | Set a custom prefix for creation & deletion matching |
| `--show-all-scripts` | (When selecting scripts) show additional script info output |

> Order is not important. Flags are case‑insensitive.

### Typical Workflows
Import everything (default):
```bash
pwsh ./src/mainScript.ps1
```

Import ONLY policies and scripts with custom prefix:
```bash
pwsh ./src/mainScript.ps1 --policies --scripts --prefix="[POC] "
```

Import apps and assign them to a group:
```bash
pwsh ./src/mainScript.ps1 --apps --assign-group="macOS POC Devices"
```

Full environment rebuild (dangerous):
```bash
pwsh ./src/mainScript.ps1 --remove-all --prefix="[intune-my-mac] "
# Type YES when prompted
pwsh ./src/mainScript.ps1 --prefix="[intune-my-mac] "
```

Import compliance policies only:
```bash
pwsh ./src/mainScript.ps1 --compliance --assign-group="Secure Devices"
```

### Deletion Logic (`--remove-all`)
1. Lists all matching objects (policies, compliance policies, scripts, apps).
2. Shows a summary & requires typing `YES` (uppercase) before deletion proceeds.
3. Uses `startsWith()` server-side filtering where supported; compliance falls back to client filtering if necessary.

### Assignments
If `--assign-group` is used:
- Policies, compliance policies, scripts are assigned via their respective `/assign` endpoints.
- Apps are assigned with intent `required`.
- Only objects created in the current run are assigned; previous objects are unaffected.

### macOS PKG App Upload Notes
- Utilizes Graph beta endpoints and chunked upload logic.
- Requires valid PKG path from the manifest `<SourceFile>`.
- Automatically commits version and waits for publishing state.

### Troubleshooting
| Symptom | Hint |
|---------|------|
| 403 Forbidden | Ensure you consented to requested scopes when prompted |
| App upload hangs | Large PKG: allow processing time; monitor verbose output |
| Nothing deleted with `--remove-all` | Confirm prefix spacing matches creation prefix |
| Group not found | Display name mismatch; verify exact Entra group name |

### Exit & Error Behavior
- Script sets `$ErrorActionPreference = 'Stop'` for fail-fast behavior in most blocks but wraps API calls in try/catch to continue other items.
- Individual failures are logged; the script proceeds with remaining objects.

### Extending
Potential future additions (not yet in this version):
- Enrollment restrictions
- Dry-run mode (`--what-if` style)
- Structured JSON summary output
- Log level flag (`--debug`)

### Minimal Quick Start
```bash
git clone https://github.com/microsoft/intune-my-macs.git
cd intune-my-macs
pwsh ./src/mainScript.ps1 --scripts --policies --assign-group="Your Group"
```

### Disclaimer
This script manipulates production Intune objects. Test in a lab tenant before applying to production.

---
Maintained by the Intune Customer Experience Engineering team.
