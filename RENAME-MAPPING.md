# Artifact Renaming Mapping

This document maps old names to new reference IDs according to the Policy Naming Standard.

## Core Security Items (001-099)

### Configuration Policies (POL-SEC)
- POL-SEC-001: FileVault Disk Encryption ✅ DONE
  - OLD: configurations/intune/filevault.{json,xml}
  - NEW: configurations/intune/pol-sec-001-filevault.{json,xml}

- POL-SEC-002: Firewall Configuration
  - OLD: configurations/intune/FirewallConfiguration.{json,xml}
  - NEW: configurations/intune/pol-sec-002-firewall.{json,xml}

- POL-SEC-003: Gatekeeper Security
  - OLD: configurations/intune/GatekeeperSecurityConfiguration.{json,xml}
  - NEW: configurations/intune/pol-sec-003-gatekeeper.{json,xml}

- POL-SEC-004: Guest Account Security
  - OLD: configurations/intune/GuestAccountSecurityConfiguration.{json,xml}
  - NEW: configurations/intune/pol-sec-004-guest-account.{json,xml}

- POL-SEC-005: Screensaver Security
  - OLD: configurations/intune/ScreensaverSecurityConfiguration.{json,xml}
  - NEW: configurations/intune/pol-sec-005-screensaver.{json,xml}

- POL-SEC-006: Restrictions
  - OLD: configurations/intune/Restrictions.{json,xml}
  - NEW: configurations/intune/pol-sec-006-restrictions.{json,xml}

### Custom Configurations (CFG-SEC)
- CFG-SEC-001: Login Window Security
  - OLD: configurations/intune/LoginWindowSecurityConfiguration.{mobileconfig,xml}
  - NEW: configurations/intune/cfg-sec-001-login-window.{mobileconfig,xml}

- CFG-SEC-002: Screensaver Idle Time
  - OLD: configurations/intune/ScreensaverIdleTimeConfiguration.{mobileconfig,xml}
  - NEW: configurations/intune/cfg-sec-002-screensaver-idle.{mobileconfig,xml}

### Compliance Policies (CMP-CMP)
- CMP-CMP-001: macOS Compliance Policy
  - OLD: configurations/intune/macos-compliance.{json,xml}
  - NEW: configurations/intune/cmp-cmp-001-macos-baseline.{json,xml}

## Identity & Authentication (IDP)

- CFG-IDP-001: Entra Platform SSO
  - OLD: configurations/entra/entra-psso.{json,xml}
  - NEW: configurations/entra/cfg-idp-001-platform-sso.{json,xml}

## System Configuration (SYS)

- POL-SYS-100: Network Time Protocol
  - OLD: configurations/intune/Network Time Protocol.{json,xml}
  - NEW: configurations/intune/pol-sys-100-ntp.{json,xml}

- POL-SYS-101: Managed Login Items
  - OLD: configurations/intune/Managed Login Items.{json,xml}
  - NEW: configurations/intune/pol-sys-101-login-items.{json,xml}

- POL-SYS-102: Power Management
  - OLD: configurations/intune/Energy.{json,_xml}
  - NEW: configurations/intune/pol-sys-102-power.{json,xml}

- POL-SYS-103: Software Update Policy
  - OLD: configurations/intune/Software Update Policy.{json,xml}
  - NEW: configurations/intune/pol-sys-103-software-update.{json,xml}

- POL-SYS-104: DDM Passcode
  - OLD: configurations/intune/ddm-passcode.{json,xml}
  - NEW: configurations/intune/pol-sys-104-ddm-passcode.{json,xml}

- POL-SYS-105: macOS Enrollment Restriction
  - OLD: configurations/intune/macos-enrollment-restriction.{json,xml}
  - NEW: configurations/intune/pol-sys-105-enrollment-restriction.{json,xml}

## Applications (APP)

- POL-APP-100: Microsoft Office Configuration
  - OLD: configurations/intune/Office.{json,xml}
  - NEW: configurations/intune/pol-app-100-office.{json,xml}

- POL-APP-101: Edge Browser - Level 1 Basic
  - OLD: configurations/Secure Enterprise Browser/Edge macOS Level 1 Basic.{json,xml}
  - NEW: configurations/Secure Enterprise Browser/pol-app-101-edge-level1.{json,xml}

- POL-APP-102: Edge Browser - Level 2 Recommended
  - OLD: configurations/Secure Enterprise Browser/Edge macOS Level 2 Recommended.{json,xml}
  - NEW: configurations/Secure Enterprise Browser/pol-app-102-edge-level2.{json,xml}

- POL-APP-103: Edge Browser - Level 3 Strict
  - OLD: configurations/Secure Enterprise Browser/Edge macOS Level 3 Strict.{json,xml}
  - NEW: configurations/Secure Enterprise Browser/pol-app-103-edge-level3.{json,xml}

## Microsoft Defender for Endpoint (MDE)

- POL-MDE-001: MDE Settings Catalog Combined
  - OLD: mde/MDE - Settings Catalog Combined.{json,xml}
  - NEW: mde/pol-mde-001-settings-catalog.{json,xml}

- CFG-MDE-001: MDE Onboarding Profile
  - OLD: mde/WindowsDefenderATPOnboarding.{mobileconfig,xml}
  - NEW: mde/cfg-mde-001-onboarding.{mobileconfig,xml}

- SCR-MDE-100: Install Defender Script
  - OLD: mde/99 - installDefender.{zsh,xml}
  - NEW: mde/scr-mde-100-install-defender.{zsh,xml}

## Utilities (APP-UTL)

- APP-UTL-001: Swift Dialog Package
  - OLD: apps/00 - dialog-2.5.6-4805.{pkg,xml}
  - NEW: apps/app-utl-001-swift-dialog.{pkg,xml}

- APP-UTL-002: Swift Dialog Onboarding
  - OLD: apps/01 - Swift Dialog Onboarding.{pkg,xml,zip} + pre/post scripts
  - NEW: apps/app-utl-002-dialog-onboarding.{pkg,xml,zip} + pre/post scripts

- APP-UTL-003: Mac Evaluation Utility
  - OLD: apps/ZZ - MacEvaluationUtility.{pkg,xml}
  - NEW: apps/app-utl-003-mac-evaluation.{pkg,xml}

- APP-UTL-004: Intune Log Watch
  - OLD: apps/ZZ - IntuneLogWatch.{pkg,xml}
  - NEW: apps/app-utl-004-log-watch.{pkg,xml}

## Scripts (SCR-SYS, SCR-APP)

- SCR-APP-100: Install Company Portal
  - OLD: scripts/intune/10 - install-company-portal.{sh,xml}
  - NEW: scripts/intune/scr-app-100-install-company-portal.{sh,xml}

- SCR-SEC-100: Install Escrow Buddy
  - OLD: scripts/intune/11 - install-escrow-buddy.{sh,xml}
  - NEW: scripts/intune/scr-sec-100-install-escrow-buddy.{sh,xml}

- SCR-SYS-100: Device Rename
  - OLD: scripts/intune/12 - device-rename.{sh,xml}
  - NEW: scripts/intune/scr-sys-100-device-rename.{sh,xml}

- SCR-SYS-101: Configure Dock
  - OLD: scripts/intune/ZZ - configure-dock.{sh,xml}
  - NEW: scripts/intune/scr-sys-101-configure-dock.{sh,xml}

- SCR-APP-101: Set Office Default Apps
  - OLD: scripts/intune/ZZ - setOfficeDefaultApps.{sh,xml}
  - NEW: scripts/intune/scr-app-101-office-defaults.{sh,xml}

## Custom Attributes (CAT-SYS)

- CAT-SYS-100: macOS Compatibility Checker
  - OLD: custom attributes/macOSCompatibilityChecker.{zsh,xml}
  - NEW: custom attributes/cat-sys-100-compatibility-checker.{zsh,xml}
