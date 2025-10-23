#!/usr/bin/env python3
"""
Fix manifest Type fields and ensure clean names without prefixes
"""

import os
import re
from pathlib import Path

REPO_ROOT = Path("/Users/neiljohnson/Documents/GitHub/intune-my-macs")

# Corrections needed for manifests
MANIFEST_FIXES = {
    # Identity - wrong Type
    "configurations/entra/cfg-idp-001-platform-sso.xml": {
        "type": "CustomConfig",  # Not Policy
    },
    
    # Apps - ensure correct naming
    "apps/app-utl-001-swift-dialog.xml": {
        "name": "Swift Dialog",
    },
    "apps/app-utl-002-dialog-onboarding.xml": {
        "name": "Swift Dialog Onboarding",
    },
    "apps/app-utl-003-mac-evaluation.xml": {
        "name": "Mac Evaluation Utility",
    },
    "apps/app-utl-004-log-watch.xml": {
        "name": "Intune Log Watch",
    },
    
    # MDE scripts
    "mde/scr-mde-100-install-defender.xml": {
        "name": "Install Microsoft Defender",
    },
    
    # Scripts
    "scripts/intune/scr-app-100-install-company-portal.xml": {
        "name": "Install Company Portal",
    },
    "scripts/intune/scr-sec-100-install-escrow-buddy.xml": {
        "name": "Install Escrow Buddy",
    },
    "scripts/intune/scr-sys-100-device-rename.xml": {
        "name": "Device Rename",
    },
    "scripts/intune/scr-sys-101-configure-dock.xml": {
        "name": "Configure Dock",
    },
    "scripts/intune/scr-app-101-office-defaults.xml": {
        "name": "Set Office Default Applications",
    },
    
    # Custom Attributes
    "custom attributes/cat-sys-100-compatibility-checker.xml": {
        "name": "macOS Compatibility Checker",
    },
}


def fix_manifest(manifest_path, fixes):
    """Fix a single manifest file"""
    full_path = REPO_ROOT / manifest_path
    
    if not full_path.exists():
        print(f"⚠️  Skipping {manifest_path} - file not found")
        return
    
    print(f"📝 Fixing {manifest_path}")
    
    content = full_path.read_text()
    modified = False
    
    # Fix Type if specified
    if "type" in fixes:
        new_type = fixes["type"]
        if f"<Type>{new_type}</Type>" not in content:
            content = re.sub(
                r"<Type>.*?</Type>",
                f"<Type>{new_type}</Type>",
                content
            )
            modified = True
            print(f"   ✓ Updated Type to {new_type}")
    
    # Fix Name if specified
    if "name" in fixes:
        new_name = fixes["name"]
        if f"<Name>{new_name}</Name>" not in content:
            content = re.sub(
                r"<Name>.*?</Name>",
                f"<Name>{new_name}</Name>",
                content
            )
            modified = True
            print(f"   ✓ Updated Name to {new_name}")
    
    if modified:
        full_path.write_text(content)
        print(f"✅ Fixed {manifest_path}")
    else:
        print(f"✓  No changes needed for {manifest_path}")


def main():
    print("=" * 70)
    print("Fixing manifest Types and Names")
    print("=" * 70)
    print()
    
    for manifest_path, fixes in MANIFEST_FIXES.items():
        fix_manifest(manifest_path, fixes)
    
    print()
    print("=" * 70)
    print("✅ All manifest fixes applied!")
    print("=" * 70)


if __name__ == "__main__":
    main()
