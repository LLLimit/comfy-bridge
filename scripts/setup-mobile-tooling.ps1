$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$toolingRoot = Join-Path $projectRoot ".tooling"
$downloadRoot = Join-Path $toolingRoot "downloads"
$tempRoot = Join-Path $toolingRoot "tmp"
$flutterRoot = Join-Path $toolingRoot "flutter"
$jdkRoot = Join-Path $toolingRoot "jdk"
$androidRoot = Join-Path $toolingRoot "android-sdk"
$pubCache = Join-Path $toolingRoot "pub-cache"
$gradleHome = Join-Path $toolingRoot "gradle-home"

New-Item -ItemType Directory -Force -Path $toolingRoot, $downloadRoot, $tempRoot, $pubCache, $gradleHome | Out-Null
$env:TEMP = $tempRoot
$env:TMP = $tempRoot
$env:PUB_CACHE = $pubCache
$env:GRADLE_USER_HOME = $gradleHome

function Get-VerifiedArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Sha256
    )
    $valid = $false
    if (Test-Path -LiteralPath $Destination) {
        $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        $valid = $actual -eq $Sha256.ToLowerInvariant()
        if (-not $valid) {
            Remove-Item -LiteralPath $Destination -Force
        }
    }
    if (-not $valid) {
        & curl.exe --fail --location --retry 3 --output $Destination $Uri
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed: $Uri"
        }
        $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Sha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $Destination -Force
            throw "SHA-256 mismatch for $Destination"
        }
    }
}

$flutterExe = Join-Path $flutterRoot "bin\flutter.bat"
if (-not (Test-Path -LiteralPath $flutterExe)) {
    $releaseIndex = Invoke-RestMethod -Uri "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
    $stableHash = $releaseIndex.current_release.stable
    $stable = $releaseIndex.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1
    if ($null -eq $stable) {
        throw "Cannot resolve the current stable Flutter release."
    }
    $flutterArchive = Join-Path $downloadRoot "flutter-stable.zip"
    Get-VerifiedArchive -Uri "$($releaseIndex.base_url)/$($stable.archive)" -Destination $flutterArchive -Sha256 $stable.sha256
    Expand-Archive -LiteralPath $flutterArchive -DestinationPath $toolingRoot -Force
    Remove-Item -LiteralPath $flutterArchive -Force
}

$javaExe = Join-Path $jdkRoot "bin\java.exe"
if (-not (Test-Path -LiteralPath $javaExe)) {
    $assets = Invoke-RestMethod -Uri "https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"
    $package = $assets[0].binary.package
    $jdkArchive = Join-Path $downloadRoot "jdk17.zip"
    Get-VerifiedArchive -Uri $package.link -Destination $jdkArchive -Sha256 $package.checksum
    $jdkExtract = Join-Path $toolingRoot "jdk-extract"
    New-Item -ItemType Directory -Force -Path $jdkExtract | Out-Null
    Expand-Archive -LiteralPath $jdkArchive -DestinationPath $jdkExtract -Force
    $jdkSource = Get-ChildItem -LiteralPath $jdkExtract -Directory | Select-Object -First 1
    if ($null -eq $jdkSource) {
        throw "JDK archive did not contain a directory."
    }
    Move-Item -LiteralPath $jdkSource.FullName -Destination $jdkRoot
    Remove-Item -LiteralPath $jdkExtract -Recurse -Force
    Remove-Item -LiteralPath $jdkArchive -Force
}

$sdkManager = Join-Path $androidRoot "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path -LiteralPath $sdkManager)) {
    $androidArchive = Join-Path $downloadRoot "android-commandline-tools.zip"
    Get-VerifiedArchive `
        -Uri "https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip" `
        -Destination $androidArchive `
        -Sha256 "90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a"
    $androidExtract = Join-Path $toolingRoot "android-commandline-extract"
    New-Item -ItemType Directory -Force -Path $androidExtract | Out-Null
    Expand-Archive -LiteralPath $androidArchive -DestinationPath $androidExtract -Force
    $latestRoot = Join-Path $androidRoot "cmdline-tools\latest"
    New-Item -ItemType Directory -Force -Path $latestRoot | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $androidExtract "cmdline-tools") -Force | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination $latestRoot
    }
    Remove-Item -LiteralPath $androidExtract -Recurse -Force
    Remove-Item -LiteralPath $androidArchive -Force
}

$env:JAVA_HOME = $jdkRoot
$env:ANDROID_HOME = $androidRoot
$env:ANDROID_SDK_ROOT = $androidRoot
$env:Path = "$(Join-Path $jdkRoot 'bin');$(Join-Path $flutterRoot 'bin');$(Join-Path $androidRoot 'platform-tools');$env:Path"

$licenseAnswers = 1..100 | ForEach-Object { "y" }
$licenseAnswers | & $sdkManager --licenses | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Android SDK license setup failed."
}

& $sdkManager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
if ($LASTEXITCODE -ne 0) {
    throw "Android SDK package installation failed."
}

$localProperties = Join-Path $projectRoot "apps\mobile\android\local.properties"
$flutterProperty = $flutterRoot.Replace("\", "\\")
$androidProperty = $androidRoot.Replace("\", "\\")
@(
    "flutter.sdk=$flutterProperty"
    "sdk.dir=$androidProperty"
    "flutter.buildMode=debug"
    "flutter.versionName=1.0.0"
    "flutter.versionCode=1"
) | Set-Content -LiteralPath $localProperties -Encoding ASCII

& $flutterExe config --no-analytics
& $flutterExe precache --android

Write-Host "Flutter: $flutterRoot"
Write-Host "JDK: $jdkRoot"
Write-Host "Android SDK: $androidRoot"
Write-Host "Pub cache: $pubCache"
Write-Host "Gradle cache: $gradleHome"
