# 将 flutter build windows 的产物打包成 Inno Setup 安装器。
#
# 需要 Inno Setup 6：winget install --id JRSoftware.InnoSetup -e
# 安装器按用户安装到 %LOCALAPPDATA%\Programs，应用内静默升级不需要 UAC。
param(
    [string]$Version,
    [int]$BuildNumber = 0,
    [string]$ReleaseDir,
    [string]$OutputDir,
    [string]$IsccPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'

if ([string]::IsNullOrWhiteSpace($Version)) {
    $pubspec = Get-Content -LiteralPath $pubspecPath -Raw
    if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?') {
        throw '无法从 pubspec.yaml 解析版本号。'
    }
    $Version = $Matches[1]
    if ($BuildNumber -le 0 -and $Matches[2]) {
        $BuildNumber = [int]$Matches[2]
    }
}
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "版本号必须形如 1.2.3（不含 +build）：$Version"
}
if ($BuildNumber -le 0) {
    $BuildNumber = 1
}

if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $ReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
} elseif (-not [System.IO.Path]::IsPathRooted($ReleaseDir)) {
    $ReleaseDir = Join-Path $repoRoot $ReleaseDir
}
$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path
$exePath = Join-Path $ReleaseDir 'simul_groove_player.exe'
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "缺少 Windows 构建产物：$exePath。请先运行 flutter build windows --release。"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot 'build\artifacts\windows-installer'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $repoRoot $OutputDir
}
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$isccCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($IsccPath)) {
    $isccCandidates += $IsccPath
}
if (-not [string]::IsNullOrWhiteSpace($env:ISCC)) {
    $isccCandidates += $env:ISCC
}
if (-not [string]::IsNullOrWhiteSpace($env:INNO_SETUP_HOME)) {
    $isccCandidates += (Join-Path $env:INNO_SETUP_HOME 'ISCC.exe')
}
$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
if ($programFilesX86) {
    $isccCandidates += (Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe')
}
if ($env:ProgramFiles) {
    $isccCandidates += (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
}
if ($env:LOCALAPPDATA) {
    $isccCandidates += (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
}
$isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($isccCommand) {
    $isccCandidates += $isccCommand.Source
}

$iscc = $isccCandidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -First 1

if (-not $iscc) {
    throw @'
未找到 Inno Setup 6 的 ISCC.exe。
安装方式（任选其一）：
  winget install --id JRSoftware.InnoSetup -e
  或从 https://jrsoftware.org/isdl.php 安装后重新运行。
'@
}

$issPath = Join-Path $PSScriptRoot 'installer\simul_groove_music.iss'
if (-not (Test-Path -LiteralPath $issPath -PathType Leaf)) {
    throw "缺少安装器脚本：$issPath"
}

Write-Host "Inno Setup: $iscc"
Write-Host "版本: $Version+$BuildNumber"
Write-Host "源目录: $ReleaseDir"
Write-Host "输出目录: $OutputDir"

& $iscc `
    "/DAppVersion=$Version" `
    "/DAppBuild=$BuildNumber" `
    "/DReleaseDir=$ReleaseDir" `
    "/DOutputDir=$OutputDir" `
    $issPath
if ($LASTEXITCODE -ne 0) {
    throw "ISCC 编译失败，退出码: $LASTEXITCODE"
}

$installerPath = Join-Path $OutputDir "SimulGrooveMusic-Setup-$Version-x64.exe"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "安装器没有生成到预期位置：$installerPath"
}

$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
$size = (Get-Item -LiteralPath $installerPath).Length
Write-Host ''
Write-Host '安装器构建成功：' -ForegroundColor Green
Write-Host "  $installerPath"
Write-Host ("  大小: {0:N0} 字节" -f $size)
Write-Host "  SHA-256: $hash"
