# 在线音乐生产告警与处置

本页定义 `Music.Api` 在线音乐链路的生产告警契约与最小处置步骤。规则文件位于 [`../deploy/observability/online_music_alerts.yml`](../deploy/observability/online_music_alerts.yml)，生产编排位于 [`../compose.online-music.production.yml`](../compose.online-music.production.yml)。编排会启动私有 Collector、Prometheus 和 Alertmanager，并只通过 Caddy 发布 HTTPS API；真正的通知接收方和来源授权仍必须由部署方提供与批准。

## 接入前提

1. 生产 Compose 默认将 `Observability:OtlpEndpoint` 指向同一私有网络中的 `otel-collector:4317`；改用外部 Collector 时必须使用部署方批准的加密端点。
2. Collector 接收 OTLP 指标并向 Prometheus 导出，使用下划线转义与 counter `_total` 后缀策略。
3. Prometheus 加载 `online_music_alerts.yml` 并把告警发送给私有 Alertmanager；`ALERTMANAGER_CONFIG_PATH` 必须指向仓库外已复核的真实通知配置。
4. 用部署版本的 `promtool check rules deploy/observability/online_music_alerts.yml` 校验规则，再执行一次受控 sidecar 失败演练。

若 Collector 改写了指标名称，必须先根据实际导出结果调整规则，不能在没有查询到样本的情况下视为接入成功。指标与告警标签不得增加搜索词、来源、曲目 ID、账号、Token、Cookie、`streamRef` 或 URL。

## Sidecar failure ratio

告警分别在 10 分钟失败率超过 25% 和 5 分钟失败率超过 50% 时触发，并要求窗口内至少有 20 次请求，避免低流量偶发错误造成噪声。

处置顺序：

1. 检查 `/health/ready`，确认故障来自 sidecar 依赖而不是 API 进程本身。
2. 按 `operation` 和 `failure_type` 低基数标签查看失败分布，不查询或记录用户搜索词及资源标识。
3. 核对 sidecar 进程、上游访问能力、DNS、代理、超时和 429/5xx 响应。
4. 若来源授权、条款或访问方式存在疑问，立即清空生产 `OnlineMusic:AllowedSources`，不要通过提高重试或绕过限流维持服务。
5. 恢复后确认失败率回落、就绪检查恢复，并在事件记录中保存时间线与配置变更。

## Circuit breaker open

只要熔断器持续拒绝请求就触发关键告警。熔断器打开通常表示连续瞬时错误已达到阈值，继续增加流量不会帮助恢复。

处置顺序：

1. 检查 sidecar 与其上游依赖是否恢复，不要反复重启 API 来掩盖故障。
2. 等待配置的 `CircuitBreakerBreakSeconds` 后观察单次半开探测结果。
3. 探测继续失败时保持在线音乐关闭或移除受影响来源，并按失败率告警步骤排查。
4. 探测成功后确认 `circuit_rejections` 停止增长，再恢复正常流量。

## 发布验收

生产启用前必须保存以下证据：

- Collector 端实际出现三个 counter，并确认名称与规则一致。
- 告警规则校验通过，受控演练能够触发并恢复 warning、critical 与 circuit breaker 告警。
- 通知路由到达值班渠道，链接能够打开本页对应处置段落。
- 指标样本与通知中不存在任何高基数或敏感字段。
- [`online_music_release_review.md`](online_music_release_review.md) 中的来源授权门禁已经逐来源批准。

### 自动化验收入口

`tool/production_acceptance.ps1` 将配置、外部 HTTPS 和通知路由检查串成同一份本地证据。脚本不会输出 JWT、管理员密码、Webhook 或 Cookie，结果只写入已被忽略的 `build/acceptance/production/`。

上线前先让生产环境文件引用仓库外的真实 Alertmanager 配置。真实域名、ACME 邮箱、JWT 密钥和管理员密码不能保留示例值：

生产环境文件还必须设置 `MUSIC_SERVER_LIBRARY_PATH`，指向后端主机上已存在且位于仓库外的专用音乐目录；不得填写 `/`、`C:\` 等文件系统根目录。Compose 会把它只读挂载到 API 容器的 `/music`，并把 `/music` 配置为唯一的 `Scanning:AllowedRoots`；管理员页填写的是容器内 `/music` 或其子目录，不能填写宿主路径。

```powershell
$buildRevision = git rev-parse HEAD
pwsh ./tool/production_acceptance.ps1 `
  -BaseUrl "https://music.example.org" `
  -EnvironmentFile "C:/secure/simulgroove/production.env" `
  -BuildRevision $buildRevision `
  -ConfigurationOnly
```

服务启动后执行运行时验收。它会确认全部私有服务正在运行、系统信任 HTTPS 证书、证书剩余有效期、Caddy 安全响应头、关联 ID 回显和存活/就绪检查；同时通过 Compose 私有网络查询 Prometheus，确认 `simulgroove-otel-collector` 抓取目标在线：

```powershell
pwsh ./tool/production_acceptance.ps1 `
  -BaseUrl "https://music.example.org" `
  -EnvironmentFile "C:/secure/simulgroove/production.env" `
  -BuildRevision $buildRevision
```

在线音乐启用时，运行时验收还要求 Prometheus 最近七天内实际存在请求、失败和熔断拒绝三个 counter。上线演练应先制造不包含用户或媒体数据的受控 sidecar 瞬时失败与熔断拒绝，再执行运行时验收；仅有 Collector 进程存活、CI 中的合成指标或直接向 Alertmanager 注入告警都不能替代这项生产证据。验收结果只保存每个指标的时间序列数量和标签名，不保存标签值；任何搜索词、来源、曲目、账号、用户、Token、Cookie、密码、StreamRef 或 URL 类标签名都会使验收失败。

通知送达必须对 `FailureWarning`、`FailureCritical` 和 `CircuitBreaker` 三个场景分别完成，以命中真实规则使用的告警名、严重级别和组件标签。每个场景的第一步都从 Compose 私有观测网络向 Alertmanager 发送不含用户或媒体数据的受控告警：

```powershell
pwsh ./tool/production_acceptance.ps1 `
  -BaseUrl "https://music.example.org" `
  -EnvironmentFile "C:/secure/simulgroove/production.env" `
  -BuildRevision $buildRevision `
  -AlertAction Fire `
  -AlertScenario FailureWarning `
  -AlertTestId CHG-20260907-01 `
  -RunbookUrl "https://ops.example.org/runbooks/simulgroove-online-music"
```

脚本会从 Alertmanager API 反查该告警确实处于活动状态。值班渠道确认收到通知后，使用完全相同的 `AlertScenario` 和 `AlertTestId` 发送恢复，并记录通知或工单编号：

```powershell
pwsh ./tool/production_acceptance.ps1 `
  -BaseUrl "https://music.example.org" `
  -EnvironmentFile "C:/secure/simulgroove/production.env" `
  -BuildRevision $buildRevision `
  -AlertAction Resolve `
  -AlertScenario FailureWarning `
  -AlertTestId CHG-20260907-01 `
  -RunbookUrl "https://ops.example.org/runbooks/simulgroove-online-music" `
  -NotificationReceiptReference "INC-12345"
```

恢复步骤必须找到七天内相同场景、测试 ID、域名与仓库提交，且完成时间早于本次 Resolve 开始时间的 Fire 证据，并从 Alertmanager API 确认告警不再活动，随后生成 `scenario_complete`。三个场景均完成后执行最终汇总：

```powershell
pwsh ./tool/production_acceptance.ps1 `
  -BaseUrl "https://music.example.org" `
  -EnvironmentFile "C:/secure/simulgroove/production.env" `
  -BuildRevision $buildRevision `
  -AlertAction Finalize
```

最终汇总要求七天内三个场景的 `scenario_complete` 证据都早于本次 Finalize 开始时间，并与当前仓库提交、域名、在线音乐启用状态和来源白名单一致。证据的 `checked_at_utc` 在该阶段全部检查成功后写入，不再表示阶段开始时间。只有汇总证据状态才是 `complete`。提供 `-BuildRevision` 时，脚本会验证它等于当前检出的 Git HEAD，并要求工作区不存在未提交、未跟踪或子模块改动，避免把脏检出的配置和脚本错误归属给该提交；Fire、Resolve 或 Finalize 缺少该参数时也会直接拒绝执行，避免伪造、未来时间或跨提交拼接验收证据。

本地生产验收应从干净 worktree 或 clone 执行；若当前开发目录保留个人文档或其他未提交内容，不要为了通过门禁删除仍需保留的工作。

若 `ONLINE_MUSIC_ENABLED=true`，脚本还要求 `-ApprovedSourceId` 与生产白名单完全相同，并要求 `-SourceApprovalEvidencePath` 指向仓库外的结构化 JSON 记录；字段模板见 [`deploy/compliance/online_music_source_approval.example.json`](../deploy/compliance/online_music_source_approval.example.json)。脚本会校验批准状态、有效期、能力范围、政策链接、三方审批人、固定提交、镜像摘要、对应源码地址和敏感字段名。运行时还会读取正在运行的 `music-sidecar` 容器镜像 ID，要求它与所有来源共同批准的 `image_digest` 完全一致；Finalize 只接受由同一镜像完成的三个告警场景。该检查不能替代业务、安全与法律/合规审批，只用于防止部署参数绕过已经定义的门禁。

### GitHub 受保护验收工作流

`.github/workflows/production-acceptance.yml` 把上述命令封装为只允许从仓库默认分支手动触发的生产验收。工作流使用 `production` Environment 和带有 `simulgroove-production` 自定义标签的自托管执行器；应为 Environment 配置必需审批人，并确保执行器与生产 Compose 位于同一受控主机或能够访问同一 Docker daemon。GitHub 托管执行器不能替代这个条件。

外部证据目录可以跨阶段保留历史 JSON，但每次工作流只接受本次脚本新建且唯一的证据文件，并复核其 schema、提交和 Base URL；不会按文件修改时间把旧证据误认成本次结果。

在 `production` Environment 中配置以下变量，所有路径都必须位于检出的仓库工作区之外：

- `PRODUCTION_BASE_URL`：真实 HTTPS API 根地址。
- `PRODUCTION_ENV_FILE`：生产 `.env` 的绝对路径；文件本身继续留在主机的密钥存储边界内。
- `PRODUCTION_ACCEPTANCE_EVIDENCE_DIR`：跨工作流运行持久保存 Fire、Resolve 和 Finalize 证据的目录。
- `PRODUCTION_APPROVED_SOURCE_IDS`：用逗号分隔的已批准来源 ID；在线音乐关闭时可为空。
- `PRODUCTION_SOURCE_APPROVAL_EVIDENCE_FILE`：在线音乐启用时必填的仓库外 JSON 审批索引。
- `PRODUCTION_RUNBOOK_URL`：执行 Fire 或 Resolve 时使用的真实 HTTPS 处置手册地址。

`PRODUCTION_ENV_FILE` 指向的 `.env` 必须包含 `MUSIC_SERVER_LIBRARY_PATH`。验收会拒绝不存在、使用文件系统根、位于仓库内、非 bind、非只读或没有与容器 `/music` 允许根严格对应的挂载。

工作流按 `Configuration`、`Runtime`、`Fire`、`Resolve`、`Finalize` 五个阶段运行，并自动把当前 `GITHUB_SHA` 写入证据。三个告警场景必须在同一提交上分别使用相同测试编号完成 Fire 与 Resolve，最后再运行 Finalize；默认分支若在演练期间更新，应从新提交重新执行整套阶段。工作流摘要只显示阶段和状态，完整证据保留在自托管执行器的外部证据目录，不上传到 GitHub；输入的通知回执编号也必须是不含秘密或个人信息的审计引用。
