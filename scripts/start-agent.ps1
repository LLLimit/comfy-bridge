$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentDir = Join-Path $projectRoot "apps\agent"
$venvPython = Join-Path $agentDir ".venv\Scripts\python.exe"
$dataDir = Join-Path $agentDir "data"
$tokenFile = Join-Path $dataDir "device-token.txt"
$workflowDir = Join-Path $projectRoot "workflow-packs"

if (-not (Test-Path -LiteralPath $venvPython)) {
    & (Join-Path $PSScriptRoot "setup-agent.ps1")
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
if (-not (Test-Path -LiteralPath $tokenFile)) {
    $bytes = New-Object byte[] 32
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }
    $token = [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
    [System.IO.File]::WriteAllText($tokenFile, $token + [Environment]::NewLine)
}

$token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
$comfyUrl = "http://127.0.0.1:8188"
$comfyOnline = $false
try {
    $null = Invoke-RestMethod -Uri "$comfyUrl/system_stats" -TimeoutSec 5
    $comfyOnline = $true
}
catch {
    $comfyOnline = $false
}

$lanAddress = $null
$preferredInterfaceIndex = $null
$preferredInterfaceAlias = $null
$networkIsPublic = $false
try {
    $activeIndexes = @(
        Get-NetAdapter -ErrorAction Stop |
            Where-Object { $_.Status -eq "Up" } |
            ForEach-Object { [int]$_.ifIndex }
    )
    $preferredRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
        Where-Object { $activeIndexes -contains [int]$_.InterfaceIndex } |
        Sort-Object @{ Expression = { [int]$_.RouteMetric + [int]$_.InterfaceMetric } }, InterfaceIndex |
        Select-Object -First 1
    if ($null -ne $preferredRoute) {
        $preferredInterfaceIndex = [int]$preferredRoute.InterfaceIndex
        $preferredInterfaceAlias = $preferredRoute.InterfaceAlias
        $lanAddress = Get-NetIPAddress -InterfaceIndex $preferredInterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike "169.254.*" -and
                $_.IPAddress -notlike "127.*" -and
                -not $_.SkipAsSource
            } |
            Select-Object -First 1 -ExpandProperty IPAddress
        $networkIsPublic = [bool](
            Get-NetConnectionProfile -ErrorAction SilentlyContinue |
                Where-Object {
                    [int]$_.InterfaceIndex -eq $preferredInterfaceIndex -and
                    $_.NetworkCategory -eq "Public"
                }
        )
    }
}
catch {
    $lanAddress = $null
    $preferredInterfaceIndex = $null
    $preferredInterfaceAlias = $null
    $networkIsPublic = $false
}

$env:COMFY_BRIDGE_HOST = "0.0.0.0"
$env:COMFY_BRIDGE_PORT = "8787"
$env:COMFY_BRIDGE_COMFY_URL = $comfyUrl
$env:COMFY_BRIDGE_DATA_DIR = $dataDir
$env:COMFY_BRIDGE_WORKFLOW_DIR = $workflowDir
$env:PYTHONUTF8 = "1"

Clear-Host
Write-Host "Comfy Bridge Agent" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host "ComfyUI backend: $comfyUrl ($(if ($comfyOnline) { 'online' } else { 'offline' }))"
if ($null -ne $lanAddress) {
    Write-Host "Network interface: $preferredInterfaceAlias" -ForegroundColor DarkGray
    Write-Host "Mobile Agent URL: http://${lanAddress}:8787" -ForegroundColor Yellow
}
else {
    Write-Host "Mobile Agent URL: http://<Windows LAN IP>:8787" -ForegroundColor Yellow
}
Write-Host "Device token: $token" -ForegroundColor Yellow
Write-Host "Agent log: $(Join-Path $dataDir 'agent.log')" -ForegroundColor DarkGray
if ($networkIsPublic) {
    Write-Host "WARNING: The active Windows network is Public; the phone may be blocked." -ForegroundColor Red
    Write-Host "For a trusted home LAN, change its network profile to Private." -ForegroundColor Yellow
    Write-Host "Windows Settings > Network and Internet > Properties > Network profile > Private" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Keep this window open. Press Ctrl+C or close it to stop the Agent."
Write-Host "If the phone cannot connect, allow Python on Private networks in Windows Firewall."
Write-Host ""

Push-Location $agentDir
try {
    & $venvPython -m comfy_bridge
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}