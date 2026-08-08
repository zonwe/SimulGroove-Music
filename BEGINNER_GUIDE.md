# Flutter Music 初学者学习指南

这是一份从“能运行项目”到“能够独立完成一个小功能”的中文学习路线。它假设你知道最基础的编程概念，但不要求你已经熟悉 Flutter、Riverpod、Drift、音频播放或 ASP.NET Core。

如果你的目标是直接参与开发，请同时阅读根目录的 [`AGENTS.md`](AGENTS.md)。`AGENTS.md` 讲“修改项目时必须遵守什么”，本文重点讲“应该按什么顺序理解项目”。

## 1. 先建立正确预期

这是一个真实的跨平台应用，不是只有一个页面的 Flutter 教程。它同时包含：

- Flutter 响应式 UI。
- Riverpod 依赖注入与响应式状态。
- Drift/SQLite 本地数据库。
- `just_audio` 与 `audio_service` 音频播放。
- Android Kotlin 原生 MediaStore/Document Tree 桥接。
- Windows 文件系统、窗口、托盘、快捷键和 media_kit 音频后端。
- Web 的 SQLite WASM/Worker。
- ASP.NET Core + SQLite 实验性后端。

不要试图第一天读完每个文件。最有效的路线是先掌握一条完整、稳定的数据流，再逐步增加平台和后端知识。

推荐顺序：

1. 运行 UI，认识产品页面。
2. 阅读启动入口和应用壳。
3. 理解 Riverpod 如何把数据库数据送到页面。
4. 追踪“扫描一首歌进入数据库”的流程。
5. 追踪“点击歌曲开始播放”的流程。
6. 理解歌单、喜欢和设置如何持久化。
7. 最后学习 Android/Windows 平台代码和实验性后端。

## 2. 学完后你应该能够做到什么

完成本文路线后，你应该可以：

- 解释 `main.dart → ProviderScope → MusicApp → AppShell → Feature Page` 的启动关系。
- 知道页面中的歌曲列表为什么会在数据库写入后自动刷新。
- 找到本地扫描、数据库、播放队列和界面分别由哪个文件负责。
- 区分 Widget 临时状态、Riverpod 共享状态和 Drift 持久化状态。
- 理解 Android `content://` URI 与 Windows 文件路径不能用同一种方式处理。
- 修改一个页面或设置项，并添加相应测试。
- 在修改 Drift 表结构时正确写迁移并重新生成代码。
- 判断一个问题属于 Flutter UI、Provider、数据库、音频插件、平台宿主还是后端。
- 如实执行并报告格式化、分析、测试和构建结果。

## 3. 开发环境准备

### 3.1 通用工具

建议准备：

- Git。
- Flutter SDK；项目 `pubspec.yaml` 要求 Dart SDK `^3.12.2`，因此 Flutter 必须携带兼容的 Dart 版本。
- Android Studio 或 VS Code + Flutter/Dart 插件。
- 至少一个运行目标：Chrome、Windows、Android Emulator 或 Android 真机。
- 如果研究后端：.NET 10 SDK。

先检查环境：

```powershell
flutter --version
dart --version
flutter doctor -v
flutter devices
git status --short
```

看到 `flutter doctor` 的警告时，不必一次性安装所有平台工具。你只需要先把准备学习的目标平台配置好。

### 3.2 各目标平台额外要求

| 目标 | 主要要求 | 初学者建议 |
| --- | --- | --- |
| Web | Chrome/Edge | 最快看到 UI，但不能学习真实本地扫描和播放 |
| Windows | Visual Studio 的 Desktop development with C++、Windows SDK | 最适合完整观察目录扫描、播放器、窗口和托盘 |
| Android | Android SDK、模拟器或开启调试的真机 | 最适合学习权限、MediaStore 和后台音频 |
| 后端 | .NET 10 SDK | 在理解 Flutter 本地主链路后再学习 |

`ios/`、`macos/`、`linux/` 是 Flutter 脚手架，但不是当前主要交付目标。初学阶段不要因为看见这些目录就假设功能已经适配。

### 3.3 获取依赖

在仓库根目录运行：

```powershell
flutter pub get
```

项目通过 `dependency_overrides` 使用本地 `third_party/just_audio_media_kit`，因此不要随意删除 `third_party/` 或把它替换成 pub.dev 版本。Windows 音频行为可能依赖其中的本地补丁。

## 4. 第一次运行

### 4.1 Web：先认识界面

```powershell
flutter run -d chrome
```

适合观察：

- 宽屏侧栏和窄屏抽屉。
- 歌单、喜欢、音乐库、账号、设置页面。
- 浅色/深色主题和主题色。
- loading/empty 状态。

Web 当前不支持本地目录扫描与本地音乐播放，所以空音乐库是预期行为，不一定是 bug。

### 4.2 Windows：体验主要本地链路

```powershell
flutter run -d windows
```

第一次建议按下面的顺序操作：

1. 打开“音乐库”。
2. 选择一个只含少量音乐副本的测试目录，不要一开始扫描整个巨大音乐库。
3. 观察歌曲、专辑、艺术家视图。
4. 点击歌曲，观察底部迷你播放器和正在播放页。
5. 打开队列，切换歌曲、循环模式和音量。
6. 新建歌单，把歌曲加入歌单。
7. 切换主题并重启，观察设置是否保存。
8. 测试自绘标题栏、托盘和紧凑窗口。

如果 Windows 构建失败，先回到 `flutter doctor -v` 检查 Visual Studio C++ 工作负载和 Windows SDK，不要立即修改 Dart 业务代码。

### 4.3 Android：体验权限与后台播放

```powershell
flutter run -d <设备 ID>
```

可以从 `flutter devices` 复制设备 ID。Android 重点体验：

- “添加音乐文件夹”使用系统目录选择器。
- “扫描整台设备”使用媒体读取权限和 MediaStore。
- Android 13+ 的音频与通知权限。
- 应用切到后台后的通知控制。
- 锁屏、耳机和系统媒体按钮。
- 同名 `.lrc` 与内嵌歌词。

Android Emulator 访问电脑后端时，`localhost` 指向模拟器自己；通常需要使用 `10.0.2.2`。真机则需要电脑的局域网地址，并处理防火墙和明文 HTTP 策略。

## 5. 用 10 分钟认识目录

先只记住这张表：

| 你想找什么 | 从哪里开始 |
| --- | --- |
| 应用如何启动 | `lib/main.dart` |
| 主题和 `MaterialApp` | `lib/app/music_app.dart` |
| 全局依赖/响应式数据 | `lib/app/providers.dart` |
| 导航、宽窄屏和页面切换 | `lib/features/shell/app_shell.dart` |
| 数据库表和查询 | `lib/core/database/app_database.dart` |
| 本地音乐扫描 | `lib/core/library/` |
| 音频播放 | `lib/core/player/music_audio_handler.dart` |
| 音乐库 UI | `lib/features/library/library_page.dart` |
| 歌单 UI | `lib/features/playlists/` |
| 播放 UI | `lib/features/player/` |
| Android 原生扫描 | `android/app/src/main/kotlin/.../MainActivity.kt` |
| Windows 窗口/托盘 | `lib/core/window/` |
| 后端 | `backend/Music.Api/` |
| 后端接口说明 | `docs/api.md` |
| 测试示例 | `test/` |

看到下面这些目录时先跳过：

- `build/`：构建产物。
- `.dart_tool/`：Dart/Flutter 工具缓存。
- `lib/core/database/app_database.g.dart`：Drift 生成代码。
- `backend/Music.Api/bin/`、`obj/`：.NET 构建产物。
- `backend/Music.Api/storage/music.db*`：后端运行数据库。
- 平台目录中名字带 `generated` 的插件注册文件。

初学者常见错误是把大量时间花在生成代码里。你只需要知道生成代码把表定义变成了 Drift 可用的 DataClass、Companion 和查询辅助类型。

## 6. 第一条主线：应用如何启动

按顺序打开：

1. `lib/main.dart`
2. `lib/app/providers.dart`
3. `lib/app/music_app.dart`
4. `lib/features/shell/app_shell.dart`
5. `lib/features/shell/app_destination.dart`

### 6.1 `main.dart`

先理解这几个问题：

- 为什么第一行不是直接 `runApp`？
- 为什么数据库和播放器在 `ProviderScope` 中 override？
- 为什么 Windows 不走与 Android 完全相同的 `AudioService.init`？
- 哪些工作必须在首帧前完成，哪些工作可以用 `unawaited` 放到首帧后？

核心对象只有两个：

- `AppDatabase`：本地持久化事实源。
- `MusicAudioHandler`：播放状态事实源。

它们在启动时只创建一次，然后注入整个 Widget 树。这样所有页面看到的是同一个数据库和同一个播放器。

### 6.2 为什么 Provider 默认抛异常

`providers.dart` 中类似：

```dart
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);
```

这不是未完成代码，而是一种依赖注入方式：Provider 声明“项目中有一个数据库依赖”，真正实例由生产入口或测试环境提供。

因此：

- 正常应用由 `main.dart` override。
- Widget 测试必须自己 override。
- 如果你把某个页面脱离 `ProviderScope` 单独运行，会看到 `UnimplementedError`。

### 6.3 `MusicApp` 与 `AppShell`

`MusicApp` 做两件事：

1. 监听 `appearanceProvider`，构造浅色/深色主题。
2. 把 `AppShell` 设为首页。

`AppShell` 决定：

- 当前一级页面。
- 是否正在查看某个歌单详情。
- 宽屏使用侧栏，窄屏使用抽屉。
- Windows 紧凑模式是否替换成 `CompactPlayer`。
- 播放队列显示成右侧停靠面板还是其他形式。
- 返回键是离开详情、回歌单，还是退出应用。

学习练习：在纸上画出 `AppDestination` 的七个目的地，然后在运行中的应用里逐个找到它们。

## 7. 第二条主线：数据为什么会自动刷新 UI

按顺序阅读：

1. `lib/core/database/app_database.dart`
2. `lib/app/providers.dart`
3. `lib/features/playlists/playlists_page.dart`
4. `test/playlists_page_test.dart`

### 7.1 Drift 表、DataClass 和 Companion

以 `Tracks` 为例：

- `Tracks extends Table` 是表结构。
- 生成的 `Track` 是从数据库读取的一行数据。
- `TracksCompanion` 用于插入或部分更新。
- `Value(...)` 区分“把字段写成 null”和“本次不修改字段”。

数据库主要关系：

```text
Tracks ─────< PlaylistEntries >───── Playlists
   │
   └────────< LikedTracks

ScanSources  描述 Tracks 的本地来源
Accounts     可关联同步后的 Playlists/Tracks
AppSettings  保存主题、托盘、快捷键等键值
```

`PlaylistEntries` 的主键是 `(playlistId, trackId)`，所以同一首歌不能重复加入同一歌单。外键配置级联删除，删除歌单或歌曲时关系行会一起清理。

### 7.2 `watch` 与 `Future` 的区别

```dart
Stream<List<Track>> watchTracks()
Future<List<Track>> allTracks()
```

- `allTracks()` 是一次快照。
- `watchTracks()` 会持续发出新结果。

`tracksProvider` 把数据库的 Stream 包成 Riverpod `StreamProvider`。页面 `ref.watch(tracksProvider)` 后，扫描器写入歌曲会触发 Drift Stream，Riverpod 再使页面重建。这就是“数据库写完，列表自动出现”的完整解释。

### 7.3 `AsyncValue` 的四种用户体验状态

页面不应只考虑成功数据：

- loading：数据库/网络还没返回。
- error：查询失败。
- empty：成功返回，但列表为空。
- data：有实际内容。

阅读 `playlists_page.dart` 后，再看 `playlists_page_test.dart`，观察测试如何 override Provider 来构造不同状态。

学习练习：给某个列表的错误状态加一个“重试”按钮，并写 Widget 测试验证按钮存在。先不碰音频和平台代码。

## 8. 第三条主线：一首本地歌曲如何进入音乐库

按顺序阅读：

1. `lib/core/library/library_scanner.dart`
2. `lib/core/library/scanner_factory.dart`
3. `lib/core/library/scanned_track.dart`
4. `lib/core/library/library_scanner_stub.dart`
5. `lib/core/library/library_scanner_io.dart`
6. `lib/features/library/library_page.dart` 中 `_scan`、`_rescanAll`、`_toCompanion`
7. Android 学习者再读 `MainActivity.kt`

### 8.1 先理解接口，不急着看 300 行实现

`LibraryScanner` 只告诉上层：

- 当前平台是否支持扫描。
- 是否支持扫描整台设备。
- 按钮应该显示什么。
- 如何新增扫描、整机扫描和重新扫描一个来源。

页面只依赖接口，所以页面不需要知道 Android 是 MethodChannel，Windows 是目录选择器。

### 8.2 条件导出是 Web 能编译的关键

```dart
export 'library_scanner_stub.dart'
    if (dart.library.io) 'library_scanner_io.dart';
```

浏览器没有 `dart:io`。如果公共文件直接 import `dart:io`，哪怕代码用 `if (!kIsWeb)` 包住，Web 编译也可能失败。条件导出让编译器在不同平台看到不同实现。

项目中的窗口、音源、文件可用性、封面缓存和启动清理也使用类似模式。这是本项目最值得掌握的跨平台技巧之一。

### 8.3 Windows 扫描流程

```text
点击“添加音乐文件夹”
  → DirectoryPicker 选择目录（UI isolate）
  → Isolate.run 执行递归遍历和元数据解析
  → audio_metadata_reader 读取标题/艺术家/专辑/时长/封面/歌词
  → 查找同名 .lrc
  → 生成稳定 UUID v5
  → 返回 ScanResult
  → 页面转成 TracksCompanion
  → AppDatabase.upsertTracks
  → tracksProvider 自动发出新列表
```

为什么用 isolate？目录遍历和同步元数据解析可能很慢，如果全在 UI isolate 执行，动画和输入会卡住。

### 8.4 Android 扫描流程

有两种来源：

- 用户授权目录：Storage Access Framework 的 Document Tree，URI 常以 `content://` 开头。
- 整台设备：MediaStore，来源 URI 使用项目约定的 `media-store://external`。

Dart 通过 MethodChannel 调用 Kotlin：

- `pickAudioDirectory`
- `scanAudioTree`
- `scanAudio`

Kotlin 负责访问 Android API、读取元数据和压缩封面，再把 Map 列表返回 Dart。Dart 把它映射成 `ScannedTrack`。

不要把 `content://` URI 当作普通文件路径。它代表由 ContentResolver 管理的资源，权限和生命周期都与 Windows 路径不同。

### 8.5 为什么扫描 ID 必须稳定

如果每次扫描使用随机 UUID，同一首歌重扫后会变成另一行：

- 歌单关系可能失效。
- 喜欢状态会丢失。
- 数据库会积累重复歌曲。

所以项目使用 UUID v5：相同规范化路径或 URI 得到相同 ID。

### 8.6 重新扫描为什么比新增扫描危险

新增扫描主要是 upsert。重新扫描还要删除“本次已经不存在”的旧曲目。来源匹配条件写错可能删除其他目录的歌曲。

学习时重点阅读 `replaceScanSourceTracks`：

- 它先把本次 URI 放进集合。
- 找出属于当前来源但不在新集合里的旧曲目。
- 在事务内删除旧曲目并 upsert 新曲目。

练习时不要直接对重要音乐库数据库测试删除逻辑，使用小型临时目录或内存数据库。

## 9. 第四条主线：点击歌曲后如何播放

按顺序阅读：

1. `lib/features/library/library_page.dart` 中歌曲 `onTap`
2. `lib/features/player/playback_navigation.dart`
3. `lib/core/player/music_audio_handler.dart`
4. `lib/core/player/local_audio_source.dart` 及 IO/stub 实现
5. `lib/features/player/mini_player_bar.dart`
6. `lib/features/player/now_playing_page.dart`
7. `lib/features/player/queue_sheet.dart`

### 9.1 播放器的唯一事实源

项目只应有一个 `MusicAudioHandler`。它内部持有一个 `just_audio.AudioPlayer`，并通过 `audio_service` 把状态同步给：

- Flutter 正在播放页。
- 底部迷你播放器。
- 播放队列。
- Android 系统通知和锁屏。
- 耳机/系统媒体控制。
- Windows 托盘和桌面快捷键。

如果每个页面自己创建播放器，这些入口会互相冲突。因此页面通过 `audioHandlerProvider` 获取同一个实例。

### 9.2 `Track`、`MediaItem` 与 `AudioSource`

三个模型职责不同：

- `Track`：数据库中的歌曲记录。
- `MediaItem`：`audio_service` 用于系统媒体展示的歌曲信息。
- `AudioSource`：`just_audio` 真正要加载的播放源。

`playTracks` 会把整组 `Track` 转为 `MediaItem` 和 `AudioSource`，设置队列和起始索引，然后调用 `play()`。

Windows 本地歌曲优先从 `filePath` 构造 `Uri.file`。Android 更常播放 `content://` URI。这个差异被隔离在 `local_audio_source_io.dart`。

### 9.3 页面如何响应播放状态

`MusicAudioHandler` 暴露多个流：

- 当前位置。
- 总时长。
- 播放/暂停状态。
- 音量。
- 当前索引。

同时从 `BaseAudioHandler` 得到 `queue`、`mediaItem`、`playbackState`。Widget 使用 `StreamBuilder`/`ValueListenable` 等方式展示。

学习练习：选择一首两分钟左右的测试音频，在断点中观察：

1. `playTracks` 收到的列表和 `initialIndex`。
2. `_toMediaItem` 生成的 `extras`。
3. `_updateCurrentItem` 更新当前歌曲。
4. `_broadcastState` 在播放/暂停时发布的 controls。

### 9.4 歌词链路

扫描阶段读取歌词文本，保存在 `Tracks.lyrics`。播放时放入 `MediaItem.extras`，正在播放页用 `lrc_parser.dart` 解析时间标签，并根据 position 高亮当前行。

这是很适合初学者的纯逻辑模块。先阅读 `test/lrc_parser_test.dart`，再尝试添加以下测试：

- 一行多个时间标签。
- 毫秒位数不同。
- 无效行被忽略。
- 相同时间的排序。
- 只有纯文本、没有时间标签。

## 10. 第五条主线：歌单、喜欢和设置

### 10.1 歌单

阅读顺序：

1. `playlists_page.dart`
2. `playlist_detail_page.dart`
3. `app_database.dart` 的歌单方法

主要操作：

- 新建/删除 `Playlists`。
- 用 `PlaylistEntries` 添加/移除歌曲。
- `position` 维护歌单顺序。
- 修改本地歌单后把 `syncState` 标为 `local`。
- `watchPlaylistTracks` join 两张表并持续输出结果。

歌单详情同时涉及 Sliver、响应式布局和播放器，是中级阅读材料。第一次不要从 400 多行页面顶部逐行读到底，先搜索 `watchPlaylistTracks`、`playTracks`、`removeTrackFromPlaylist`，围绕行为阅读。

### 10.2 喜欢

`LikedTracks` 只保存 `trackId` 和时间。真正展示歌曲信息时 join `Tracks`。这样不会重复存储标题、艺术家和封面。

注意外键级联：删除歌曲后，对应喜欢关系自动删除。

### 10.3 设置与主题

阅读：

- `lib/core/theme/app_appearance.dart`
- `lib/app/music_app.dart`
- `lib/features/placeholders/settings_page.dart`
- `test/app_appearance_test.dart`

设置以字符串键值保存在 `AppSettings`。`appearanceProvider` 监听整张设置表，再映射成类型安全的 `AppAppearance`。`MusicApp` watch 它，因此切换主题会立即重建主题。

适合第一个独立任务：新增一个纯 UI 设置项，完成“定义 key → 读取默认值 → 页面修改 → 数据库保存 → 重启仍生效 → 单元测试映射”的闭环。

## 11. 第六条主线：账号与后端，最后再学

这里最重要的是分清本地 Drift 事实源、客户端认证会话和后端 SQLite 三者的职责。

### 11.1 当前账号页使用真实 HTTP 后端

阅读：

- `lib/core/auth/backend_gateway.dart`
- `lib/core/auth/http_backend_gateway.dart`
- `lib/core/auth/auth_token_store.dart`
- `lib/core/auth/auth_repository.dart`
- `lib/features/account/account_page.dart`

`HttpBackendGateway` 负责 JSON/HTTP 契约，`BackendAuthRepository` 负责会话生命周期和本地同步，`SecureAuthTokenStore` 通过平台安全存储保存 Access Token、Refresh Token 和过期时间。页面只调用 Repository，不直接读写令牌。

Access Token 即将到期或请求返回 401 时，Repository 会执行一次 Refresh Token 轮换；刷新失败会清理本地登录状态。后端地址由 `MUSIC_API_URL` 编译期变量配置。

### 11.2 ASP.NET Core 后端

后端位于 `backend/Music.Api`，建议按以下顺序阅读：

1. `backend/README.md`
2. `docs/api.md`
3. `Program.cs`
4. `Endpoints/AuthEndpoints.cs`
5. `Services/Auth/IAuthService.cs` 与 `AuthService.cs`
6. `Data/` 中的接口和 SQLite 实现
7. `Endpoints/ScanSourceEndpoints.cs`
8. `Services/Scanning/`
9. `Middleware/AuditLogMiddleware.cs`

启动命令：

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

检查健康状态：

```powershell
Invoke-RestMethod http://localhost:5080/health
```

不要把示例 JWT 密钥用于生产。真实环境应通过 `Auth__JwtKey` 提供至少 32 字节随机密钥。

### 11.3 服务器扫描不是客户端扫描

两者名字相似，但完全不同：

| 本地音乐扫描 | 服务器路径扫描 |
| --- | --- |
| Android/Windows 客户端读取自己的文件 | ASP.NET 服务读取服务器机器的文件 |
| 写入 Flutter 本地 Drift 数据库 | 写入后端 SQLite |
| 使用目录选择器/MediaStore | 使用后端配置的绝对路径 |
| 不需要 HTTP | 需要认证 HTTP API |

`lib/core/scanning/remote_scan_repository.dart` 与 `lib/features/scanning/remote_scan_page.dart` 已经接入认证会话、Provider 和“服务器扫描”一级导航。扫描结果目前只用于查看服务端索引，不等于客户端已经能流式播放服务器文件。

### 11.4 学习真实认证时要关注什么

- 密码只在传输时出现，数据库保存 PBKDF2 哈希而非明文。
- Access Token 生命周期短，用于请求认证。
- Refresh Token 用于换新令牌，并且每次刷新轮换。
- Refresh Token 在数据库只保存摘要。
- 重复使用旧 Refresh Token 会触发更广泛撤销。
- 客户端安全存储、自动刷新、401 单次重试和退出清理必须一起设计。
- 普通 Drift 设置表不是敏感 Refresh Token 的理想存储位置。

## 12. 推荐的四阶段学习计划

时间可以按你的基础拉长，不必严格按天。

### 阶段一：会运行、会找文件（1～2 天）

目标：认识页面和 Flutter 基础 Widget。

任务：

1. 跑起 Web 或 Windows。
2. 阅读 `main.dart`、`music_app.dart`、`app_shell.dart`。
3. 给一个占位页改文案和图标。
4. 在窄屏和宽屏分别观察布局。
5. 学会 Hot Reload、Hot Restart 和完整重启的区别。

验收：你能指出一级导航从哪里定义、页面从哪里映射、主题从哪里生成。

### 阶段二：会读响应式数据（2～4 天）

目标：理解 Riverpod + Drift。

任务：

1. 阅读 Provider 与数据库表。
2. 在歌单页为 empty 状态加一段辅助说明。
3. 修改/新增 Widget 测试。
4. 写一个纯 Dart 测试扩展 LRC 解析覆盖。
5. 使用 DevTools 观察 Widget 重建。

验收：你能解释 `watchPlaylists → playlistsProvider → ref.watch → AsyncValue`。

### 阶段三：掌握核心业务链路（4～7 天）

目标：理解扫描、播放、歌词、歌单。

任务：

1. 用小目录完成一次 Windows 或 Android 扫描。
2. 在 `_scan`、`upsertTracks`、`playTracks` 设置断点。
3. 画出扫描与播放数据流。
4. 实现一个小功能，例如歌曲时长格式化测试、列表排序选项或更好的空状态。
5. 完成分析、测试和目标平台运行验证。

验收：你能从一次点击追踪到平台文件，再回到数据库和 UI；也能从歌曲点击追踪到系统音频。

### 阶段四：平台与后端（1～2 周）

目标：理解跨平台边界和客户端/服务端分工。

任务：

1. 阅读条件导出模式。
2. 对比 Android `content://`、Windows `file://` 和 Web 不支持分支。
3. 阅读 Kotlin MethodChannel。
4. 启动后端并调用 health/OpenAPI。
5. 用 `FlutterMusic.Api.http` 或 PowerShell 手工走一遍登录和认证接口。
6. 为后端写第一个测试，而不是直接大改认证。

验收：你能说明新增一个平台功能时为什么需要公共 API、IO 实现和 stub，也能说明本地扫描与服务器扫描的区别。

## 13. 推荐练习清单

按风险从低到高选择，不要一次做多个。

### 入门练习 A：改进空状态

范围：一个 Feature 页面。

要求：

- 空状态有标题、说明和下一步按钮。
- 窄屏不溢出。
- 深色主题颜色正常。
- 添加 Widget 测试。

你会学到：Widget 组合、主题、测试查找器和 Provider override。

### 入门练习 B：扩展 LRC 测试

范围：`lrc_parser.dart` 和测试。

要求：

- 先写失败测试。
- 再做最小实现。
- 不依赖 Flutter 插件或真实音频。

你会学到：纯函数、边界条件和快速反馈。

### 初级练习 C：增加歌曲排序方式

范围：音乐库 UI，必要时增加纯排序函数。

要求：

- 支持标题、艺术家或时长排序。
- 搜索与歌曲/专辑/艺术家视图不被破坏。
- 排序控件在窄屏可用。
- 排序逻辑有单元测试。

你会学到：局部状态、派生数据和大页面中的逻辑抽取。

### 初级练习 D：新增持久化设置

示例：是否显示未知艺术家歌曲。

要求：

- 定义稳定设置 key。
- 默认值明确。
- 重启保留。
- Provider 类型安全。
- 有模型/映射测试。

你会学到：Drift 键值设置、StreamProvider 和应用重建。

### 中级练习 E：数据库查询测试

范围：`AppDatabase.forTesting`。

要求：

- 使用内存数据库。
- 插入歌曲和歌单。
- 验证重复加入同一歌单的行为。
- 验证删除歌曲后的歌单关系和喜欢关系。
- 每个测试关闭数据库。

你会学到：Drift Companion、外键、事务和测试隔离。

### 中级练习 F：扫描错误摘要

范围：扫描器模型、页面与测试。

要求：

- 单个损坏文件不终止整次扫描。
- 扫描结果能告诉用户跳过了多少文件。
- 不在 UI isolate 做重元数据解析。
- Android/Windows/stub API 一致。

你会学到：跨平台接口演进、降级策略和用户反馈。

### 高级练习 G：强化真实后端认证

只有在前面路线完成后再做。

要求至少覆盖：

- HTTP Gateway。
- Access/Refresh Token 模型。
- 安全存储。
- 启动恢复。
- 过期前刷新和 401 单次重试。
- 并发请求只触发一次刷新。
- 退出撤销和本地清理。
- Gateway、令牌存储与 Repository 可用测试替身替换。
- 单元、集成和错误状态测试。

这不是“把登录按钮接到一个 URL”这么简单，应拆成多个小 PR/任务。

## 14. 如何阅读一个大文件

`library_page.dart`、`now_playing_page.dart`、`playlist_detail_page.dart` 和 `remote_scan_page.dart` 都比较大。不要逐字线性阅读，使用下面的方法：

1. 先看 import，判断它依赖哪些层。
2. 搜索顶级 `class`、`enum`、`Future<void>` 和 Provider 名称。
3. 找 `build`，只理解页面骨架。
4. 找用户交互入口：`onPressed`、`onTap`、`onChanged`。
5. 跟进被调用的私有异步方法。
6. 找 `ref.watch`，确认页面读了哪些事实源。
7. 找 `ref.read` 和数据库方法，确认写操作。
8. 最后看私有小组件和样式细节。

常用命令：

```powershell
rg -n "class |enum |ref\.watch|ref\.read|Future<void>|onPressed:|onTap:" lib/features/library/library_page.dart
rg -n "watchTracks|upsertTracks|replaceScanSourceTracks" lib
rg -n "playTracks|playbackState|mediaItem|queue" lib
```

这种“围绕行为搜索”的方式比从第一行看到最后一行更容易建立结构。

## 15. 调试方法

### 15.1 先判断问题属于哪一层

| 现象 | 优先检查 |
| --- | --- |
| 页面不显示数据 | Provider loading/error、数据库 watch 查询、Provider override |
| 扫描按钮没反应 | 页面 busy 状态、`LibraryScanner.isSupported`、权限/目录选择器 |
| 扫描完成但没歌曲 | `ScanResult`、`TracksCompanion`、唯一 URI、数据库写入 |
| 重扫后误删/重复 | 稳定 ID、来源匹配、`replaceScanSourceTracks` |
| 点击歌曲无声音 | URI/filePath、AudioSource、格式解码、播放器异常 |
| UI 显示的歌曲与声音不一致 | queue、currentIndex、mediaItem 更新 |
| Android 后台控制失败 | `audio_service` 初始化、Manifest service、音频会话 |
| Windows 启动/播放失败 | media_kit 初始化、本地 override、CMake/原生依赖 |
| Web 编译报 `dart:io` | 条件导出/导入边界 |
| 主题重启丢失 | AppSettings 写入、appearanceProvider、默认值 |
| 后端 401 | Bearer Token、过期时间、刷新流程、issuer/audience/key |
| 模拟器连不上电脑后端 | `10.0.2.2`、端口监听、防火墙、CORS/HTTP |

### 15.2 推荐断点

- `main.dart`：数据库和播放器构造后。
- `library_page.dart`：`_scan` 收到 `ScanResult` 后。
- `app_database.dart`：`upsertTracks` 和 `replaceScanSourceTracks`。
- `music_audio_handler.dart`：`playTracks`、`_updateCurrentItem`、`_broadcastState`。
- `lrc_parser.dart`：解析每行时间标签的位置。
- `auth_repository.dart`：`signIn`、`syncNow` 和会话恢复。
- 后端 `AuthEndpoints`：请求校验后。
- 后端 `MusicScanService`：路径验证和扫描开始处。

### 15.3 Hot Reload 不是万能的

- 改普通 Widget 样式：通常 Hot Reload。
- 改 Provider 初始化、顶级常量或状态构造：可能需要 Hot Restart。
- 改 `main.dart` 初始化、原生 Kotlin/C++、Manifest、插件、依赖：完整停止并重新运行。
- 改 Drift 表结构：重新生成代码，并考虑清理测试数据库或验证迁移；不能只 Hot Reload。

## 16. 测试与质量检查

### 16.1 日常命令

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

修改后端时：

```powershell
dotnet build backend/Music.Api/Music.Api.csproj
```

修改平台边界、依赖或初始化时，再做相应构建：

```powershell
flutter build web
flutter build windows
flutter build apk --debug
```

### 16.2 当前测试能教你什么

- `lrc_parser_test.dart`：最简单的纯 Dart 输入/输出测试。
- `app_appearance_test.dart`：设置 Map 到领域模型的映射测试。
- `playlists_page_test.dart`：Riverpod Provider override 与 Widget 状态测试。

推荐按这个顺序读测试，正好对应从纯逻辑到 Provider/Widget 的难度增长。

### 16.3 如何描述验证结果

只使用准确措辞：

- “`flutter test` 通过”：命令结束且退出码为 0。
- “未运行”：时间或环境不允许。
- “超时”：命令没有在限制内结束，不能算通过。
- “失败”：列出与本次改动相关的首要错误。
- “基线已有失败”：修改前已复现，并说明本次是否新增错误。

工具卡住时先检查遗留 Dart/Flutter 进程、SDK 状态和依赖获取，不要未经判断就删除用户缓存、数据库或整个构建目录。

## 17. 初学者最常见的坑

### 坑 1：在页面里复制数据库数据长期保存

后果：数据库更新了，页面自己的 List 没更新。

做法：能由 Provider/数据库派生的数据就从事实源派生；页面只保存搜索词、选中项、展开状态等临时 UI 状态。

### 坑 2：`ref.read` 和 `ref.watch` 用反

- `build` 中需要响应变化：`watch`。
- 点击事件中执行一次动作：`read`。
- 在 `build` 中 `read` 一个会变化的数据，UI 不会自动刷新。

### 坑 3：只写成功状态

数据库、扫描、网络都有 loading、empty 和 error。只写 data 状态会让失败时页面空白或一直可重复提交。

### 坑 4：`await` 后直接 `setState`

用户可能在异步任务期间离开页面。先检查 `mounted`，否则可能出现 “setState called after dispose”。

### 坑 5：手改 `app_database.g.dart`

下次生成会覆盖。表和查询改 `app_database.dart`，然后运行 build_runner。

### 坑 6：改表不写迁移

新安装可能正常，老用户升级会崩。必须提升 schema 版本并写从旧版本到新版本的迁移。

### 坑 7：把所有 URI 当文件路径

- Windows 常见绝对路径和 `file://`。
- Android 常见 `content://`。
- 后端扫描的是服务器绝对路径。

三者权限、打开方式和生命周期完全不同。

### 坑 8：只验证当前桌面宽度

页面在 1280 像素正常，不代表手机宽度或文本缩放正常。至少检查一个宽屏和一个窄屏。

### 坑 9：以为能扫描就一定能播放

扩展名过滤只决定文件是否进入库；真正能否播放还取决于平台解码器和音频后端。

### 坑 10：把开发后端当成完整生产认证

账号页已接入仓库内后端，但“首次登录自动创建账号”、开放 CORS 和本地 HTTP 都是开发期策略。生产仍需要正式注册/找回、HTTPS、限流和更严格的 Web 会话设计。

### 坑 11：随意升级音频依赖

音频、后台服务和平台插件耦合度高，且 Windows 使用本地 vendored adapter。升级前要阅读 changelog，并在播放、队列、系统控制和多个平台上验证。

### 坑 12：清理脏工作区

仓库里可能有用户尚未提交的实验改动。不要使用破坏性 Git 命令或整体覆盖文件；先看 `git status` 和 diff，只修改任务需要的范围。

## 18. Dart/Flutter 知识补课清单

如果阅读卡住，按需学习，不必先学完整本书。

### Dart

- null safety：`T?`、`!`、`?.`、`??`。
- `Future`、`async`/`await`、异常。
- `Stream` 与订阅。
- collection `map`、`where`、展开和集合字面量。
- sealed/switch pattern 的现代语法。
- extension、mixin、abstract interface class。
- isolate 与主 isolate 的限制。

### Flutter

- StatelessWidget 与 StatefulWidget。
- Widget、Element、State 的基本关系。
- `BuildContext` 和 `mounted`。
- LayoutBuilder、Flex、Expanded、Wrap、Sliver。
- Navigator、Dialog、BottomSheet。
- ThemeData、ColorScheme 和 Material 3。
- Widget test、pump 与 finder。

### Riverpod

- ProviderScope 与 override。
- Provider、StreamProvider、AsyncValue。
- ConsumerWidget、ConsumerStatefulWidget。
- `ref.watch`、`ref.read`、`ref.invalidate`。
- Provider 依赖图和可测试替换。

### Drift/SQLite

- Table、DataClass、Companion。
- select/update/delete 和 where。
- Stream query。
- join、外键、唯一约束。
- transaction、batch。
- schema version、migration、generated code。

### 平台与音频

- MethodChannel。
- Android MediaStore、Storage Access Framework、运行时权限。
- URI 与文件路径。
- `just_audio` 播放器状态。
- `audio_service` 后台媒体会话。
- Windows 插件和 CMake 构建的基本概念。

### 后端

- ASP.NET Core Minimal API。
- 依赖注入。
- HTTP 状态码和 JSON DTO。
- JWT、Refresh Token、密码哈希。
- SQLite 参数化查询与事务。
- BackgroundService。

## 19. 项目术语表

| 术语 | 在本项目中的含义 |
| --- | --- |
| Track | Drift 中一首本地或同步歌曲记录 |
| ScannedTrack | 扫描器刚产出的、尚未写入数据库的歌曲模型 |
| MediaItem | 提供给 audio_service 和系统媒体 UI 的歌曲信息 |
| AudioSource | just_audio 实际加载的音频来源 |
| ScanSource | Flutter 本地数据库记录的目录/MediaStore 来源 |
| RemoteScanSource | 后端服务器要定时扫描的绝对路径配置 |
| Provider | Riverpod 中提供对象或响应式数据的节点 |
| AsyncValue | Riverpod 对 loading/error/data 的统一包装 |
| Companion | Drift 用于插入或部分更新的对象 |
| HTTP Backend | 仓库内 ASP.NET Core 账号、同步和服务器扫描服务 |
| Audio Handler | 对播放器队列、状态和系统控制的统一封装 |
| Stub | 不支持平台上的安全替代实现，用来保持编译通过 |
| Vendored dependency | 复制到仓库并由项目直接维护/覆盖的第三方依赖 |

## 20. 遇到问题时的提问模板

高质量问题会显著加快排查。可以按下面格式记录：

```text
目标：我想让……
平台：Windows / Android 版本 / Web
操作步骤：1. … 2. … 3. …
预期：……
实际：……
完整错误的第一处：……
我已经检查：flutter doctor / analyze / test / 权限 / URI / Provider 状态
相关文件：……
是否能稳定复现：……
```

不要只说“不能运行”。至少提供目标平台、命令、第一段有意义的错误和你修改过的文件。

## 21. 第一次贡献前自检

- [ ] 我能在一个目标平台运行项目或清楚记录环境阻塞。
- [ ] 我读过 `main.dart`、`providers.dart`、`app_shell.dart`。
- [ ] 我知道本次修改的数据事实源在哪里。
- [ ] 我没有手改生成文件。
- [ ] 我检查了 `git status --short`，没有覆盖别人改动。
- [ ] 我处理了 loading、empty、error 和 data。
- [ ] 我在异步回调后检查了 `mounted`。
- [ ] 我考虑了 Web 与 IO 平台隔离。
- [ ] 如果改数据库，我写了版本迁移并重新生成代码。
- [ ] 如果改 API，我同步更新了接口文档。
- [ ] 我运行了与改动风险相称的测试/构建，并准确记录结果。

## 22. 最推荐的第一个完整任务

如果你不知道从哪里开始，建议选择“改进一个空状态并补 Widget 测试”：

1. 选 `PlaylistsPage` 或 `FavoritesPage`。
2. 运行现有页面，截图或记下空状态。
3. 阅读页面如何 watch Provider。
4. 设计一个不依赖新数据库字段的改进。
5. 在测试中 override Provider 返回空列表。
6. 先写/修改测试，再改 UI。
7. 检查浅色、深色、宽屏和窄屏。
8. 运行目标测试、`flutter analyze`，最后再运行全量测试。

这个任务足够小，却会让你走完“读代码 → 理解状态 → 修改 UI → 写测试 → 验证”的完整开发循环。完成后再进入排序、持久化设置、数据库查询、扫描或音频功能，学习曲线会平滑很多。
