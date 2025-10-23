#!/usr/bin/env python3
"""
Update all XML manifests with ReferenceId and correct SourceFile paths
According to policy-naming-standard.md
"""

import os
import re
from pathlib import Path

REPO_ROOT = Path("/Users/neiljohnson/Documents/GitHub/intune-my-macs")

# Mapping of XML manifest files to their reference IDs and metadata
MANIFEST_UPDATES = {
    # Security Policies (POL-SEC 001-006)
    "configurations/intune/pol-sec-001-filevault.xml": {
        "ref_id": "POL-SEC-001",
        "name": "FileVault Disk Encryption",
        "source_file": "configurations/intune/pol-sec-001-filevault.json",
    },
    "configurations/intune/pol-sec-002-firewall.xml": {
        "ref_id": "POL-SEC-002",
        "name": "Firewall Configuration",
        "source_file": "configurations/intune/pol-sec-002-firewall.json",
    },
    "configurations/intune/pol-sec-003-gatekeeper.xml": {
        "ref_id": "POL-SEC-003",
        "name": "Gatekeeper Security",
        "source_file": "configurations/intune/pol-sec-003-gatekeeper.json",
    },
    "configurations/intune/pol-sec-004-guest-account.xml": {
        "ref_id": "POL-SEC-004",
        "name": "Guest Account Security",
        "source_file": "configurations/intune/pol-sec-004-guest-account.json",
    },
    "configurations/intune/pol-sec-005-screensaver.xml": {
        "ref_id": "POL-SEC-005",
        "name": "Screensaver Security",
        "source_file": "configurations/intune/pol-sec-005-screensaver.json",
    },
    "configurations/intune/pol-sec-006-restrictions.xml": {
        "ref_id": "POL-SEC-006",
        "name": "System Restrictions",
        "source_file": "configurations/intune/pol-sec-006-restrictions.json",
    },
    
    # Security Custom Configs (CFG-SEC)
    "configurations/intune/cfg-sec-001-login-window.xml": {
        "ref_id": "CFG-SEC-001",
        "name": "Login Window Security Configuration",
        "source_file": "configurations/intune/cfg-sec-001-login-window.mobileconfig",
    },
    "configurations/intune/cfg-sec-002-screensaver-idle.xml": {
        "ref_id": "CFG-SEC-002",
        "name": "Screensaver Idle Time Configuration",
        "source_file": "configurations/intune/cfg-sec-002-screensaver-idle.mobileconfig",
    },
    
    # Compliance (CMP-CMP)
    "configurations/intune/cmp-cmp-001-macos-baseline.xml": {
        "ref_id": "CMP-CMP-001",
        "name": "macOS Compliance Baseline",
        "source_file": "configurations/intune/cmp-cmp-001-macos-baseline.json",
    },
    
    # Identity (CFG-IDP)
    "configurations/entra/cfg-idp-001-platform-sso.xml": {
        "ref_id": "CFG-IDP-001",
        "name": "Entra Platform SSO",
        "source_file": "configurations/entra/cfg-idp-001-platform-sso.json",
    },
    
    # System Policies (POL-SYS)
    "configurations/intune/pol-sys-100-ntp.xml": {
        "ref_id": "POL-SYS-100",
        "name": "Network Time Protocol",
        "source_file": "configurations/intune/pol-sys-100-ntp.json",
    },
    "configurations/intune/pol-sys-101-login-items.xml": {
        "ref_id": "POL-SYS-101",
        "name": "Managed Login Items",
        "source_file": "configurations/intune/pol-sys-101-login-items.json",
    },
    "configurations/intune/pol-sys-102-power.xml": {
        "ref_id": "POL-SYS-102",
        "name": "Power Management",
        "source_file": "configurations/intune/pol-sys-102-power.json",
    },
    "configurations/intune/pol-sys-103-software-update.xml": {
        "ref_id": "POL-SYS-103",
        "name": "Software Update Policy",
        "source_file": "configurations/intune/pol-sys-103-software-update.json",
    },
    "configurations/intune/pol-sys-104-ddm-passcode.xml": {
        "ref_id": "POL-SYS-104",
        "name": "DDM Passcode Configuration",
        "source_file": "configurations/intune/pol-sys-104-ddm-passcode.json",
    },
    "configurations/intune/pol-sys-105-enrollment-restriction.xml": {
        "ref_id": "POL-SYS-105",
        "name": "macOS Enrollment Restriction",
        "source_file": "configurations/intune/pol-sys-105-enrollment-restriction.json",
    },
    
    # Application Policies (POL-APP)
    "configurations/intune/pol-app-100-office.xml": {
        "ref_id": "POL-APP-100",
        "name": "Microsoft Office Configuration",
        "source_file": "configurations/intune/pol-app-100-office.json",
    },
    "configurations/Secure Enterprise Browser/pol-app-101-edge-level1.xml": {
        "ref_id": "POL-APP-101",
        "name": "Edge Browser - Level 1 Basic",
        "source_file": "configurations/Secure Enterprise Browser/pol-app-101-edge-level1.json",
    },
    "configurations/Secure Enterprise Browser/pol-app-102-edge-level2.xml": {
        "ref_id": "POL-APP-102",
        "name": "Edge Browser - Level 2 Recommended",
        "source_file": "configurations/Secure Enterprise Browser/pol-app-102-edge-level2.json",
    },
    "configurations/Secure Enterprise Browser/pol-app-103-edge-level3.xml": {
        "ref_id": "POL-APP-103",
        "name": "Edge Browser - Level 3 Strict",
        "source_file": "configurations/Secure Enterprise Browser/pol-app-103-edge-level3.json",
    },
    
    # Microsoft Defender (MDE)
    "mde/pol-mde-001-settings-catalog.xml": {
        "ref_id": "POL-MDE-001",
        "name": "Microsoft Defender Settings Catalog",
        "source_file": "mde/pol-mde-001-settings-catalog.json",
    },
    "mde/cfg-mde-001-onboarding.xml": {
        "ref_id": "CFG-MDE-001",
        "name": "Microsoft Defender Onboarding Profile",
        "source_file": "mde/cfg-mde-001-onboarding.mobileconfig",
    },
    "mde/scr-mde-100-install-defender.xml": {
        "ref_id": "SCR-MDE-100",
        "name": "Install Microsoft Defender",
        "source_file": "mde/scr-mde-100-install-defender.zsh",
    },
    
    # Utility Applications (APP-UTL)
    "apps/app-utl-001-swift-dialog.xml": {
        "ref_id": "APP-UTL-001",
        "name": "Swift Dialog Package",
        "source_file": "apps/app-utl-001-swift-dialog.pkg",
    },
    "apps/app-utl-002-dialog-onboarding.xml": {
        "ref_id": "APP-UTL-002",
        "name": "Swift Dialog Onboarding",
        "source_file": "apps/app-utl-002-dialog-onboarding.pkg",
        "pre_install": "apps/app-utl-002-dialog-onboarding_pre.sh",
        "post_install": "apps/app-utl-002-dialog-onboarding_post.sh",
    },
    "apps/app-utl-003-mac-evaluation.xml": {
        "ref_id": "APP-UTL-003",
        "name": "Mac Evaluation Utility",
        "source_file": "apps/app-utl-003-mac-evaluation.pkg",
    },
    "apps/app-utl-004-log-watch.xml": {
        "ref_id": "APP-UTL-004",
        "name": "Intune Log Watch",
        "source_file": "apps/app-utl-004-log-watch.pkg",
    },
    
    # Scripts (SCR)
    "scripts/intune/scr-app-100-install-company-portal.xml": {
        "ref_id": "SCR-APP-100",
        "name": "Install Company Portal",
        "source_file": "scripts/intune/scr-app-100-install-company-portal.sh",
    },
    "scripts/intune/scr-sec-100-install-escrow-buddy.xml": {
        "ref_id": "SCR-SEC-100",
        "name": "Install Escrow Buddy",
        "source_file": "scripts/intune/scr-sec-100-install-escrow-buddy.sh",
    },
    "scripts/intune/scr-sys-100-device-rename.xml": {
        "ref_id": "SCR-SYS-100",
        "name": "Device Rename",
        "source_file": "scripts/intune/scr-sys-100-device-rename.sh",
    },
    "scripts/intune/scr-sys-101-configure-dock.xml": {
        "ref_id": "SCR-SYS-101",
        "name": "Configure Dock",
        "source_file": "scripts/intune/scr-sys-101-configure-dock.sh",
    },
    "scripts/intune/scr-app-101-office-defaults.xml": {
        "ref_id": "SCR-APP-101",
        "name": "Set Office Default Applications",
        "source_file": "scripts/intune/scr-app-101-office-defaults.sh",
    },
    
    # Custom Attributes (CAT)
    "custom attributes/cat-sys-100-compatibility-checker.xml": {
        "ref_id": "CAT-SYS-100",
        "name": "macOS Compatibility Checker",
        "source_file": "custom attributes/cat-sys-100-compatibility-checker.zsh",
    },
}


def update_manifest(manifest_path, metadata):
    """Update a single XML manifest file"""
    full_path = REPO_ROOT / manifest_path
    
    if not full_path.exists():
        print(f"⚠️  Skipping {manifest_path} - file not found")
        return
    
    print(f"📝 Updating {manifest_path}")
    
    content = full_path.read_text()
    
    # Add ReferenceId after <MacIntuneManifest> if not present
    if "<ReferenceId>" not in content:
        content = content.replace(
            "<MacIntuneManifest>\n",
            f"<MacIntuneManifest>\n  <ReferenceId>{metadata['ref_id']}</ReferenceId>\n"
        )
    
    # Add Version if not present
    if "<Version>" not in content and "<ReferenceId>" in content:
        content = content.replace(
            f"  <ReferenceId>{metadata['ref_id']}</ReferenceId>\n",
            f"  <ReferenceId>{metadata['ref_id']}</ReferenceId>\n  <Version>1.0</Version>\n"
        )
    
    # Update Name element
    content = re.sub(
        r"<Name>.*?</Name>",
        f"<Name>{metadata['name']}</Name>",
        content
    )
    
    # Update SourceFile element
    content = re.sub(
        r"<SourceFile>.*?</SourceFile>",
        f"<SourceFile>{metadata['source_file']}</SourceFile>",
        content
    )
    
    # Update PreInstallScript if present in metadata
    if "pre_install" in metadata:
        if "<PreInstallScript>" in content:
            content = re.sub(
                r"<PreInstallScript>.*?</PreInstallScript>",
                f"<PreInstallScript>{metadata['pre_install']}</PreInstallScript>",
                content
            )
        elif "<Package>" in content:
            # Add PreInstallScript element
            content = content.replace(
                "</Package>",
                f"    <PreInstallScript>{metadata['pre_install']}</PreInstallScript>\n  </Package>"
            )
    
    # Update PostInstallScript if present in metadata
    if "post_install" in metadata:
        if "<PostInstallScript>" in content:
            content = re.sub(
                r"<PostInstallScript>.*?</PostInstallScript>",
                f"<PostInstallScript>{metadata['post_install']}</PostInstallScript>",
                content
            )
        elif "<Package>" in content and "<PreInstallScript>" in content:
            # Add PostInstallScript after PreInstallScript
            content = content.replace(
                "</Package>",
                f"    <PostInstallScript>{metadata['post_install']}</PostInstallScript>\n  </Package>"
            )
    
    full_path.write_text(content)
    print(f"✅ Updated {manifest_path}")


def main():
    print("=" * 70)
    print("Updating all XML manifests with ReferenceId and corrected paths")
    print("=" * 70)
    print()
    
    for manifest_path, metadata in MANIFEST_UPDATES.items():
        update_manifest(manifest_path, metadata)
    
    print()
    print("=" * 70)
    print("✅ All manifests updated successfully!")
    print("=" * 70)


if __name__ == "__main__":
    main()
