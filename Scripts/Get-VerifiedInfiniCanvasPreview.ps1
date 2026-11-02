# Download an EXISTING unsigned PREVIEW IPA for a known exact source SHA.
# This NEVER builds, signs, installs, erases, or replaces the user's iPad app.
# Requires GitHub CLI installed and authenticated on Windows.
param(
    [Parameter(Mandatory=$true)][string]$ExpectedSha,
    [string]$Branch = "main",
    [string]$Destination = "$HOME\\Downloads\\InfiniCanvas-preview"
)

$ErrorActionPreference = "Stop"
$Repo = "perspective2001/InfiniCanvasCore"
$Workflow = "Build unsigned iPad IPA for personal sideloading"

if ($ExpectedSha -notmatch '^[0-9a-fA-F]{40}$') {
    throw "ExpectedSha must be the full 40-character commit SHA of the tested source."
}

& gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Run gh auth login first." }
$raw = & gh run list --repo $Repo --workflow $Workflow --branch $Branch --limit 75 --json databaseId,headSha,conclusion
if ($LASTEXITCODE -ne 0) { throw "Unable to retrieve workflow runs." }
$runs = $raw | ConvertFrom-Json
$selected = $runs |
    Where-Object { $_.headSha -eq $ExpectedSha -and $_.conclusion -eq "success" } |
    Select-Object -First 1
if ($null -eq $selected) {
    throw "No successful PREVIEW IPA artifact build for SHA $ExpectedSha on branch $Branch. Do not substitute a different build."
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
& gh run download $selected.databaseId --repo $Repo --name InfiniCanvas-unsigned-preview --dir $Destination
if ($LASTEXITCODE -ne 0) { throw "Artifact download failed or has expired." }
$ipa = Join-Path $Destination "InfiniCanvas-unsigned-preview.ipa"
$infoPath = Join-Path $Destination "InfiniCanvas-BUILD-INFO.txt"
if (-not (Test-Path $ipa) -or -not (Test-Path $infoPath)) {
    throw "Missing IPA or required build provenance. Do NOT install."
}
$info = Get-Content $infoPath -Raw
if ($info -notmatch [regex]::Escape("Source commit: $ExpectedSha")) {
    throw "Downloaded IPA provenance SHA does not match. Do NOT install."
}
if ($info -notmatch "InfiniCanvas-unsigned-preview") {
    throw "Downloaded artifact is not the separate preview identity."
}
Write-Host "Verified matching source SHA: $ExpectedSha"
Write-Host "Unsigned candidate IPA at: $ipa"
Write-Host "This is an UNINSTALLED preview, not physical Pencil verification."
Write-Host "Keep the existing app and all its local data. Sideload only after the device-test decision."
