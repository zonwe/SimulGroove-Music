# SimulGroove Music API

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
| `OnlineMusic:Enabled` | `false` | 是否启用在线音乐搜索；默认关闭 |
| `OnlineMusic:SidecarBaseUrl` | `http://127.0.0.1:8080` | 仅供 Music.Api 访问的 go-music-dl sidecar 地址 |
| `OnlineMusic:AllowedSources` | `[]` | 允许搜索的规范来源 ID 白名单 |
| `OnlineMusic:RequestTimeoutSeconds` | `12` | sidecar 搜索请求超时秒数 |
| `OnlineMusic:HealthCheckTimeoutSeconds` | `3` | 就绪检查访问 sidecar 的超时秒数，运行时限制为 1–10 |
| `OnlineMusic:CircuitBreakerFailureThreshold` | `5` | 连续瞬时失败达到该次数后打开熔断，运行时限制为 2–20 |
| `OnlineMusic:CircuitBreakerBreakSeconds` | `30` | 熔断持续秒数，运行时限制为 5–300；恢复窗口仅允许一个探测请求 |
| `OnlineMusic:SearchCacheSeconds` | `60` | 相同搜索的短期缓存秒数 |
| `OnlineMusic:RequestsPerMinute` | `30` | 每账号和每 IP 的每分钟搜索上限 |
| `OnlineMusic:MaxResults` | `50` | 单次搜索允许的最大结果数，服务端上限 100 |
| `OnlineMusic:PlaybackTicketSeconds` | `300` | 账号绑定播放票据有效秒数，运行时限制为 60–300 |
| `OnlineMusic:LyricsCacheSeconds` | `900` | 歌词缓存秒数，运行时限制为 30–86400 |
| `OnlineMusic:ArtworkCacheSeconds` | `21600` | 封面缓存秒数，运行时限制为 60–86400 |
| `OnlineMusic:AssetCacheSizeBytes` | `33554432` | 歌词与封面的独立内存缓存总容量 |
| `OnlineMusic:MaxLyricsBytes` | `524288` | 单份歌词最大字节数，运行时限制为 4 KiB–2 MiB |
| `OnlineMusic:MaxArtworkBytes` | `2097152` | 单张封面最大字节数，运行时限制为 16 KiB–8 MiB |

OpenAPI：`GET /openapi.json`。存活检查：`GET /health`。就绪检查：`GET /health/ready`；在线音乐启用时该端点会探测私有 sidecar，依赖不可用时返回 `503`，功能关闭时不阻塞服务就绪。

所有请求响应都会带有 `X-Correlation-ID`。客户端可传入最多 64 个字符、仅包含 ASCII 字母、数字、点、下划线和连字符的值；其他值会被替换。该 ID 同时写入账号审计记录并转发给 sidecar，便于跨进程排障，且不包含 Token、Cookie 或上游 URL。

在线音乐 sidecar 调用使用 .NET `Meter` `FlutterMusic.OnlineMusic` 发布 `requests`、`failures`、`duration` 和 `circuit_rejections` 指标。完整指标名以 `flutter_music.online_music.sidecar.` 开头；标签仅包含低基数的规范操作名和失败类型，不包含搜索词、来源、曲目 ID、Token 或 URL。连续的 HTTP 408、429、5xx 或网络错误会触发进程内熔断；恢复窗口只允许一个探测请求。`/health/ready` 使用独立客户端绕过熔断，以便依赖恢复后仍能被就绪检查准确发现。

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

## 8. 在线音乐搜索与播放

在线搜索采用 `Flutter -> Music.Api -> go-music-dl sidecar` 的 BFF 边界。除健康检查外，公开接口需要 Bearer Access Token。Flutter 不接触 sidecar 地址、第三方 Cookie、签名参数或原始播放 URL。

部署环境必须显式审核 `OnlineMusic:Enabled`、私有 sidecar 地址和来源白名单。仓库内 `go-music-dl` clone 的集成提交 `11bfd8b` 基于上游提交 `c5a30343f12fafbad83245eee2119768a77be575` 实现了 JSON 集成契约；本地启动命令：

```powershell
go -C go-music-dl run ./cmd/music-dl integration --host 127.0.0.1 --port 8080
```

Development 配置默认启用 `netease`、`kugou`、`kuwo`。生产部署需要显式启用并设置经过验证的来源白名单：

```json
{
  "OnlineMusic": {
    "Enabled": true,
    "SidecarBaseUrl": "http://127.0.0.1:8080",
    "AllowedSources": ["实际来源 ID"]
  }
}
```

### 8.1 查询允许的来源

`GET /api/online-music/sources`

成功返回 `enabled` 和 `sources`。未认证返回 `401`。

### 8.2 搜索

`POST /api/online-music/search`

```json
{
  "query": "夜曲",
  "sources": [],
  "limit": 20,
  "cursor": null
}
```

`sources` 为空时搜索全部允许来源。成功响应包含稳定身份 `provider + trackId`、展示字段、可播放状态和来源级警告。单个来源失败时返回 `200` 且 `partial: true`；全部来源不可用返回 `503`，整体超时返回 `504`，限流返回 `429`。

### 8.3 获取播放票据

`POST /api/online-music/tracks/{source}/{trackId}/playback`

成功返回账号绑定、不可猜测的短期票据：

```json
{
  "playbackUrl": "/api/online-music/playback/opaque-ticket",
  "expiresAt": "2026-08-08T12:05:00Z",
  "mimeType": "audio/mpeg"
}
```

来源不在白名单或曲目 ID 无效返回 `400`；sidecar 不可用返回 `503`；解析超时返回 `504`。响应不包含 sidecar 私有 `streamRef` 或第三方 URL。

### 8.4 播放在线音频

`GET /api/online-music/playback/{ticket}`

请求必须继续携带签发账号的 Bearer Token，可携带 `Range: bytes=...`。服务端返回 `200` 或 `206`，只转发 `Content-Type`、`Content-Length`、`Accept-Ranges`、`Content-Range`、`ETag`。票据过期返回 `410 online_music_playback_expired`，不存在或属于其他账号统一返回 `404 online_music_playback_not_found`，无效或越界 Range 返回 `416 online_music_invalid_range`。

票据允许在有效期内发起多个 Range 请求；已经建立的流不会因票据随后到期而被主动截断。过期后的新请求必须重新获取票据。Flutter 的 Windows/Android 播放使用同一个 `MusicAudioHandler`；Web 音频元素无法可靠附加 Bearer 请求头，因此当前不显示可用播放操作。

### 8.5 获取歌词

`GET /api/online-music/tracks/{source}/{trackId}/lyrics`

请求必须携带 Bearer Token。成功返回 `{ "lyrics": "...", "format": "lrc" }`，Flutter 在播放前获取并交给现有 LRC 解析与同步歌词界面。曲目未注册、来源没有歌词或歌词为空时返回 `404 online_music_asset_not_found`；超时返回 `504`。单份歌词默认最多 512 KiB。

### 8.6 获取封面

`GET /api/online-music/tracks/{source}/{trackId}/cover`

请求必须携带 Bearer Token。成功返回经过 MIME 校验的图片字节，并附带私有缓存策略、`ETag` 和 `X-Content-Type-Options: nosniff`；客户端可用 `If-None-Match` 获取 `304`。无封面返回 `404 online_music_asset_not_found`，损坏、超限或上游失败返回稳定的 `502`。单张封面默认最多 2 MiB。

歌词与封面共享一个独立、按字节计量的内存缓存，总容量默认 32 MiB；歌词默认缓存 15 分钟，封面默认缓存 6 小时。缓存不保存第三方 Cookie、原始封面 URL 或 sidecar 私有字段。

### 8.7 下载歌曲

`GET /api/online-music/tracks/{source}/{trackId}/download`

请求必须携带 Bearer Token。API 通过私有 sidecar 下载歌曲，并在音频格式支持时优先写入封面和歌词元数据。响应头 `X-Online-Artwork-Embedded` 与 `X-Online-Lyrics-Embedded` 表示对应资源是否已成功内嵌；客户端可在值为 `false` 时将封面或同名 `.lrc` 文件保存到下载目录。当前 sidecar 没有独立的歌手照片或专辑级封面接口，封面仍按搜索结果中的歌曲标识获取。

## Flutter 客户端接入状态

仓库内 Flutter 客户端已经按以下规则接入，具体运行步骤和已知限制见 [`flutter_backend_integration.md`](flutter_backend_integration.md)：

1. 登录后保存 `token`、`refreshToken` 和 `expiresAt`。
2. API 请求使用 `token` 作为 Bearer Token。
3. Access Token 即将过期或接口返回 `401` 时，通过 `/api/auth/refresh` 刷新一次。
4. 刷新成功后同时替换两个 Token；刷新失败则清除登录状态。
5. 退出时调用 `/api/auth/logout`，随后清除本地两个 Token。
