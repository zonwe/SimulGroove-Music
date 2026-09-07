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
