
$manifestUrl = "https://raw.githubusercontent.com/microsoft/intune-my-macs/refs/heads/main/manifest.json?token=GHSAT0AAAAAADGFKNLD3FSIMUE5TVBOWIRS2EVFJRA"

$jsonManifest = (Invoke-WebRequest -Uri $manifestUrl -Method GET)
#$jsonManifest = $jsonManifest.Content 

# convert json to object
$objManifest = $jsonManifest | ConvertFrom-Json

foreach ($item in $objManifest.manifest.policies.policy) {
    # Process each policy in the manifest
    $item.name
}