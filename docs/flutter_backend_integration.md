# Flutter 与 Music.Api 接入说明

本文记录 Flutter 客户端与仓库内 `backend/Music.Api` 的实际接入方式、运行步骤、数据流和当前限制。最后更新：2026-09-06。

## 1. 接入范围

已完成：

- Flutter 账号页通过 HTTP 调用 `POST /api/auth/login`，不再使用进程内 Mock。
- Access Token、Refresh Token 和过期时间写入 `flutter_secure_storage`，不写入 Drift 普通设置表。
- Access Token 即将过期时主动刷新；受保护请求返回 401 时只刷新并重试一次。
- 退出登录调用 `/api/auth/logout`，即使服务不可用也会清理本地令牌和账号快照。
- 本地歌单、喜欢歌曲、均衡器预设和删除墓碑通过 `/api/playlists/sync` 双向合并，服务端返回的较新版本会写回 Drift。
- Flutter 客户端不承载服务器扫描管理；该功能位于 Music.Api 的 `/admin/scanning` Razor Pages 管理后台。
- Windows、Linux、Android、Web 共用相同 Gateway/Repository；服务地址优先从账号页保存的运行时设置读取，也可由 `MUSIC_API_URL` 提供编译期兜底。
- 在线搜索、播放票据、Range 音频代理、歌词、封面和下载都经 `Music.Api` 访问私有 sidecar；Flutter 不接触第三方 Cookie、原始资源 URL 或 sidecar 私有字段。

尚未完成：

- 服务器索引已有账号隔离且支持 Range 的流式播放接口，管理页也可直接试听；Flutter 客户端尚未提供服务器曲目浏览入口，服务器索引仍没有独立封面或歌词接口。在线音乐的 Range/封面/歌词代理是另一条独立链路。
- 本地文件跨设备匹配仍是启发式规则：先匹配完全相同的 URI，再按文件名、标题、歌手、专辑和时长寻找唯一候选；没有唯一候选时不会关联歌曲。
- 后端当前为方便开发采用“首次登录自动创建账号并设置密码”，不适合作为公开注册策略。
- Web 安全存储只能在 HTTPS 或 localhost 安全上下文使用；生产 Web 还应评估 HttpOnly Cookie/BFF 方案。
- 生产部署仍需接入指标导出与告警、配置 HTTPS 入口，并在正式发布前完成在线来源授权与第三方平台条款复核。
- Android 与 Linux 的最新构建和深度实机回归、CI 工作流首次线上运行仍待确认；iOS 与 macOS 目前仅保留平台脚手架。

## 2. 客户端结构

```text
AccountPage
    ↓ Riverpod
      BackendAuthRepository
        ↙             ↘
HttpBackendGateway   SecureAuthTokenStore
        ↓ HTTP             ↓ OS/Web 安全存储
   Music.Api          Access/Refresh/ExpiresAt
        ↓
 ASP.NET Core Services → backend SQLite / server filesystem
```

主要文件：

| 文件 | 职责 |
| --- | --- |
| `lib/core/auth/backend_gateway.dart` | 后端 DTO、异常和网关接口；定义默认服务地址 |
| `lib/core/auth/http_backend_gateway.dart` | 登录、刷新、退出、同步的 JSON/HTTP 实现和超时/错误映射 |
| `lib/core/auth/auth_token_store.dart` | 令牌安全存储抽象及 `flutter_secure_storage` 实现 |
| `lib/core/auth/auth_repository.dart` | 会话恢复、刷新去重、401 单次重试、本地 Drift 同步 |
| `lib/app/providers.dart` | 注册真实 Gateway、Token Store 和认证 Provider |
| `lib/features/account/account_page.dart` | 真实登录、退出和手动同步 UI |
| `backend/Music.Api/Pages/Admin/` | 管理员登录与服务器扫描 Razor Pages |
| `backend/Music.Api` | ASP.NET Core 10 + SQLite 后端，并托管扫描控制台 |

## 3. 后端地址配置

客户端按“账号页保存的运行时地址 → `MUSIC_API_URL` 编译期兜底”的优先级解析后端地址。仓库不内置真实服务器地址，未配置时会在账号页提示用户填写：

```dart
const String.fromEnvironment(
  'MUSIC_API_URL',
  defaultValue: '',
)
```

账号页保存的地址写入 Drift `AppSettings` 的 `backend.base_url`，下一次请求立即生效并在重启后恢复。登录页默认把地址收进「高级设置」，已保存的地址不会直接显示；只有尚未配置时地址输入框才会自动展开。编译期变量适合开发调试或预置部署地址；两者同时存在时，运行时设置优先。

| 客户端 | 开发地址示例 | 说明 |
| --- | --- | --- |
| Windows/Linux 桌面 | `http://localhost:5080` | 客户端和后端运行在同一台电脑时可使用回环地址 |
| Web | `http://localhost:5080` | 后端已启用 CORS；Web 安全存储支持 localhost |
| Android Emulator | `http://10.0.2.2:5080` | 模拟器里的 `localhost` 指模拟器自身 |
| Android 真机 | `http://192.168.x.x:5080` | 后端需监听局域网地址，并允许防火墙端口；生产应使用 HTTPS |

Android 主 Manifest 已声明网络权限；Debug/Profile 允许明文 HTTP 以便连接本地开发服务。Release 不允许明文流量，应连接 HTTPS 服务。

## 4. 本地启动

### 4.1 启动后端

需要 .NET 10 SDK：

在线音乐联调先启动默认监听本机 `8081` 端口的 sidecar：

```powershell
go -C go-music-dl run ./cmd/music-dl integration --host 127.0.0.1 --port 8081
```

再启动 API：

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

另开终端检查：

```powershell
Invoke-RestMethod http://localhost:5080/health
Invoke-RestMethod http://localhost:5080/openapi.json
```

开发数据库默认位于 `backend/Music.Api/storage/music.db`。生产环境必须覆盖开发 JWT 密钥：

```powershell
$env:Auth__JwtKey = '<至少 32 字节的随机密钥>'
```

### 4.2 启动 Flutter

Windows：

```powershell
flutter pub get
flutter run -d windows --dart-define=MUSIC_API_URL=http://localhost:5080
```

Web：

```powershell
flutter run -d chrome --dart-define=MUSIC_API_URL=http://localhost:5080
```

Android Emulator：

```powershell
flutter run -d <emulator-id> --dart-define=MUSIC_API_URL=http://10.0.2.2:5080
```

若真机访问电脑后端，后端不能只监听 loopback。仅在可信开发网络中使用：

```powershell
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://0.0.0.0:5080
flutter run -d <device-id> --dart-define=MUSIC_API_URL=http://<电脑局域网IP>:5080
```

## 5. 首次使用

1. 启动后端和 Flutter。
2. 打开“账号”，输入一个新账号和密码。开发后端会在首次登录时创建账号；后续必须使用同一密码。
3. 登录成功后客户端自动执行一次歌单、喜欢歌曲、均衡器预设和删除墓碑同步。
4. 浏览器打开 `http://localhost:5080/admin/scanning`，使用后端 `Administration` 配置的独立管理员账号登录并输入后端机器可访问的绝对路径。
5. 后端 `Scanning:AllowedRoots` 非空时，路径必须位于允许根目录中。

服务器路径不是 Flutter 客户端路径。例如 Windows 客户端连接 Linux 服务器时，应填写 `/srv/music`，不能填写客户端的 `D:\Music`。

## 6. 会话与错误处理

- 登录响应中的 Access Token、Refresh Token、过期时间作为一组原子会话保存。
- 登录响应还包含公开的账号级 `trackMatchSalt`；客户端用登录密码派生本地曲目匹配密钥，密钥与令牌一起存入系统安全存储，刷新会话时沿用，退出时清除。
- 距离 Access Token 过期不足 30 秒时刷新，避免请求途中到期。
- 多个请求同时需要刷新时共享同一个刷新 Future，避免重复使用已经轮换的 Refresh Token。
- 受保护请求收到 401 后只允许刷新并重试一次，避免无限循环。
- Refresh Token 无效、过期或被撤销时清除安全存储和本地账号快照。
- Flutter HTTP 登录/刷新超时为 15 秒。
- 退出请求失败不会阻止本地退出，防止离线用户无法清除凭据。

`flutter_secure_storage` 的平台行为由操作系统决定。不要把令牌打印到日志、错误提示或截图中，也不要复制到 Drift `AppSettings`。

## 7. 同步语义

同步请求同时提交：

- 所有本地歌单及其曲目 URI/基础标签。
- 所有本地喜欢歌曲及其更新时间。
- 所有自定义均衡器预设、10 段增益与前级增益。
- 当前账号下歌单、喜欢歌曲和均衡器预设的删除墓碑。

服务端按账号隔离数据。歌单与均衡器预设分别以 `remoteId` 为键；有内容指纹的本地歌曲使用账号内稳定的 HMAC 盲匹配令牌，喜欢歌曲优先以该令牌合并，旧记录仍兼容 URI 键。同一实体保留 `updatedAt` 较新的版本，相同时间戳保留服务端已有内容。首次同步的本地对象使用稳定的 `playlist-<local-id>` 或 `preset-<local-id>`，响应后把服务端键保存到本地。

删除也参与时间戳合并。墓碑的 `deletedAt` 不早于实体更新时间时删除生效；较新的实体可以恢复较旧的墓碑，因此离线设备不会仅因晚同步就把更新后的对象再次删除或把已删除对象意外复活。

返回数据写回规则：

- 本地没有相同 `remoteId` 的歌单或均衡器预设时创建对应对象；本地版本更新时保留本地修改，远端版本不旧于本地时写回。
- 远端本地曲目依次按 URI、在线曲目 ID、账号内唯一盲匹配令牌匹配；仍未命中时，才在本机已扫描曲目中按文件名、标题、歌手、专辑和时长寻找唯一候选。
- 无法唯一匹配的跨设备本地路径不会保存成不可播放占位歌曲，也不会错误关联到相似文件。
- 受控在线歌曲可以保存为同步占位记录，继续通过 `Music.Api` 的在线播放链路解析。
- 应用远端墓碑后，客户端会保存合并后的墓碑集合，供下一台设备继续同步。

内容 SHA-256 只保存在本地 Drift 数据库。客户端以安全存储中的账号密钥计算 `hmac-sha256:` 令牌，后端仅保存该令牌，无法从接口或数据库得到原始指纹；相同内容存在多份本机副本时仍按歧义处理。同步接口不上传或下载本地音频文件。

## 8. 服务器扫描配置

服务器扫描不出现在 Flutter 客户端导航中。Music.Api 启动后，通过同源页面管理：

```text
http://localhost:5080/admin/scanning
```

页面支持登录、创建/编辑/删除扫描源、启停计划、立即扫描和查看索引曲目。管理员身份由独立 HttpOnly Cookie 保存，不使用 Flutter 的 Access Token/Refresh Token。生产部署必须设置 `Administration__Username`、`Administration__Password`，使用 HTTPS，并继续限制允许扫描的根目录。

建议生产/共享环境限制允许根目录：

```json
{
  "Scanning": {
    "PollSeconds": 30,
    "AllowedRoots": ["F:\\Music", "D:\\SharedMusic"]
  }
}
```

扫描接口按登录账号隔离。创建扫描源后页面会立即执行首次扫描；以后可以修改周期、暂停定时扫描、手动扫描、查看索引或删除扫描源。删除会同时删除该扫描源的服务端索引。

## 9. 验证命令

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test test/http_backend_gateway_test.dart
flutter test
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
```

手工联调至少要覆盖：服务器地址保存与重启恢复、Flutter 登录成功、错误密码、Access Token 刷新、后端离线错误、退出、歌单/喜欢/均衡器预设同步、删除传播和较新修改恢复；扫描控制台还需覆盖登录、窄屏布局、路径越界、重复路径、立即扫描、启停计划、查看曲目和删除扫描源。

后端完整接口契约见 [`api.md`](api.md)。

项目验证记录（测试于 2026-09-06 复核，构建与运行时烟测沿用表中注明的最近记录）：

| 验证 | 结果 |
| --- | --- |
| `flutter analyze` | 2026-09-06 通过，0 个问题 |
| `flutter test` | 2026-09-06 通过，111 项测试 |
| `dotnet test backend/Music.Api.Tests/Music.Api.Tests.csproj --no-restore -c Release` | 2026-09-06 通过，51 项测试 |
| `flutter build web`、`flutter build windows --debug` | 最近于 2026-09-03 通过，本次文档更新未重跑 |
| 后端运行时烟测 | 最近于 2026-09-03 通过：`/health` 与 `/openapi.json` 返回 200；本地未启动 sidecar 时 `/health/ready` 返回预期的 503 |
| 尚未执行 | CI 首次线上运行、Android 构建、Linux 构建与跨平台深度手工回归 |
