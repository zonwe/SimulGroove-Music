#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [uri]$BaseUrl,

    [string]$EnvironmentFile = ".env",

    [ValidateRange(1, 365)]
    [int]$MinimumCertificateDays = 14,

    [ValidateSet("None", "Fire", "Resolve", "Finalize")]
    [string]$AlertAction = "None",

    [ValidateSet("FailureWarning", "FailureCritical", "CircuitBreaker")]
    [string]$AlertScenario,

    [ValidatePattern("^[A-Za-z0-9._-]{1,64}$")]
    [string]$AlertTestId,

    [uri]$RunbookUrl,

    [string]$NotificationReceiptReference,

    [ValidatePattern("^(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{64})$")]
    [string]$BuildRevision,

    [string[]]$ApprovedSourceId = @(),

    [string]$SourceApprovalEvidencePath,

    [switch]$ConfigurationOnly,

    [string]$EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$acceptanceStartedAt = [DateTimeOffset]::UtcNow

. (Join-Path $PSScriptRoot "production_acceptance_evidence.ps1")

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$composeFile = Join-Path $repositoryRoot "compose.online-music.production.yml"
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $repositoryRoot "build/acceptance/production"
}
$resolvedEvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$alertScenarios = [ordered]@{
    FailureWarning = [ordered]@{
        alertname = "SimulGrooveOnlineMusicSidecarFailureRatioHigh"
        severity = "warning"
        summary = "Online music sidecar failure ratio is high"
    }
    FailureCritical = [ordered]@{
        alertname = "SimulGrooveOnlineMusicSidecarFailureRatioCritical"
        severity = "critical"
        summary = "Online music sidecar failure ratio is critical"
    }
    CircuitBreaker = [ordered]@{
        alertname = "SimulGrooveOnlineMusicCircuitRejectingRequests"
        severity = "critical"
        summary = "Online music circuit breaker is rejecting requests"
    }
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

function Resolve-RequiredPath {
    param(
        [string]$Path,
        [string]$BaseDirectory,
        [string]$Description
    )

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Path)) "$Description 未配置。"
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $BaseDirectory $Path
    }
    Assert-Condition (Test-Path -LiteralPath $candidate -PathType Leaf) "$Description 不存在：$candidate"
    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
}

function Test-IsInsideRepository {
    param([string]$Path)

    $relative = [IO.Path]::GetRelativePath($repositoryRoot, [IO.Path]::GetFullPath($Path))
    return -not [IO.Path]::IsPathRooted($relative) -and
        $relative -ne ".." -and
        -not $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")
}

function Read-DotEnv {
    param([string]$Path)

    $values = @{}
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            continue
        }

        $separator = $line.IndexOf("=")
        Assert-Condition ($separator -gt 0) "环境文件包含无效行，请使用 KEY=VALUE：$rawLine"
        $key = $line.Substring(0, $separator).Trim()
        Assert-Condition ($key -match "^[A-Za-z_][A-Za-z0-9_]*$") "环境变量名无效：$key"
        $value = $line.Substring($separator + 1).Trim()
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        $values[$key] = $value
    }
    return $values
}

function Get-RequiredEnvironmentValue {
    param(
        [hashtable]$Values,
        [string]$Name
    )

    Assert-Condition ($Values.ContainsKey($Name)) "环境文件缺少 $Name。"
    $value = [string]$Values[$Name]
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($value)) "环境文件中的 $Name 不能为空。"
    return $value
}

function Assert-NotPlaceholder {
    param(
        [string]$Value,
        [string]$Name
    )

    $placeholderPattern = "(?i)(example\.(com|net|org)|\.example(?:$|[/:])|\.invalid(?:$|[/:])|\.test(?:$|[/:])|localhost|your[-_. ]?domain|replace[-_ ]|change[-_ ]?me|ci-only|placeholder)"
    Assert-Condition ($Value -notmatch $placeholderPattern) "$Name 仍是示例或占位值。"
}

function Get-RequiredJsonString {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )

    $property = $Object.PSObject.Properties[$Name]
    Assert-Condition ($null -ne $property) "$Context 缺少 $Name。"
    $value = [string]$property.Value
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($value)) "$Context 的 $Name 不能为空。"
    return $value.Trim()
}

function Get-RequiredJsonArray {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )

    $property = $Object.PSObject.Properties[$Name]
    Assert-Condition ($null -ne $property) "$Context 缺少 $Name。"
    $values = @($property.Value)
    Assert-Condition ($values.Count -gt 0) "$Context 的 $Name 不能为空。"
    return $values
}

function Assert-NoSensitiveJsonFields {
    param(
        [object]$Value,
        [string]$Path = "approval"
    )

    if ($null -eq $Value -or $Value -is [string]) {
        return
    }
    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            Assert-Condition (
                $property.Name -notmatch "(?i)(password|token|cookie|secret|credential|authorization|private[_-]?key)"
            ) "来源审批证据不得包含敏感字段：$Path.$($property.Name)"
            Assert-NoSensitiveJsonFields $property.Value "$Path.$($property.Name)"
        }
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            Assert-Condition (
                ([string]$key) -notmatch "(?i)(password|token|cookie|secret|credential|authorization|private[_-]?key)"
            ) "来源审批证据不得包含敏感字段：$Path.$key"
            Assert-NoSensitiveJsonFields $Value[$key] "$Path.$key"
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $Value) {
            Assert-NoSensitiveJsonFields $item "$Path[$index]"
            $index++
        }
        return
    }
}

function Assert-HttpsUrl {
    param(
        [string]$Value,
        [string]$Description
    )

    $parsedUri = $null
    Assert-Condition (
        [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$parsedUri) -and
        $parsedUri.Scheme -eq "https"
    ) "$Description 必须是绝对 HTTPS URL。"
    Assert-NotPlaceholder $parsedUri.AbsoluteUri $Description
}

function Invoke-Docker {
    param(
        [string[]]$Arguments,
        [switch]$Capture
    )

    $output = @(& $script:dockerCommand @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Docker 命令失败：docker $($Arguments -join ' ')$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
    }
    if ($Capture) {
        return @($output | ForEach-Object { $_.ToString() })
    }
    foreach ($line in $output) {
        Write-Host $line
    }
}

function Get-ResponseHeader {
    param(
        [System.Net.Http.HttpResponseMessage]$Response,
        [string]$Name
    )

    $values = $null
    if ($Response.Headers.TryGetValues($Name, [ref]$values)) {
        return ($values -join ",")
    }
    if ($Response.Content.Headers.TryGetValues($Name, [ref]$values)) {
        return ($values -join ",")
    }
    return $null
}

$environmentPath = Resolve-RequiredPath $EnvironmentFile $repositoryRoot "生产环境文件"
$environmentDirectory = Split-Path -Parent $environmentPath
$environment = Read-DotEnv $environmentPath
$controlledEnvironmentPattern = "^(MUSIC_|ONLINE_MUSIC_|ACME_EMAIL$|ALERTMANAGER_CONFIG_PATH$|PROMETHEUS_RETENTION$)"
foreach ($entry in Get-ChildItem Env:) {
    if ($entry.Name -match $controlledEnvironmentPattern -and -not $environment.ContainsKey($entry.Name)) {
        [Environment]::SetEnvironmentVariable($entry.Name, $null, "Process")
    }
}
foreach ($entry in $environment.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable([string]$entry.Key, [string]$entry.Value, "Process")
}

Assert-Condition ($BaseUrl.Scheme -eq "https") "BaseUrl 必须使用 HTTPS。"
Assert-Condition (
    ($BaseUrl.AbsolutePath -eq "/" -or [string]::IsNullOrEmpty($BaseUrl.AbsolutePath)) -and
    [string]::IsNullOrEmpty($BaseUrl.Query) -and
    [string]::IsNullOrEmpty($BaseUrl.Fragment)
) "BaseUrl 只能包含协议、域名和可选端口。"

$domain = Get-RequiredEnvironmentValue $environment "MUSIC_DOMAIN"
$acmeEmail = Get-RequiredEnvironmentValue $environment "ACME_EMAIL"
$jwtKey = Get-RequiredEnvironmentValue $environment "MUSIC_API_JWT_KEY"
$adminPassword = Get-RequiredEnvironmentValue $environment "MUSIC_API_ADMIN_PASSWORD"
$alertmanagerConfigValue = Get-RequiredEnvironmentValue $environment "ALERTMANAGER_CONFIG_PATH"

Assert-NotPlaceholder $domain "MUSIC_DOMAIN"
Assert-NotPlaceholder $acmeEmail "ACME_EMAIL"
Assert-NotPlaceholder $jwtKey "MUSIC_API_JWT_KEY"
Assert-NotPlaceholder $adminPassword "MUSIC_API_ADMIN_PASSWORD"
Assert-Condition ($BaseUrl.DnsSafeHost -eq $domain) "BaseUrl 域名与 MUSIC_DOMAIN 不一致。"
$parsedAddress = $null
Assert-Condition (-not [Net.IPAddress]::TryParse($domain, [ref]$parsedAddress)) "MUSIC_DOMAIN 必须是真实域名，不能是 IP 地址。"
Assert-Condition ($jwtKey.Length -ge 32) "MUSIC_API_JWT_KEY 至少需要 32 个字符。"
Assert-Condition ($adminPassword.Length -ge 16) "MUSIC_API_ADMIN_PASSWORD 至少需要 16 个字符。"

$alertmanagerConfigPath = Resolve-RequiredPath $alertmanagerConfigValue $environmentDirectory "Alertmanager 配置"
Assert-Condition (-not (Test-IsInsideRepository $alertmanagerConfigPath)) "真实 Alertmanager 配置必须位于仓库外。"
$alertmanagerConfig = Get-Content -LiteralPath $alertmanagerConfigPath -Raw
Assert-Condition (
    $alertmanagerConfig -notmatch "(?i)(replace-before-production|example\.(com|net|org|invalid)|replace-with|change[-_ ]?me|placeholder)"
) "Alertmanager 配置仍包含示例通知接收方。"
Assert-Condition (
    $alertmanagerConfig -match "(?m)^\s+[a-zA-Z0-9_]+_configs\s*:"
) "Alertmanager 配置没有实际通知集成。"

$onlineMusicEnabled = if ($environment.ContainsKey("ONLINE_MUSIC_ENABLED")) {
    [string]$environment["ONLINE_MUSIC_ENABLED"] -eq "true"
}
else {
    $false
}
$configuredSources = @(
    $environment.Keys |
        Where-Object { $_ -match "^ONLINE_MUSIC_SOURCE_[0-9]+$" } |
        Sort-Object |
        ForEach-Object { ([string]$environment[$_]).Trim().ToLowerInvariant() } |
        Where-Object { $_ } |
        Select-Object -Unique
)
$approvedSources = @(
    $ApprovedSourceId |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ } |
        Select-Object -Unique
)
$sourceEvidencePath = $null
$sourceApprovalSummary = $null
$approvedImageDigests = @()

if ($onlineMusicEnabled) {
    Assert-Condition ($configuredSources.Count -gt 0) "在线音乐启用时至少需要一个已批准来源。"
    Assert-Condition ($approvedSources.Count -gt 0) "在线音乐启用时必须通过 -ApprovedSourceId 显式确认批准来源。"
    $sourceDifference = @(Compare-Object $configuredSources $approvedSources)
    Assert-Condition ($sourceDifference.Count -eq 0) "生产白名单与 -ApprovedSourceId 不完全一致。"
    $sourceEvidencePath = Resolve-RequiredPath $SourceApprovalEvidencePath $environmentDirectory "来源审批证据"
    Assert-Condition (-not (Test-IsInsideRepository $sourceEvidencePath)) "来源审批证据必须位于仓库外的受控证据库。"
    Assert-Condition ([IO.Path]::GetExtension($sourceEvidencePath) -eq ".json") "来源审批证据必须使用 JSON 格式。"
    try {
        $sourceApproval = Get-Content -LiteralPath $sourceEvidencePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "来源审批证据不是有效 JSON：$($_.Exception.Message)"
    }
    Assert-NoSensitiveJsonFields $sourceApproval
    $schemaVersionProperty = $sourceApproval.PSObject.Properties["schema_version"]
    Assert-Condition (
        $null -ne $schemaVersionProperty -and [int]$schemaVersionProperty.Value -eq 1
    ) "来源审批证据 schema_version 必须为 1。"
    $changeTicket = Get-RequiredJsonString $sourceApproval "change_ticket" "来源审批证据"
    Assert-NotPlaceholder $changeTicket "来源审批证据 change_ticket"
    $approvalRecords = @(Get-RequiredJsonArray $sourceApproval "sources" "来源审批证据")
    $approvalSourceIds = @(
        $approvalRecords |
            ForEach-Object {
                $approvalSourceId = (Get-RequiredJsonString $_ "source_id" "来源审批记录").ToLowerInvariant()
                Assert-Condition ($approvalSourceId -match "^[a-z0-9][a-z0-9._-]{0,63}$") "来源审批记录的 source_id 格式无效。"
                Assert-NotPlaceholder $approvalSourceId "来源审批记录 source_id"
                $approvalSourceId
            } |
            Select-Object -Unique
    )
    Assert-Condition ($approvalSourceIds.Count -eq $approvalRecords.Count) "来源审批 JSON 包含重复 source_id。"
    $sourceDifference = @(Compare-Object $approvedSources $approvalSourceIds)
    Assert-Condition ($sourceDifference.Count -eq 0) "来源审批 JSON 与 -ApprovedSourceId 不完全一致。"

    $requiredCapabilities = @(
        "search",
        "metadata",
        "cover",
        "lyrics",
        "playback",
        "range",
        "download"
    )
    $approvalExpirySummary = @()
    foreach ($record in $approvalRecords) {
        $sourceId = (Get-RequiredJsonString $record "source_id" "来源审批记录").ToLowerInvariant()
        $context = "来源 $sourceId 的审批记录"
        Assert-Condition ((Get-RequiredJsonString $record "decision" $context) -eq "approved") "$context 的 decision 必须为 approved。"

        $effectiveAtText = Get-RequiredJsonString $record "effective_at_utc" $context
        $expiresAtText = Get-RequiredJsonString $record "expires_at_utc" $context
        $effectiveAt = [DateTimeOffset]::MinValue
        $expiresAt = [DateTimeOffset]::MinValue
        Assert-Condition ([DateTimeOffset]::TryParse($effectiveAtText, [ref]$effectiveAt)) "$context 的 effective_at_utc 无效。"
        Assert-Condition ([DateTimeOffset]::TryParse($expiresAtText, [ref]$expiresAt)) "$context 的 expires_at_utc 无效。"
        Assert-Condition ($effectiveAt -le [DateTimeOffset]::UtcNow) "$context 尚未生效。"
        Assert-Condition ($expiresAt -gt [DateTimeOffset]::UtcNow) "$context 已过期。"
        Assert-Condition ($expiresAt -gt $effectiveAt) "$context 的有效期顺序无效。"

        $regions = @(Get-RequiredJsonArray $record "regions" $context)
        foreach ($region in $regions) {
            Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$region)) "$context 包含空地区。"
            Assert-NotPlaceholder ([string]$region) "$context 的 regions"
        }
        $allowedCapabilities = @(
            Get-RequiredJsonArray $record "allowed_capabilities" $context |
                ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
                Select-Object -Unique
        )
        foreach ($capability in $requiredCapabilities) {
            Assert-Condition ($allowedCapabilities -contains $capability) "$context 未批准当前产品会暴露的能力：$capability"
        }

        $policyUrls = @(Get-RequiredJsonArray $record "policy_urls" $context)
        Assert-Condition ($policyUrls.Count -ge 3) "$context 至少需要三条官方条款、版权或隐私政策链接。"
        foreach ($policyUrl in $policyUrls) {
            Assert-HttpsUrl ([string]$policyUrl) "$context 的 policy_urls"
        }
        $accessMethod = Get-RequiredJsonString $record "access_method" $context
        Assert-NotPlaceholder $accessMethod "$context 的 access_method"
        foreach ($approverField in @("business_approver", "security_approver", "compliance_approver")) {
            $approver = Get-RequiredJsonString $record $approverField $context
            Assert-NotPlaceholder $approver "$context 的 $approverField"
        }

        $upstreamCommit = Get-RequiredJsonString $record "upstream_commit" $context
        $forkCommit = Get-RequiredJsonString $record "fork_commit" $context
        Assert-Condition ($upstreamCommit -match "^[0-9a-fA-F]{7,64}$" -and $upstreamCommit -notmatch "^0+$") "$context 的 upstream_commit 无效。"
        Assert-Condition ($forkCommit -match "^[0-9a-fA-F]{7,64}$" -and $forkCommit -notmatch "^0+$") "$context 的 fork_commit 无效。"
        $imageDigest = Get-RequiredJsonString $record "image_digest" $context
        Assert-Condition ($imageDigest -match "^sha256:[0-9a-fA-F]{64}$" -and $imageDigest -notmatch "^sha256:0+$") "$context 的 image_digest 无效。"
        $normalizedImageDigest = $imageDigest.ToLowerInvariant()
        $approvedImageDigests += $normalizedImageDigest
        $correspondingSourceUrl = Get-RequiredJsonString $record "corresponding_source_url" $context
        Assert-HttpsUrl $correspondingSourceUrl "$context 的 corresponding_source_url"

        $approvalExpirySummary += [ordered]@{
            source_id = $sourceId
            expires_at_utc = $expiresAt.ToUniversalTime().ToString("O")
            image_digest = $normalizedImageDigest
        }
    }
    $sourceApprovalSummary = [ordered]@{
        change_ticket = $changeTicket
        sources = $approvalExpirySummary
    }
    $approvedImageDigests = @($approvedImageDigests | Select-Object -Unique)
    Assert-Condition ($approvedImageDigests.Count -eq 1) "所有批准来源必须绑定同一个生产 sidecar 镜像摘要。"
}
elseif ($configuredSources.Count -gt 0) {
    Write-Warning "在线音乐当前关闭，但环境文件已填写来源；启用前仍必须提供逐来源审批证据。"
}

$docker = Get-Command docker -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $docker) "未找到 Docker CLI。"
$script:dockerCommand = $docker.Source
$alertmanagerMount = "$($alertmanagerConfigPath):/etc/alertmanager/alertmanager.yml:ro"
$null = Invoke-Docker -Arguments @(
    "run", "--rm",
    "--volume", $alertmanagerMount,
    "--entrypoint", "/bin/amtool",
    "prom/alertmanager:v0.34.0",
    "check-config", "/etc/alertmanager/alertmanager.yml"
) -Capture
$composeArguments = @(
    "compose",
    "--env-file", $environmentPath,
    "-f", $composeFile
)

$null = Invoke-Docker -Arguments ($composeArguments + @("config", "--quiet")) -Capture
$composeJson = (Invoke-Docker -Arguments ($composeArguments + @("config", "--format", "json")) -Capture) -join [Environment]::NewLine
$composeConfiguration = $composeJson | ConvertFrom-Json
$observabilityNetworkConfiguration = $composeConfiguration.networks."observability-private"
$networkNameProperty = $observabilityNetworkConfiguration.PSObject.Properties["name"]
$observabilityNetwork = if ($null -ne $networkNameProperty) {
    [string]$networkNameProperty.Value
}
else {
    ""
}
if ([string]::IsNullOrWhiteSpace($observabilityNetwork)) {
    $observabilityNetwork = "$($composeConfiguration.name)_observability-private"
}

$normalizedBuildRevision = if ([string]::IsNullOrWhiteSpace($BuildRevision)) {
    $null
}
else {
    $BuildRevision.ToLowerInvariant()
}
if ($null -ne $normalizedBuildRevision) {
    Assert-Condition ($normalizedBuildRevision -notmatch "^0+$") "BuildRevision 不能为全零提交。"
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $gitCommand) "提供 BuildRevision 时必须能够调用 git。"
    $revisionOutput = @(
        & $gitCommand.Source -C $repositoryRoot rev-parse HEAD 2>&1
    )
    Assert-Condition ($LASTEXITCODE -eq 0) "无法读取当前仓库提交。"
    $repositoryRevision = ($revisionOutput -join "").Trim().ToLowerInvariant()
    Assert-Condition (
        $repositoryRevision -eq $normalizedBuildRevision
    ) "BuildRevision 与当前检出提交不一致。"
}
if ($AlertAction -in @("Fire", "Resolve", "Finalize")) {
    Assert-Condition ($null -ne $normalizedBuildRevision) "$AlertAction 阶段必须提供 -BuildRevision，以绑定同一仓库提交的证据链。"
}

$result = [ordered]@{
    schema_version = 2
    checked_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
    status = "configuration_valid"
    build_revision = $normalizedBuildRevision
    base_url = $BaseUrl.AbsoluteUri.TrimEnd("/")
    domain = $domain
    environment_file = $environmentPath
    alertmanager_config_file = $alertmanagerConfigPath
    online_music_enabled = $onlineMusicEnabled
    configured_sources = $configuredSources
    approved_sources = $approvedSources
    source_approval_evidence_file = $sourceEvidencePath
    source_approval = $sourceApprovalSummary
    compose_configuration_valid = $true
    compose_services = @()
    certificate = $null
    health = $null
    readiness = $null
    prometheus = $null
    sidecar_image = $null
    alert_test = [ordered]@{
        action = $AlertAction
        scenario = $AlertScenario
        test_id = $AlertTestId
        runbook_url = if ($null -ne $RunbookUrl) { $RunbookUrl.AbsoluteUri } else { $null }
        notification_receipt_reference = $NotificationReceiptReference
        prerequisite_evidence_files = @()
    }
}

if (-not $ConfigurationOnly) {
    $expectedServices = @(
        "caddy",
        "music-api",
        "music-sidecar",
        "otel-collector",
        "prometheus",
        "alertmanager"
    )
    $runningServices = @(
        Invoke-Docker -Arguments ($composeArguments + @("ps", "--services", "--status", "running")) -Capture |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    foreach ($service in $expectedServices) {
        Assert-Condition ($runningServices -contains $service) "生产服务未运行：$service"
    }
    $result.compose_services = $runningServices

    if ($onlineMusicEnabled) {
        $sidecarContainerIds = @(
            Invoke-Docker -Arguments ($composeArguments + @("ps", "--quiet", "music-sidecar")) -Capture |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ }
        )
        Assert-Condition ($sidecarContainerIds.Count -eq 1) "无法唯一定位正在运行的 music-sidecar 容器。"
        $sidecarImageArguments = @{
            ContainerId = $sidecarContainerIds[0]
            ApprovedDigest = $approvedImageDigests[0]
        }
        $result.sidecar_image = & (Join-Path $PSScriptRoot "container_image_acceptance.ps1") @sidecarImageArguments
    }

    $prometheusArguments = @{
        DockerNetwork = $observabilityNetwork
        LookbackDays = 7
        TimeoutSeconds = 60
    }
    if ($onlineMusicEnabled) {
        $prometheusArguments.RequireOnlineMusicSeries = $true
    }
    $result.prometheus = & (Join-Path $PSScriptRoot "prometheus_acceptance.ps1") @prometheusArguments

    $certificateHolder = [hashtable]::Synchronized(@{
        certificate = $null
        errors = $null
    })
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.ServerCertificateCustomValidationCallback = {
        param($request, $certificate, $chain, $sslPolicyErrors)
        $certificateHolder.errors = $sslPolicyErrors.ToString()
        if ($null -ne $certificate) {
            $certificateHolder.certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate)
        }
        return $sslPolicyErrors -eq [Net.Security.SslPolicyErrors]::None
    }.GetNewClosure()
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)

    try {
        $correlationId = "production-acceptance-$([Guid]::NewGuid().ToString('N'))"
        $healthRequest = [Net.Http.HttpRequestMessage]::new(
            [Net.Http.HttpMethod]::Get,
            [uri]::new($BaseUrl, "health")
        )
        $healthRequest.Headers.Add("X-Correlation-ID", $correlationId)
        $healthResponse = $client.SendAsync($healthRequest).GetAwaiter().GetResult()
        $healthBody = $healthResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        Assert-Condition ($healthResponse.StatusCode -eq [Net.HttpStatusCode]::OK) "/health 未返回 200。"
        Assert-Condition ((Get-ResponseHeader $healthResponse "X-Correlation-ID") -eq $correlationId) "关联 ID 未被安全回显。"
        Assert-Condition ((Get-ResponseHeader $healthResponse "Strict-Transport-Security") -match "max-age=31536000") "HTTPS 响应缺少预期 HSTS。"
        Assert-Condition ((Get-ResponseHeader $healthResponse "X-Content-Type-Options") -eq "nosniff") "HTTPS 响应缺少 X-Content-Type-Options。"
        Assert-Condition ((Get-ResponseHeader $healthResponse "X-Frame-Options") -eq "DENY") "HTTPS 响应缺少 X-Frame-Options。"
        Assert-Condition ([string]::IsNullOrWhiteSpace((Get-ResponseHeader $healthResponse "Server"))) "HTTPS 响应暴露了 Server 头。"
        $healthPayload = $healthBody | ConvertFrom-Json
        Assert-Condition ($healthPayload.status -eq "ok") "/health 响应内容不符合契约。"
        $result.health = [ordered]@{
            status_code = [int]$healthResponse.StatusCode
            correlation_id = $correlationId
        }

        $readyRequest = [Net.Http.HttpRequestMessage]::new(
            [Net.Http.HttpMethod]::Get,
            [uri]::new($BaseUrl, "health/ready")
        )
        $readyResponse = $client.SendAsync($readyRequest).GetAwaiter().GetResult()
        Assert-Condition ($readyResponse.StatusCode -eq [Net.HttpStatusCode]::OK) "/health/ready 未返回 200。"
        $result.readiness = [ordered]@{
            status_code = [int]$readyResponse.StatusCode
            correlation_id = Get-ResponseHeader $readyResponse "X-Correlation-ID"
        }

        $certificate = $certificateHolder.certificate
        Assert-Condition ($null -ne $certificate) "未能读取 HTTPS 证书。"
        $remainingDays = [Math]::Floor(($certificate.NotAfter.ToUniversalTime() - [DateTime]::UtcNow).TotalDays)
        Assert-Condition ($remainingDays -ge $MinimumCertificateDays) "HTTPS 证书将在 $remainingDays 天后过期，低于要求的 $MinimumCertificateDays 天。"
        $result.certificate = [ordered]@{
            subject = $certificate.Subject
            issuer = $certificate.Issuer
            thumbprint_sha1 = $certificate.Thumbprint
            not_after_utc = $certificate.NotAfter.ToUniversalTime().ToString("O")
            remaining_days = $remainingDays
            ssl_policy_errors = $certificateHolder.errors
        }
    }
    finally {
        if ($null -ne $client) {
            $client.Dispose()
        }
        if ($null -ne $handler) {
            $handler.Dispose()
        }
    }

    if ($AlertAction -eq "Finalize") {
        $scenarioEvidenceFiles = @()
        foreach ($scenarioName in $alertScenarios.Keys) {
            $evidenceQuery = @{
                EvidenceDirectory = $resolvedEvidenceDirectory
                RequiredStatus = "scenario_complete"
                RequiredScenario = $scenarioName
                RequiredTestId = ""
                RequiredBaseUrl = $result.base_url
                RequiredBuildRevision = $normalizedBuildRevision
                MatchDeployment = $true
                RequiredOnlineMusicEnabled = $onlineMusicEnabled
                RequiredConfiguredSources = $configuredSources
                RequiredApprovedSources = $approvedSources
                RequiredSidecarImageDigest = if ($onlineMusicEnabled) {
                    $result.sidecar_image.image_digest
                }
                else {
                    ""
                }
                CheckedAtNotAfterUtc = $acceptanceStartedAt
            }
            $scenarioEvidence = Find-ProductionAcceptanceEvidence @evidenceQuery
            Assert-Condition ($null -ne $scenarioEvidence) "缺少七天内完成的 $scenarioName 告警通知演练证据。"
            $scenarioEvidenceFiles += $scenarioEvidence.path
        }
        $result.alert_test.prerequisite_evidence_files = $scenarioEvidenceFiles
        $result.status = "complete"
    }
    elseif ($AlertAction -in @("Fire", "Resolve")) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($AlertTestId)) "告警演练必须提供 -AlertTestId。"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($AlertScenario)) "告警演练必须提供 -AlertScenario。"
        Assert-Condition ($null -ne $RunbookUrl -and $RunbookUrl.Scheme -eq "https") "告警演练必须提供可访问的 HTTPS -RunbookUrl。"
        Assert-HttpsUrl $RunbookUrl.AbsoluteUri "告警演练 RunbookUrl"
        if ($AlertAction -eq "Resolve") {
            Assert-Condition (-not [string]::IsNullOrWhiteSpace($NotificationReceiptReference)) "恢复告警前必须记录值班渠道的通知或工单编号。"
            Assert-Condition (
                $NotificationReceiptReference -match "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$"
            ) "通知或工单编号必须为 1 到 128 位安全字符。"
            Assert-NotPlaceholder $NotificationReceiptReference "通知或工单编号"
            $evidenceQuery = @{
                EvidenceDirectory = $resolvedEvidenceDirectory
                RequiredStatus = "alert_fired_awaiting_notification_confirmation"
                RequiredScenario = $AlertScenario
                RequiredTestId = $AlertTestId
                RequiredBaseUrl = $result.base_url
                RequiredBuildRevision = $normalizedBuildRevision
                MatchDeployment = $true
                RequiredOnlineMusicEnabled = $onlineMusicEnabled
                RequiredConfiguredSources = $configuredSources
                RequiredApprovedSources = $approvedSources
                RequiredSidecarImageDigest = if ($onlineMusicEnabled) {
                    $result.sidecar_image.image_digest
                }
                else {
                    ""
                }
                CheckedAtNotAfterUtc = $acceptanceStartedAt
            }
            $fireEvidence = Find-ProductionAcceptanceEvidence @evidenceQuery
            Assert-Condition ($null -ne $fireEvidence) "未找到同一提交、部署、场景、AlertTestId 和 BaseUrl 的有效 Fire 证据。"
            $result.alert_test.prerequisite_evidence_files = @($fireEvidence.path)
        }

        $scenario = $alertScenarios[$AlertScenario]
        $now = [DateTimeOffset]::UtcNow
        $endsAt = if ($AlertAction -eq "Fire") { $now.AddHours(1) } else { $now }
        $alert = @(
            [ordered]@{
                labels = [ordered]@{
                    alertname = $scenario.alertname
                    severity = $scenario.severity
                    component = "online-music"
                    service = "music-api"
                    acceptance_id = $AlertTestId
                }
                annotations = [ordered]@{
                    summary = $scenario.summary
                    description = "Controlled acceptance alert; no user or media data is included."
                    runbook_url = $RunbookUrl.AbsoluteUri
                }
                startsAt = $now.AddMinutes(-1).ToString("O")
                endsAt = $endsAt.ToString("O")
                generatorURL = [uri]::new($BaseUrl, "health").AbsoluteUri
            }
        )
        $alertJson = $alert | ConvertTo-Json -Depth 6 -Compress
        $null = Invoke-Docker -Arguments @(
            "run", "--rm",
            "--network", $observabilityNetwork,
            "--read-only",
            "--cap-drop", "ALL",
            "curlimages/curl:8.14.1",
            "--fail-with-body",
            "--silent",
            "--show-error",
            "--header", "Content-Type: application/json",
            "--data-binary", $alertJson,
            "http://alertmanager:9093/api/v2/alerts"
        ) -Capture

        function Get-ActiveScenarioAlert {
            $activeJson = (Invoke-Docker -Arguments @(
                "run", "--rm",
                "--network", $observabilityNetwork,
                "--read-only",
                "--cap-drop", "ALL",
                "curlimages/curl:8.14.1",
                "--fail-with-body",
                "--silent",
                "--show-error",
                "http://alertmanager:9093/api/v2/alerts?active=true&silenced=false&inhibited=false"
            ) -Capture) -join [Environment]::NewLine
            $activeAlerts = @($activeJson | ConvertFrom-Json)
            return @(
                $activeAlerts |
                    Where-Object {
                        $_.labels.alertname -eq $scenario.alertname -and
                        $_.labels.acceptance_id -eq $AlertTestId
                    }
            )
        }

        if ($AlertAction -eq "Fire") {
            $activeScenarioAlerts = @(Get-ActiveScenarioAlert)
            Assert-Condition ($activeScenarioAlerts.Count -gt 0) "Alertmanager 未显示刚发送的 $AlertScenario 告警。"
            $result.status = "alert_fired_awaiting_notification_confirmation"
        }
        else {
            $activeScenarioAlerts = @()
            foreach ($attempt in 1..10) {
                $activeScenarioAlerts = @(Get-ActiveScenarioAlert)
                if ($activeScenarioAlerts.Count -eq 0) {
                    break
                }
                Start-Sleep -Seconds 1
            }
            Assert-Condition ($activeScenarioAlerts.Count -eq 0) "Alertmanager 中的 $AlertScenario 告警未恢复。"
            $result.status = "scenario_complete"
        }
    }
    else {
        $result.status = "runtime_valid_alert_delivery_not_exercised"
    }
}

$result.checked_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
$null = New-Item -ItemType Directory -Path $resolvedEvidenceDirectory -Force
$timestamp = [DateTimeOffset]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
$evidencePath = Join-Path $resolvedEvidenceDirectory "production-$timestamp.json"
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8

Write-Host "生产验收状态：$($result.status)"
Write-Host "证据文件：$evidencePath"
if ($result.status -eq "alert_fired_awaiting_notification_confirmation") {
    Write-Host "请在值班渠道确认通知后，以相同 AlertScenario 和 AlertTestId 执行 Resolve，并填写 NotificationReceiptReference。"
}
elseif ($result.status -eq "scenario_complete") {
    Write-Host "该场景已完成；三个场景都完成后使用 -AlertAction Finalize 生成最终证据。"
}
