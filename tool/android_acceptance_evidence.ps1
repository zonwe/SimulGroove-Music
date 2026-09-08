#requires -Version 7.2

function Find-AndroidPreflightEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EvidenceDirectory,

        [Parameter(Mandatory)]
        [string]$DeviceEvidenceId,

        [Parameter(Mandatory)]
        [string]$RequiredBuildRevision,

        [Parameter(Mandatory)]
        [string]$RequiredApkHash,

        [ValidateRange(1, 30)]
        [int]$MaximumAgeDays = 7
    )

    Set-StrictMode -Version Latest

    if (-not (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)) {
        return $null
    }

    $minimumTimestamp = [DateTimeOffset]::UtcNow.AddDays(-$MaximumAgeDays)
    foreach ($file in Get-ChildItem -LiteralPath $EvidenceDirectory -Filter "android-$DeviceEvidenceId-*.json" -File |
        Sort-Object LastWriteTimeUtc -Descending) {
        try {
            $payload = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($payload.schema_version -ne 2 -or
                $payload.status -ne "manual_checks_pending" -or
                $payload.build_revision -ne $RequiredBuildRevision -or
                $payload.apk.sha256 -ne $RequiredApkHash -or
                $payload.installed_app.apk_sha256 -ne $RequiredApkHash -or
                [bool]$payload.installed_app.install_skipped -or
                $payload.device.serial_fingerprint -ne $DeviceEvidenceId -or
                [DateTimeOffset]::Parse($payload.checked_at_utc) -lt $minimumTimestamp) {
                continue
            }
            return [pscustomobject]@{
                path = $file.FullName
                payload = $payload
            }
        }
        catch {
            Write-Warning "忽略无法解析的旧 Android 验收证据：$($file.FullName)"
        }
    }
    return $null
}
