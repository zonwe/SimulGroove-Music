# SimulGroove Music 项目协作指南

本文是仓库根目录级别的开发与智能体协作说明，适用于整个仓库。无论是人类开发者还是自动化编码智能体，在修改代码前都应先阅读本文件。

## 1. 项目目标与当前边界

SimulGroove Music 是一个面向 Android、Windows、Linux 和 Web 的私人本地音乐播放器。核心目标是提供接近 Groove Music 的本地音乐体验，同时为账号、同步和服务器音乐目录扫描保留清晰的扩展边界。

当前主要能力：

- Android：授权目录或扫描整台设备、读取 MediaStore/Document Tree、后台播放、媒体通知、锁屏和耳机控制。
- Windows：递归扫描本地目录、读取音频元数据、桌面快捷键、系统托盘、自绘标题栏和紧凑悬浮播放器。
- Linux：递归扫描本地目录、读取音频元数据、media_kit 播放、MPRIS 媒体控制、桌面快捷键、原生标题栏和紧凑悬浮播放器。
- Web：响应式界面、Drift Web 数据库、真实后端账号和在线搜索；不支持本地目录扫描与本地音乐播放。
- 通用功能：歌曲/专辑/艺术家视图、搜索、封面、歌词、播放队列、歌单、喜欢、10 段均衡器、扫描通知、主题外观和设置持久化。
- 实验性后端：`backend/Music.Api` 提供 ASP.NET Core + SQLite 的认证、歌单/喜欢/均衡器预设与删除墓碑同步、服务器目录扫描、在线音乐 BFF 和审计日志接口；在线音乐链路已具备存活/就绪检查、关联 ID、低基数指标和进程内熔断。
- 应用更新：Windows 安装版支持 SHA-256 校验后的静默升级，Android 下载 APK 后交给系统安装界面；更新源为 GitHub Release 的 `latest.json`。Linux/Web 暂不支持应用内更新。
- 发布状态：`v1.1.0`（tag `v1.1.0`）已通过 GitHub Release 工作流发布；Android 从 v1.0.0 的 debug 证书切换到固定发布密钥，v1.0.0 → v1.1.0 需要卸载一次（清除应用数据），之后必须保持同一密钥。

以下内容尚未视为完整产品能力：

- Flutter 账号页通过 `HttpBackendGateway` 连接真实后端，运行时服务器地址保存在 `AppSettings`，令牌由安全存储保存；修改认证时必须继续保持刷新轮换和 401 单次重试。
- 服务器扫描管理位于 `backend/Music.Api/Pages/Admin/` Razor Pages，不放入 Flutter 客户端；扫描的是后端机器目录，已索引曲目可在管理页试听，也可通过账号隔离且支持 Range 的 API 播放。
- 在线搜索、歌词/封面、下载与 Windows/Linux/Android 在线播放已通过 `Music.Api` 接入受控 sidecar 契约；播放使用账号绑定短期票据与 Range 代理，Web 因认证请求头限制暂不开放在线播放和下载。仓库提供非 root API 镜像与单机 Compose 编排模板，但生产指标导出、告警和 HTTPS 入口仍由部署环境提供；听歌识曲仍是占位页。
- Web 本地文件扫描和播放未实现。
- Android 实机与 Windows 界面上的应用内更新尚未手工验收；Release 工作流已跑通，但“已发布旧版 → 应用内升级”的真实链路还需要设备验证。
- `ios/`、`macos/` 保留 Flutter 平台脚手架，但不是 README 声明的主要交付目标。涉及这些平台时必须单独验证，不能根据 Android/Windows/Linux 的结果推断可用。

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
| `lib/core/library/` | 本地音乐扫描抽象、Android/Windows/Linux 实现和扫描模型 | 保持 Web/不支持平台的 stub 可编译 |
| `lib/core/player/` | `just_audio`/`audio_service` 播放器、队列、平台音源、均衡器、音量状态和封面缓存 | 不要让 Widget 直接持有第二个 `AudioPlayer` |
| `lib/core/notifications/` | 本地扫描通知抽象、IO 实现和不支持平台 stub | 通知失败应降级并记录，不能阻断扫描 |
| `lib/core/online_music/` | 在线搜索、播放票据、封面、歌词、下载与本地持久化边界 | 只经 `Music.Api`，不得保存 sidecar 私有字段 |
| `lib/core/lyrics/` | LRC 解析 | 适合优先写纯 Dart 单元测试 |
| `lib/core/theme/` | 外观设置模型 | 设置最终保存在 Drift `AppSettings` 表中 |
| `lib/core/window/` | Windows 窗口、托盘和拖动区域，含平台 stub | Web 构建依赖条件导出隔离 `dart:io` |
| `lib/core/shortcuts/` | Windows 全局快捷键注册和持久化 | 注意快捷键冲突、生命周期和非 Windows 分支 |
| `lib/core/auth/` | HTTP 认证、令牌安全存储和歌单/喜欢/均衡器预设/删除墓碑同步边界 | 保持 Access/Refresh Token 轮换、单次刷新重试和退出清理 |
| `lib/features/shell/` | 响应式应用壳、一级导航、播放队列停靠区 | 宽屏阈值当前为 900；返回行为统一回到歌单 |
| `lib/features/library/` | 音乐库、喜欢、专辑/艺术家集合和封面组件 | `library_page.dart` 较大，新增逻辑时优先抽取可测试单元 |
| `lib/features/player/` | 迷你播放器、正在播放页、队列、音量和歌曲信息 | UI 状态来自 `MusicAudioHandler` 的流和值流 |
| `lib/features/playlists/` | 歌单列表和详情 | 写操作经 `AppDatabase`，不要在页面内维护另一份事实源 |
| `lib/features/account/` | 服务器地址、真实登录和资料库同步 UI | 页面不直接持有 Token 或 HTTP 客户端 |
| `lib/features/placeholders/` | 听歌识曲占位页 | 识曲功能仍未实现，不应主动调用麦克风 |
| `lib/features/settings/` | 实际设置页：外观、播放界面、音效、扫描、在线音乐、托盘与快捷键区块 | 各区块独立成文件；新增设置优先加区块而不是往 `settings_page.dart` 堆叠 |
| `lib/features/online_search/` | 在线音乐搜索状态、页面和结果项 | 只调用 `Music.Api`；不得直连 sidecar 或保存第三方 URL/Cookie |
| `lib/core/update/` | 更新清单/版本模型、检查与下载、SHA-256 校验、Windows 更新助手和 Android 安装桥 | 清单契约、信任主机和路径校验不能放宽；公共文件不得导入 `dart:io` |
| `lib/features/update/` | 启动更新检查闸门和更新对话框 | 自动检查只提示，不自动下载；下载/安装期间禁止重复提交 |
| `build_command/installer/` | Inno Setup 安装器脚本（按用户安装） | `AppId` 固定；升级必须原地覆盖；不要随意改 `Runner.rc` 的 `CompanyName`/`ProductName`（影响应用支持目录，Drift 数据库在 Documents） |
| `build_command/build_installer.ps1` | Windows 安装器构建入口 | 需要 Inno Setup 6；脚本用 UTF-8 BOM 保存以兼容 Windows PowerShell 5.1 |
| `tool/build_update_manifest.ps1` | 生成 `latest.json` | 资产名、URL、SHA-256 必须与 Release 实际文件一致 |
| `tool/generate_android_keystore.ps1` | 生成 Android 发布密钥并输出 CI secrets | 现有发布密钥已生成；仅在首次配置或明确轮换时使用，不要覆盖 |
| `.github/workflows/release.yml` | tag/手动发布安装器、APK、`latest.json` 与校验和 | `v1.1.0` 已实际跑通；Android 签名 secrets 缺失时必须失败 |
| `android/` | Android 宿主、权限、MediaStore 与更新安装 MethodChannel | 修改 Kotlin 后至少做 Android 编译或实机验证；APK 安装必须经 FileProvider + 系统安装界面 |
| `windows/` | Windows Runner、CMake、图标和生成的插件注册 | 生成的 registrant 不手改；CMake 有 MSVC 兼容设置 |
| `linux/` | Linux GTK Runner、CMake 与生成的插件注册 | 在 Linux 主机验证 GTK、libmpv、MPRIS、X11/Wayland 和桌面环境差异 |
| `web/` | Web 启动页、PWA 资源、Drift worker 和 SQLite WASM | 不要遗漏 `sqlite3.wasm`、`drift_worker.js` 的部署路径 |
| `backend/Music.Api/` | ASP.NET Core 10 Minimal API + SQLite 后端 | 与 Flutter 主工程是独立构建单元 |
| `backend/Music.Api/Services/OnlineMusic/` | sidecar 网关、缓存、票据、资源代理、指标和熔断 | 指标标签保持低基数；不得包含搜索词、曲目 ID、Token、Cookie 或 URL |
| `go-music-dl/` | 固定上游 clone 与私有 JSON sidecar | 集成模式默认仅监听 `127.0.0.1`；搜索私有字段与上游 URL 只进短期内存注册表，不得向公网或 Flutter 暴露 |
| `compose.online-music.yml` | `Music.Api` 与 sidecar 的单机容器编排模板 | 只发布 API 端口；sidecar 仅加入 Compose 私有网络并保留必要的外网访问能力 |
| `compose.online-music.nginx.yml` | 宿主机 Nginx 反向代理的单机编排 | `Music.Api` 只绑定 `127.0.0.1`，公网流量必须经 Nginx；转发头由应用内中间件处理 |
| `deploy/nginx/` | Nginx 站点、安全头与限流模板 | 模板只保留占位值；证书路径、域名和出口 IP 由部署环境替换 |
| `.env.nginx.example` | Nginx 反代编排的环境变量模板 | 只能保存占位值；真实域名、密钥写入未提交的 `.env` |
| `.env.example` | Compose 环境变量模板 | 只能保存占位值；真实 JWT、管理员密码和 Cookie 写入未提交的 `.env` 或密钥系统 |
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
- `.env`、`.env.*`（`.env.example` 除外）
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

数据库位于 `lib/core/database/app_database.dart`，当前 schema 版本为 5，包含：

- `Accounts`：本地账号快照。
- `Tracks`：歌曲、来源、文件 URI/路径、标签、封面、歌词和同步字段。
- `ScanSources`：用户已授权或选择的本地扫描位置。
- `Playlists`：歌单元数据。
- `PlaylistEntries`：歌单与歌曲的多对多关系及顺序。
- `AppSettings`：字符串键值设置。
- `PlaybackSnapshots`：保存本地曲目 ID、原始/实际队列顺序、进度与循环/随机模式，恢复后保持暂停；不保存在线票据或认证头。
- `LikedTracks`：喜欢歌曲关系。
- `EqualizerPresets`：可同步的自定义均衡器预设。
- `SyncTombstones`：按账号保存歌单、喜欢歌曲和均衡器预设的删除墓碑。

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

数据库每次打开都启用 SQLite 外键，并一次性清理旧版本残留的孤立歌单条目与喜欢关系；级联删除回归必须使用真实 SQLite 验证。

扫描重建尤其要谨慎：`replaceScanSourceTracks` 会删除某一来源中本次未发现的旧曲目。修改来源匹配表达式时必须验证运算符分组、Android Document URI 和 Windows 路径前缀，避免误删其他来源数据。

## 8. 本地音乐扫描约定

`LibraryScanner` 是平台扫描边界：

- `library_scanner.dart` 定义接口。
- `scanner_factory.dart` 使用条件导出，在 IO 平台选择真实实现，在 Web 选择 stub。
- Windows 目录选择器在 UI isolate 调用，递归遍历和同步元数据解析放入 `Isolate.run`。
- Android 通过 `top.zonwe.simul_groove_player/media_store` MethodChannel 调用 Kotlin。
- `ScannedTrack` 是扫描层模型，由扫描控制器映射成 Drift `TracksCompanion`。
- `LibraryScanController` 统一持有扫描、重扫与来源删除任务，跨页面共享进度和互斥状态，并在事务中提交扫描结果；页面不持有长时间扫描任务。
- Windows/Linux 重扫可以按规范路径、文件大小和修改时间复用内容指纹，标签与同名歌词仍重新读取；数据库历史修改时间精度为秒，内容变更但大小和修改时间都不变时需重新添加目录执行完整扫描。

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

`EqualizerController` 负责均衡器状态与平台效果链，`volume_state.dart` 与 `playback_queue_logic.dart` 保存可独立测试的纯状态转换；`MusicAudioHandler` 保留播放器编排和兼容的公开委托 API。

- `playTracks` 把 Drift `Track` 转成 `MediaItem` 和平台音源，设置队列和初始索引后播放。
- `queue`、`mediaItem`、`playbackState` 是 UI 与系统控制共同使用的状态。
- Windows 本地文件优先使用 `filePath` 构造 `Uri.file`；其他平台使用曲目 URI。
- 循环和随机模式修改后要主动广播状态，因为底层不一定产生足以刷新 UI 的播放事件。
- 封面通过缓存 URI 提供给系统通知，原始字节仍可放在 `extras` 给 Flutter UI。
- 播放错误、文件失效和权限失效应在进入播放前或播放失败时给用户清晰反馈。
- `MusicAudioHandler.play()` 在发出播放命令后返回，异步播放错误通过统一错误流展示；不要用底层 `AudioPlayer.play()` 的结束 Future 表示加载完成。
- `PlaybackPersistence` 每 5 秒及播放状态变化时保存本地队列快照，在首帧后尝试恢复；恢复不得覆盖用户新发起的播放，也不得自动出声。

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
- `_io.dart` 中实现 Android/Windows/Linux 等本地能力。
- `_stub.dart` 为 Web/不支持平台提供安全的空实现或明确错误。
- 仅靠运行时 `kIsWeb` 判断并不能阻止 Web 编译器解析一个直接导入的 `dart:io` 文件。

Android 原生桥接还必须同步检查：

- Kotlin MethodChannel 名称与 Dart 端完全一致。
- Manifest 权限适配 Android 版本。
- 长耗时扫描不阻塞主线程。
- Document Tree 的持久授权和 MediaStore URI 语义不被破坏。
- 应用内更新桥（`top.zonwe.simul_groove_player/updater`）的 APK 路径必须限制在 `cache/SimulGrooveMusic/updates` 内，并通过 FileProvider 授予一次性读权限；`REQUEST_INSTALL_PACKAGES` 与 Android 8+ 的“安装未知应用”授权必须单独处理。不要尝试绕过系统安装确认界面。

Windows 相关改动还要检查窗口生命周期、托盘释放、快捷键注销和 CMake/MSVC 兼容性。

应用内更新的平台边界：

- `lib/core/update/` 的公共文件不得导入 `dart:io`；Windows/Android 实现在 `_io.dart`，Web 使用 `_stub.dart`。
- Windows 静默升级依赖安装版目录中的 `unins000.exe` 判断；解压版只能引导用户手动下载安装器。
- 更新助手脚本由 `update_install_script.dart` 生成；路径通过环境变量传给 `cmd.exe`（避免中文路径被批处理代码页解码），必须继续校验绝对路径与扩展名，并拒绝引号、换行和 NUL。
- 更新包下载后必须校验清单中的大小与 SHA-256，再交给安装器；不得跳过校验。
- 清单资产地址只允许 HTTPS 和受信任主机（GitHub 资产域名或清单自身主机）。

## 12. 后端约定

`backend/Music.Api` 是独立的 ASP.NET Core 10 Minimal API 项目，目标框架由 `global.json` 和 `Music.Api.csproj` 固定。默认服务地址是 `http://localhost:5080`。

后端分层：

- `Program.cs`：依赖注入、中间件和路由注册。
- `Endpoints/`：请求校验、认证上下文和 HTTP 响应。
- `Services/Auth/`：密码哈希、JWT 和 Refresh Token。
- `Services/Scanning/`：服务器目录扫描与定时后台任务。
- `Services/OnlineMusic/`：sidecar HTTP 契约、搜索/资源缓存、播放票据、调用指标和熔断。
- `Data/`：SQLite 表和 Store。
- `Models/`：请求/响应 DTO。
- `Middleware/`：关联 ID 与审计日志。
- `OpenApi/`：OpenAPI 文档。

后端修改规则：

- Endpoint 保持薄，业务逻辑进入 Service，持久化进入 Store。
- 需要认证的资源按账号隔离；查询和写入都不能只按资源 ID 而漏掉账号条件。
- 不在日志中记录密码、JWT、Refresh Token 或请求体中的敏感数据。
- Refresh Token 轮换、重复使用检测和撤销语义不能因 UI 方便而弱化。
- 文件扫描必须进行绝对路径、存在性和 `Scanning:AllowedRoots` 校验。
- API 请求/响应变化同时更新 `docs/api.md`、OpenAPI 和 `FlutterMusic.Api.http` 示例。
- `/health` 只表示 API 进程存活；`/health/ready` 在在线音乐启用时探测 sidecar。就绪检查使用独立客户端绕过业务熔断，避免依赖恢复后仍被旧熔断状态遮蔽。
- 入站 `X-Correlation-ID` 必须限制长度和字符集；响应、审计记录与 sidecar 请求复用同一安全 ID，不接受可造成日志注入的任意文本。
- 在线音乐指标只使用规范操作名、失败类型等低基数标签，不记录搜索词、来源、曲目 ID、账号、Token、Cookie、`streamRef` 或 URL。
- sidecar 业务调用的熔断**按操作隔离**（`search`/`resolve`/`stream`/`lyrics`/`artwork`/`download` 各自计数），只统计网络错误、超时、HTTP 408/429/5xx 等瞬时失败；404、422 等稳定业务响应不得错误打开熔断。共用单一全局熔断会让一次批量封面失败连坐搜索。
- sidecar 的状态码是熔断器的输入：4xx 表示"这首曲目没有可用资源"这类稳定结果，5xx 只留给值得重试的故障。把稳定业务结果映射成 5xx 属于契约破坏。
- 只对传输层错误（连接被重置、DNS 失败）做一次重试，且仅在搜索路径上；HTTP 状态响应、业务错误和超时都不重试。
- 生产环境必须覆盖默认 JWT 密钥；代码和文档中不得加入真实密钥。
- 数据库文件、WAL/SHM、`bin/` 和 `obj/` 不应纳入功能改动。
- 反向代理部署必须由应用显式注册转发头中间件（`Program.cs` 的 `UseForwardedHeaders`），默认只信任回环代理；不要改用 `ASPNETCORE_FORWARDEDHEADERS_ENABLED`——它同样会注册中间件，但使用默认选项、接受任意来源的 `X-Forwarded-For`，并与显式配置重复。容器化入口代理不在回环网段，需设置 `ForwardedHeaders:TrustNonLoopbackProxy=true`，且仅在外部无法直达 API 时开启。只接受 `X-Forwarded-For`/`X-Forwarded-Proto`，不信任客户端可伪造的 `X-Forwarded-Host`。
- 配置 `AllowedHosts` 时必须保留 `127.0.0.1`，否则容器内 healthcheck 的 Host 头会被拒绝；Nginx 侧需转发 `Host`、`X-Real-IP`、`X-Forwarded-For` 与 `X-Forwarded-Proto`。
- Compose 编排只发布 `Music.Api` 端口，sidecar 不映射宿主机端口；`.env`、数据卷导出、Data Protection 密钥和 sidecar Cookie 不得提交。

后端标准命令：

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
dotnet test backend/Music.Api.Tests/Music.Api.Tests.csproj --no-restore -c Release
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

`backend/Music.Api.Tests` 已覆盖认证、在线搜索/播放/资源代理、关联 ID、健康检查、指标与熔断等边界。修改认证、路径隔离、数据库写入、扫描删除、票据隔离或 sidecar 失败映射时，应继续在该工程补回归测试，不能只用手工 HTTP 请求证明成功路径。

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

### 发布一个新版本

> **当前 Android 发布密钥（2026-10-21，勿覆盖）**
>
> - keystore：`android/app/simulgroove-release.jks`；alias：`simulgroove`
> - 证书 SHA-256：`9333616c5867d1a4872a5102584b8895cf33473338edaff1bb9c812ae94e9129`
> - 密码：`android/key.properties`（与 keystore 一起离线备份，二者均被 Git 忽略）
> - GitHub Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、`ANDROID_STORE_PASSWORD` 已配置
> - v1.0.0 使用旧的 debug 证书；升级到 v1.1.0 需要先卸载（清除应用数据）。v1.1.0 起必须保持同一密钥，**不要重新运行生成脚本覆盖**。

1. 确认 `pubspec.yaml` 的 `version: x.y.z+build`，**每次发布递增 build**（Android `versionName` 的 `+build` 与 Windows 版本资源都取自它；Flutter 还会给 Android `versionCode` 加 ABI 千位偏移）。
2. 确认本机 keystore / `android/key.properties` 和离线备份仍可用；**不要重新生成密钥**。只有明确轮换（会要求所有已安装用户卸载重装）时才使用 `tool/generate_android_keystore.ps1`。
3. 同步 `README.md` 的功能/安装说明与 `docs/release_and_updates.md` 的契约或流程变化。
4. 本地至少运行 `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test`、`flutter build windows --release` 和 `powershell -ExecutionPolicy Bypass -File build_command/build_installer.ps1`。
5. 推送 `v<version>` tag 或手动运行 `Release` 工作流；`v1.1.0` 已由该流程发布（run 39596997713），后续沿用。工作流会校验 pubspec 与 tag 一致，生成安装器、便携包、三个 ABI 的 APK、`latest.json` 和 `SHA256SUMS.txt`。
6. 验证 Release 资产文件名与 `latest.json` 中的 URL 完全一致；`latest.json` 必须在该 Release 中，客户端才能通过 `releases/latest/download/latest.json` 取到。
7. 用旧版本实际走一遍“检查更新 → 下载 → 校验 → 安装”，并确认升级后数据库仍在。

### 修改应用内更新

- 更新清单字段变化必须同时修改 `lib/core/update/update_manifest.dart`、`tool/build_update_manifest.ps1`、`docs/release_and_updates.md` 和测试。
- Windows 与 Android 的资产类型不同（`installer`/`apk`），不要让一个平台下载另一个平台的包。
- Windows 更新助手脚本必须保持“等待旧进程退出 → 静默安装 → 重启/失败标记”的顺序；不要在应用进程内直接替换正在使用的 exe/DLL。
- 任何新增的下载路径都必须校验 HTTPS、主机白名单、大小上限和 SHA-256。

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
- 歌单、喜欢歌曲、均衡器预设的时间戳合并、删除墓碑传播和跨设备曲目匹配规则。
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
flutter build linux
flutter build apk --debug
flutter build web
```

涉及安装器或应用内更新时，额外运行：

```powershell
flutter build windows --release
powershell -ExecutionPolicy Bypass -File build_command/build_installer.ps1
flutter build apk --release --split-per-abi
```

安装器构建需要 Inno Setup 6；本机已配置 `android/key.properties`（固定发布密钥），不要用 debug 签名构建对外发布的更新包。

不要把所有平台构建都当成每个文案改动的硬性要求，但平台层、依赖、条件导出、初始化和数据库变更通常值得做相关平台构建。

### 后端验证

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet build backend/Music.Api/Music.Api.csproj --no-restore
dotnet test backend/Music.Api.Tests/Music.Api.Tests.csproj --no-restore -c Release
```

启动后至少检查：

```powershell
Invoke-RestMethod http://localhost:5080/health
Invoke-WebRequest http://localhost:5080/health/ready
Invoke-RestMethod http://localhost:5080/openapi.json
```

修改 `Dockerfile`、`.env.example`、`compose.online-music.yml` 或 `compose.online-music.nginx.yml` 时，在 Docker 可用的环境至少运行：

```powershell
docker compose --env-file .env -f compose.online-music.yml config
docker compose --env-file .env -f compose.online-music.yml build
docker compose --env-file .env -f compose.online-music.nginx.yml config
```

若当前机器没有 Docker CLI，必须明确记录为“未执行”，不能仅凭 YAML 可读或后端单测通过推断镜像可构建。

### 手工验证重点

| 改动 | 最少手工检查 |
| --- | --- |
| 音乐库 | 空库、扫描、搜索、三种视图、重扫、删除来源 |
| 播放 | 首次播放、暂停/继续、切歌、拖动进度、队列、循环/随机 |
| 歌词 | 无歌词、内嵌歌词、同名 LRC、时间同步、长歌词滚动、点击定位与二次点按确认（第一次点按只选中，不弹框） |
| 歌单/喜欢/均衡器 | 新建、删除、加入、移除、空状态、级联删除、同步墓碑和较新修改恢复 |
| 主题/设置 | 浅色、深色、跟随系统、重启后持久化 |
| Windows | 标题栏、拖动、最小化托盘、紧凑窗、快捷键；安装器静默安装/卸载与解压版提示 |
| Linux | 目录选择、递归扫描、本地/在线播放、MPRIS 媒体键、原生标题栏、紧凑窗、快捷键 |
| Android | 权限拒绝/允许、目录授权、全设备扫描、后台通知、媒体键；更新下载、未知来源授权、系统安装确认、签名一致与 versionCode 递增 |
| 应用更新 | Windows 检查/下载/SHA-256/静默升级/失败标记；Android ABI 选择与系统安装；`latest.json` 404、哈希不匹配、解压版与签名不一致 |
| Web | 首屏、响应式布局、刷新后数据库、无 IO 平台异常 |
| 后端 | 未认证 401、账号隔离、路径越界、重复路径、令牌轮换、`/health/ready`、关联 ID、sidecar 超时与熔断恢复 |

如果工具命令卡住或超时：

1. 记录命令、持续时间和最后输出，不要写成“通过”。
2. 检查是否有遗留 `dart`/`flutter` 进程或 pub 缓存锁。
3. 使用 `flutter doctor -v`、`flutter --version` 和 `flutter pub get -v` 缩小到 SDK、依赖或项目分析阶段。
4. 在不破坏用户缓存的前提下重试目标测试；不要默认删除整个缓存或工作区生成物。
5. 在交付说明中明确“未执行”“超时”“失败”与“通过”的区别。

## 16. 现有测试说明

- `test/lrc_parser_test.dart`：LRC 时间标签解析和排序。
- `test/lyrics_settings_test.dart`：歌词点击定位、二次点按确认与设置持久化。
- `test/app_appearance_test.dart`：设置值到 `ThemeMode`/主题色的映射。
- `test/playlists_page_test.dart`：歌单页面的 loading/error/empty 等 Widget 状态。
- `test/playback_queue_logic_test.dart`、`test/equalizer_test.dart`、`test/equalizer_controller_test.dart`：播放器队列与均衡器纯逻辑。
- `test/auth_sync_test.dart`、`test/http_backend_gateway_test.dart`：同步合并、删除墓碑、刷新重试与 HTTP 契约。
- `test/online_*_test.dart`、`test/http_online_music_gateway_test.dart`：在线搜索、菜单、批量操作、下载与网关契约。
- `test/linux_library_scanner_test.dart`、`test/scan_notification_service_test.dart`：Linux 扫描与通知降级边界。
- `test/update_manifest_test.dart`：版本比较、清单字段校验（含 Android APK 与带下划线的 ABI 键）。
- `test/update_install_script_test.dart`：Windows 更新助手脚本的等待/静默安装/失败标记与环境变量路径校验。
- `test/update_service_test.dart`：MockClient 下的检查、下载、SHA-256 校验、信任主机与错误映射。
- `backend/Music.Api.Tests/`：认证、账号隔离、同步墓碑、在线音乐搜索/播放/下载/歌词/封面、关联 ID、健康检查、指标和熔断测试。

新测试建议：

- 纯函数和模型优先写快速单元测试。
- Drift 使用 `AppDatabase.forTesting` 加内存 executor 测查询、事务、级联和迁移。
- Widget 测试通过 `ProviderScope(overrides: ...)` 注入数据库、播放器或 AsyncValue。
- 平台通道使用 mock method call handler，不让单元测试依赖真实文件选择器。
- 音频层尽量把队列/模式转换逻辑与实际插件调用分开，否则测试容易依赖平台插件初始化。
- 后端继续扩展现有 `Music.Api.Tests`，重点补跨账号访问、扫描根目录限制、SQLite 迁移/并发和容器配置边界。

## 17. 安全与数据保护

- 不提交真实音乐、用户数据库、令牌、密码、服务密钥或个人绝对路径。
- 不在日志、异常或截图中暴露 Access Token/Refresh Token。
- 删除扫描源会连带删除本地索引数据；修改相关 SQL 前必须理解范围。
- 服务端目录扫描必须限制在允许根目录内，并防止路径规范化绕过。
- Android 权限只在功能需要时请求；当前麦克风权限为识曲预留，未实现功能不应主动录音。
- 不把音频文件上传到后端，除非未来需求明确改变产品语义并经过专门设计。
- 对 `third_party/` 的修改要保留上游来源、补丁原因和验证平台，方便后续升级。
- Android 发布 keystore、密码和 GitHub Secrets 不得提交；`android/key.properties`、`*.jks`、`*.keystore` 必须保持忽略。当前发布密钥为 `android/app/simulgroove-release.jks`（alias `simulgroove`），证书指纹与备份要求见“发布一个新版本”；丢失密钥等于失去应用内更新能力。
- 应用内更新必须保留 HTTPS、受信任主机、大小上限与 SHA-256 校验；不得为了调试方便关闭或绕过。
- Windows PowerShell 5.1 会把无 BOM 的 UTF-8 中文脚本按 ANSI 解码；修改 `build_command/`/`tool/` 下含中文的脚本时要确认编码（本次新增的发布脚本使用 UTF-8 BOM），且不要假设开发机一定有 `pwsh`。

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
- `docs/api.md`：后端配置、认证与 API 契约。
- `backend/README.md`：后端单独运行说明。
- `docs/release_and_updates.md`：更新清单契约、Windows 安装器、Android 签名与应用内更新流程。
- `docs/releases/v<version>.md`：Release body 与 `latest.json` 的 notes 来源。

文档必须描述仓库真实状态。实验代码存在不等于已接入产品；某个平台能够编译也不等于已完成实际功能验证。
