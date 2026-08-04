# Flutter Music 后端

`backend/Music.Api` 是 Flutter Music 的实验性同步后端，基于 ASP.NET Core 10 Minimal API 和 SQLite。它提供账号会话、歌单/喜欢同步、服务器目录扫描和审计日志，并已通过 `HttpBackendGateway` 接入 Flutter 主界面。客户端运行配置见 [`../docs/flutter_backend_integration.md`](../docs/flutter_backend_integration.md)。

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
Invoke-RestMethod http://localhost:5080/openapi.json
```

默认数据库为 `backend/Music.Api/storage/music.db`。开发时可使用 `Database:Path` 指向临时文件；不要把运行数据库、WAL/SHM 文件提交到版本库。

## 配置

配置文件为 `backend/Music.Api/appsettings.json`，环境变量使用双下划线替换层级分隔符：

```powershell
$env:Auth__JwtKey = "使用密码管理器生成的至少 32 字节随机密钥"
```

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `Database:Path` | `storage/music.db` | SQLite 文件路径；相对路径相对于 API 内容根目录 |
| `Auth:Issuer` | `flutter-music-api` | JWT 签发者 |
| `Auth:Audience` | `flutter-music-client` | JWT 接收方 |
| `Auth:AccessTokenMinutes` | `15` | Access Token 有效期 |
| `Auth:RefreshTokenDays` | `30` | Refresh Token 有效期 |
| `Scanning:PollSeconds` | `30` | 后台扫描任务轮询间隔，代码会限制在 5–3600 秒 |
| `Scanning:AllowedRoots` | `[]` | 允许用户配置的服务器目录根；生产环境应显式设置 |
| `Audit:RetentionDays` | `90` | 审计日志保留时间，范围为 7–3650 天 |

## API 概览

除 `/`、`/health` 和 `/openapi.json` 外，业务接口需要 `Authorization: Bearer <access-token>`：

- `POST /api/auth/login`：首次使用账号时创建账号并登录。
- `POST /api/auth/refresh`：轮换 Access Token 和 Refresh Token；客户端必须替换旧 Refresh Token。
- `GET /api/auth/me`、`POST /api/auth/logout`：读取当前账号、撤销当前账号的 Refresh Token。
- `POST /api/playlists/sync`：按 `remoteId` 合并歌单和喜欢的歌曲。
- `GET/POST /api/scan-sources/`、`PUT/DELETE /api/scan-sources/{id}`：管理服务器扫描源。
- `POST /api/scan-sources/{id}/scan`、`GET /api/scan-sources/{id}/tracks`：立即扫描和读取索引结果。
- `GET /api/audit-logs`：分页查询当前账号的审计日志。

完整请求/响应契约见 [`../docs/api.md`](../docs/api.md)，可执行示例见 [`Music.Api/FlutterMusic.Api.http`](Music.Api/FlutterMusic.Api.http)。扫描只读取后端机器可访问的文件，不上传或复制音频内容；索引保存于 SQLite，并按账号隔离。

## 项目结构

| 路径 | 职责 |
| --- | --- |
| `Music.Api/Program.cs` | 依赖注入、中间件和路由注册 |
| `Music.Api/Endpoints/` | 请求校验、认证上下文和 HTTP 响应 |
| `Music.Api/Services/Auth/` | PBKDF2 密码哈希、JWT 和 Refresh Token 轮换 |
| `Music.Api/Services/Scanning/` | 目录扫描和定时后台任务 |
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

后端的协作约束和验证矩阵见 [`AGENTS.md`](AGENTS.md)。
