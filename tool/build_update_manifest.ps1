# 生成应用内更新使用的 latest.json。
#
# 生成结果同时作为 Release 资产上传；客户端通过
# https://github.com/<owner>/<repo>/releases/latest/download/latest.json 读取。
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [int]$BuildNumber,

    [string]$InstallerPath,
    [string]$AndroidArm64Apk,
    [string]$AndroidArmV7Apk,
    [string]$AndroidX64Apk,
    [string]$Notes = '',
    [string]$NotesFile = '',
    [string]$Channel = 'stable',
    [string]$DownloadBaseUrl = 'https://github.com/zonwe/SimulGroove-Music/releases/download',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "版本号必须形如 1.2.3（不含 +build）：$Version"
}
if ($BuildNumber -le 0) {
    throw "构建号必须为正整数：$BuildNumber"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'build\artifacts\latest.json'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

if (-not [string]::IsNullOrWhiteSpace($NotesFile)) {
    if (-not (Test-Path -LiteralPath $NotesFile -PathType Leaf)) {
        throw "发布说明文件不存在：$NotesFile"
    }
    $Notes = [System.IO.File]::ReadAllText($NotesFile, [System.Text.Encoding]::UTF8)
}
$Notes = $Notes.Trim()
if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = "SimulGroove Music $Version"
}
if ($Notes.Length -gt 20000) {
    throw "发布说明超过 20000 字符上限。"
}

function New-UpdateAsset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    $resolved = (Resolve-Path -LiteralPath $FilePath).Path
    $file = Get-Item -LiteralPath $resolved
    if ($file.Length -le 0) {
        throw "更新包为空：$resolved"
    }
    $url = "$($DownloadBaseUrl.TrimEnd('/'))/v$Version/$([uri]::EscapeDataString($FileName))"
    return [ordered]@{
        url = $url
        size = [long]$file.Length
        sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
        kind = $Kind
    }
}

$assets = [ordered]@{}
$provided = 0

if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
    $assets['windows-x64'] = New-UpdateAsset `
        -FilePath $InstallerPath `
        -FileName ([System.IO.Path]::GetFileName($InstallerPath)) `
        -Kind 'installer'
    $provided++
}
if (-not [string]::IsNullOrWhiteSpace($AndroidArm64Apk)) {
    $assets['android-arm64-v8a'] = New-UpdateAsset `
        -FilePath $AndroidArm64Apk `
        -FileName ([System.IO.Path]::GetFileName($AndroidArm64Apk)) `
        -Kind 'apk'
    $provided++
}
if (-not [string]::IsNullOrWhiteSpace($AndroidArmV7Apk)) {
    $assets['android-armeabi-v7a'] = New-UpdateAsset `
        -FilePath $AndroidArmV7Apk `
        -FileName ([System.IO.Path]::GetFileName($AndroidArmV7Apk)) `
        -Kind 'apk'
    $provided++
}
if (-not [string]::IsNullOrWhiteSpace($AndroidX64Apk)) {
    $assets['android-x86_64'] = New-UpdateAsset `
        -FilePath $AndroidX64Apk `
        -FileName ([System.IO.Path]::GetFileName($AndroidX64Apk)) `
        -Kind 'apk'
    $provided++
}

if ($provided -eq 0) {
    throw '至少需要提供 Windows 安装器或一个 Android APK。'
}

$manifest = [ordered]@{
    schemaVersion = 1
    channel = $Channel
    version = $Version
    buildNumber = $BuildNumber
    publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    notes = $Notes
    assets = $assets
}

$json = $manifest | ConvertTo-Json -Depth 8
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $json, $utf8)

# 回读校验，避免生成客户端无法解析的清单。
$written = [System.IO.File]::ReadAllText($OutputPath, $utf8)
$parsed = $written | ConvertFrom-Json
if ($parsed.schemaVersion -ne 1 -or $parsed.version -ne $Version) {
    throw '生成的更新清单回读校验失败。'
}
if (@($parsed.assets.PSObject.Properties).Count -ne $provided) {
    throw '生成的更新清单平台条目数量不一致。'
}

Write-Host ''
Write-Host '更新清单已生成：' -ForegroundColor Green
Write-Host "  $OutputPath"
foreach ($entry in $assets.GetEnumerator()) {
    Write-Host ("  {0}: {1:N0} 字节  {2}" -f $entry.Key, $entry.Value['size'], $entry.Value['sha256'])
}
