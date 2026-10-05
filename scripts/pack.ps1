# 打 Android APK 与 Windows 发布目录。产物在 dist/。网络请求走国内镜像，见 scripts/china-mirrors.ps1。

param(
    [string]$FlutterPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

. (Join-Path $PSScriptRoot "china-mirrors.ps1")

$flutterBin = "D:\AI\tools\flutter\bin"
if ($env:Path -notlike "*$flutterBin*") {
    $env:Path = "$env:Path;$flutterBin"
}

if (-not $FlutterPath) {
    $candidate = Join-Path $flutterBin "flutter.bat"
    $FlutterPath = if (Test-Path $candidate) { $candidate } else { "flutter" }
}

$jdk17 = Join-Path $env:LOCALAPPDATA "Programs\Microsoft\jdk-17.0.10.7-hotspot"
if (Test-Path $jdk17) {
    $env:JAVA_HOME = $jdk17
    $env:Path = "$jdk17\bin;$env:Path"
    Write-Host "Using JAVA_HOME=$jdk17"
}

Install-LiushengGradleMirror -RepoRoot $root
Install-LiushengAndroidRepoCfg
Write-Host "Mirrors: pub=$env:PUB_HOSTED_URL sdk=$env:SDK_TEST_BASE_URL"

$version = "2.2.2"
if (Test-Path "pubspec.yaml") {
    $match = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*([^\+]+)" | Select-Object -First 1
    if ($match) { $version = $match.Matches[0].Groups[1].Value.Trim() }
}

New-Item -ItemType Directory -Force -Path "dist" | Out-Null

Write-Host "Ensuring Android NDK from Tencent mirror..."
Install-LiushengAndroidNdk

# gradle, flutter and ISCC all write ordinary progress to stderr. This script
# sets ErrorActionPreference = Stop so the helper functions above can catch
# failures with try/catch, but under Stop a native tool's stderr line becomes a
# terminating error: the script used to die right after a successful
# `flutter build apk` and never reach the Windows step, leaving dist/ without
# the APK it had just produced. Run every native tool through this wrapper - the
# preference is relaxed only for the call itself and the real exit code comes
# back for the explicit checks below. Everything else (Copy-Item,
# Compress-Archive) stays under Stop and still throws on failure.
function Invoke-NativeTool {
    param(
        [string]$File,
        [string[]]$ToolArgs
    )

    $strictPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Out-Host is required, not decoration: a PowerShell function returns
        # everything the native command wrote to the output stream, so without
        # it the caller's exit-code check would compare a whole array of build
        # log lines against 0 and report a false failure.
        & $File @ToolArgs | Out-Host
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $strictPreference
    }
    return $code
}

if (Test-Path (Join-Path $root "android\key.properties")) {
    Write-Host "Android signing: release keystore (android/key.properties)"
} else {
    Write-Host "Android signing: debug (missing android/key.properties)"
}

$gradlew = Join-Path $root "android\gradlew.bat"
if (Test-Path $gradlew) {
    Write-Host "Stopping Gradle daemon..."
    $stopExit = Invoke-NativeTool -File $gradlew -ToolArgs @("--stop")
    if ($stopExit -ne 0) {
        Write-Host "gradlew --stop exited $stopExit; continuing pack"
    }
}

Write-Host "Building Android APK..."
$apkExit = Invoke-NativeTool -File $FlutterPath -ToolArgs @("build", "apk", "--release")
if ($apkExit -ne 0) { throw "Android APK build failed" }
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "dist\liusheng-$version.apk" -Force

Write-Host "Building Windows zip..."
$winExit = Invoke-NativeTool -File $FlutterPath -ToolArgs @("build", "windows", "--release")
if ($winExit -ne 0) { throw "Windows build failed" }

$winDir = "build\windows\x64\runner\Release"
if (-not (Test-Path $winDir)) {
    $winDir = "build\windows\runner\Release"
}
$zipPath = "dist\liusheng-windows-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$winDir\*" -DestinationPath $zipPath -Force

Write-Host "Building Windows installer with Inno Setup..."
$iscc = "D:\PF\Inno Setup 7\ISCC.exe"
if (-not (Test-Path $iscc)) {
    $iscc = "ISCC.exe"
}
$issExit = Invoke-NativeTool -File $iscc -ToolArgs @((Join-Path $PSScriptRoot "liusheng-windows.iss"))
if ($issExit -ne 0) { throw "Inno Setup build failed" }

Write-Host "Done."
Write-Host "  Android: dist\liusheng-$version.apk"
Write-Host "  Windows zip: $zipPath"
$exePath = "dist\liusheng-windows-$version.exe"
if (Test-Path $exePath) { Write-Host "  Windows installer: $exePath" }
