$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'build-slu.py'
python $script
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
