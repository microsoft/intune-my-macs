# Configuration Summary

Concise overview of every managed payload: policies, custom configs (mobileconfig), compliance, scripts, custom attribute, and app packages. Each entry lists a few representative key/value settings or core actions. For exhaustive details, see raw JSON/mobileconfig or script source.

_Last Updated: 2025-10-23_

---
## Legend
- **Ref ID**: Repository reference identifier (TYPE-CATEGORY-NUMBER)
- **Type**: Policy / CustomConfig / Compliance / Script / CustomAttribute / Package
- **Keys**: Representative settings (not complete list)
- **Actions**: Script/package behavior summary

---
## Security Policies (POL-SEC)
| Ref ID | Name | Representative Keys / Values | Purpose |
|--------|------|------------------------------|---------|
| POL-SEC-001 | FileVault Disk Encryption | defer=true; forceEnableInSetupAssistant=true; useRecoveryKey=true; showRecoveryKey=false; escrowLocation=https://user.manage.microsoft.com | Enforce full‑disk encryption and escrow recovery key |
| POL-SEC-002 | Firewall Configuration | enableFirewall=true; blockFirewallUI=true | Enable firewall and lock UI |
| POL-SEC-003 | Gatekeeper Security | allowIdentifiedDevelopers=true; enableAssessment=true; enableXProtectMalwareUpload=true; disableOverride=true | Harden app execution & malware assessment |
| POL-SEC-004 | Guest Account Security | disableGuestAccount=true | Remove unauthenticated guest access |
| POL-SEC-005 | Screensaver Security | askForPassword=true; passwordDelay=60s; loginWindowIdle=1200s; userIdle=600s; module=Flurry | Lock when idle & require password |
| POL-SEC-006 | Restrictions (subset) | disableGuestAccount=true; allowAirDrop=false; allowAssistant=false; allowCloudKeychainSync=false; allowCloudPhotos=false; allowCloudPrivateRelay=false | Broad system & iCloud feature lock-down |

## System Policies (POL-SYS)
| Ref ID | Name | Representative Keys / Values | Purpose |
|--------|------|------------------------------|---------|
| POL-SYS-100 | Network Time Protocol | (Time sync enforced) | Ensure accurate system time |
| POL-SYS-101 | Managed Login Items | rule[PaloAlto]:team=PXPZ95SK77; rule[Microsoft]:team=UBF8T346G9 | Control background/login services |
| POL-SYS-102 | Power Management | (Energy saver settings) | Optimize power/security posture |
| POL-SYS-103 | Software Update Configuration | (Auto update enforce) | Keep OS/app patches current |
| POL-SYS-104 | DDM Passcode | minLength=6; complexChars>=1; alphanumeric=true; maxAgeDays=365; reuseLimit=1; maxFailedAttempts=11 | Enforce passcode complexity |
| POL-SYS-105 | macOS Enrollment Restriction | (Restrict enrollment classes) | Limit device types allowed |

## Application Policies (POL-APP)
| Ref ID | Name | Representative Keys / Values | Purpose |
|--------|------|------------------------------|---------|
| POL-APP-100 | Microsoft Office Settings | (Channel/preferences) | Standardize Office behavior |
| POL-APP-101 | Edge Security Level 1 | baseline protections | Entry security posture |
| POL-APP-102 | Edge Security Level 2 | stricter controls | Elevated security posture |
| POL-APP-103 | Edge Security Level 3 | max restrictions | Highest lockdown level |

## Defender Policy (POL-MDE)
| Ref ID | Name | Representative Keys / Values | Purpose |
|--------|------|------------------------------|---------|
| POL-MDE-001 | MDE Settings Catalog | (Real-time/network protection, telemetry) | Configure Defender runtime settings |

---
## Custom Configurations (CFG)
| Ref ID | Name | Keys / Values | Purpose |
|--------|------|---------------|---------|
| CFG-SEC-001 | Login Window Security | disableFDEAutoLogin=true; disableAutoLoginClient=true; enableExternalAccounts=false; adminMayDisableMCX=false | Harden login window & external auth |
| CFG-SEC-002 | Screensaver Idle Time | idleTime=600 | Enforce idle activation threshold |
| CFG-IDP-001 | Entra Platform SSO | (Platform SSO payload) | Enable unified Entra SSO |
| CFG-MDE-001 | MDE Onboarding Profile | (Onboarding plist identifiers) | Connect device to Defender service |

---
## Compliance Policy (CMP)
| Ref ID | Name | Representative Checks | Purpose |
|--------|------|-----------------------|---------|
| CMP-CMP-001 | macOS Compliance Baseline | OS version; FileVault enabled; passcode present; Defender active | Assess device compliance posture |

---
## Scripts (SCR)
| Ref ID | Name | Core Actions | Purpose |
|--------|------|-------------|---------|
| SCR-SYS-100 | Device Rename | Build new name (Prefix-Model-Serial-Country); set ComputerName/HostName/LocalHostName; log | Standardize asset naming |
| SCR-SYS-101 | Configure Dock | Wait for Dock & apps; optionally install dockutil; populate Dock; add Downloads; mark configured | Provide consistent user workspace |
| SCR-SEC-100 | Install Escrow Buddy | Install Escrow Buddy; support FileVault key escrow improvements | Strengthen key escrow reliability |
| SCR-APP-100 | Install Company Portal | Download & install latest Intune Company Portal; verify | Enable user self-service / enrollment features |
| SCR-APP-101 | Office Default Settings | Apply default Office prefs (privacy, channels) | Standardize Office user experience |
| SCR-MDE-100 | Install Microsoft Defender | Check Rosetta; wait for prerequisite apps; download PKG; update logic via Last-Modified; Octory status | Deploy & update endpoint protection |

---
## Custom Attribute (CAT)
| Ref ID | Name | Action | Purpose |
|--------|------|--------|---------|
| CAT-SYS-100 | macOS Compatibility Checker | Evaluate upgrade readiness (model/OS) and output attribute | Drive dynamic assignment based on upgrade viability |

---
## Application Packages (APP)
| Ref ID | Name | Actions | Purpose |
|--------|------|--------|---------|
| APP-UTL-001 | Swift Dialog | Install swiftDialog app bundle | Provide UI dialogs for other scripts |
| APP-UTL-002 | Swift Dialog Onboarding | Deploy onboarding workflow (pkg + pre/post scripts) | Guided first-run user experience |
| APP-UTL-003 | Mac Evaluation Utility | Install evaluation tool | Hardware & compliance inspection |
| APP-UTL-004 | Log Watch Utility | Install log monitoring tool | Operational & security log review |

---
## Layered Security Overview
- Encryption: FileVault + Escrow Buddy
- Execution control: Gatekeeper + Restrictions + Defender
- Session protection: Screensaver (POL + CFG) + Passcode Policy
- Network & perimeter: Firewall enforced
- Identity: Platform SSO + Passcode complexity
- Hygiene & UX: Device rename + Dock standardization

---
## Maintenance Guidance
Update this file when adding/modifying payloads or when key settings materially change. Keep entries concise; link deep details to source artifacts.
