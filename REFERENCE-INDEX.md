# Reference Index

This document provides a comprehensive index of all Intune artifacts in this repository, organized by their reference IDs according to the [Policy Naming Standard](policy-naming-standard.md).

**Last Updated:** [Auto-generated]  
**Total Artifacts:** 33

## Table of Contents
- [Configuration Policies (POL)](#configuration-policies-pol)
  - [Security (POL-SEC)](#security-pol-sec)
  - [System (POL-SYS)](#system-pol-sys)
  - [Applications (POL-APP)](#applications-pol-app)
  - [Microsoft Defender (POL-MDE)](#microsoft-defender-pol-mde)
- [Custom Configurations (CFG)](#custom-configurations-cfg)
  - [Security (CFG-SEC)](#security-cfg-sec)
  - [Identity (CFG-IDP)](#identity-cfg-idp)
  - [Microsoft Defender (CFG-MDE)](#microsoft-defender-cfg-mde)
- [Compliance Policies (CMP)](#compliance-policies-cmp)
- [Shell Scripts (SCR)](#shell-scripts-scr)
  - [Security (SCR-SEC)](#security-scr-sec)
  - [System (SCR-SYS)](#system-scr-sys)
  - [Applications (SCR-APP)](#applications-scr-app)
  - [Microsoft Defender (SCR-MDE)](#microsoft-defender-scr-mde)
- [Custom Attributes (CAT)](#custom-attributes-cat)
- [Application Packages (APP)](#application-packages-app)

---

## Configuration Policies (POL)

### Security (POL-SEC)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| POL-SEC-001 | FileVault Disk Encryption | Enforces full disk encryption using FileVault for macOS devices | Active | [pol-sec-001-filevault.xml](configurations/intune/pol-sec-001-filevault.xml) |
| POL-SEC-002 | Firewall Configuration | Configures macOS firewall settings to block unauthorized network access | Active | [pol-sec-002-firewall.xml](configurations/intune/pol-sec-002-firewall.xml) |
| POL-SEC-003 | Gatekeeper Security | Enforces Gatekeeper to allow only trusted applications from App Store and identified developers | Active | [pol-sec-003-gatekeeper.xml](configurations/intune/pol-sec-003-gatekeeper.xml) |
| POL-SEC-004 | Guest Account Security | Disables guest account access to prevent unauthorized system usage | Active | [pol-sec-004-guest-account.xml](configurations/intune/pol-sec-004-guest-account.xml) |
| POL-SEC-005 | Screensaver Security | Enforces screensaver lock after idle timeout with password requirement | Active | [pol-sec-005-screensaver.xml](configurations/intune/pol-sec-005-screensaver.xml) |
| POL-SEC-006 | Security Restrictions | Comprehensive security restrictions including system preferences and security features | Active | [pol-sec-006-restrictions.xml](configurations/intune/pol-sec-006-restrictions.xml) |

### System (POL-SYS)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| POL-SYS-100 | Network Time Protocol | Configures NTP time synchronization to ensure accurate system time | Active | [pol-sys-100-ntp.xml](configurations/intune/pol-sys-100-ntp.xml) |
| POL-SYS-101 | Managed Login Items | Controls applications and services that start at user login | Active | [pol-sys-101-login-items.xml](configurations/intune/pol-sys-101-login-items.xml) |
| POL-SYS-102 | Power Management | Configures power and energy saver settings for macOS devices | Active | [pol-sys-102-power.xml](configurations/intune/pol-sys-102-power.xml) |
| POL-SYS-103 | Software Update Configuration | Manages automatic software update settings and enforcement | Active | [pol-sys-103-software-update.xml](configurations/intune/pol-sys-103-software-update.xml) |
| POL-SYS-104 | DDM Passcode Requirements | Declarative Device Management passcode policy enforcing complexity requirements | Active | [pol-sys-104-ddm-passcode.xml](configurations/intune/pol-sys-104-ddm-passcode.xml) |
| POL-SYS-105 | macOS Enrollment Restriction | Controls which types of macOS devices can enroll in Intune | Active | [pol-sys-105-enrollment-restriction.xml](configurations/intune/pol-sys-105-enrollment-restriction.xml) |

### Applications (POL-APP)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| POL-APP-100 | Microsoft Office Settings | Configuration settings for Microsoft Office suite on macOS | Active | [pol-app-100-office.xml](configurations/intune/pol-app-100-office.xml) |
| POL-APP-101 | Edge Security Level 1 | Microsoft Edge browser baseline security configuration (Level 1) | Active | [pol-app-101-edge-level1.xml](configurations/Secure Enterprise Browser/pol-app-101-edge-level1.xml) |
| POL-APP-102 | Edge Security Level 2 | Microsoft Edge browser enhanced security configuration (Level 2) | Active | [pol-app-102-edge-level2.xml](configurations/Secure Enterprise Browser/pol-app-102-edge-level2.xml) |
| POL-APP-103 | Edge Security Level 3 | Microsoft Edge browser maximum security configuration (Level 3) | Active | [pol-app-103-edge-level3.xml](configurations/Secure Enterprise Browser/pol-app-103-edge-level3.xml) |

### Microsoft Defender (POL-MDE)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| POL-MDE-001 | MDE Settings Catalog | Microsoft Defender for Endpoint comprehensive configuration using Settings Catalog | Active | [pol-mde-001-settings-catalog.xml](mde/pol-mde-001-settings-catalog.xml) |

---

## Custom Configurations (CFG)

### Security (CFG-SEC)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| CFG-SEC-001 | Login Window Security | Custom mobileconfig for login window security settings and restrictions | Active | [cfg-sec-001-login-window.xml](configurations/intune/cfg-sec-001-login-window.xml) |
| CFG-SEC-002 | Screensaver Idle Time | Custom mobileconfig enforcing screensaver activation after idle period | Active | [cfg-sec-002-screensaver-idle.xml](configurations/intune/cfg-sec-002-screensaver-idle.xml) |

### Identity (CFG-IDP)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| CFG-IDP-001 | Entra Platform SSO | Microsoft Entra ID Platform Single Sign-On configuration for macOS | Active | [cfg-idp-001-platform-sso.xml](configurations/entra/cfg-idp-001-platform-sso.xml) |

### Microsoft Defender (CFG-MDE)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| CFG-MDE-001 | MDE Onboarding Profile | Microsoft Defender for Endpoint onboarding mobileconfig profile | Active | [cfg-mde-001-onboarding.xml](mde/cfg-mde-001-onboarding.xml) |

---

## Compliance Policies (CMP)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| CMP-CMP-001 | macOS Compliance Baseline | Baseline compliance policy for macOS devices including OS version, encryption, and security requirements | Active | [cmp-cmp-001-macos-baseline.xml](configurations/intune/cmp-cmp-001-macos-baseline.xml) |

---

## Shell Scripts (SCR)

### Security (SCR-SEC)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| SCR-SEC-100 | Install Escrow Buddy | Script to install and configure Escrow Buddy for FileVault key escrow | Active | [scr-sec-100-install-escrow-buddy.xml](scripts/intune/scr-sec-100-install-escrow-buddy.xml) |

### System (SCR-SYS)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| SCR-SYS-100 | Device Rename Script | Automatically renames macOS device based on organizational naming convention | Active | [scr-sys-100-device-rename.xml](scripts/intune/scr-sys-100-device-rename.xml) |
| SCR-SYS-101 | Configure Dock Layout | Configures macOS Dock with standard organizational apps and layout | Active | [scr-sys-101-configure-dock.xml](scripts/intune/scr-sys-101-configure-dock.xml) |

### Applications (SCR-APP)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| SCR-APP-100 | Install Company Portal | Script to install and configure Microsoft Intune Company Portal app | Active | [scr-app-100-install-company-portal.xml](scripts/intune/scr-app-100-install-company-portal.xml) |
| SCR-APP-101 | Office Default Settings | Script to configure default settings for Microsoft Office applications | Active | [scr-app-101-office-defaults.xml](scripts/intune/scr-app-101-office-defaults.xml) |

### Microsoft Defender (SCR-MDE)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| SCR-MDE-100 | Install Microsoft Defender | Script to install and configure Microsoft Defender for Endpoint on macOS | Active | [scr-mde-100-install-defender.xml](mde/scr-mde-100-install-defender.xml) |

---

## Custom Attributes (CAT)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| CAT-SYS-100 | macOS Compatibility Checker | Custom attribute to report macOS upgrade compatibility status | Active | [cat-sys-100-compatibility-checker.xml](custom attributes/cat-sys-100-compatibility-checker.xml) |

---

## Application Packages (APP)

| Reference ID | Name | Description | Status | Manifest |
|-------------|------|-------------|---------|----------|
| APP-UTL-001 | Swift Dialog | swiftDialog utility for displaying rich user dialogs and notifications | Active | [app-utl-001-swift-dialog.xml](apps/app-utl-001-swift-dialog.xml) |
| APP-UTL-002 | Swift Dialog Onboarding | Complete onboarding experience using swiftDialog with pre/post scripts | Active | [app-utl-002-dialog-onboarding.xml](apps/app-utl-002-dialog-onboarding.xml) |
| APP-UTL-003 | Mac Evaluation Utility | Utility for evaluating Mac hardware and compliance status | Active | [app-utl-003-mac-evaluation.xml](apps/app-utl-003-mac-evaluation.xml) |
| APP-UTL-004 | Log Watch Utility | Utility for monitoring and analyzing macOS system logs | Active | [app-utl-004-log-watch.xml](apps/app-utl-004-log-watch.xml) |

---

## Reference ID Format

All reference IDs follow the format: `TYPE-CATEGORY-NUMBER`

### Type Codes
- **POL** - Configuration Policy (Settings Catalog or Device Configuration)
- **CMP** - Compliance Policy
- **CFG** - Custom Configuration (mobileconfig profile)
- **SCR** - Shell Script
- **CAT** - Custom Attribute
- **APP** - Application Package (.pkg)

### Category Codes
- **SEC** - Security
- **MDE** - Microsoft Defender for Endpoint
- **IDP** - Identity & Authentication
- **CMP** - Compliance
- **SYS** - System Management
- **APP** - Applications
- **UTL** - Utilities

### Sequence Numbers
- **001-099**: Reserved for core and critical security items
- **100-999**: Standard sequential assignment for other items

---

## Change History

### 2025-01-XX - Initial Standardization
- Created reference ID system for all artifacts
- Renamed all artifacts according to policy naming standard
- Updated all manifests with ReferenceId and Version elements
- Generated initial reference index

---

## Usage

To reference an artifact in documentation, issues, or communications, use its Reference ID:
- Example: "Please review POL-SEC-001 (FileVault) before deployment"
- Example: "SCR-SYS-100 failed to rename device"
- Example: "Deploy APP-UTL-001 to all pilot users"

For deployment using mainScript.ps1, artifacts can be deployed by:
- Type: `.\mainScript.ps1 -Policy` (deploys all POL items)
- Specific manifest: `.\mainScript.ps1 -ManifestFile "configurations/intune/pol-sec-001-filevault.xml"`
- Prefix filter: `.\mainScript.ps1 -Prefix "[intune-my-macs]"`

---

## Maintenance

This index should be updated whenever:
1. New artifacts are added to the repository
2. Existing artifacts are renamed or reorganized
3. Artifact status changes (Active → Deprecated)
4. Reference IDs are reassigned

To add a new artifact:
1. Assign appropriate reference ID following the naming standard
2. Create/update manifest with ReferenceId element
3. Add entry to this index in the appropriate category table
4. Update "Total Artifacts" count at top of document
