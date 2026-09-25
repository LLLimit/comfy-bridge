$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentDir = Join-Path $projectRoot "apps\agent"
$venvPython = Join-Path $agentDir ".venv\Scripts\python.exe"
$venvPythonw = Join-Path $agentDir ".venv\Scripts\pythonw.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
    & (Join-Path $PSScriptRoot "setup-agent.ps1")
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath $venvPythonw)) {
    throw "Python GUI runtime was not found: $venvPythonw"
}

$process = Start-Process `
    -FilePath $venvPythonw `
    -ArgumentList @("-m", "comfy_bridge.gui") `
    -WorkingDirectory $agentDir `
    -PassThru

if ($null -eq $process) {
    throw "Failed to launch the Comfy Bridge Control Center."
}
