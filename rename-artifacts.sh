#!/bin/zsh
# Automated renaming script for intune-my-macs repository
# Following policy-naming-standard.md

set -e

REPO_ROOT="/Users/neiljohnson/Documents/GitHub/intune-my-macs"
cd "$REPO_ROOT"

echo "Starting systematic renaming according to policy-naming-standard.md..."
echo "================================================================"

# Function to rename file pairs (json/xml, pkg/xml, etc.)
rename_pair() {
    local old_base="$1"
    local new_base="$2"
    local ext1="$3"
    local ext2="$4"
    
    if [ -f "${old_base}.${ext1}" ]; then
        echo "Renaming: ${old_base}.${ext1} -> ${new_base}.${ext1}"
        mv "${old_base}.${ext1}" "${new_base}.${ext1}"
    fi
    
    if [ -f "${old_base}.${ext2}" ]; then
        echo "Renaming: ${old_base}.${ext2} -> ${new_base}.${ext2}"
        mv "${old_base}.${ext2}" "${new_base}.${ext2}"
    fi
}

echo "\n## Core Security Policies (POL-SEC 002-006) ##"
rename_pair "configurations/intune/FirewallConfiguration" "configurations/intune/pol-sec-002-firewall" "json" "xml"
rename_pair "configurations/intune/GatekeeperSecurityConfiguration" "configurations/intune/pol-sec-003-gatekeeper" "json" "xml"
rename_pair "configurations/intune/GuestAccountSecurityConfiguration" "configurations/intune/pol-sec-004-guest-account" "json" "xml"
rename_pair "configurations/intune/ScreensaverSecurityConfiguration" "configurations/intune/pol-sec-005-screensaver" "json" "xml"
rename_pair "configurations/intune/Restrictions" "configurations/intune/pol-sec-006-restrictions" "json" "xml"

echo "\n## Security Custom Configs (CFG-SEC) ##"
rename_pair "configurations/intune/LoginWindowSecurityConfiguration" "configurations/intune/cfg-sec-001-login-window" "mobileconfig" "xml"
rename_pair "configurations/intune/ScreensaverIdleTimeConfiguration" "configurations/intune/cfg-sec-002-screensaver-idle" "mobileconfig" "xml"

echo "\n## Compliance Policies (CMP-CMP) ##"
rename_pair "configurations/intune/macos-compliance" "configurations/intune/cmp-cmp-001-macos-baseline" "json" "xml"

echo "\n## Identity Configs (CFG-IDP) ##"
rename_pair "configurations/entra/entra-psso" "configurations/entra/cfg-idp-001-platform-sso" "json" "xml"

echo "\n## System Policies (POL-SYS) ##"
rename_pair "configurations/intune/Network Time Protocol" "configurations/intune/pol-sys-100-ntp" "json" "xml"
rename_pair "configurations/intune/Managed Login Items" "configurations/intune/pol-sys-101-login-items" "json" "xml"

# Handle Energy file (has _xml instead of xml)
if [ -f "configurations/intune/Energy.json" ]; then
    echo "Renaming: configurations/intune/Energy.json -> configurations/intune/pol-sys-102-power.json"
    mv "configurations/intune/Energy.json" "configurations/intune/pol-sys-102-power.json"
fi
if [ -f "configurations/intune/Energy._xml" ]; then
    echo "Renaming: configurations/intune/Energy._xml -> configurations/intune/pol-sys-102-power.xml"
    mv "configurations/intune/Energy._xml" "configurations/intune/pol-sys-102-power.xml"
fi

rename_pair "configurations/intune/Software Update Policy" "configurations/intune/pol-sys-103-software-update" "json" "xml"
rename_pair "configurations/intune/ddm-passcode" "configurations/intune/pol-sys-104-ddm-passcode" "json" "xml"
rename_pair "configurations/intune/macos-enrollment-restriction" "configurations/intune/pol-sys-105-enrollment-restriction" "json" "xml"

echo "\n## Application Policies (POL-APP) ##"
rename_pair "configurations/intune/Office" "configurations/intune/pol-app-100-office" "json" "xml"
rename_pair "configurations/Secure Enterprise Browser/Edge macOS Level 1 Basic" "configurations/Secure Enterprise Browser/pol-app-101-edge-level1" "json" "xml"
rename_pair "configurations/Secure Enterprise Browser/Edge macOS Level 2 Recommended" "configurations/Secure Enterprise Browser/pol-app-102-edge-level2" "json" "xml"
rename_pair "configurations/Secure Enterprise Browser/Edge macOS Level 3 Strict" "configurations/Secure Enterprise Browser/pol-app-103-edge-level3" "json" "xml"

echo "\n## Microsoft Defender (MDE) ##"
rename_pair "mde/MDE - Settings Catalog Combined" "mde/pol-mde-001-settings-catalog" "json" "xml"
rename_pair "mde/WindowsDefenderATPOnboarding" "mde/cfg-mde-001-onboarding" "mobileconfig" "xml"
rename_pair "mde/99 - installDefender" "mde/scr-mde-100-install-defender" "zsh" "xml"

echo "\n## Utility Applications (APP-UTL) ##"
rename_pair "apps/00 - dialog-2.5.6-4805" "apps/app-utl-001-swift-dialog" "pkg" "xml"
rename_pair "apps/01 - Swift Dialog Onboarding" "apps/app-utl-002-dialog-onboarding" "pkg" "xml"

# Handle onboarding zip and scripts
if [ -f "apps/01 - Swift Dialog Onboarding.zip" ]; then
    echo "Renaming: apps/01 - Swift Dialog Onboarding.zip -> apps/app-utl-002-dialog-onboarding.zip"
    mv "apps/01 - Swift Dialog Onboarding.zip" "apps/app-utl-002-dialog-onboarding.zip"
fi
if [ -f "apps/01 - Swift Dialog Onboarding_pre.sh" ]; then
    echo "Renaming: apps/01 - Swift Dialog Onboarding_pre.sh -> apps/app-utl-002-dialog-onboarding_pre.sh"
    mv "apps/01 - Swift Dialog Onboarding_pre.sh" "apps/app-utl-002-dialog-onboarding_pre.sh"
fi
if [ -f "apps/01 - Swift Dialog Onboarding_post.sh" ]; then
    echo "Renaming: apps/01 - Swift Dialog Onboarding_post.sh -> apps/app-utl-002-dialog-onboarding_post.sh"
    mv "apps/01 - Swift Dialog Onboarding_post.sh" "apps/app-utl-002-dialog-onboarding_post.sh"
fi

rename_pair "apps/ZZ - MacEvaluationUtility" "apps/app-utl-003-mac-evaluation" "pkg" "xml"
rename_pair "apps/ZZ - IntuneLogWatch" "apps/app-utl-004-log-watch" "pkg" "xml"

echo "\n## Scripts ##"
rename_pair "scripts/intune/10 - install-company-portal" "scripts/intune/scr-app-100-install-company-portal" "sh" "xml"
rename_pair "scripts/intune/11 - install-escrow-buddy" "scripts/intune/scr-sec-100-install-escrow-buddy" "sh" "xml"
rename_pair "scripts/intune/12 - device-rename" "scripts/intune/scr-sys-100-device-rename" "sh" "xml"
rename_pair "scripts/intune/ZZ - configure-dock" "scripts/intune/scr-sys-101-configure-dock" "sh" "xml"
rename_pair "scripts/intune/ZZ - setOfficeDefaultApps" "scripts/intune/scr-app-101-office-defaults" "sh" "xml"

echo "\n## Custom Attributes ##"
rename_pair "custom attributes/macOSCompatibilityChecker" "custom attributes/cat-sys-100-compatibility-checker" "zsh" "xml"

echo "\n================================================================"
echo "Physical file renaming complete!"
echo "Next step: Update all XML manifests with ReferenceId and corrected SourceFile paths"
