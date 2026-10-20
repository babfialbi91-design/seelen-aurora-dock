param([switch]$DryRun)

# Native tools write progress to stderr; with 'Stop' PowerShell would treat
# that as a fatal error, so failures are checked explicitly instead.
$ErrorActionPreference = 'Continue'
$env:GH_PAGER = ''
$env:GH_PROMPT_DISABLED = '1'
$env:GIT_TERMINAL_PROMPT = '0'

# Builds dist/aurora-dock.slu, bumps the patch version from the latest remote
# tag, pushes the repo and publishes the .slu as a GitHub release asset.

$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try {
  # Prefer local tags (instant). Only ask GitHub when there are none yet.
  $tags = @(git tag --list 'v*')
  if ($tags.Count -eq 0) {
    $tags = @(
      git ls-remote --tags origin 2>$null |
        ForEach-Object { ($_ -split "`t")[1] -replace '^refs/tags/', '' } |
        Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }
    )
  }

  $latest = $tags | Sort-Object { [version]($_ -replace '^v', '') } -Descending | Select-Object -First 1
  if ($latest) {
    $v = [version]($latest -replace '^v', '')
    $version = "$($v.Major).$($v.Minor).$($v.Build + 1)"
  } else {
    $version = '1.0.0'
  }

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-slu.ps1')
  if ($LASTEXITCODE -ne 0) { throw 'build-slu failed' }

  $asset = Join-Path $repo 'dist\aurora-dock.slu'
  if (-not (Test-Path $asset)) { throw 'dist/aurora-dock.slu was not created' }

  if ($DryRun) {
    Write-Output "dry run: would release v$version with $asset"
    return
  }

  if (git status --porcelain) {
    git add -A
    git commit -m "release: v$version" | Out-Null
  }
  $ahead = [int](git rev-list --count 'origin/master..HEAD' 2>$null)
  if ($ahead -gt 0) {
    # GitHub connectivity here is intermittent, so retry with a stall guard.
    $gitOpts = @('-c', 'http.lowSpeedLimit=1000', '-c', 'http.lowSpeedTime=45')
    $pushed = $false
    for ($i = 1; $i -le 3; $i++) {
      git @gitOpts push origin HEAD 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
      Start-Sleep -Seconds 4
    }
    if (-not $pushed) { throw 'git push failed after 3 attempts' }
  }

  gh release create "v$version" $asset --title "Aurora Dock v$version" --generate-notes
  if ($LASTEXITCODE -ne 0) { throw "gh release create failed with exit code $LASTEXITCODE" }

  git tag "v$version" 2>$null
  Write-Output "released v$version -> $asset"
} finally {
  Pop-Location
}
