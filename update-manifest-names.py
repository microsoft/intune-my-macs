#!/usr/bin/env python3
"""
Update all manifest Names to include Reference IDs in format: REF-ID - Descriptive Name
"""

import os
import re
from pathlib import Path

REPO_ROOT = Path("/Users/neiljohnson/Documents/GitHub/intune-my-macs")

# All manifests with their reference IDs and descriptive names
MANIFEST_UPDATES = {
    # Security Policies (POL-SEC 001-006)
    "configurations/intune/pol-sec-001-filevault.xml": {
        "ref_id": "POL-SEC-001",
        "name": "FileVault Disk Encryption",
    },
    "configurations/intune/pol-sec-002-firewall.xml": {
        "ref_id": "POL-SEC-002",
        "name": "Firewall Configuration",
    },
    "configurations/intune/pol-sec-003-gatekeeper.xml": {
        "ref_id": "POL-SEC-003",
        "name": "Gatekeeper Security",
    },
    "configurations/intune/pol-sec-004-guest-account.xml": {
        "ref_id": "POL-SEC-004",
        "name": "Guest Account Security",
    },
    "configurations/intune/pol-sec-005-screensaver.xml": {
        "ref_id": "POL-SEC-005",
        "name": "Screensaver Security",
    },
    "configurations/intune/pol-sec-006-restrictions.xml": {
        "ref_id": "POL-SEC-006",
        "name": "System Restrictions",
    },
    
    # Security Custom Configs (CFG-SEC)
    "configurations/intune/cfg-sec-001-login-window.xml": {
        "ref_id": "CFG-SEC-001",
        "name": "Login Window Security Configuration",
    },
    "configurations/intune/cfg-sec-002-screensaver-idle.xml": {
        "ref_id": "CFG-SEC-002",
        "name": "Screensaver Idle Time Configuration",
    },
    
    # Compliance (CMP-CMP)
    "configurations/intune/cmp-cmp-001-macos-baseline.xml": {
        "ref_id": "CMP-CMP-001",
        "name": "macOS Compliance Baseline",
    },
    
    # Identity (CFG-IDP)
    "configurations/entra/cfg-idp-001-platform-sso.xml": {
        "ref_id": "CFG-IDP-001",
        "name": "Entra Platform SSO",
    },
    
    # System Policies (POL-SYS)
    "configurations/intune/pol-sys-100-ntp.xml": {
        "ref_id": "POL-SYS-100",
        "name": "Network Time Protocol",
    },
    "configurations/intune/pol-sys-101-login-items.xml": {
        "ref_id": "POL-SYS-101",
        "name": "Managed Login Items",
    },
    "configurations/intune/pol-sys-102-power.xml": {
        "ref_id": "POL-SYS-102",
        "name": "Power Management",
    },
    "configurations/intune/pol-sys-103-software-update.xml": {
        "ref_id": "POL-SYS-103",
        "name": "Software Update Policy",
    },
    "configurations/intune/pol-sys-104-ddm-passcode.xml": {
        "ref_id": "POL-SYS-104",
        "name": "DDM Passcode Configuration",
    },
    "configurations/intune/pol-sys-105-enrollment-restriction.xml": {
        "ref_id": "POL-SYS-105",
        "name": "macOS Enrollment Restriction",
    },
    
    # Application Policies (POL-APP)
    "configurations/intune/pol-app-100-office.xml": {
        "ref_id": "POL-APP-100",
        "name": "Microsoft Office Configuration",
    },
    "configurations/Secure Enterprise Browser/pol-app-101-edge-level1.xml": {
        "ref_id": "POL-APP-101",
        "name": "Edge Browser Level 1 Basic",
    },
    "configurations/Secure Enterprise Browser/pol-app-102-edge-level2.xml": {
        "ref_id": "POL-APP-102",
        "name": "Edge Browser Level 2 Enhanced",
    },
    "configurations/Secure Enterprise Browser/pol-app-103-edge-level3.xml": {
        "ref_id": "POL-APP-103",
        "name": "Edge Browser Level 3 High Security",
    },
    
    # Microsoft Defender (MDE)
    "mde/pol-mde-001-settings-catalog.xml": {
        "ref_id": "POL-MDE-001",
        "name": "Microsoft Defender Settings Catalog",
    },
    "mde/cfg-mde-001-onboarding.xml": {
        "ref_id": "CFG-MDE-001",
        "name": "Microsoft Defender Onboarding Profile",
    },
    "mde/scr-mde-100-install-defender.xml": {
        "ref_id": "SCR-MDE-100",
        "name": "Install Microsoft Defender",
    },
    
    # Utility Applications (APP-UTL)
    "apps/app-utl-001-swift-dialog.xml": {
        "ref_id": "APP-UTL-001",
        "name": "Swift Dialog",
    },
    "apps/app-utl-002-dialog-onboarding.xml": {
        "ref_id": "APP-UTL-002",
        "name": "Swift Dialog Onboarding",
    },
    "apps/app-utl-003-mac-evaluation.xml": {
        "ref_id": "APP-UTL-003",
        "name": "Mac Evaluation Utility",
    },
    "apps/app-utl-004-log-watch.xml": {
        "ref_id": "APP-UTL-004",
        "name": "Intune Log Watch",
    },
    
    # Scripts (SCR)
    "scripts/intune/scr-app-100-install-company-portal.xml": {
        "ref_id": "SCR-APP-100",
        "name": "Install Company Portal",
    },
    "scripts/intune/scr-sec-100-install-escrow-buddy.xml": {
        "ref_id": "SCR-SEC-100",
        "name": "Install Escrow Buddy",
    },
    "scripts/intune/scr-sys-100-device-rename.xml": {
        "ref_id": "SCR-SYS-100",
        "name": "Device Rename",
    },
    "scripts/intune/scr-sys-101-configure-dock.xml": {
        "ref_id": "SCR-SYS-101",
        "name": "Configure Dock",
    },
    "scripts/intune/scr-app-101-office-defaults.xml": {
        "ref_id": "SCR-APP-101",
        "name": "Set Office Default Applications",
    },
    
    # Custom Attributes (CAT)
    "custom attributes/cat-sys-100-compatibility-checker.xml": {
        "ref_id": "CAT-SYS-100",
        "name": "macOS Compatibility Checker",
    },
}


def update_manifest_name(manifest_path, metadata):
    """Update manifest Name to include Reference ID"""
    full_path = REPO_ROOT / manifest_path
    
    if not full_path.exists():
        print(f"⚠️  Skipping {manifest_path} - file not found")
        return
    
    content = full_path.read_text()
    
    # Create the new name format: REF-ID - Descriptive Name
    new_name = f"{metadata['ref_id']} - {metadata['name']}"
    
    # Check if already in correct format
    if f"<Name>{new_name}</Name>" in content:
        print(f"✓  {manifest_path} already correct")
        return
    
    print(f"📝 Updating {manifest_path}")
    
    # Update Name element
    content = re.sub(
        r"<Name>.*?</Name>",
        f"<Name>{new_name}</Name>",
        content
    )
    
    full_path.write_text(content)
    print(f"✅ Updated to: {new_name}")


def main():
    print("=" * 80)
    print("Updating all manifest Names to include Reference IDs")
    print("=" * 80)
    print()
    
    for manifest_path, metadata in MANIFEST_UPDATES.items():
        update_manifest_name(manifest_path, metadata)
    
    print()
    print("=" * 80)
    print("✅ All manifest names updated!")
    print("=" * 80)


if __name__ == "__main__":
    main()
