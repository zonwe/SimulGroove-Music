# Flutter Music 项目协作指南

本文是仓库根目录级别的开发与智能体协作说明，适用于整个仓库。无论是人类开发者还是自动化编码智能体，在修改代码前都应先阅读本文件。面向第一次接触项目的学习路线见 [`BEGINNER_GUIDE.md`](BEGINNER_GUIDE.md)。

## 1. 项目目标与当前边界

Flutter Music 是一个面向 Android、Windows 和 Web 的私人本地音乐播放器。核心目标是提供接近 Groove Music 的本地音乐体验，同时为账号、同步和服务器音乐目录扫描保留清晰的扩展边界。

当前主要能力：

- Android：授权目录或扫描整台设备、读取 MediaStore/Document Tree、后台播放、媒体通知、锁屏和耳机控制。
- Windows：递归扫描本地目录、读取音频元数据、桌面快捷键、系统托盘、自绘标题栏和紧凑悬浮播放器。
- Web：响应式界面、Drift Web 数据库、真实后端账号和在线搜索；不支持本地目录扫描与本地音乐播放。
- 通用功能：歌曲/专辑/艺术家视图、搜索、封面、歌词、播放队列、歌单、喜欢、主题外观和设置持久化。
- 实验性后端：`backend/Music.Api` 提供 ASP.NET Core + SQLite 的认证、歌单同步、服务器目录扫描和审计日志接口。

以下内容尚未视为完整产品能力：

- Flutter 账号页通过 `HttpBackendGateway` 连接真实后端，令牌由安全存储保存；修改认证时必须继续保持刷新轮换和 401 单次重试。
- 服务器扫描管理位于 `backend/Music.Api/Pages/Admin/` Razor Pages，不放入 Flutter 客户端；扫描的是后端机器目录，结果目前只供查看，尚不能直接播放。
- 在线搜索、歌词/封面与 Windows/Android 在线播放已通过 `Music.Api` 接入受控 sidecar 契约；播放使用账号绑定短期票据与 Range 代理，Web 因认证请求头限制暂不开放在线播放；听歌识曲仍是占位页。
- Web 本地文件扫描和播放未实现。
- `ios/`、`macos/`、`linux/` 保留 Flutter 平台脚手架，但不是 README 声明的主要交付目标。涉及这些平台时必须单独验证，不能根据 Android/Windows 的结果推断可用。

## 2. 修改前必须做的事

1. 运行 `git status --short`，识别用户已有改动。仓库可能处于脏工作区；未明确授权时，不得覆盖、回退、格式化或删除无关改动。
2. 阅读与任务最接近的入口文件，再沿 import、Provider、数据库方法和平台实现向下追踪。不要只改 UI 表象而忽略数据与平台层。
3. 确认目标平台。涉及 `dart:io`、音频、文件系统、窗口、托盘、快捷键或 Android 原生代码时，平台差异属于功能设计的一部分。
4. 建立验证基线。至少记录准备运行的分析/测试命令；如果基线本来失败，应区分“已有失败”和“本次引入的失败”。
5. 优先做最小闭环改动。不要把一个局部需求扩展成无关的架构重写、依赖升级或生成文件清理。

## 3. 仓库地图

| 路径 | 职责 | 修改提示 |
| --- | --- | --- |
| `lib/main.dart` | 进程启动、音频后端、数据库、窗口/托盘/快捷键初始化、Provider 覆盖 | 启动顺序敏感；异步初始化必须发生在 `runApp` 前还是后需要明确判断 |
| `lib/app/` | `MaterialApp`、主题和全局 Riverpod Provider | `databaseProvider`、`audioHandlerProvider` 必须由根部覆盖 |
| `lib/core/database/` | Drift 表定义、迁移、查询和持久化操作 | 修改表结构后更新版本、迁移并重新生成代码 |
| `lib/core/library/` | 本地音乐扫描抽象、Android/Windows 实现和扫描模型 | 保持 Web/不支持平台的 stub 可编译 |
| `lib/core/player/` | `just_audio`/`audio_service` 播放器、队列、平台音源和封面缓存 | 不要让 Widget 直接持有第二个 `AudioPlayer` |
| `lib/core/lyrics/` | LRC 解析 | 适合优先写纯 Dart 单元测试 |
| `lib/core/theme/` | 外观设置模型 | 设置最终保存在 Drift `AppSettings` 表中 |
| `lib/core/window/` | Windows 窗口、托盘和拖动区域，含平台 stub | Web 构建依赖条件导出隔离 `dart:io` |
| `lib/core/shortcuts/` | Windows 全局快捷键注册和持久化 | 注意快捷键冲突、生命周期和非 Windows 分支 |
| `lib/core/auth/` | HTTP 认证、令牌安全存储和歌单/喜欢同步边界 | 保持 Access/Refresh Token 轮换、单次刷新重试和退出清理 |
| `lib/features/shell/` | 响应式应用壳、一级导航、播放队列停靠区 | 宽屏阈值当前为 900；返回行为统一回到歌单 |
| `lib/features/library/` | 音乐库、喜欢、专辑/艺术家集合和封面组件 | `library_page.dart` 较大，新增逻辑时优先抽取可测试单元 |
| `lib/features/player/` | 迷你播放器、正在播放页、队列、音量和歌曲信息 | UI 状态来自 `MusicAudioHandler` 的流和值流 |
| `lib/features/playlists/` | 歌单列表和详情 | 写操作经 `AppDatabase`，不要在页面内维护另一份事实源 |
| `lib/features/account/` | 真实登录和歌单/喜欢同步 UI | 页面不直接持有 Token 或 HTTP 客户端 |
| `lib/features/placeholders/` | 设置与听歌识曲占位页 | `settings_page.dart` 已是实际设置页，目录名不代表全部都是占位功能 |
| `lib/features/online_search/` | 在线音乐搜索状态、页面和结果项 | 只调用 `Music.Api`；不得直连 sidecar 或保存第三方 URL/Cookie |
| `android/` | Android 宿主、权限和 MediaStore MethodChannel | 修改 Kotlin 后至少做 Android 编译或实机验证 |
| `windows/` | Windows Runner、CMake、图标和生成的插件注册 | 生成的 registrant 不手改；CMake 有 MSVC 兼容设置 |
| `web/` | Web 启动页、PWA 资源、Drift worker 和 SQLite WASM | 不要遗漏 `sqlite3.wasm`、`drift_worker.js` 的部署路径 |
| `backend/Music.Api/` | ASP.NET Core 10 Minimal API + SQLite 后端 | 与 Flutter 主工程是独立构建单元 |
| `go-music-dl/` | 固定上游 clone 与私有 JSON sidecar | 集成模式默认仅监听 `127.0.0.1`；搜索私有字段与上游 URL 只进短期内存注册表，不得向公网或 Flutter 暴露 |
| `backend/Music.Api/Pages/Admin/` | 后端托管的服务器扫描 Razor Pages | 使用独立管理员 Cookie；PageModel 调用扫描 Service，不复用 Flutter JWT |
| `backend/Music.Api/wwwroot/admin/scanning/` | 管理页面样式资源 | 不应再放置独立 HTML/JavaScript 应用 |
| `docs/api.md` | 后端配置和接口契约 | 接口行为变化时同步更新 |
| `test/` | Flutter/纯 Dart 测试 | 当前覆盖有限，新功能应就近补回归测试 |
| `third_party/just_audio_media_kit/` | 被 `dependency_overrides` 引用的本地 vendored 包 | 视为有意维护的补丁，不要随意换回 pub 包或整体覆盖 |

以下目录或文件通常是生成物/运行物，不应作为源码直接编辑：

- `build/`、`.dart_tool/`、`.flutter-plugins-dependencies`
- `lib/core/database/app_database.g.dart`
- 各平台的 `generated_plugin_registrant.*`、`generated_plugins.cmake`
- `backend/Music.Api/bin/`、`backend/Music.Api/obj/`
- `backend/Music.Api/storage/music.db*`
- 本地 IDE、NuGet、Dart 运行缓存目录

如果这些内容已经出现在用户工作区中，只忽略它们，不要未经授权清理。

## 4. 总体架构与事实源

项目采用“功能页面 + 核心能力”的轻量分层，没有额外的 domain/application 目录。关键规则是：

- Widget 负责展示、收集交互和管理短生命周期 UI 状态。
- Riverpod Provider 负责把数据库、播放器、扫描器和 Repository 注入页面。
- Drift 数据库是音乐库、歌单、喜欢、账号和设置的本地事实源。
- `MusicAudioHandler` 是播放队列和播放状态的事实源。
- 平台能力通过接口、条件导出或 MethodChannel 隔离。
- 后端接口通过 `BackendGateway`/`AuthRepository` 接入 Flutter；Widget 不应绕过这两个边界直接管理令牌。

主数据流可以概括为：

```text
平台文件/MediaStore
        ↓ LibraryScanner
     ScanResult
        ↓ AppDatabase 写入
     Drift/SQLite
        ↓ watch...() Stream
 Riverpod StreamProvider
        ↓
       Widget
        ↓ 用户选择歌曲
 MusicAudioHandler → just_audio/audio_service → 平台音频后端
```

后端实验链路是另一条数据流：

```text
Flutter 页面/Repository → HTTP + Bearer Token → Music.Api Endpoints
                                              ↓
                                      Services / Stores
                                              ↓
                                      后端 SQLite 与文件系统
```

服务器扫描的是“后端机器能够访问的目录”，不是把客户端音乐上传给服务器。这一语义在 UI、API 和文档中必须保持一致。

## 5. 启动生命周期

`lib/main.dart` 的当前顺序有明确目的：

1. `WidgetsFlutterBinding.ensureInitialized()` 允许在 `runApp` 前调用插件。
2. `configureAudioBackend()` 在 Windows 注册 media_kit 作为 `just_audio` 后端。
3. 创建 `AppDatabase`，读取“关闭时最小化到托盘”设置。
4. 初始化桌面窗口控制器。
5. Windows 直接构造 `MusicAudioHandler`；其他目标通过 `AudioService.init` 初始化后台音频服务。
6. 将播放器动作绑定到托盘，初始化桌面快捷键。
7. 用 `ProviderScope.overrides` 注入同一个数据库和播放器实例。
8. Android 在应用启动后异步配置音乐音频会话并清理旧 Debug 资产。

修改启动逻辑时重点检查：

- 插件是否要求 `ensureInitialized`。
- 一个资源是否只应创建一次。
- 初始化失败是否会阻止整个应用启动。
- Web 编译是否会静态触达 `dart:io`。
- `unawaited` 的后台任务是否真的可以不阻塞首帧，以及错误如何被处理。

## 6. Riverpod 约定

- 全局 Provider 集中在 `lib/app/providers.dart`。
- `databaseProvider` 和 `audioHandlerProvider` 默认抛出 `UnimplementedError`，生产入口必须覆盖；Widget 测试也必须提供替身或 override。
- 数据库可观察查询使用 `StreamProvider`，UI 用 `AsyncValue.when` 或明确处理 loading/error/data。
- 读取一次动作用 `ref.read`；需要随数据变化重建 UI 用 `ref.watch`。
- 不要在 `build` 中执行写操作、启动扫描或发起网络请求。
- 页面私有的输入框、选择态、忙碌态可以保留在 `State` 中；跨页面共享或需要持久化的状态不应只放在 Widget 中。
- 新增真实后端 Provider 时，要保持依赖方向：页面依赖抽象/Repository，Repository 再依赖认证会话与 HTTP 客户端。

## 7. Drift 数据库约定

数据库位于 `lib/core/database/app_database.dart`，当前 schema 版本为 2，包含：

- `Accounts`：本地账号快照。
- `Tracks`：歌曲、来源、文件 URI/路径、标签、封面、歌词和同步字段。
- `ScanSources`：用户已授权或选择的本地扫描位置。
- `Playlists`：歌单元数据。
- `PlaylistEntries`：歌单与歌曲的多对多关系及顺序。
- `AppSettings`：字符串键值设置。
- `PlaybackSnapshots`：为恢复播放状态预留的数据结构。
- `LikedTracks`：喜欢歌曲关系。

数据库修改规则：

1. 优先在 `app_database.dart` 中修改表和查询，不手改 `app_database.g.dart`。
2. 任何表结构变化都必须递增 `schemaVersion`。
3. 为旧版本写 `onUpgrade` 迁移；不能只依赖卸载应用或删除数据库。
4. 外键删除、事务和唯一约束要作为行为的一部分测试。
5. 表定义修改后执行：

   ```powershell
   dart run build_runner build --delete-conflicting-outputs
   ```

6. 检查生成 diff 是否只反映预期表结构变化。
7. UI 读取优先使用 `watch...` 响应式查询，批处理和一致性更新使用 `batch`/`transaction`。

扫描重建尤其要谨慎：`replaceScanSourceTracks` 会删除某一来源中本次未发现的旧曲目。修改来源匹配表达式时必须验证运算符分组、Android Document URI 和 Windows 路径前缀，避免误删其他来源数据。

## 8. 本地音乐扫描约定

`LibraryScanner` 是平台扫描边界：

- `library_scanner.dart` 定义接口。
- `scanner_factory.dart` 使用条件导出，在 IO 平台选择真实实现，在 Web 选择 stub。
- Windows 目录选择器在 UI isolate 调用，递归遍历和同步元数据解析放入 `Isolate.run`。
- Android 通过 `top.zonwe.music_player/media_store` MethodChannel 调用 Kotlin。
- `ScannedTrack` 是扫描层模型，页面再映射成 Drift `TracksCompanion`。

必须保持的行为：

- 同一文件的 ID 应稳定。Windows 以规范化、忽略大小写的绝对路径生成 UUID v5；Android 以媒体 URI 生成稳定 ID。
- 无标签或损坏标签的可播放文件仍应进入音乐库，并使用文件名/“未知艺术家”/“未知专辑”兜底。
- 支持的扩展名集合在 Flutter、Android 和后端之间应尽量一致。
- 封面需压缩，避免把原始大图直接写入 SQLite。
- 内嵌歌词和同名 `.lrc` 都可能是来源；读取失败不应导致整次扫描失败。
- 用户取消选择目录返回 `null`，不应显示成错误。
- Android 权限被拒绝、授权 URI 失效和 Windows 目录被移动必须得到可理解的错误。
- Web stub 必须保持可编译且明确返回“不支持”。

改扫描功能时至少检查：新扫描、重新扫描、删除搜索位置、重复文件、空目录、损坏文件和权限丢失。

## 9. 播放器约定

`MusicAudioHandler` 封装唯一的 `just_audio.AudioPlayer`，并通过 `audio_service` 暴露系统媒体状态。

- `playTracks` 把 Drift `Track` 转成 `MediaItem` 和平台音源，设置队列和初始索引后播放。
- `queue`、`mediaItem`、`playbackState` 是 UI 与系统控制共同使用的状态。
- Windows 本地文件优先使用 `filePath` 构造 `Uri.file`；其他平台使用曲目 URI。
- 循环和随机模式修改后要主动广播状态，因为底层不一定产生足以刷新 UI 的播放事件。
- 封面通过缓存 URI 提供给系统通知，原始字节仍可放在 `extras` 给 Flutter UI。
- 播放错误、文件失效和权限失效应在进入播放前或播放失败时给用户清晰反馈。

不要：

- 在页面中直接创建新的 `AudioPlayer` 与全局播放器竞争。
- 只更新按钮本地状态而不更新 `MusicAudioHandler`。
- 假设所有平台都能播放相同 URI 或编码格式。
- 在没有队列的情况下对索引做未经检查的访问。

涉及播放控制的改动应同时验证页面按钮、迷你播放器、队列、系统通知/媒体键和桌面快捷键中的相关入口。

## 10. UI、导航和可访问性约定

- 使用 Material 3 与 `ColorScheme.fromSeed`，颜色从主题取得，不硬编码只适用于浅色模式的颜色。
- 保持响应式设计：`AppShell` 当前以 900 像素区分桌面侧栏与窄屏抽屉；页面内容还应在更窄宽度下不溢出。
- Windows 自绘标题栏和紧凑模式是产品功能，布局改动不能遮挡拖动区域或窗口按钮。
- 歌单是默认一级页。非歌单一级页面的返回操作回到歌单；歌单详情先退回歌单列表。
- 宽屏播放队列是右侧停靠面板，窄屏通常以底部面板呈现。相关修改要验证两种布局。
- 异步操作期间禁用重复提交，显示进度，并在 `await` 后用 `mounted` 检查再访问 `context`/`setState`。
- 所有图标按钮提供 `tooltip`；可交互区域保持足够尺寸；文本缩放后不应严重溢出。
- loading、empty、error、data 四种状态都应有明确 UI。
- 用户可见文案当前以中文为主；同一区域保持术语一致。

## 11. 平台隔离约定

项目大量使用以下模式：

```dart
export 'feature_stub.dart'
    if (dart.library.io) 'feature_io.dart';
```

新增平台功能时优先沿用这个结构：

- 公共文件只暴露统一 API，不导入 `dart:io`。
- `_io.dart` 中实现 Android/Windows 等本地能力。
- `_stub.dart` 为 Web/不支持平台提供安全的空实现或明确错误。
- 仅靠运行时 `kIsWeb` 判断并不能阻止 Web 编译器解析一个直接导入的 `dart:io` 文件。

Android 原生桥接还必须同步检查：

- Kotlin MethodChannel 名称与 Dart 端完全一致。
- Manifest 权限适配 Android 版本。
- 长耗时扫描不阻塞主线程。
- Document Tree 的持久授权和 MediaStore URI 语义不被破坏。

Windows 相关改动还要检查窗口生命周期、托盘释放、快捷键注销和 CMake/MSVC 兼容性。

## 12. 后端约定

`backend/Music.Api` 是独立的 ASP.NET Core 10 Minimal API 项目，目标框架由 `global.json` 和 `Music.Api.csproj` 固定。默认服务地址是 `http://localhost:5080`。

后端分层：

- `Program.cs`：依赖注入、中间件和路由注册。
- `Endpoints/`：请求校验、认证上下文和 HTTP 响应。
- `Services/Auth/`：密码哈希、JWT 和 Refresh Token。
- `Services/Scanning/`：服务器目录扫描与定时后台任务。
- `Data/`：SQLite 表和 Store。
- `Models/`：请求/响应 DTO。
- `Middleware/`：审计日志。
- `OpenApi/`：OpenAPI 文档。

后端修改规则：

- Endpoint 保持薄，业务逻辑进入 Service，持久化进入 Store。
- 需要认证的资源按账号隔离；查询和写入都不能只按资源 ID 而漏掉账号条件。
- 不在日志中记录密码、JWT、Refresh Token 或请求体中的敏感数据。
- Refresh Token 轮换、重复使用检测和撤销语义不能因 UI 方便而弱化。
- 文件扫描必须进行绝对路径、存在性和 `Scanning:AllowedRoots` 校验。
- API 请求/响应变化同时更新 `docs/api.md`、OpenAPI 和 `FlutterMusic.Api.http` 示例。
- 生产环境必须覆盖默认 JWT 密钥；代码和文档中不得加入真实密钥。
- 数据库文件、WAL/SHM、`bin/` 和 `obj/` 不应纳入功能改动。

后端标准命令：

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

当前仓库没有独立后端测试工程。修改认证、路径隔离、数据库写入或扫描删除逻辑时，应优先补测试工程，而不是只用手工 HTTP 请求证明成功路径。

## 13. 常见任务的建议落点

### 新增一个一级页面

1. 在对应 `lib/features/<feature>/` 中实现页面。
2. 在 `AppDestination` 增加目的地、中文标签和选中/未选中图标。
3. 在 `AppShell._pageFor` 映射页面。
4. 验证宽屏侧栏、窄屏抽屉、返回行为和迷你播放器布局。
5. 如果依赖共享状态，在 `providers.dart` 添加边界清晰的 Provider。

### 新增一个设置项

1. 在核心模块定义稳定的设置 key，避免页面散落字符串。
2. 通过 `AppDatabase.setSetting` 写入。
3. 用 `watchSettings` 映射成类型安全模型/Provider。
4. 明确默认值与旧数据库行为。
5. 如果设置影响启动期插件，在 `main.dart` 的初始化顺序中读取。

### 修改数据库表

1. 改表定义。
2. 提升 schema 版本并写迁移。
3. 生成 `app_database.g.dart`。
4. 添加新建数据库与旧版本升级测试。
5. 运行分析、测试和至少一个目标平台构建。

### 新增音频格式

同步检查 Flutter Windows 扫描、Android 文件判断、后端扫描扩展名、实际解码器支持和文档。能被扫描到不等于能被每个平台解码。

### 维护真实账号后端接入

认证链路已接入 HTTP；继续修改时必须一起维护：

- 登录/刷新/退出的 HTTP Gateway。
- Access Token 过期与单次刷新重试。
- Refresh Token 的安全持久化；敏感令牌不适合明文放入普通设置表。
- App 启动时恢复会话。
- 401、离线、超时和服务端错误映射。
- 账号页文案和 `isMock` 字段语义。
- 歌单冲突、喜欢歌曲同步和删除传播规则。
- Android Emulator 的 `10.0.2.2`、真机局域网地址和 Web CORS。

## 14. 代码风格

- 遵循 `analysis_options.yaml` 中的 `flutter_lints`。
- 提交前对改动的 Dart 文件运行 `dart format`，不要为了一个小任务格式化整个脏工作区。
- 文件名使用 `snake_case.dart`；类型使用 `UpperCamelCase`；私有成员以下划线开头。
- 优先使用 `const`，但不要为了 `const` 牺牲可读性或引入错误共享状态。
- 异步返回值使用明确的 `Future<T>`；故意不等待时使用 `unawaited` 并考虑错误处理。
- 不吞掉本应告知用户的错误。只有“单个损坏媒体文件不应中断整库扫描”这类有明确降级语义的边界才可捕获并继续。
- 注释解释“为什么”，尤其是平台限制、生命周期、迁移和看似多余的状态广播，不重复代码字面含义。
- 大页面新增复杂逻辑时，优先抽成小组件、纯函数、Repository 或 Service，并给可测试部分补测试。
- 后端启用了 nullable reference types；不要用无意义的空值抑制掩盖请求校验问题。

## 15. 测试与验证矩阵

先按改动范围选择最小验证，再尽可能完成全量验证。

### Flutter 通用验证

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

若只改少量文件，可先运行目标测试：

```powershell
flutter test test/lrc_parser_test.dart
flutter test test/app_appearance_test.dart
flutter test test/playlists_page_test.dart
```

### 构建验证

```powershell
flutter build windows
flutter build apk --debug
flutter build web
```

不要把所有平台构建都当成每个文案改动的硬性要求，但平台层、依赖、条件导出、初始化和数据库变更通常值得做相关平台构建。

### 后端验证

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
```

启动后至少检查：

```powershell
Invoke-RestMethod http://localhost:5080/health
Invoke-RestMethod http://localhost:5080/openapi.json
```

### 手工验证重点

| 改动 | 最少手工检查 |
| --- | --- |
| 音乐库 | 空库、扫描、搜索、三种视图、重扫、删除来源 |
| 播放 | 首次播放、暂停/继续、切歌、拖动进度、队列、循环/随机 |
| 歌词 | 无歌词、内嵌歌词、同名 LRC、时间同步、长歌词滚动 |
| 歌单/喜欢 | 新建、删除、加入、移除、空歌单、级联删除 |
| 主题/设置 | 浅色、深色、跟随系统、重启后持久化 |
| Windows | 标题栏、拖动、最小化托盘、紧凑窗、快捷键 |
| Android | 权限拒绝/允许、目录授权、全设备扫描、后台通知、媒体键 |
| Web | 首屏、响应式布局、刷新后数据库、无 IO 平台异常 |
| 后端 | 未认证 401、账号隔离、路径越界、重复路径、令牌轮换 |

如果工具命令卡住或超时：

1. 记录命令、持续时间和最后输出，不要写成“通过”。
2. 检查是否有遗留 `dart`/`flutter` 进程或 pub 缓存锁。
3. 使用 `flutter doctor -v`、`flutter --version` 和 `flutter pub get -v` 缩小到 SDK、依赖或项目分析阶段。
4. 在不破坏用户缓存的前提下重试目标测试；不要默认删除整个缓存或工作区生成物。
5. 在交付说明中明确“未执行”“超时”“失败”与“通过”的区别。

## 16. 现有测试说明

- `test/lrc_parser_test.dart`：LRC 时间标签解析和排序。
- `test/app_appearance_test.dart`：设置值到 `ThemeMode`/主题色的映射。
- `test/playlists_page_test.dart`：歌单页面的 loading/error/empty 等 Widget 状态。

新测试建议：

- 纯函数和模型优先写快速单元测试。
- Drift 使用 `AppDatabase.forTesting` 加内存 executor 测查询、事务、级联和迁移。
- Widget 测试通过 `ProviderScope(overrides: ...)` 注入数据库、播放器或 AsyncValue。
- 平台通道使用 mock method call handler，不让单元测试依赖真实文件选择器。
- 音频层尽量把队列/模式转换逻辑与实际插件调用分开，否则测试容易依赖平台插件初始化。
- 后端建立独立测试工程，覆盖认证失败、跨账号访问、扫描根目录限制和 SQLite 行为。

## 17. 安全与数据保护

- 不提交真实音乐、用户数据库、令牌、密码、服务密钥或个人绝对路径。
- 不在日志、异常或截图中暴露 Access Token/Refresh Token。
- 删除扫描源会连带删除本地索引数据；修改相关 SQL 前必须理解范围。
- 服务端目录扫描必须限制在允许根目录内，并防止路径规范化绕过。
- Android 权限只在功能需要时请求；当前麦克风权限为识曲预留，未实现功能不应主动录音。
- 不把音频文件上传到后端，除非未来需求明确改变产品语义并经过专门设计。
- 对 `third_party/` 的修改要保留上游来源、补丁原因和验证平台，方便后续升级。

## 18. 完成任务后的交付清单

交付前逐项确认：

- [ ] 改动只覆盖用户要求，没有覆盖工作区中的无关修改。
- [ ] 新代码遵循现有 Provider、数据库和平台隔离边界。
- [ ] 没有手改生成文件或提交运行数据库/缓存。
- [ ] 用户可见功能处理 loading、empty、error 和窄屏布局。
- [ ] 数据库结构变化包含版本、迁移和生成代码。
- [ ] API 变化同步更新接口文档和示例。
- [ ] 已运行与风险相称的格式化、分析、测试和构建。
- [ ] 对未能运行、超时或失败的验证如实说明。
- [ ] 交付说明包含修改文件、用户可见结果和必要的后续验证。

## 19. 文档维护

架构、依赖、运行命令、平台支持或真实/Mock 边界变化时，应同步更新：

- `README.md`：对所有使用者的功能与快速运行说明。
- `AGENTS.md`：开发约束、架构边界和验证要求。
- `BEGINNER_GUIDE.md`：学习顺序和练习路径。
- `docs/api.md`：后端配置、认证与 API 契约。
- `backend/README.md`：后端单独运行说明。

文档必须描述仓库真实状态。实验代码存在不等于已接入产品；某个平台能够编译也不等于已完成实际功能验证。
