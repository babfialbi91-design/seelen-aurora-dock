$ErrorActionPreference = 'SilentlyContinue'

# Commits and pushes the theme repo when anything changed.
$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try {
  $dirty = git status --porcelain
  if (-not $dirty) { return }
  git add -A
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
  git commit -m "chore: auto-sync $stamp" | Out-Null
  git push origin HEAD | Out-Null
} finally {
  Pop-Location
}
