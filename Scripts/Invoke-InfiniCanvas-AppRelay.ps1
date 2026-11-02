# InfiniCanvas's one-command Windows handoff.
# Same existing GitHub Xcode -> automatic extract -> Explorer -> Sideloadly
# pattern. Never touches or uninstalls the current iPad app.
# Usage (from PowerShell):
#   .\Invoke-InfiniCanvas-AppRelay.ps1
param(
  [string]$Branch = 'candidate-infini-navigation-delete-morph-20261102',
  [string]$Destination = (Join-Path $env:USERPROFILE 'Downloads\InfiniCanvas-AppRelay'),
  [switch]$DownloadOnly
)
$ErrorActionPreference = 'Stop'
$repo = 'perspective2001/InfiniCanvasCore'
$workflow = 'build-unsigned-ipa.yml'
$artifact = 'InfiniCanvas-unsigned-preview'

function Assert-GitHub {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI not found. Install gh or use your existing AppRelay setup.'
  }
  & gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI login required: gh auth login' }
}
function Get-Runs {
  $json = & gh run list -R $repo --workflow $workflow --branch $Branch --limit 100 --json databaseId,headSha,status,conclusion
  if ($LASTEXITCODE -ne 0) { throw 'Unable to list GitHub IPA workflow runs.' }
  return @($json | ConvertFrom-Json)
}
Assert-GitHub
$rawRef = & gh api "repos/$repo/git/ref/heads/$Branch"
if ($LASTEXITCODE -ne 0) { throw "Cannot resolve branch $Branch" }
$expected = ($rawRef | ConvertFrom-Json).object.sha
if ($expected -notmatch '^[0-9a-f]{40}$') { throw 'Invalid source SHA.' }
Write-Host "InfiniCanvas source: $expected"

$matches = @(Get-Runs | Where-Object {
    $_.headSha -eq $expected -and $_.conclusion -eq 'success'
})
$run = $matches | Select-Object -First 1
if (-not $run -and -not $DownloadOnly) {
  Write-Host 'No completed IPA for this exact source. Triggering the existing unsigned PREVIEW build.'
  & gh workflow run $workflow -R $repo --ref $Branch -f identity=preview
  if ($LASTEXITCODE -ne 0) { throw 'Could not request the GitHub Xcode build.' }
  $attempt = 0
  do {
    Start-Sleep -Seconds 10
    $attempt++
    $latest = @(Get-Runs | Where-Object { $_.headSha -eq $expected } |
      Select-Object -First 1)
    if ($latest.Count -gt 0) {
      if ($latest[0].conclusion -eq 'failure' -or $latest[0].conclusion -eq 'cancelled') {
        throw "The build did not succeed. Inspect GitHub Actions run $($latest[0].databaseId)."
      }
      if ($latest[0].conclusion -eq 'success') {
        $run = $latest[0]
      }
    }
  } until ($run -or $attempt -ge 120)
}
if (-not $run) {
  throw 'No successful unsigned preview IPA for this exact source SHA. Refusing to use an older IPA.'
}

$folder = Join-Path $Destination $expected
New-Item -ItemType Directory -Force -Path $folder | Out-Null
# 'gh run download' already extracts the GitHub artifact ZIP to this folder.
& gh run download $run.databaseId -R $repo -n $artifact -D $folder
if ($LASTEXITCODE -ne 0) { throw 'Unable to download or extract the IPA artifact.' }

$ipa = Join-Path $folder 'InfiniCanvas-unsigned-preview.ipa'
$manifestPath = Join-Path $folder 'InfiniCanvas-BUILD-INFO.txt'
if (-not (Test-Path -LiteralPath $ipa) -or -not (Test-Path -LiteralPath $manifestPath)) {
  throw 'Artifact missing IPA or source information. Do not install.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw
if (-not $manifest.Contains("Source commit: $expected")) {
  throw 'Source SHA mismatch: refusing the IPA.'
}
if (-not $manifest.Contains('InfiniCanvas-unsigned-preview')) {
  throw 'Wrong app identity: expected PREVIEW. Refusing to overwrite primary app.'
}
Write-Host "MATCHED IPA: $ipa"
Write-Host 'Explorer is opening. Drag the .ipa file into Sideloadly and sign with the existing Apple ID.'
Write-Host 'Keep your installed primary app and its drawings. This preview app uses a separate sandbox.'
Start-Process explorer.exe -ArgumentList $folder
