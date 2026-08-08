# Flutter 与 Music.Api 接入说明

本文记录 Flutter 客户端与仓库内 `backend/Music.Api` 的实际接入方式、运行步骤、数据流和当前限制。最后更新：2026-08-01。

## 1. 接入范围

已完成：

- Flutter 账号页通过 HTTP 调用 `POST /api/auth/login`，不再使用进程内 Mock。
- Access Token、Refresh Token 和过期时间写入 `flutter_secure_storage`，不写入 Drift 普通设置表。
- Access Token 即将过期时主动刷新；受保护请求返回 401 时只刷新并重试一次。
- 退出登录调用 `/api/auth/logout`，即使服务不可用也会清理本地令牌和账号快照。
- 本地歌单与喜欢歌曲通过 `/api/playlists/sync` 上传，服务端返回的新歌单和能按 URI 匹配到的喜欢歌曲会写回 Drift。
- Flutter 客户端不承载服务器扫描管理；该功能位于 Music.Api 的 `/admin/scanning` Razor Pages 管理后台。
- Windows、Android、Web 共用相同 Gateway/Repository；服务地址用 `MUSIC_API_URL` 区分。

尚未完成：

- 服务器扫描结果不能直接播放。后端没有音频流、Range 请求、封面或歌词接口。
- 同步不是完整的双向冲突解决：同 `remoteId` 的歌单以本次客户端提交为准，服务端未收到的旧歌单会保留；删除传播尚未定义。
- 后端当前为方便开发采用“首次登录自动创建账号并设置密码”，不适合作为公开注册策略。
- Web 安全存储只能在 HTTPS 或 localhost 安全上下文使用；生产 Web 还应评估 HttpOnly Cookie/BFF 方案。

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

客户端使用编译期变量：

```dart
const String.fromEnvironment(
  'MUSIC_API_URL',
  defaultValue: 'http://localhost:5080',
)
```

必须在 `flutter run` 或 `flutter build` 时传入；它不是运行后可修改的设置。

| 客户端 | 开发地址示例 | 说明 |
| --- | --- | --- |
| Windows 桌面 | `http://localhost:5080` | 客户端和后端运行在同一台电脑时可直接使用默认值 |
| Web | `http://localhost:5080` | 后端已启用 CORS；Web 安全存储支持 localhost |
| Android Emulator | `http://10.0.2.2:5080` | 模拟器里的 `localhost` 指模拟器自身 |
| Android 真机 | `http://192.168.x.x:5080` | 后端需监听局域网地址，并允许防火墙端口；生产应使用 HTTPS |

Android 主 Manifest 已声明网络权限；Debug/Profile 允许明文 HTTP 以便连接本地开发服务。Release 不允许明文流量，应连接 HTTPS 服务。

## 4. 本地启动

### 4.1 启动后端

需要 .NET 10 SDK：

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
3. 登录成功后客户端自动执行一次歌单/喜欢同步。
4. 浏览器打开 `http://localhost:5080/admin/scanning`，使用后端 `Administration` 配置的独立管理员账号登录并输入后端机器可访问的绝对路径。
5. 后端 `Scanning:AllowedRoots` 非空时，路径必须位于允许根目录中。

服务器路径不是 Flutter 客户端路径。例如 Windows 客户端连接 Linux 服务器时，应填写 `/srv/music`，不能填写客户端的 `D:\Music`。

## 6. 会话与错误处理

- 登录响应中的 Access Token、Refresh Token、过期时间作为一组原子会话保存。
- 距离 Access Token 过期不足 30 秒时刷新，避免请求途中到期。
- 多个请求同时需要刷新时共享同一个刷新 Future，避免重复使用已经轮换的 Refresh Token。
- 受保护请求收到 401 后只允许刷新并重试一次，避免无限循环。
- Refresh Token 无效、过期或被撤销时清除安全存储和本地账号快照。
- Flutter HTTP 登录/刷新超时为 15 秒。
- 退出请求失败不会阻止本地退出，防止离线用户无法清除凭据。

`flutter_secure_storage` 的平台行为由操作系统决定。不要把令牌打印到日志、错误提示或截图中，也不要复制到 Drift `AppSettings`。

## 7. 同步语义

同步请求同时提交：

- 所有本地歌单及其本地曲目 URI/基础标签。
- 所有本地喜欢歌曲。

服务端以账号隔离数据，以歌单 `remoteId` 合并。首次同步的本地歌单使用稳定值 `playlist-<local-id>`，响应后保存到本地 `remoteId`。

返回数据写回规则：

- 本地没有相同 `remoteId` 的歌单时创建歌单。
- 远端歌单曲目只有在本机 Drift 能按 URI 找到同一曲目时才加入本地歌单。
- 远端喜欢歌曲同样只对本机可匹配 URI 生效；不会凭远端元数据创建一个不可播放的本地 Track。

因此跨设备使用不同文件 URI 时，歌单元数据能够出现，但曲目不一定能匹配。这需要后续设计内容指纹或服务端曲目 ID 才能可靠解决。

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

手工联调至少要覆盖：Flutter 登录成功、错误密码、重启恢复、Access Token 刷新、后端离线错误、退出、歌单同步和喜欢同步；扫描控制台还需覆盖登录、窄屏布局、路径越界、重复路径、立即扫描、启停计划、查看曲目和删除扫描源。

后端完整接口契约见 [`api.md`](api.md)。

本次接入验证结果：

| 验证 | 结果 |
| --- | --- |
| `flutter test` | 通过，9 个测试 |
| `flutter test test/http_backend_gateway_test.dart` | 通过，3 个 HTTP 契约测试 |
| `dotnet build backend/Music.Api/Music.Api.csproj --no-restore` | 通过，0 警告/0 错误 |
| `dotnet test backend/Music.Api.Tests/Music.Api.Tests.csproj --no-restore` | 通过，6 个测试 |
| 临时后端端到端烟测 | 通过：health、首次登录、同步、Refresh Token 轮换、退出 |
| `flutter analyze` | 无错误；仓库已有 6 条 info 级 lint |
| `flutter build windows` | 两次在 C++/MSBuild 静默阶段超时，未判定为通过；不是 Dart/HTTP 错误 |
