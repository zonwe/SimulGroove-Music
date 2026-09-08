#requires -Version 7.2

function Find-ProductionAcceptanceEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EvidenceDirectory,

        [Parameter(Mandatory)]
        [string]$RequiredStatus,

        [string]$RequiredScenario,

        [string]$RequiredTestId,

        [Parameter(Mandatory)]
        [string]$RequiredBaseUrl,

        [Parameter(Mandatory)]
        [string]$RequiredBuildRevision,

        [switch]$MatchDeployment,

        [bool]$RequiredOnlineMusicEnabled,

        [string[]]$RequiredConfiguredSources = @(),

        [string[]]$RequiredApprovedSources = @(),

        [string]$RequiredSidecarImageDigest,

        [ValidateRange(1, 30)]
        [int]$MaximumAgeDays = 7,

        [ValidateRange(0, 60)]
        [int]$MaximumFutureMinutes = 5,

        [DateTimeOffset]$CheckedAtNotAfterUtc = [DateTimeOffset]::MaxValue
    )

    Set-StrictMode -Version Latest

    if (-not (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)) {
        return $null
    }

    function ConvertTo-NormalizedSet {
        param([object[]]$Values)

        return @(
            $Values |
                ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
    }

    $now = [DateTimeOffset]::UtcNow
    $minimumTimestamp = $now.AddDays(-$MaximumAgeDays)
    $maximumTimestamp = $now.AddMinutes($MaximumFutureMinutes)
    if ($CheckedAtNotAfterUtc -lt $maximumTimestamp) {
        $maximumTimestamp = $CheckedAtNotAfterUtc
    }
    $expectedConfiguredSources = ConvertTo-NormalizedSet $RequiredConfiguredSources
    $expectedApprovedSources = ConvertTo-NormalizedSet $RequiredApprovedSources
    $expectedDigest = $RequiredSidecarImageDigest.Trim().ToLowerInvariant()

    foreach ($file in Get-ChildItem -LiteralPath $EvidenceDirectory -Filter "production-*.json" -File |
        Sort-Object LastWriteTimeUtc -Descending) {
        try {
            $payload = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $checkedAt = [DateTimeOffset]::MinValue
            if ($payload.schema_version -ne 2 -or
                $payload.status -ne $RequiredStatus -or
                $payload.base_url -ne $RequiredBaseUrl -or
                $payload.build_revision -ne $RequiredBuildRevision -or
                -not [DateTimeOffset]::TryParse([string]$payload.checked_at_utc, [ref]$checkedAt) -or
                $checkedAt -lt $minimumTimestamp -or
                $checkedAt -gt $maximumTimestamp) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($RequiredScenario) -and
                $payload.alert_test.scenario -ne $RequiredScenario) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($RequiredTestId) -and
                $payload.alert_test.test_id -ne $RequiredTestId) {
                continue
            }
            if ($MatchDeployment) {
                if ([bool]$payload.online_music_enabled -ne $RequiredOnlineMusicEnabled) {
                    continue
                }
                $actualConfiguredSources = ConvertTo-NormalizedSet @($payload.configured_sources)
                $actualApprovedSources = ConvertTo-NormalizedSet @($payload.approved_sources)
                if (($actualConfiguredSources -join [char]0) -ne
                    ($expectedConfiguredSources -join [char]0) -or
                    ($actualApprovedSources -join [char]0) -ne
                    ($expectedApprovedSources -join [char]0)) {
                    continue
                }
                if ($RequiredOnlineMusicEnabled) {
                    $actualDigest = ([string]$payload.sidecar_image.image_digest).Trim().ToLowerInvariant()
                    if ([string]::IsNullOrWhiteSpace($expectedDigest) -or
                        $actualDigest -ne $expectedDigest) {
                        continue
                    }
                }
            }
            return [pscustomobject]@{
                path = $file.FullName
                payload = $payload
            }
        }
        catch {
            Write-Warning "忽略无法解析或字段不完整的旧生产验收证据：$($file.FullName)"
        }
    }
    return $null
}
