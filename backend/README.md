# SimulGroove Music 后端

`backend/Music.Api` 是 SimulGroove Music 的实验性同步后端，基于 ASP.NET Core 10 Minimal API 和 SQLite。它提供账号会话、歌单/喜欢同步、服务器目录扫描、在线音乐搜索 BFF 和审计日志，并已接入 Flutter 主界面。客户端运行配置见 [`../docs/flutter_backend_integration.md`](../docs/flutter_backend_integration.md)。

## 快速开始

要求：.NET 10 SDK。仓库根目录的 `global.json` 固定 SDK 的主版本。

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

启动后可检查：

```powershell
Invoke-RestMethod http://localhost:5080/health
Invoke-WebRequest http://localhost:5080/health/ready
Invoke-RestMethod http://localhost:5080/openapi.json
```

在线搜索联调还需要在仓库根目录的 `go-music-dl` clone 中启动仅监听本机的集成服务：

```powershell
go -C go-music-dl run ./cmd/music-dl integration --host 127.0.0.1 --port 8080
```

Development 配置默认启用 `netease`、`kugou`、`kuwo` 三个已验证来源；生产 `appsettings.json` 仍默认关闭在线音乐功能。

服务器扫描管理页面由 API 项目直接托管，浏览器打开：

```text
http://localhost:5080/admin/scanning
```

页面由 Razor Pages 渲染，PageModel 直接调用扫描 Service。管理员登录使用独立的 HttpOnly Cookie，不复用 Flutter 的 JWT/Refresh Token。生产环境必须使用 HTTPS。

默认数据库为 `backend/Music.Api/storage/music.db`。开发时可使用 `Database:Path` 指向临时文件；不要把运行数据库、WAL/SHM 文件提交到版本库。

## 容器部署

仓库根目录的 [`compose.online-music.yml`](../compose.online-music.yml) 会构建非 root 的 `Music.Api` 镜像，并从固定在本地的 `go-music-dl` clone 构建 sidecar。只有 API 的 `5080` 端口映射到宿主机；sidecar 仅加入 Compose 私有网络，但仍可通过容器网络访问第三方音乐平台。

首次启动前复制环境模板并替换全部占位密钥：

```powershell
Copy-Item .env.example .env
# 使用密码管理器编辑 .env 中的 JWT 与管理员密钥
docker compose --env-file .env -f compose.online-music.yml config
docker compose --env-file .env -f compose.online-music.yml up --detach --build
Invoke-WebRequest http://localhost:5080/health/ready
```

API 数据库、Data Protection 密钥和 sidecar 数据分别保存在命名卷中。不要提交 `.env`、数据库、Cookie 或卷导出文件。生产环境还应在 API 前配置 HTTPS 反向代理；Compose 文件不负责申请证书。

升级前记录主仓库与 sidecar commit，备份 `music-api-data` 卷，并先运行 Go 契约测试与后端测试。随后重新构建并检查就绪状态：

```powershell
git rev-parse HEAD
git -C go-music-dl rev-parse HEAD
docker compose --env-file .env -f compose.online-music.yml build --pull
docker compose --env-file .env -f compose.online-music.yml up --detach
docker compose --env-file .env -f compose.online-music.yml ps
Invoke-WebRequest http://localhost:5080/health/ready
```

若升级失败，恢复记录的两个 commit 并重新构建；只有数据库迁移不兼容时才恢复升级前的数据卷备份。不要用删除卷的方式代替回滚。

## 配置

配置文件为 `backend/Music.Api/appsettings.json`，环境变量使用双下划线替换层级分隔符：

```powershell
$env:Auth__JwtKey = "使用密码管理器生成的至少 32 字节随机密钥"
$env:Administration__Username = "admin"
$env:Administration__Password = "使用密码管理器生成的管理员密码"
```

开发环境内置仅供本机联调的账号 `admin`，密码为
`LOCAL-DEVELOPMENT-ONLY-CHANGE-BEFORE-USE`。共享开发机和任何生产部署都必须通过环境变量覆盖；生产配置未提供密码时，管理员登录会保持禁用。

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `Database:Path` | `storage/music.db` | SQLite 文件路径；相对路径相对于 API 内容根目录 |
| `Auth:Issuer` | `flutter-music-api` | JWT 签发者 |
| `Auth:Audience` | `flutter-music-client` | JWT 接收方 |
| `Auth:AccessTokenMinutes` | `15` | Access Token 有效期 |
| `Auth:RefreshTokenDays` | `30` | Refresh Token 有效期 |
| `Administration:Username` | `admin` | Razor Pages 管理员用户名；生产环境通过环境变量覆盖 |
| `Administration:Password` | 空 | Razor Pages 管理员密码；不得提交真实密码 |
| `Scanning:PollSeconds` | `30` | 后台扫描任务轮询间隔，代码会限制在 5–3600 秒 |
| `Scanning:AllowedRoots` | `[]` | 允许用户配置的服务器目录根；生产环境应显式设置 |
| `Audit:RetentionDays` | `90` | 审计日志保留时间，范围为 7–3650 天 |
| `OnlineMusic:Enabled` | `false` | 是否启用在线音乐搜索 |
| `OnlineMusic:SidecarBaseUrl` | `http://127.0.0.1:8080` | 私有 go-music-dl sidecar 地址 |
| `OnlineMusic:HealthCheckTimeoutSeconds` | `3` | 就绪检查访问 sidecar 的超时秒数，运行时限制为 1–10 |
| `OnlineMusic:CircuitBreakerFailureThreshold` | `5` | 连续瞬时失败达到该次数后打开熔断，运行时限制为 2–20 |
| `OnlineMusic:CircuitBreakerBreakSeconds` | `30` | 熔断持续秒数，运行时限制为 5–300；恢复窗口仅允许一个探测请求 |
| `OnlineMusic:AllowedSources` | `[]` | sidecar 规范来源 ID 白名单 |
| `OnlineMusic:RequestsPerMinute` | `30` | 每账号和每 IP 的搜索限额 |
| `OnlineMusic:PlaybackTicketSeconds` | `300` | 账号绑定播放票据的有效秒数，限制为 60–300 |
| `OnlineMusic:LyricsCacheSeconds` | `900` | 歌词缓存秒数，运行时限制为 30–86400 |
| `OnlineMusic:ArtworkCacheSeconds` | `21600` | 封面缓存秒数，运行时限制为 60–86400 |
| `OnlineMusic:AssetCacheSizeBytes` | `33554432` | 歌词与封面的独立内存缓存总容量 |
| `OnlineMusic:MaxLyricsBytes` | `524288` | 单份歌词最大字节数 |
| `OnlineMusic:MaxArtworkBytes` | `2097152` | 单张封面最大字节数 |

## API 概览

除 `/`、`/health`、`/health/ready` 和 `/openapi.json` 外，业务接口需要 `Authorization: Bearer <access-token>`。`/health` 仅表示 API 进程存活；`/health/ready` 在在线音乐启用时探测私有 sidecar，不可用时返回 `503`：

客户端可以传入最多 64 个字符的 `X-Correlation-ID`（仅允许 ASCII 字母、数字、点、下划线和连字符）。服务端会拒绝不安全的值并生成替代 ID，在响应、账号审计记录和发往 sidecar 的请求中复用该 ID。

在线音乐 sidecar 调用通过 .NET `Meter` `FlutterMusic.OnlineMusic` 提供请求数、失败数、耗时和熔断拒绝数。标签只包含规范操作名与失败类型，不包含搜索词、来源、曲目 ID、Token 或 URL。生产部署可用 OpenTelemetry 或兼容的 `MeterListener` 订阅以下指标：

- `flutter_music.online_music.sidecar.requests`
- `flutter_music.online_music.sidecar.failures`
- `flutter_music.online_music.sidecar.duration`
- `flutter_music.online_music.sidecar.circuit_rejections`

- `POST /api/auth/login`：首次使用账号时创建账号并登录。
- `POST /api/auth/refresh`：轮换 Access Token 和 Refresh Token；客户端必须替换旧 Refresh Token。
- `GET /api/auth/me`、`POST /api/auth/logout`：读取当前账号、撤销当前账号的 Refresh Token。
- `POST /api/playlists/sync`：按 `remoteId` 合并歌单和喜欢的歌曲。
- `GET/POST /api/scan-sources/`、`PUT/DELETE /api/scan-sources/{id}`：管理服务器扫描源。
- `POST /api/scan-sources/{id}/scan`、`GET /api/scan-sources/{id}/tracks`：立即扫描和读取索引结果。
- `GET /api/audit-logs`：分页查询当前账号的审计日志。
- `GET /api/online-music/sources`、`POST /api/online-music/search`：查询允许来源和执行跨来源搜索。
- `POST /api/online-music/tracks/{source}/{trackId}/playback`、`GET /api/online-music/playback/{ticket}`：签发账号绑定短期票据并转发支持 Range 的在线音频流。
- `GET /api/online-music/tracks/{source}/{trackId}/lyrics`、`GET /api/online-music/tracks/{source}/{trackId}/cover`：读取受控歌词与封面代理；空资源返回稳定 404。

服务器扫描管理页位于 `/admin/scanning`，登录页位于 `/admin/login`。Flutter 客户端不包含服务器扫描管理入口。

完整请求/响应契约见 [`../docs/api.md`](../docs/api.md)，可执行示例见 [`Music.Api/FlutterMusic.Api.http`](Music.Api/FlutterMusic.Api.http)。扫描只读取后端机器可访问的文件，不上传或复制音频内容；索引保存于 SQLite，并按账号隔离。

## 项目结构

| 路径 | 职责 |
| --- | --- |
| `Music.Api/Program.cs` | 依赖注入、中间件和路由注册 |
| `Music.Api/Endpoints/` | 请求校验、认证上下文和 HTTP 响应 |
| `Music.Api/Services/Auth/` | PBKDF2 密码哈希、JWT 和 Refresh Token 轮换 |
| `Music.Api/Services/Scanning/` | 目录扫描和定时后台任务 |
| `Music.Api/Services/Administration/` | 管理员配置凭据校验与授权常量 |
| `Music.Api/Services/OnlineMusic/` | sidecar JSON 网关、搜索/资源缓存、限流、播放票据和稳定错误映射 |
| `Music.Api/Pages/Admin/` | 管理员登录与服务器扫描 Razor Pages |
| `Music.Api/Data/` | SQLite 建表、歌单、扫描源和审计日志存取 |
| `Music.Api/Models/` | API 请求/响应 DTO |
| `Music.Api/Middleware/` | 已认证请求的审计日志 |
| `Music.Api.Tests/` | 服务和安全边界的单元测试 |

Endpoint 应保持薄，业务规则放在 Service，数据库访问通过 Store 接口隔离。扫描路径必须是服务器上的绝对路径，并通过 `Scanning:AllowedRoots` 做规范化后的目录边界校验。

## 测试

运行后端单元测试：

```powershell
dotnet restore backend/Music.Api.Tests/Music.Api.Tests.csproj --configfile backend/NuGet.Config
dotnet test backend/Music.Api.Tests/Music.Api.Tests.csproj --no-restore
```

测试使用临时 SQLite 文件和内存 fake store，不会修改 `Music.Api/storage/music.db`。修改认证、账号隔离、扫描路径校验或扫描删除逻辑时，应同步补充回归测试。

## 安全与部署提示

- 生产环境必须替换开发 JWT 密钥，并通过安全配置注入，不要提交密钥。
- 不记录密码、Access Token、Refresh Token 或请求体；审计日志按账号隔离。
- 配置 `Scanning:AllowedRoots`，避免用户把任意服务器目录加入扫描。
- Refresh Token 只保存 SHA-256 摘要，每次刷新都会轮换；客户端应在刷新失败时清除本地会话。
- 服务端扫描的是后端机器上的目录，不是客户端上传的音乐文件。
- 在线音乐功能默认关闭；sidecar 只应在回环地址或私有网络监听，Flutter 不得直接访问它。

后端的协作约束和验证矩阵见 [`AGENTS.md`](AGENTS.md)。
