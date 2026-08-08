# Flutter Music API

后端项目位于 `backend/Music.Api`，使用 ASP.NET Core 10 和 SQLite。服务默认监听 `http://localhost:5080`。

## 启动

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

默认数据库位于 `backend/Music.Api/storage/music.db`，首次启动自动建表并启用 WAL。可通过 `Database:Path` 修改。

生产环境必须通过环境变量替换 JWT 密钥：

```powershell
$env:Auth__JwtKey = "使用密码管理器生成的至少 32 字节随机密钥"
$env:Administration__Username = "admin"
$env:Administration__Password = "使用密码管理器生成的管理员密码"
```

相关配置：

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `Auth:Issuer` | `flutter-music-api` | JWT 签发者 |
| `Auth:Audience` | `flutter-music-client` | JWT 接收方 |
| `Auth:AccessTokenMinutes` | `15` | Access Token 有效分钟数 |
| `Auth:RefreshTokenDays` | `30` | Refresh Token 有效天数 |
| `Administration:Username` | `admin` | Razor Pages 管理员用户名 |
| `Administration:Password` | 空 | Razor Pages 管理员密码；生产环境必须通过安全配置注入 |
| `Scanning:PollSeconds` | `30` | 后台任务检查到期扫描源的间隔秒数 |
| `Scanning:AllowedRoots` | `[]` | 允许扫描的根目录；空数组表示后端可访问的任意目录 |
| `Audit:RetentionDays` | `90` | 审计日志保留天数，范围 7-3650 |

OpenAPI：`GET /openapi.json`。健康检查：`GET /health`。

服务器扫描管理页面由 Razor Pages 提供：`GET /admin/login` 和 `GET /admin/scanning`。页面使用独立管理员 Cookie，并由 PageModel 直接调用扫描 Service；它不复用下述 Flutter JWT 接口，Flutter 客户端也不包含服务器扫描入口。

## 项目分层

为了后续扩展，项目按职责拆分：

| 层 | 目录 | 职责 |
| --- | --- | --- |
| Composition Root | `Program.cs` | 配置依赖注入、中间件和基础路由 |
| Endpoints | `Endpoints/` | HTTP 请求校验、认证上下文和响应映射 |
| Services | `AuthService.cs`、`Services/` | 密码哈希、JWT、Refresh Token 轮换等业务逻辑 |
| Data | `Data/` | SQLite 建表和歌单持久化 |
| Models | `Models/` | API 请求/响应 DTO |
| OpenAPI | `OpenApi/` | OpenAPI 文档生成 |
| Admin UI | `Pages/Admin/` | 管理员 Cookie 登录和服务器扫描 Razor Pages |

歌单接口依赖 `IPlaylistStore`，以后可以新增 PostgreSQL 或远程同步实现而不修改接口层；认证接口依赖 `IAuthService`，以后可以接入短信登录、第三方 OAuth 或独立认证服务。

## 认证机制

- 密码使用 PBKDF2-HMAC-SHA256、随机 16 字节盐和 210,000 次迭代保存，数据库不保存明文密码。
- Access Token 是 HS256 JWT，默认 15 分钟过期。
- Refresh Token 使用 64 字节安全随机数，只在数据库保存 SHA-256 摘要。
- 每次刷新都会轮换 Refresh Token，旧令牌立即失效。
- 检测到已使用过的 Refresh Token 时，会撤销该账号所有仍有效的 Refresh Token。
- 当前 Flutter 没有注册页，因此账号首次登录时自动创建并设置密码；之后登录必须使用同一密码。

需要认证的接口使用：

```http
Authorization: Bearer <JWT access token>
```

## 1. 登录

`POST /api/auth/login`

请求：

```json
{
  "username": "user@example.com",
  "password": "a-strong-password"
}
```

成功响应 `200`：

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "secure-random-refresh-token",
  "expiresAt": "2026-07-24T10:35:12.8206313+00:00",
  "account": {
    "remoteId": "account-user@example.com",
    "username": "user@example.com",
    "displayName": "user",
    "avatarUri": null
  }
}
```

参数为空返回 `400`；密码不正确返回 `401`：

```json
{
  "code": "invalid_credentials",
  "message": "账号或密码错误。"
}
```

## 2. 刷新令牌

`POST /api/auth/refresh`

请求：

```json
{
  "refreshToken": "登录或上次刷新返回的 refreshToken"
}
```

成功响应与登录响应一致，并返回全新的 Access Token 和 Refresh Token。客户端必须立即覆盖旧的 Refresh Token。

令牌无效、过期、已撤销或被重复使用时返回 `401`：

```json
{
  "code": "invalid_refresh_token",
  "message": "刷新令牌无效、已过期或已撤销。"
}
```

## 3. 当前账号

`GET /api/auth/me`

需要 Bearer Access Token。成功返回 `200`：

```json
{
  "account": {
    "remoteId": "account-user@example.com",
    "username": "user@example.com",
    "displayName": "user",
    "avatarUri": null
  }
}
```

JWT 签名错误、受众不匹配或已过期时返回 `401`。

## 4. 退出登录

`POST /api/auth/logout`

需要 Bearer Access Token。成功返回 `204 No Content`，同时撤销该账号的全部 Refresh Token。已签发的 Access Token 无法即时撤销，会在最多 15 分钟内自然过期；客户端应立即删除本地令牌。

## 5. 歌单同步

`POST /api/playlists/sync`

需要 Bearer Access Token。服务端以 `remoteId` 为键合并歌单，后提交的数据覆盖同 ID 旧数据，未提交的旧歌单保留。

请求：

```json
{
  "playlists": [
    {
      "remoteId": "playlist-favorites",
      "name": "Favorites",
      "updatedAt": "2026-07-24T08:00:00Z",
      "tracks": [
        {
          "uri": "file:///music/song.mp3",
          "title": "Song",
          "artist": "Artist",
          "album": "Album",
          "durationMs": 215000
        }
      ]
    }
  ]
}
```

成功响应 `200` 包含该账号合并后的 `playlists` 和 `likedTracks`。歌单缺少 `remoteId` 或 `name` 返回 `400`，未认证返回 `401`。

## 6. 定时路径扫描

所有扫描接口都需要 Bearer Access Token，并按登录账号隔离。路径是**后端所在机器能够访问的绝对目录**；Flutter 客户端只提交配置，不直接读取服务器文件系统。

支持扩展名：`mp3`、`flac`、`m4a`、`aac`、`wav`、`ogg`、`opus`、`wma`。当前版本从文件名和目录结构推导元数据：文件名作为标题、父目录作为专辑、再上一层目录作为艺术家；同时记录文件大小和最后修改时间。后续可在 `IMusicScanService` 实现中接入音频标签读取库，不影响接口层。

### 6.1 查询扫描路径

`GET /api/scan-sources/`

成功返回 `200` 和当前账号的扫描源数组。

### 6.2 创建扫描路径

`POST /api/scan-sources/`

```json
{
  "path": "F:\\Music",
  "intervalMinutes": 60,
  "enabled": true
}
```

`intervalMinutes` 范围是 `1` 至 `10080`，默认 `60`；`enabled` 默认 `true`。目录不存在或超出 `Scanning:AllowedRoots` 返回 `400`，同一账号重复添加相同路径返回 `409`。成功返回 `201`：

```json
{
  "id": "scan-source-id",
  "path": "F:\\Music",
  "intervalMinutes": 60,
  "enabled": true,
  "status": "idle",
  "trackCount": 0,
  "lastScanAt": null,
  "nextScanAt": "2026-07-24T08:00:00Z",
  "lastError": null
}
```

### 6.3 修改和删除扫描路径

- `PUT /api/scan-sources/{id}`：请求体字段与创建接口相同，字段可以省略；成功返回 `200`。
- `DELETE /api/scan-sources/{id}`：删除扫描源及其已索引曲目；成功返回 `204`。

### 6.4 立即扫描

`POST /api/scan-sources/{id}/scan`

无论定时扫描是否启用，都可以手动发起一次扫描。扫描完成返回最新的扫描源状态；单个文件无法读取时会跳过，目录级错误会写入 `lastError`，并将状态设为 `failed`。

### 6.5 查询已扫描音乐

`GET /api/scan-sources/{id}/tracks?limit=200`

`limit` 默认 `200`，最大 `1000`。每次成功扫描会新增或更新仍存在的音乐，并移除该扫描路径下本次未发现的旧记录。

后台 `ScheduledMusicScanWorker` 每隔 `Scanning:PollSeconds` 检查已启用且到期的扫描源。部署时建议配置 `Scanning:AllowedRoots`，例如：

```json
{
  "Scanning": {
    "PollSeconds": 30,
    "AllowedRoots": ["F:\\Music", "D:\\SharedMusic"]
  }
}
```

## 7. 日志审计

`GET /api/audit-logs`

需要 Bearer Access Token。接口只返回当前登录账号的日志，支持以下查询参数：

| 参数 | 说明 |
| --- | --- |
| `level` | `information`、`warning` 或 `error` |
| `eventType` | 例如 `auth.login.succeeded`、`scan.manual`、`scan.scheduled`、`http.request` |
| `search` | 在消息、事件类型、接口路径和详情中搜索 |
| `from` / `to` | ISO 8601 时间范围 |
| `page` | 页码，默认 1 |
| `pageSize` | 每页数量，默认 50，最大 100 |

响应示例：

```json
{
  "items": [
    {
      "id": "log-id",
      "username": "user@example.com",
      "level": "information",
      "eventType": "scan.scheduled",
      "message": "Scheduled scan finished with status idle.",
      "createdAt": "2026-07-24T08:00:00Z",
      "method": null,
      "path": null,
      "statusCode": null,
      "durationMs": null,
      "ipAddress": null,
      "traceId": null,
      "details": "{\"sourceId\":\"...\",\"trackCount\":12}"
    }
  ],
  "total": 1,
  "page": 1,
  "pageSize": 50
}
```

审计内容包括登录成功/失败、令牌刷新、退出登录、扫描路径变更、手动扫描、定时扫描和已认证 API 请求。密码、JWT、Refresh Token 及请求体不会写入日志。

## Flutter 客户端接入状态

仓库内 Flutter 客户端已经按以下规则接入，具体运行步骤和已知限制见 [`flutter_backend_integration.md`](flutter_backend_integration.md)：

1. 登录后保存 `token`、`refreshToken` 和 `expiresAt`。
2. API 请求使用 `token` 作为 Bearer Token。
3. Access Token 即将过期或接口返回 `401` 时，通过 `/api/auth/refresh` 刷新一次。
4. 刷新成功后同时替换两个 Token；刷新失败则清除登录状态。
5. 退出时调用 `/api/auth/logout`，随后清除本地两个 Token。
