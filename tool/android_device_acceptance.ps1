#requires -Version 7.2

[CmdletBinding()]
param(
    [string]$Serial,

    [string]$ApkPath = "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk",

    [string]$PackageName = "top.zonwe.simul_groove_player",

    [string]$ExpectedModelPattern = "K80|25060",

    [string[]]$ConfirmedCheck = @(),

    [string]$ConfirmationReference,

    [ValidatePattern("^[0-9A-Fa-f]{7,64}$")]
    [string]$BuildRevision,

    [switch]$SkipInstall,

    [switch]$RequireProductionSignature,

    [switch]$ListChecks,

    [string]$EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $repositoryRoot "build/acceptance/android"
}

$acceptanceChecks = [ordered]@{
    "permission-flow" = "分别拒绝和允许通知、媒体读取权限，确认应用给出可理解反馈"
    "folder-scan" = "授权一个真实音乐目录，确认扫描、封面、歌词与重扫结果"
    "device-scan" = "执行全设备扫描，确认重复曲目与损坏文件不会中断扫描"
    "scan-notification" = "确认扫描进度与完成通知在前后台均正常"
    "local-playback" = "播放真实本地音频并验证暂停、切歌、进度、循环、随机和队列"
    "media-controls" = "验证通知栏、锁屏、耳机或蓝牙媒体键与音频焦点"
    "account-sync" = "连接真实后端，验证登录恢复及歌单、喜欢、均衡器同步"
}

if ($ListChecks) {
    foreach ($entry in $acceptanceChecks.GetEnumerator()) {
        Write-Host "$($entry.Key): $($entry.Value)"
    }
    return
}

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-RepositoryPath {
    param(
        [string]$Path,
        [string]$Description
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $repositoryRoot $Path
    }
    Assert-Condition (Test-Path -LiteralPath $candidate -PathType Leaf) "$Description 不存在：$candidate"
    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
}

function Invoke-NativeCommand {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$Description
    )

    $output = @(& $Command @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$Description 失败。$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
    }
    return @($output | ForEach-Object { $_.ToString() })
}

function Invoke-Adb {
    param(
        [string[]]$Arguments,
        [string]$Description
    )

    $allArguments = @("-s", $script:deviceSerial) + $Arguments
    return Invoke-NativeCommand $script:adbCommand $allArguments $Description
}

function Get-DeviceProperty {
    param([string]$Name)

    return ((Invoke-Adb @("shell", "getprop", $Name) "读取设备属性 $Name") -join "").Trim()
}

$normalizedConfirmedChecks = @(
    $ConfirmedCheck |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ } |
        Select-Object -Unique
)
foreach ($check in $normalizedConfirmedChecks) {
    Assert-Condition $acceptanceChecks.Contains($check) "未知人工检查项：$check"
}

$resolvedApkPath = Resolve-RepositoryPath $ApkPath "ARM64 Release APK"
$apkHash = (Get-FileHash -LiteralPath $resolvedApkPath -Algorithm SHA256).Hash.ToUpperInvariant()
$apkSize = (Get-Item -LiteralPath $resolvedApkPath).Length

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolvedApkPath)
try {
$apkAbis = @(
    @(
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match "^lib/([^/]+)/.+\.so$") {
                $Matches[1]
            }
        }
    ) | Sort-Object -Unique
)
}
finally {
    $archive.Dispose()
}
Assert-Condition ($apkAbis.Count -eq 1 -and $apkAbis[0] -eq "arm64-v8a") "APK 必须且只能包含 arm64-v8a 原生库；实际为：$($apkAbis -join ', ')"

$apksigner = Get-Command apksigner -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $apksigner) "未找到 apksigner，请把 Android SDK build-tools 加入 PATH。"
$signatureOutput = Invoke-NativeCommand $apksigner.Source @(
    "verify",
    "--verbose",
    "--print-certs",
    $resolvedApkPath
) "APK 签名校验"
$signatureText = $signatureOutput -join [Environment]::NewLine
Assert-Condition ($signatureText -match "Verified using v2 scheme \(APK Signature Scheme v2\): true") "APK 未通过 v2 签名校验。"

$signerDn = if ($signatureText -match "Signer #1 certificate DN:\s*(.+)") {
    $Matches[1].Trim()
}
else {
    "unknown"
}
$signerSha256 = if ($signatureText -match "Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]+)") {
    $Matches[1].ToUpperInvariant()
}
else {
    "unknown"
}
$usesDebugCertificate = $signerDn -match "(?i)CN=Android Debug"
if ($RequireProductionSignature) {
    Assert-Condition (-not $usesDebugCertificate) "APK 仍使用 Android Debug 证书，不能作为正式发布签名验收。"
}

$adb = Get-Command adb -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $adb) "未找到 adb，请把 Android SDK platform-tools 加入 PATH。"
$script:adbCommand = $adb.Source
$deviceLines = Invoke-NativeCommand $script:adbCommand @("devices", "-l") "枚举 Android 设备"
$devices = @(
    foreach ($line in $deviceLines) {
        if ($line -match "^(\S+)\s+(device|offline|unauthorized)\b(.*)$") {
            [pscustomobject]@{
                serial = $Matches[1]
                state = $Matches[2]
                details = $Matches[3].Trim()
            }
        }
    }
)

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $readyDevices = @($devices | Where-Object { $_.state -eq "device" })
    Assert-Condition ($readyDevices.Count -eq 1) "请只连接一台已授权真机，或使用 -Serial 指定设备；当前可用设备数：$($readyDevices.Count)"
    $script:deviceSerial = $readyDevices[0].serial
}
else {
    $selectedDevice = @($devices | Where-Object { $_.serial -eq $Serial })
    Assert-Condition ($selectedDevice.Count -eq 1) "未找到序列号为 $Serial 的设备。"
    Assert-Condition ($selectedDevice[0].state -eq "device") "设备 $Serial 当前状态为 $($selectedDevice[0].state)，请先完成 USB 调试授权。"
    $script:deviceSerial = $Serial
}

$kernelQemu = Get-DeviceProperty "ro.kernel.qemu"
$bootQemu = Get-DeviceProperty "ro.boot.qemu"
Assert-Condition ($kernelQemu -ne "1" -and $bootQemu -ne "1") "该脚本只接受真实 Android 设备，当前目标被识别为模拟器。"

$manufacturer = Get-DeviceProperty "ro.product.manufacturer"
$model = Get-DeviceProperty "ro.product.model"
$deviceName = Get-DeviceProperty "ro.product.device"
$deviceAbi = Get-DeviceProperty "ro.product.cpu.abi"
$androidVersion = Get-DeviceProperty "ro.build.version.release"
$androidSdk = Get-DeviceProperty "ro.build.version.sdk"
Assert-Condition ($deviceAbi -eq "arm64-v8a") "目标设备主 ABI 不是 arm64-v8a：$deviceAbi"
if (-not [string]::IsNullOrWhiteSpace($ExpectedModelPattern)) {
    Assert-Condition ("$manufacturer $model $deviceName" -match $ExpectedModelPattern) "设备型号与 -ExpectedModelPattern 不匹配：$manufacturer $model ($deviceName)"
}

$installResult = @()
if (-not $SkipInstall) {
    $installResult = Invoke-Adb @("install", "-r", $resolvedApkPath) "安装 APK"
    Assert-Condition (($installResult -join [Environment]::NewLine) -match "(?m)^Success\s*$") "adb 未确认 APK 安装成功。"
}

$packagePath = (Invoke-Adb @("shell", "pm", "path", $PackageName) "确认应用安装") -join [Environment]::NewLine
Assert-Condition ($packagePath -match "(?m)^package:") "设备上未找到包 $PackageName。"
$baseApkMatch = [regex]::Match($packagePath, "(?m)^package:(.+/base\.apk)\s*$")
Assert-Condition $baseApkMatch.Success "未能从设备包信息定位已安装的 base.apk。"
$installedApkPath = $baseApkMatch.Groups[1].Value.Trim()
$installedHashOutput = (
    Invoke-Adb @("shell", "sha256sum", $installedApkPath) "校验设备上的 APK"
) -join [Environment]::NewLine
Assert-Condition ($installedHashOutput -match "(?i)^([0-9a-f]{64})\s+") "设备未返回有效的 APK SHA-256。"
$installedApkHash = $Matches[1].ToUpperInvariant()
Assert-Condition ($installedApkHash -eq $apkHash) "设备安装的 APK 与本次验收候选包不一致。"

$null = Invoke-Adb @("shell", "am", "force-stop", $PackageName) "停止旧应用进程"
$launchOutput = Invoke-Adb @(
    "shell",
    "am",
    "start",
    "-W",
    "-n",
    "$PackageName/.MainActivity"
) "启动应用"
$launchText = $launchOutput -join [Environment]::NewLine
Assert-Condition ($launchText -match "(?m)^Status:\s+ok\s*$") "应用启动未返回 Status: ok。"
Start-Sleep -Seconds 2
$processId = ((Invoke-Adb @("shell", "pidof", $PackageName) "确认应用进程") -join "").Trim()
Assert-Condition (-not [string]::IsNullOrWhiteSpace($processId)) "应用启动后没有存活进程。"

$packageDump = (Invoke-Adb @("shell", "dumpsys", "package", $PackageName) "读取已安装包信息") -join [Environment]::NewLine
$versionName = if ($packageDump -match "(?m)^\s*versionName=(.+)$") { $Matches[1].Trim() } else { "unknown" }
$versionCode = if ($packageDump -match "(?m)^\s*versionCode=(\d+)") { $Matches[1] } else { "unknown" }
$primaryCpuAbi = if ($packageDump -match "(?m)^\s*primaryCpuAbi=(.+)$") { $Matches[1].Trim() } else { "unknown" }
$serialHash = [Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes($script:deviceSerial)
)
$deviceEvidenceId = [Convert]::ToHexString($serialHash).Substring(0, 16)

$pendingChecks = @(
    $acceptanceChecks.Keys |
        Where-Object { $normalizedConfirmedChecks -notcontains $_ }
)
if ($pendingChecks.Count -eq 0) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($ConfirmationReference)) "全部人工检查完成后必须填写 -ConfirmationReference，记录设备回归批次或证据编号。"
}

$result = [ordered]@{
    schema_version = 1
    checked_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
    status = if ($pendingChecks.Count -eq 0) { "complete" } else { "manual_checks_pending" }
    confirmation_reference = $ConfirmationReference
    build_revision = $BuildRevision
    apk = [ordered]@{
        path = [IO.Path]::GetRelativePath($repositoryRoot, $resolvedApkPath)
        size_bytes = $apkSize
        sha256 = $apkHash
        abis = $apkAbis
        signer_dn = $signerDn
        signer_sha256 = $signerSha256
        uses_debug_certificate = $usesDebugCertificate
        production_signature_required = [bool]$RequireProductionSignature
    }
    device = [ordered]@{
        serial_fingerprint = $deviceEvidenceId
        manufacturer = $manufacturer
        model = $model
        device = $deviceName
        abi = $deviceAbi
        android_version = $androidVersion
        sdk = $androidSdk
        is_emulator = $false
    }
    installed_app = [ordered]@{
        package_name = $PackageName
        version_name = $versionName
        version_code = $versionCode
        primary_cpu_abi = $primaryCpuAbi
        apk_sha256 = $installedApkHash
        process_id = $processId
        install_skipped = [bool]$SkipInstall
        launch_status = "ok"
    }
    confirmed_checks = $normalizedConfirmedChecks
    pending_checks = $pendingChecks
}

$resolvedEvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$null = New-Item -ItemType Directory -Path $resolvedEvidenceDirectory -Force
$timestamp = [DateTimeOffset]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
$evidencePath = Join-Path $resolvedEvidenceDirectory "android-$deviceEvidenceId-$timestamp.json"
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8

Write-Host "设备：$manufacturer $model ($deviceName)，Android $androidVersion，ABI $deviceAbi"
Write-Host "APK：$apkSize 字节，SHA-256 $apkHash"
Write-Host "签名：$signerDn"
Write-Host "验收状态：$($result.status)"
Write-Host "证据文件：$evidencePath"
if ($pendingChecks.Count -gt 0) {
    Write-Host "仍需人工确认："
    foreach ($check in $pendingChecks) {
        Write-Host "  $check - $($acceptanceChecks[$check])"
    }
    Write-Host "完成后使用 -SkipInstall、全部 -ConfirmedCheck 和 -ConfirmationReference 再运行一次。"
}
