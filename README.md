# SimulGroove Music

面向 Android、Windows、Linux 和 Web 的私人本地音乐播放器。当前版本实现 Groove Music 风格的本地音乐体验，并已接入仓库内的 ASP.NET Core 后端，用于账号、歌单/喜欢/均衡器预设同步、服务器目录扫描和受控在线音乐聚合。

截至 2026-09-07，本次核对已确认 `flutter analyze`、120 项 Flutter 测试、60 项后端测试和最新 Android Debug/ARM64 Release 构建通过；K80 Ultra 模拟器已通过 APK 安装启动、通知/媒体权限拒绝与允许、MediaStore 扫描落库、扫描完成通知和本机后端登录同步冒烟。隔离分支的线上 CI 已通过 Flutter 格式/分析/测试、Web 构建、后端测试、Android Debug 构建、生产部署配置校验、非 root API 镜像构建与容器就绪冒烟、API→OTLP Collector 的真实指标和敏感字段检查，以及告警阈值、持续时间和恢复测试。Windows Debug 构建最近一次通过记录为 2026-09-03，Linux 构建与实机回归按当前安排暂缓，Android 深度实机回归仍需连接真实设备确认。

2026-10-21：Windows 安装器/应用内更新与 Android APK 自更新已接入。本地已通过 `flutter analyze`、191 项 Flutter 测试、Windows/Android/Web Release 构建、Inno Setup 安装器静默安装/卸载冒烟、更新助手端到端冒烟（真实 `cmd.exe` + 假安装器），以及 `latest.json` 生成与 Dart 回读。GitHub Release 工作流已由 `v1.1.0` tag 实际运行并通过（[run 39596997713](https://github.com/zonwe/SimulGroove-Music/actions/runs/39596997713)），[v1.1.0](https://github.com/zonwe/SimulGroove-Music/releases/tag/v1.1.0) 已发布安装器、便携包、三个 ABI APK、`latest.json` 与 `SHA256SUMS.txt`；真实设备上的应用内更新尚待验收。

## 当前功能

- Android：通过系统目录选择器授权一个或多个音乐文件夹并递归扫描，也可选择扫描整台设备；支持后台播放、媒体通知、锁屏/耳机媒体控制与音频焦点。
- Windows：在设置中选择一个或多个音乐目录并递归扫描；使用自绘标题栏，主窗口固定为 1280×720，可切换 384×144 置顶悬浮控制窗。当前版本提供按用户安装的 Inno Setup 安装器（无需管理员权限），解压版仍可直接运行。
- Linux：通过系统目录选择器添加并递归扫描音乐目录，使用 media_kit 播放本地与在线音频，支持 MPRIS 系统媒体控制、桌面快捷键、宽屏播放队列和紧凑悬浮窗。
- 常见格式：MP3、FLAC、M4A、AAC、WAV、OGG、OPUS、WMA（最终能否解码也取决于系统/平台解码器）。
- 音乐库：歌曲、专辑、艺术家视图，本地搜索，封面及标签读取。
- 播放：队列、上一首/下一首、进度、暂停/继续、循环/随机、音量与静音、底栏迷你播放器；桌面端可切换正在播放页布局。
- 播放恢复：Android/Windows/Linux 保存本地队列的原始与随机顺序、当前歌曲、进度和循环模式，重启后恢复并保持暂停；不可用的当前曲目会跳过，在线票据和认证信息不进入播放快照。进度每 5 秒及状态变化时保存，强制结束进程可能丢失最后几秒进度。
- 歌词：读取内嵌歌词或同名 `.lrc`，Android 播放页可切换封面与同步歌词；点按任意歌词行可跳转到该句，设置中可关闭此功能，或改为二次点按确认（第一次点按只选中歌词行，再次点按同一行才跳转）。
- 歌单：新建、删除、添加歌曲并按歌单播放。
- 音效：10 段均衡器、前级增益、内置/自定义预设；Windows、Linux 和 Android 使用各自平台效果链应用配置。
- 扫描体验：可保存多个搜索位置、重新扫描全部，并按设置发送扫描开始、完成或失败的系统通知。
- 扫描任务跨页面继续执行，扫描、重扫和删除来源互斥；Windows/Linux 重扫会复用文件大小和修改时间未变的内容指纹，标签与同名歌词仍重新读取。
- 在线播放音源准备好即可出声，封面与歌词随后补齐；下载音频先入库，附件失败单独提示，可通过“重试附件”补齐而不重新下载音频。
- 导航：歌单为默认首页，其他一级页面的返回操作统一回到歌单。
- 外观：默认跟随系统浅色/深色模式，也可手动指定，并提供 8 种可持久化主题色。
- 账号：连接 `backend/Music.Api`，支持 JWT、Refresh Token 轮换、安全令牌存储、退出，以及歌单、喜欢歌曲、均衡器预设和删除墓碑的双向同步；本地曲目通过账号内 HMAC 盲匹配令牌跨设备关联，不向后端上传原始内容指纹。
- 服务器扫描：由 `backend/Music.Api` 托管的 Web 控制台配置后端机器上的音乐绝对路径、定时扫描并查看索引结果；已索引曲目可在管理页试听，也可通过账号隔离、支持 Range 的 API 播放；Flutter 客户端不提供该管理入口，也不会上传客户端音乐。
- 在线音乐：通过已登录的 `Music.Api` 聚合受控来源，点击搜索按钮后请求，搜索结果以紧凑两行展示并可整行点击播放，封面可在设置中关闭；右键或长按结果会打开歌曲菜单，可查看歌手/专辑集合与封面、选择歌曲或下载单曲。搜索、歌手和专辑页面都可批量加入新建或已有歌单；Windows/Linux/Android 可在设置页指定系统授权目录、选择下载文件命名规则并批量下载，支持的音频格式优先内嵌封面与歌词，无法内嵌时保存同名封面或 `.lrc`，下载完成后立即进入本地音乐库；Web 暂不开放需要认证请求头的播放和下载。
- 在线音乐运维：区分 `/health` 存活检查与 `/health/ready` 依赖就绪检查；支持安全的 `X-Correlation-ID`、低基数 .NET `Meter` 指标、可选 OTLP 导出和连续瞬时失败熔断；来源复核门禁见 [在线音乐来源授权与发布复核](docs/online_music_release_review.md)。
- 应用更新：Windows 安装版和 Android 可在设置页检查更新，启动时默认每 12 小时检查一次并可关闭。更新包下载后校验 SHA-256：Windows 退出应用后由更新助手静默运行安装器并重启；Android 交给系统安装界面确认安装（需要允许安装未知应用，且相邻版本必须使用同一签名）。详见 [发布、安装器与应用内更新](docs/release_and_updates.md)。
- 占位入口：听歌识曲（已声明麦克风权限但未实现）。
- Web：提供响应式界面、真实后端登录与在线搜索；按当前需求不提供本地目录扫描和本地播放。

本地在线搜索联调需先在另一个终端启动项目内的 sidecar clone：

```powershell
go -C go-music-dl run ./cmd/music-dl integration --host 127.0.0.1 --port 8081
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

开发环境默认允许 `netease`、`kugou`、`kuwo`；生产配置仍默认关闭在线音乐功能。

单机容器联调可从 `.env.example` 创建本地 `.env`，再运行：

```powershell
docker compose --env-file .env -f compose.online-music.yml up --detach --build
```

该编排只发布 `Music.Api` 端口，sidecar 保持在 Compose 私有网络。完整的密钥、数据卷、健康检查和升级说明见 [`backend/README.md`](backend/README.md)。

需要把服务放到公网时，可用宿主机 Nginx 作为 TLS 入口：

```powershell
docker compose --env-file .env -f compose.online-music.nginx.yml up --detach --build
```

该编排把 `Music.Api` 只发布到 `127.0.0.1:${MUSIC_API_HOST_PORT:-5080}`，公网流量必须经过宿主机 Nginx，sidecar 仍只在 Compose 私有网络。环境变量模板见 `.env.nginx.example`，站点、限流和证书占位配置见 `deploy/nginx/music-api.conf.example`。应用内显式启用 `UseForwardedHeaders` 并只信任回环代理，因此真实客户端 IP 与 `https` 协议能正确传入限流和审计日志；不要改用 `ASPNETCORE_FORWARDEDHEADERS_ENABLED`，那会用默认选项再注册一次中间件并信任任意来源。容器入口（如 `compose.online-music.production.yml` 里的 Caddy）不在回环网段，需要显式设置 `ForwardedHeaders__TrustNonLoopbackProxy=true`。

## 技术结构

- Flutter + Riverpod
- Drift/SQLite（Web 使用 `sqlite3.wasm` 和 Drift worker）
- `just_audio` + `audio_service`，Windows/Linux 使用 media_kit 音频后端，Linux 通过 MPRIS 接入桌面媒体控制
- Android 原生 MethodChannel 查询 MediaStore
- ASP.NET Core 10 + SQLite 后端，包含认证、同步、服务器扫描、在线音乐 BFF 和审计日志
- 独立 `go-music-dl` 私有 sidecar；Flutter 不直连 sidecar，也不接触第三方 Cookie 或原始 URL
- `compose.online-music.yml` 单机编排模板，只发布 `Music.Api` 端口
- `compose.online-music.nginx.yml` 宿主机 Nginx 反向代理编排，`Music.Api` 只绑定回环地址

## 开发与验证

先启动后端：

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

服务器扫描管理页地址为 `http://localhost:5080/admin/scanning`。管理员账号通过后端
`Administration` 配置或同名环境变量设置，与 Flutter 普通账号相互独立。

再启动 Windows 客户端。客户端不再内置任何默认服务器地址，可通过以下两种方式指定：

1. 运行时在「账号」页点开「高级设置」填写服务器地址（例如 `http://localhost:5080`），地址会持久化到本地数据库，改动立即生效；登录页默认不展示已保存的后端地址；
2. 编译期注入，适合开发调试或分发固定部署环境：

```powershell
flutter run -d windows --dart-define=MUSIC_API_URL=http://localhost:5080
```

两种方式同时存在时，账号页保存的地址优先。

Linux 需要 Flutter Linux 桌面工具链、GTK 3 开发包、系统 `mpv` 运行库和 `libnotify` 开发包；Ubuntu/Debian 可安装 `libmpv-dev mpv libnotify-dev`。在 Linux 主机上运行：

```bash
flutter run -d linux --dart-define=MUSIC_API_URL=http://localhost:5080
```

完整配置、Android/Web 地址差异、令牌策略和已知限制见 [`docs/flutter_backend_integration.md`](docs/flutter_backend_integration.md)。

仓库 CI（`.github/workflows/ci.yml`）包含 Flutter 格式检查、静态分析、单元测试、Web 冒烟构建、后端 Release 测试、Android Debug 和 Windows Release 构建；支持推送、PR 和手动触发，不会上传构建产物。Linux Release 任务暂缓且默认跳过，仅在手动运行工作流时勾选 `run_linux` 才会执行。

发布工作流 `.github/workflows/release.yml` 由 `v*` tag 或手动触发：构建 Windows 安装器/便携包与三个 ABI 的 Android APK，生成 `latest.json` 和 `SHA256SUMS.txt`，上传到对应 GitHub Release。Android 发布任务要求配置固定签名 secrets，否则会失败，避免发布无法自更新的 APK。完整流程与签名配置见 [发布、安装器与应用内更新](docs/release_and_updates.md)。

后端回归测试：

```powershell
dotnet test backend/Music.Api.Tests/Music.Api.Tests.csproj --no-restore -c Release
```

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build web
flutter build windows
flutter build linux
```

Windows 安装器需要 Inno Setup 6：

```powershell
winget install --id JRSoftware.InnoSetup -e
flutter build windows --release
powershell -ExecutionPolicy Bypass -File build_command/build_installer.ps1
```

产物位于 `build\artifacts\windows-installer\SimulGrooveMusic-Setup-<version>-x64.exe`；安装器按用户安装到 `%LOCALAPPDATA%\Programs`。Drift 数据库默认在 `%USERPROFILE%\Documents\flutter_music.sqlite`，其他应用数据在 `%APPDATA%\top.zonwe\SimulGroove Music`，卸载与升级都不会删除音乐库。

Android 日常安装不要使用体积较大的通用 Debug APK。K80 Ultra 使用 ARM64 Release：

```powershell
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

2026-09-07 构建的 ARM64 Release 测试包为 24,125,567 字节，SHA-256 为 `819F3648D06686CE2087A10D070DC85844D72783F3E2C2BB8E46344F86B304EE`；清单确认只包含 `arm64-v8a`。该历史测试包使用本机 debug 证书；当前发布构建会读取 `android/key.properties` 使用固定发布密钥，未配置时回退 debug 签名，仅用于本地调试，不能用于应用内更新。若改用新的发布密钥，Android 会拒绝覆盖 v1.0.0 的 debug 签名包，需要先卸载旧版（会清除应用数据）或沿用原 debug 密钥。应用内更新还要求 `versionCode` 随每次发布递增，并在系统设置中允许本应用安装未知应用。Debug 包约 170 MB，并会把约 99 MB JIT 资产解压到应用数据目录；升级到本项目的 Release 后会在保留数据库的前提下自动清理这些旧调试资产。扫描所得封面会压缩到最多 256–320 像素，避免音乐库数据库随原始大封面快速膨胀。完整的 K80 Ultra 安装、型号校验、人工检查项和本地证据流程见 [Android 真机验收](docs/android_device_acceptance.md)。

Drift 表结构变化后重新生成代码：

```powershell
dart run build_runner build --delete-conflicting-outputs
```

当前 Android 模拟器配置为 1280×2772、480 dpi、x86_64、8 核、12 GB RAM；CPU/RAM 修改在模拟器下次冷启动后生效。ARM64 发布/兼容性由 Redmi K80 Ultra 实机验证。

## 当前边界与待完成事项

项目的本地音乐、播放、资料库管理、账号同步和受控在线音乐主链路已经较完整，但以下产品与生产化边界尚未闭环：

- 在线音乐已具备显式启用的 OTLP 导出，以及只发布 Caddy 80/443 的生产 Compose、私有 Collector/Prometheus/Alertmanager 链路、告警规则、处置手册和逐来源发布门禁（另有宿主机 Nginx 反代的替代编排）；CI 已实际验证请求/失败/熔断计数器导出且不包含搜索词、账号或令牌，并通过告警阈值、持续时间与恢复测试。生产验收脚本会检查真实域名证书、外置通知配置、三种真实告警路由、Fire/Resolve 证据链和结构化来源审批，但真实域名、通知接收方、实际送达回执与来源批准仍需由目标部署环境提供
- CI 已补 Android Debug、生产部署配置校验、非 root API 镜像构建/就绪冒烟、OTLP 端到端指标检查与手动启用的 Linux Release 构建任务，最新线上运行已于 2026-09-07 全部通过；Linux 构建与回归按当前安排暂缓。K80 Ultra 真机验收脚本会拒绝模拟器、验证 ARM64 APK 与 v2 签名、安装启动并保存去标识化证据，深度回归仍待连接真实设备执行

## 以下待完成事项暂不需要实现

- 听歌识曲实现
- Web 本地文件扫描、本地播放、在线播放与在线下载
- Linux 与 Web 的应用内更新（当前仅 Windows 安装版与 Android 支持）
- Windows 安装器/exe 的 Authenticode 代码签名（未签名时 SmartScreen 会提示未知发布者）
- iOS 与 macOS 产品级支持（当前仅保留 Flutter 平台脚手架）
