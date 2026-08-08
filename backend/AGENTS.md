# Backend 协作指南

本文件适用于 `backend/` 下的 ASP.NET Core 后端与其测试工程。它补充仓库根目录 [`../AGENTS.md`](../AGENTS.md)；若规则冲突，以根目录和用户的明确要求为准。

## 范围与事实源

- `Music.Api` 是独立的 ASP.NET Core 10 Minimal API，默认地址为 `http://localhost:5080`。
- 后端 SQLite 是服务器端账号、歌单、扫描源、索引曲目和审计日志的事实源。
- Flutter 主 UI 当前仍使用本地 Mock 账号链路；除非任务明确要求，不要把后端改动描述为真实登录已经接入客户端。
- 服务器扫描只访问后端机器的文件系统，不上传或复制客户端音频。

## 修改前

1. 在仓库根目录运行 `git status --short`，保留用户已有改动，不回退或清理无关文件。
2. 阅读对应的 Endpoint、Service、Store、Model 和 [`../docs/api.md`](../docs/api.md)，确认请求/响应与账号隔离语义。
3. 认证、路径校验、SQLite 写入和后台扫描属于高风险边界；先建立针对性测试，再实现行为变化。
4. 不手改 `bin/`、`obj/`、`storage/music.db*` 或其他生成/运行文件。

## 分层约定

- `Program.cs` 只负责组合根、依赖注入、中间件和路由注册。
- `Endpoints/` 保持薄：做输入校验、认证上下文、异常到 HTTP 状态码的映射。
- `Services/` 承载密码哈希、JWT/Refresh Token 轮换、扫描和定时任务等业务规则。
- `Data/` 通过接口实现 SQLite 持久化；需要替换数据库时优先新增 Store 实现，而不是把 SQL 写进 Endpoint。
- `Models/` 使用明确的 nullable DTO；请求字段是否必填必须在 Endpoint 或 Service 中验证。
- `Middleware/` 不得把密码、令牌或请求体写入日志。

## 安全约束

- 所有账号相关查询和写入都必须带当前用户名条件，不能只按资源 ID 访问。
- JWT 密钥至少 32 字节；生产环境必须通过环境变量或密钥管理系统覆盖开发配置。
- Refresh Token 只保存摘要，每次刷新必须轮换旧令牌；发现重放时撤销该账号仍有效的令牌。
- 扫描路径使用 `Path.GetFullPath` 规范化，并限制在 `Scanning:AllowedRoots` 的目录本身或子目录内；不要依赖字符串前缀的未规范化比较。
- 错误响应可以包含可操作的校验信息，但不能泄露密码、令牌、绝对路径以外的敏感环境细节或堆栈。

## 数据库与扫描

- 初始化和迁移逻辑应保持幂等，启用 SQLite 外键和 WAL 时要考虑测试环境。
- 多表写入使用事务；歌单、扫描源和索引曲目的删除范围必须按账号与来源验证。
- 支持的音频扩展名变更时同步检查 Flutter 扫描、Android、Windows、后端文档和实际解码器。
- 单个损坏或无权访问的媒体文件可以跳过；目录级错误应写入扫描源状态并可被 API 查询。
- 后台 Worker 必须响应取消令牌，不能阻塞应用关闭。

## 测试与验证

最小验证命令：

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
dotnet restore backend/Music.Api.Tests/Music.Api.Tests.csproj --configfile backend/NuGet.Config
dotnet test backend/Music.Api.Tests/Music.Api.Tests.csproj --no-restore
```

测试优先覆盖：

- 首次登录、错误密码、JWT 篡改、Refresh Token 轮换和重放撤销。
- 跨账号读取/写入隔离、重复扫描源和扫描根目录越界。
- 扫描的扩展名过滤、目录元数据兜底、文件删除后的索引清理和取消行为。
- Endpoint 的 400/401/404/409/204 状态码及审计事件。

单元测试使用临时目录、内存 fake 或临时 SQLite，不得依赖 `storage/music.db`。如果修改 HTTP 契约，同步更新 `docs/api.md`、OpenAPI 输出和 `.http` 示例；如果修改认证/路径隔离逻辑，必须在交付说明中列出已执行的测试命令及结果。

## 代码风格

- 启用 nullable reference types 和 implicit usings；保持现有 C# 格式与文件命名。
- 业务方法返回明确的 nullable 类型；不要用空值抑制隐藏请求校验错误。
- 异步方法传播 `CancellationToken`，故意忽略的任务必须有明确原因。
- 注释解释安全边界、事务、生命周期等“为什么”，不要重复代码字面含义。
