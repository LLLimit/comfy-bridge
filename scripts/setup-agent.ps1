$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentDir = Join-Path $projectRoot "apps\agent"
$venvDir = Join-Path $agentDir ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if (Test-Path -LiteralPath $venvPython) {
    Write-Host "Agent environment already exists on F:." -ForegroundColor Green
    exit 0
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
    throw "Python was not found. Install Python 3.12 or newer, then run start-agent.cmd again."
}

$toolingDir = Join-Path $projectRoot ".tooling"
$env:PIP_CACHE_DIR = Join-Path $toolingDir "pip-cache"
New-Item -ItemType Directory -Force -Path $toolingDir | Out-Null

Write-Host "Creating Agent environment on F: ..." -ForegroundColor Cyan
& $pythonCommand.Source -m venv $venvDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create the Agent virtual environment."
}

Write-Host "Installing Agent dependencies on F: ..." -ForegroundColor Cyan
& $venvPython -m pip install --disable-pip-version-check -e $agentDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install the Agent dependencies."
}

Write-Host "Agent environment is ready." -ForegroundColor Green
