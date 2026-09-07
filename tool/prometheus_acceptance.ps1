#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern("^[A-Za-z0-9_.-]{1,128}$")]
    [string]$DockerNetwork,

    [uri]$PrometheusUrl = "http://prometheus:9090",

    [switch]$RequireOnlineMusicSeries,

    [ValidateRange(1, 30)]
    [int]$LookbackDays = 7,

    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 60
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

Assert-Condition ($PrometheusUrl.Scheme -in @("http", "https")) "PrometheusUrl 必须使用 HTTP 或 HTTPS。"
Assert-Condition ([string]::IsNullOrEmpty($PrometheusUrl.UserInfo)) "PrometheusUrl 不得包含用户名或密码。"
Assert-Condition (
    ($PrometheusUrl.AbsolutePath -eq "/" -or [string]::IsNullOrEmpty($PrometheusUrl.AbsolutePath)) -and
    [string]::IsNullOrEmpty($PrometheusUrl.Query) -and
    [string]::IsNullOrEmpty($PrometheusUrl.Fragment)
) "PrometheusUrl 只能包含协议、主机和可选端口。"

$docker = Get-Command docker -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $docker) "未找到 Docker CLI。"
$dockerCommand = $docker.Source

function Invoke-Docker {
    param([string[]]$Arguments)

    $output = @(& $dockerCommand @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Docker 命令失败：docker $($Arguments -join ' ')$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
    }
    return @($output | ForEach-Object { $_.ToString() })
}

$null = Invoke-Docker @("pull", "curlimages/curl:8.14.1")

function Invoke-PrometheusGet {
    param(
        [string]$Path,
        [string[]]$QueryArguments
    )

    $url = [uri]::new($PrometheusUrl, $Path).AbsoluteUri
    $dockerArguments = @(
        "run", "--rm",
        "--network", $DockerNetwork,
        "--read-only",
        "--cap-drop", "ALL",
        "curlimages/curl:8.14.1",
        "--fail-with-body",
        "--silent",
        "--show-error",
        "--get"
    ) + $QueryArguments + @($url)
    $json = (Invoke-Docker $dockerArguments) -join [Environment]::NewLine
    try {
        $payload = $json | ConvertFrom-Json
    }
    catch {
        throw "Prometheus API 未返回有效 JSON。"
    }
    Assert-Condition ($payload.status -eq "success") "Prometheus API 返回失败状态。"
    return $payload
}

function Get-CollectorTargetState {
    $payload = Invoke-PrometheusGet "/api/v1/query" @(
        "--data-urlencode",
        'query=up{job="simulgroove-otel-collector"}'
    )
    $results = @($payload.data.result)
    return $results.Count -gt 0 -and @(
        $results |
            Where-Object {
                $_.value.Count -ge 2 -and
                [double]$_.value[1] -eq 1
            }
    ).Count -gt 0
}

function Get-MetricSeries {
    param(
        [string]$MetricName,
        [DateTimeOffset]$Start,
        [DateTimeOffset]$End
    )

    $payload = Invoke-PrometheusGet "/api/v1/series" @(
        "--data-urlencode",
        "match[]=$MetricName",
        "--data-urlencode",
        "start=$($Start.ToUnixTimeSeconds())",
        "--data-urlencode",
        "end=$($End.ToUnixTimeSeconds())"
    )
    return @($payload.data)
}

$metricNames = @(
    "flutter_music_online_music_sidecar_requests_total",
    "flutter_music_online_music_sidecar_failures_total",
    "flutter_music_online_music_sidecar_circuit_rejections_total"
)
$deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
$targetUp = $false
$seriesByMetric = @{}
$lastError = $null

do {
    try {
        $targetUp = Get-CollectorTargetState
        $now = [DateTimeOffset]::UtcNow
        $start = $now.AddDays(-$LookbackDays)
        foreach ($metricName in $metricNames) {
            $seriesByMetric[$metricName] = @(Get-MetricSeries $metricName $start $now)
        }
        $lastError = $null
    }
    catch {
        $lastError = $_.Exception.Message
        $targetUp = $false
    }

    $hasRequiredSeries = -not $RequireOnlineMusicSeries -or @(
        $metricNames |
            Where-Object { @($seriesByMetric[$_]).Count -eq 0 }
    ).Count -eq 0
    if ($targetUp -and $hasRequiredSeries) {
        break
    }
    Start-Sleep -Seconds 2
} while ([DateTimeOffset]::UtcNow -lt $deadline)

if (-not $targetUp) {
    $detail = if ([string]::IsNullOrWhiteSpace($lastError)) { "" } else { " 最后错误：$lastError" }
    throw "Prometheus 未显示 simulgroove-otel-collector 抓取目标在线。$detail"
}

$forbiddenLabelPattern = "(?i)(^|[._])(query|keyword|source|track|media|account|user(name)?|token|cookie|password|secret|stream(ref)?|url|uri)([._]|$)"
$metricEvidence = @()
foreach ($metricName in $metricNames) {
    $series = @($seriesByMetric[$metricName])
    if ($RequireOnlineMusicSeries) {
        Assert-Condition ($series.Count -gt 0) "Prometheus 最近 $LookbackDays 天内没有指标：$metricName"
    }
    $labelNames = @(
        $series |
            ForEach-Object { $_.PSObject.Properties.Name } |
            Sort-Object -Unique
    )
    $forbiddenLabels = @(
        $labelNames |
            Where-Object { $_ -ne "__name__" -and $_ -match $forbiddenLabelPattern }
    )
    Assert-Condition ($forbiddenLabels.Count -eq 0) "指标 $metricName 包含禁止标签：$($forbiddenLabels -join ', ')"
    foreach ($seriesEntry in $series) {
        foreach ($property in $seriesEntry.PSObject.Properties) {
            $value = [string]$property.Value
            Assert-Condition ($value.Length -le 256) "指标 $metricName 的标签值过长。"
            Assert-Condition ($value -notmatch "[\r\n]") "指标 $metricName 的标签值包含换行。"
        }
    }
    $metricEvidence += [pscustomobject]@{
        name = $metricName
        series_count = $series.Count
        label_names = $labelNames
    }
}

[pscustomobject]@{
    target_job = "simulgroove-otel-collector"
    target_up = $targetUp
    lookback_days = $LookbackDays
    online_music_series_required = [bool]$RequireOnlineMusicSeries
    metrics = $metricEvidence
}
