## Distributed Manifest Specification

This repository uses a distributed manifest model. Each deployable artifact (Policy, Script, Package) has a sibling XML file with the same base name and the extension `.xml` describing its metadata.

### Common Root
```xml
<MacIntuneManifest>
  <Type>Policy|Script|Package</Type>
  <Name>Display name used in Intune</Name>
  <Description>Human readable description</Description>
  <Platform>macOS</Platform>
  <Category>Identity|Security|Config|Restrictions|... (free text)</Category>
  <SourceFile>relative/path/to/source</SourceFile>
  <!-- Type specific subtree below -->
</MacIntuneManifest>
```

### Script Manifest (minimal required)
```xml
<MacIntuneManifest>
  <Type>Script</Type>
  <Name>...</Name>
  <Description>...</Description>
  <Platform>macOS</Platform>
  <Category>Config</Category>
  <SourceFile>scripts/intune/example.sh</SourceFile>
  <Script>
    <RunAsAccount>system|user</RunAsAccount>
    <BlockExecutionNotifications>true|false</BlockExecutionNotifications>
    <ExecutionFrequency>PT0S|ISO8601 duration</ExecutionFrequency>
    <RetryCount>0-10</RetryCount>
  </Script>
   </MacIntuneManifest>
</MacIntuneManifest>
```
Optional (previously present but now trimmed for scripts): DisplayName, FileName, PreInstallScript, PostInstallScript, bundle metadata. Keep these only if later tooling needs them.

### Policy Manifest
```xml
<MacIntuneManifest>
  <Type>Policy</Type>
  <Name>...</Name>
  <Description>...</Description>
  <Platform>macOS</Platform>
  <Category>Security</Category>
  <SourceFile>configurations/intune/policy.json</SourceFile>
  <SettingsCount>int</SettingsCount>
</MacIntuneManifest>
```

### Package (App) Manifest
```xml
<MacIntuneManifest>
  <Type>Package</Type>
  <Name>...</Name>
  <Description>...</Description>
  <Platform>macOS</Platform>
  <Category>Config</Category>
  <SourceFile>apps/Example.pkg</SourceFile>
  <Package>
    <DisplayName>...</DisplayName>
    <FileName>Example.pkg</FileName>
    <PreInstallScript></PreInstallScript>
    <PostInstallScript></PostInstallScript>
    <PrimaryBundleId>com.example.app</PrimaryBundleId>
    <PrimaryBundleVersion>1.0.0</PrimaryBundleVersion>
    <Publisher>Example Corp</Publisher>
    <MinimumSupportedOperatingSystem>v13_0</MinimumSupportedOperatingSystem>
    <IgnoreVersionDetection>true|false</IgnoreVersionDetection>
  </Package>
</MacIntuneManifest>
```

### Loader Behavior (`mainScript.ps1`)
1. Recursively searches the repo for `*.xml` files containing `<MacIntuneManifest`.
2. Parses metadata into in-memory objects.
3. If any XML manifests are found, legacy `manifest.json` is ignored.
4. For scripts & packages, if `FileName` is omitted it is inferred from `SourceFile`.

### Conventions
- File naming: `artifactBaseName.xml` next to the source file (except packages may reside in `apps/`).
- Categories are free form but should be consistent for filtering.
- Keep descriptions concise (<= 200 chars) for UI clarity.

### Future Enhancements
- Add XSD schema for validation.
- Add lint command to verify required nodes by Type.
- Support localization via optional `<Localization ref="..." />` node.
