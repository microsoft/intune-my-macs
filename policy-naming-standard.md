# Policy Naming Standard - Product Requirements Document

## Executive Summary

This document defines a standardized naming convention and unique reference system for all policies, scripts, applications, and configurations in the intune-my-macs repository. The standard ensures that each artifact can be uniquely identified, easily referenced, and consistently organized across the entire Microsoft Intune macOS management framework.

## Problem Statement

Currently, policies and applications in the repository are identified primarily by their display names, which can lead to:
- Ambiguity when discussing specific policies across teams
- Difficulty tracking changes and versions
- Challenges in automation and scripting
- Inconsistent organization across different artifact types
- Problems with duplicate or similar names

## Goals

1. Establish a unique reference ID system for every artifact in the repository
2. Create human-readable naming conventions that convey purpose and scope
3. Enable reliable cross-referencing in documentation and scripts
4. Support version tracking and lifecycle management
5. Maintain consistency across policies, scripts, apps, and configurations

## Non-Goals

- Changing existing deployed Intune object names (display names remain flexible)
- Enforcing file system path structures (references are independent of location)
- Requiring migration of existing artifacts (standard applies to new items, optional for existing)

## Reference ID Standard

### Format

Each artifact SHALL have a unique reference ID in the format:

```
[TYPE]-[CATEGORY]-[NUMBER]
```

**Components:**
- `TYPE`: 3-letter artifact type code (see table below)
- `CATEGORY`: 2-3 letter category code (see table below)
- `NUMBER`: Zero-padded 3-digit sequence number (001-999)

**Example:** `POL-SEC-042` (Security Policy #42)

### Type Codes

| Type Code | Description | Manifest Type |
|-----------|-------------|---------------|
| `POL` | Configuration Policy (Settings Catalog) | Policy |
| `CMP` | Compliance Policy | Compliance |
| `CFG` | Custom Configuration (mobileconfig) | CustomConfig |
| `SCR` | Shell Script | Script |
| `CAT` | Custom Attribute | CustomAttribute |
| `APP` | Application Package | Package |

### Category Codes

| Category Code | Description | Scope |
|---------------|-------------|-------|
| `SEC` | Security | CIS, NIST, FileVault, firewall, hardening |
| `MDE` | Microsoft Defender | MDE settings, onboarding, threat protection |
| `IDP` | Identity | SSO, Kerberos, Entra ID, authentication |
| `CMP` | Compliance | Compliance policies, audit scripts, reporting |
| `SYS` | System | General macOS configuration, preferences |
| `APP` | Applications | App-specific settings, software management |
| `UTL` | Utilities | Helper tools, diagnostic apps |

### Sequence Numbers

- Numbers 001-099: Reserved for core/critical items
- Numbers 100-999: Sequential assignment as artifacts are created

**Assignment Process:**
- Core items (FileVault, firewall, compliance baseline, etc.) use 001-099
- All other artifacts are assigned the next available number starting from 100
- Numbers are never reused, even after artifact deletion

## Display Name Standard

### Format

Display names SHALL follow this structure:

```
[Prefix] [Reference] - [Descriptive Name]
```

**Components:**
- `Prefix`: Deployment prefix (default: `[intune-my-macs]`, customizable via --prefix)
- `Reference`: The unique reference ID
- `Descriptive Name`: Clear, human-readable description of purpose

**Example:** `[intune-my-macs] POL-SEC-042 - CIS Level 2 Screensaver Security`

### Display Name Guidelines

1. **Descriptive Names:**
   - Use Title Case for all words except articles (a, an, the) and short prepositions
   - Maximum 80 characters (excluding prefix and reference)
   - Be specific about what the policy controls
   - Include version/level information when relevant

2. **Structure:**
   - Front-load important keywords for searchability
   - Use " - " (space-hyphen-space) to separate reference from description
   - Avoid special characters except hyphens and parentheses
   - No trailing punctuation

3. **Examples:**
   ```
   POL-SEC-001 - FileVault Disk Encryption
   POL-SEC-015 - CIS Level 2 Terminal Security
   CMP-CMP-001 - macOS Compliance - Minimum Security
   CFG-SEC-023 - CIS Level 2 Login Window Configuration
   SCR-MON-005 - Intune Agent Log Viewer
   APP-UTL-010 - Swift Dialog Onboarding Tool
   CAT-CMP-001 - CIS Level 2 Compliance Check
   ```

## Manifest XML Standard

### Reference ID Integration

All XML manifests SHALL include a `<ReferenceId>` element:

```xml
<MacIntuneManifest>
    <ReferenceId>POL-SEC-042</ReferenceId>
    <Type>Policy</Type>
    <Name>CIS Level 2 Screensaver Security</Name>
    <Description>...</Description>
    <!-- other elements -->
</MacIntuneManifest>
```

### Filename Convention

XML manifest filenames SHOULD follow this pattern:

```
[reference-id]-[descriptive-slug].xml
```

**Example:** `pol-sec-042-screensaver-security.xml`

Guidelines:
- Use lowercase for filenames
- Replace spaces with hyphens
- Keep slug concise (2-4 words)
- Match the reference ID (lowercase)

## File Organization

### Directory Structure

Artifacts SHOULD be organized by type and category:

```
configurations/
├── security-baseline/      # SEC category
│   ├── pol-sec-001-filevault.xml
│   ├── pol-sec-001-filevault.json
│   └── cfg-sec-015-login-window.xml
├── mde/                    # MDE category
│   ├── pol-mde-001-settings.xml
│   └── cfg-mde-005-onboarding.xml
└── networking/             # NET category
    └── pol-net-010-time-server.xml

apps/
├── app-utl-001-swift-dialog.xml
├── app-utl-001-swift-dialog.pkg
├── app-utl-005-intune-log-watch.xml
└── app-utl-005-intune-log-watch.pkg

scripts/
├── scr-mon-001-device-inventory.xml
├── scr-mon-001-device-inventory.zsh
├── scr-sys-010-device-rename.xml
└── scr-sys-010-device-rename.sh

custom attributes/
├── cat-cmp-001-cis-compliance.xml
└── cat-cmp-001-cis-compliance.sh
```

## Reference Documentation

### Master Reference Index

A `REFERENCE-INDEX.md` file SHALL be maintained in the repository root containing:

1. Complete list of all reference IDs in use
2. Brief description of each artifact
3. Status (active, deprecated, planned)
4. Links to related artifacts
5. Change history

**Format:**

```markdown
## Configuration Policies (POL)

### Security Baseline (SEC)
- **POL-SEC-001** - FileVault Disk Encryption | Active | [manifest](configurations/intune/filevault.xml)
- **POL-SEC-002** - Firewall Configuration | Active | [manifest](configurations/intune/FirewallConfiguration.xml)
- **POL-SEC-015** - CIS Level 2 Terminal Security | Active | [manifest](security-baseline/unsigned/com.apple.Terminal.xml)

### Microsoft Defender (MDE)
- **POL-MDE-001** - MDE Settings Catalog Combined | Active | [manifest](mde/MDE-Settings-Catalog-Combined.xml)
```

### Cross-Reference Support

When artifacts reference or depend on other artifacts, use reference IDs in descriptions:

```xml
<Description>
Configures login window security settings. Requires POL-SEC-001 (FileVault) 
and works in conjunction with CFG-SEC-020 (Screensaver Security).
</Description>
```

## Version Management

### Reference ID Stability

- Reference IDs are PERMANENT once assigned
- IDs are never reused, even after artifact deletion
- Major revisions create new reference IDs
- Minor updates retain the same reference ID

### Version Tracking

For artifacts requiring version tracking:

```xml
<MacIntuneManifest>
    <ReferenceId>POL-SEC-042</ReferenceId>
    <Version>2.1</Version>
    <Type>Policy</Type>
    <!-- ... -->
</MacIntuneManifest>
```

Version semantics:
- Major version: Significant functionality change or breaking change
- Minor version: Settings addition, enhancement, or bug fix

## Migration Plan

### Phase 1: New Artifacts (Immediate)
- All new artifacts MUST follow this standard
- Reference IDs assigned from available sequence numbers
- Manifests include `<ReferenceId>` element

### Phase 2: Existing Artifacts (Optional)
- Existing artifacts MAY be updated with reference IDs
- Priority: Security baseline, compliance policies, core apps
- Update manifests and create REFERENCE-INDEX.md

### Phase 3: Tooling Enhancement (Future)
- Update mainScript.ps1 to validate reference ID uniqueness
- Add reference ID to import output
- Generate REFERENCE-INDEX.md automatically
- Cross-reference validation

## Implementation Checklist

- [ ] Create REFERENCE-INDEX.md in repository root
- [ ] Assign reference IDs to existing artifacts (security baseline priority)
- [ ] Update XML manifest schema to include `<ReferenceId>`
- [ ] Update mainScript.ps1 to read and display reference IDs
- [ ] Add reference ID validation to Test-DistributedManifest function
- [ ] Document reference ID in README.md
- [ ] Update contribution guidelines with naming standard
- [ ] Create reference ID assignment process for contributors

## Examples

### Complete Examples

#### Configuration Policy
```xml
<MacIntuneManifest>
    <ReferenceId>POL-SEC-015</ReferenceId>
    <Version>1.0</Version>
    <Type>Policy</Type>
    <Name>CIS Level 2 Terminal Security</Name>
    <Description>
    Implements CIS macOS Benchmark Level 2 controls for Terminal.app including
    secure keyboard entry and auditing settings. Part of comprehensive security
    baseline implementation.
    </Description>
    <Platform>macOS</Platform>
    <Category>CIS Level 2 Security Baseline</Category>
    <SourceFile>configurations/intune/terminal-security.json</SourceFile>
    <SettingsCount>4</SettingsCount>
</MacIntuneManifest>
```

**Deployed Name:** `[intune-my-macs] POL-SEC-015 - CIS Level 2 Terminal Security`

#### Application Package
```xml
<MacIntuneManifest>
    <ReferenceId>APP-UTL-005</ReferenceId>
    <Version>1.4</Version>
    <Type>Package</Type>
    <Name>Intune Agent Log Viewer</Name>
    <Description>
    Utility application for viewing and troubleshooting Microsoft Intune Agent
    logs on macOS devices. Provides real-time log monitoring and filtering.
    </Description>
    <Platform>macOS</Platform>
    <Category>Utilities</Category>
    <SourceFile>apps/IntuneLogWatch.pkg</SourceFile>
    <Package>
        <PrimaryBundleId>com.gilburns.IntuneLogWatch</PrimaryBundleId>
        <PrimaryBundleVersion>1.4</PrimaryBundleVersion>
        <Publisher>Gil Burns</Publisher>
        <MinimumSupportedOperatingSystem>v10_13</MinimumSupportedOperatingSystem>
        <IgnoreVersionDetection>false</IgnoreVersionDetection>
    </Package>
</MacIntuneManifest>
```

**Deployed Name:** `[intune-my-macs] APP-UTL-005 - Intune Agent Log Viewer`

#### Custom Attribute
```xml
<MacIntuneManifest>
    <ReferenceId>CAT-CMP-001</ReferenceId>
    <Version>1.0</Version>
    <Type>CustomAttribute</Type>
    <Name>CIS Level 2 Compliance Check</Name>
    <Description>
    Audits device compliance against CIS macOS Benchmark Level 2 controls.
    Returns compliance percentage and lists failed controls. Read-only audit
    mode - does not modify system configuration.
    </Description>
    <Platform>macOS</Platform>
    <Category>Compliance and Audit</Category>
    <SourceFile>security-baseline/cis_lvl2_compliance.sh</SourceFile>
    <CustomAttribute>
        <CustomAttributeType>string</CustomAttributeType>
    </CustomAttribute>
</MacIntuneManifest>
```

**Deployed Name:** `[intune-my-macs] CAT-CMP-001 - CIS Level 2 Compliance Check`

## Benefits

1. **Unique Identification**: Every artifact has a permanent, unique identifier
2. **Cross-Referencing**: Easy to reference policies in documentation, tickets, and discussions
3. **Automation**: Scripts can reliably identify and manipulate specific artifacts
4. **Organization**: Logical grouping by type and category
5. **Scalability**: System supports 999 items per category (expandable)
6. **Version Tracking**: Clear versioning without breaking references
7. **Search & Discovery**: Structured naming improves searchability
8. **Onboarding**: New team members can quickly understand artifact purpose

## Governance

- **Standard Owner**: Repository maintainers
- **Review Cycle**: Quarterly review of category codes and sequence assignments
- **Change Process**: PRD updates require pull request and review
- **Exceptions**: Must be documented with justification in REFERENCE-INDEX.md

## References

- [CIS macOS Benchmark](https://www.cisecurity.org/benchmark/apple_os)
- [Microsoft Intune Documentation](https://learn.microsoft.com/en-us/mem/intune/)
- [Semantic Versioning 2.0.0](https://semver.org/)

---

**Document Version:** 1.0  
**Last Updated:** October 23, 2025  
**Status:** Active  
**Next Review:** January 2026
