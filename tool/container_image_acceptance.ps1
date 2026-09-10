#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$")]
    [string]$ContainerId,

    [Parameter(Mandatory)]
    [ValidatePattern("^sha256:[0-9A-Fa-f]{64}$")]
    [string]$ApprovedDigest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$normalizedApprovedDigest = $ApprovedDigest.ToLowerInvariant()
Assert-Condition ($normalizedApprovedDigest -notmatch "^sha256:0+$") "批准镜像摘要不能是全零占位值。"

$docker = Get-Command docker -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $docker) "未找到 Docker CLI。"
$inspectArguments = @(
    "inspect",
    "--type", "container",
    "--format", "{{.Image}}",
    $ContainerId
)
$output = @(& $docker.Source @inspectArguments 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "无法读取目标容器镜像。$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
}

$actualDigest = ($output -join "").Trim().ToLowerInvariant()
Assert-Condition ($actualDigest -match "^sha256:[0-9a-f]{64}$") "Docker 返回的容器镜像 ID 无效。"
Assert-Condition ($actualDigest -eq $normalizedApprovedDigest) "当前容器镜像与批准镜像摘要不一致。"

$containerHash = [Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes($ContainerId)
)

[pscustomobject]@{
    container_fingerprint = [Convert]::ToHexString($containerHash).Substring(0, 16)
    image_digest = $actualDigest
    approved_digest = $normalizedApprovedDigest
    matches = $true
}
