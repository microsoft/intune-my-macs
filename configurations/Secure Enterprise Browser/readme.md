# Secure Enterprise Browser Configuration for Microsoft Edge

This directory contains three progressive security levels of Microsoft Edge browser configuration policies for macOS devices, designed to meet varying enterprise security requirements.

## 📦 Contents

The `Secure Enterprise Browser.zip` file contains three complete policy packages:

- **Level 1 - Basic Security** (22 settings)
- **Level 2 - Enhanced Security** (33 settings)  
- **Level 3 - High Security** (53 settings)

Each policy package includes:
- JSON configuration file (`pol-app-10X-edge-levelX.json`)
- XML manifest file (`pol-app-10X-edge-levelX.xml`)

## 🚀 Usage Instructions

### Step 1: Extract the Policies

Unzip the `Secure Enterprise Browser.zip` file:

```bash
unzip "Secure Enterprise Browser.zip"
```

### Step 2: Select Your Security Level

Choose **ONE** of the three security levels based on your organization's requirements. Copy both the JSON and XML files for your chosen level to the repository root or your deployment folder.

**Important:** Only include ONE level at a time. Do not mix multiple levels.

### Step 3: Deploy with mainScript.ps1

Run the main deployment script from the repository root:

```powershell
pwsh ./mainScript.ps1 --assign-group="your-security-group"
```

The script will automatically discover and deploy the Edge browser policy you've included.

## 📊 Policy Comparison

### Level 1 - Basic Security (POL-APP-101)

**Purpose:** Foundational browser security with essential controls for standard enterprise environments.

**Settings Count:** 22 settings

| Category | Key Features |
|----------|-------------|
| **Certificate Management** | Auto-select certificates for URLs, certificate handling |
| **Network Security** | DNS interception checks, QUIC protocol control, automatic HTTPS |
| **Privacy Controls** | Diagnostic data management, tracking prevention, personalization reporting |
| **User Experience** | Hide first-run experience, homepage/new tab configuration, search suggestions |
| **Password Management** | Password manager control, import saved passwords |
| **Form Data** | Autofill for addresses and credit cards |
| **Updates** | Component updates enabled, update policy override |
| **Security Features** | SmartScreen enabled, popup blocking, network prediction |

**Best For:**
- Standard corporate environments
- General productivity users
- Organizations starting their security journey
- Low-risk operations

---

### Level 2 - Enhanced Security (POL-APP-102)

**Purpose:** Comprehensive security controls with advanced features for regulated or security-conscious organizations.

**Settings Count:** 33 settings (includes all Level 1 settings plus 11 additional controls)

**Additional Settings Beyond Level 1:**

| Category | Key Features |
|----------|-------------|
| **Developer Controls** | Developer tools availability restrictions |
| **Extension Management** | Extension installation controls and policies |
| **Advanced PKI** | Enhanced certificate and authentication controls |
| **Network Isolation** | Additional network security and isolation features |
| **Data Protection** | Enhanced data loss prevention settings |
| **Browser Hardening** | Additional security lockdowns and restrictions |
| **Session Management** | Advanced session and credential handling |
| **Content Filtering** | Enhanced web content filtering and blocking |
| **Authentication** | Advanced authentication and SSO integration |
| **Telemetry Control** | Granular diagnostic and telemetry management |
| **Sync Policies** | Browser synchronization controls |

**Best For:**
- Healthcare, Financial Services, Legal industries (compliance-driven)
- Organizations with sensitive data
- Environments requiring defense-in-depth
- Medium to high-risk operations

---

### Level 3 - High Security (POL-APP-103)

**Purpose:** Maximum security posture with complete controls, isolation, and zero-trust security model for high-risk environments.

**Settings Count:** 53 settings (includes all Level 2 settings plus 20 additional controls)

**Additional Settings Beyond Level 2:**

| Category | Key Features |
|----------|-------------|
| **Zero Trust Controls** | Complete identity verification and continuous authentication |
| **Browser Isolation** | Enhanced sandbox and process isolation |
| **Credential Protection** | Advanced credential guard and authentication protection |
| **Site Isolation** | Per-site process isolation and security boundaries |
| **Download Controls** | Comprehensive download restrictions and scanning |
| **Script Restrictions** | JavaScript execution policies and restrictions |
| **Plugin Management** | Complete control over browser plugins and extensions |
| **Cross-Origin Policies** | Strict cross-origin resource sharing controls |
| **Encryption Enforcement** | Mandatory encryption for all connections |
| **Audit Logging** | Comprehensive security event logging |
| **Feature Lockdown** | Disable non-essential browser features |
| **Privacy Hardening** | Maximum privacy controls and data minimization |
| **Content Security** | Content Security Policy enforcement |
| **Navigation Protection** | Enhanced phishing and malware protection |
| **Tab Management** | Restrictions on tab/window behaviors |
| **Protocol Handlers** | Control over custom protocol handlers |
| **Clipboard Controls** | Clipboard access restrictions |
| **Geolocation** | Geolocation service controls |
| **Media Capture** | Camera and microphone access policies |
| **Notifications** | Browser notification management |

**Best For:**
- Government agencies (classified/sensitive operations)
- Defense contractors
- Critical infrastructure
- High-value target organizations
- Zero-trust security implementations
- Environments with strict compliance (CMMC, FedRAMP, etc.)

---

## 🔐 Security Progression

```
Level 1 (Basic)
    ↓
    • Foundational security
    • Essential privacy controls
    • Standard enterprise features
    
Level 2 (Enhanced)
    ↓
    • All Level 1 settings
    • Advanced security controls
    • Extension & developer restrictions
    • Enhanced authentication
    
Level 3 (High Security)
    ↓
    • All Level 2 settings
    • Zero-trust architecture
    • Complete feature lockdown
    • Maximum isolation & protection
```

## 📋 Selection Guidelines

### Choose Level 1 if:
- ✅ Standard corporate environment
- ✅ Productivity is primary concern
- ✅ Users need flexibility
- ✅ Low regulatory requirements
- ✅ General business operations

### Choose Level 2 if:
- ✅ Compliance requirements (HIPAA, PCI-DSS, SOX)
- ✅ Sensitive data handling
- ✅ Balanced security and productivity
- ✅ Regulated industry
- ✅ Professional services

### Choose Level 3 if:
- ✅ High-security requirements (CMMC, FedRAMP, DoD)
- ✅ Classified or highly sensitive data
- ✅ Known threat actors targeting organization
- ✅ Zero-trust security mandate
- ✅ Maximum security over convenience
- ✅ Critical infrastructure or government operations

## ⚠️ Important Notes

1. **Single Level Only:** Deploy only ONE security level per device group. Mixing levels will cause conflicts.

2. **Testing Required:** Always test in a pilot group before broad deployment, especially for Level 2 and Level 3.

3. **User Impact:** Higher security levels progressively restrict browser functionality. Communicate changes to users.

4. **Compatibility:** All policies require Microsoft Edge version 90 or later on macOS 11.0+.

5. **Updates:** Review and update policies quarterly to align with new Edge features and security recommendations.

## 🔧 Customization

Each JSON policy can be customized by:

1. Extracting the desired level from the ZIP
2. Editing the JSON file to modify settings
3. Updating the `<SettingsCount>` in the XML manifest if you add/remove settings
4. Deploying via `mainScript.ps1`

## 📞 Support

For questions or issues:
- Review the main repository [README.md](../../README.md)
- Check [manifest.md](../../manifest.md) for policy structure
- File issues in the GitHub repository

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

**Version:** 1.0  
**Last Updated:** October 2025  
**Maintained by:** Microsoft  
