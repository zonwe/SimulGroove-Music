# 生成 Android 发布签名密钥，并打印可直接写入 GitHub Secrets 的 base64。
#
# 注意：keystore 与密码一旦丢失，已安装用户将无法通过应用内更新升级，
# 只能卸载后手动安装新包。请离线备份生成的文件和密码。
param(
    [string]$Alias = 'simulgroove',
    [string]$OutputPath = '',
    [Parameter(Mandatory = $true)]
    [string]$StorePassword,
    [Parameter(Mandatory = $true)]
    [string]$KeyPassword,
    [int]$ValidityDays = 10000
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'android\app\simulgroove-release.jks'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytool) {
    $javaHome = $env:JAVA_HOME
    if ($javaHome) {
        $candidate = Join-Path $javaHome 'bin\keytool.exe'
        if (Test-Path -LiteralPath $candidate) {
            $keytool = Get-Command $candidate
        }
    }
}
if ($null -eq $keytool) {
    throw '未找到 keytool。请安装 JDK 17（Android Studio 自带 JBR 也可）并加入 PATH。'
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "目标密钥已存在，拒绝覆盖：$OutputPath"
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

if ($KeyPassword -ne $StorePassword) {
    Write-Warning 'PKCS12 密钥库要求 key 密码与 store 密码相同；请把两个密码设为一致。'
}

& $keytool.Source `
    -genkeypair `
    -storetype PKCS12 `
    -keystore $OutputPath `
    -alias $Alias `
    -keyalg RSA `
    -keysize 4096 `
    -validity $ValidityDays `
    -storepass $StorePassword `
    -keypass $KeyPassword `
    -dname 'CN=SimulGroove Music, OU=Personal, O=top.zonwe, L=Unknown, ST=Unknown, C=CN'
if ($LASTEXITCODE -ne 0) {
    throw "keytool 失败，退出码: $LASTEXITCODE"
}

$base64 = [Convert]::ToBase64String(
    [System.IO.File]::ReadAllBytes($OutputPath)
)
Write-Host ''
Write-Host '已生成发布密钥：' -ForegroundColor Green
Write-Host "  $OutputPath"
Write-Host ''
Write-Host 'GitHub Secrets 需要配置：' -ForegroundColor Cyan
Write-Host '  ANDROID_KEYSTORE_BASE64 = 下方 base64'
Write-Host "  ANDROID_KEY_ALIAS       = $Alias"
Write-Host '  ANDROID_KEY_PASSWORD    = 你输入的 keyPassword'
Write-Host '  ANDROID_STORE_PASSWORD  = 你输入的 storePassword'
Write-Host ''
Write-Host $base64
Write-Host ''
Write-Host '同时创建 android/key.properties（已被 git 忽略）：' -ForegroundColor Cyan
Write-Host "storePassword=$StorePassword"
Write-Host "keyPassword=$KeyPassword"
Write-Host "keyAlias=$Alias"
Write-Host "storeFile=$OutputPath"
