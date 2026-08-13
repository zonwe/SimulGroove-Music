# Flutter Music

面向 Android、Windows、Linux 和 Web 的私人本地音乐播放器。当前版本实现 Groove Music 风格的本地音乐体验，并已接入仓库内的 ASP.NET Core 后端用于账号、歌单/喜欢同步和服务器目录扫描。

## 当前功能

- Android：通过系统目录选择器授权一个或多个音乐文件夹并递归扫描，也可选择扫描整台设备；支持后台播放、媒体通知、锁屏/耳机媒体控制与音频焦点。
- Windows：选择一个或多个音乐目录并递归扫描，音乐库会列出当前搜索位置；使用自绘标题栏，主窗口固定为 1280×720，可切换 384×144 置顶悬浮控制窗。
- Linux：通过系统目录选择器添加并递归扫描音乐目录，使用 media_kit 播放本地与在线音频，支持 MPRIS 系统媒体控制、桌面快捷键、宽屏播放队列和紧凑悬浮窗。
- 常见格式：MP3、FLAC、M4A、AAC、WAV、OGG、OPUS、WMA（最终能否解码也取决于系统/平台解码器）。
- 音乐库：歌曲、专辑、艺术家视图，本地搜索，封面及标签读取。
- 播放：队列、上一首/下一首、进度、暂停/继续、底栏迷你播放器。
- 歌词：读取内嵌歌词或同名 `.lrc`，Android 播放页可切换封面与同步歌词。
- 歌单：新建、删除、添加歌曲并按歌单播放。
- 导航：歌单为默认首页，其他一级页面的返回操作统一回到歌单。
- 外观：默认跟随系统浅色/深色模式，也可手动指定，并提供 8 种可持久化主题色。
- 账号：连接 `backend/Music.Api`，支持 JWT、Refresh Token 轮换、安全令牌存储、退出和歌单/喜欢同步。
- 服务器扫描：由 `backend/Music.Api` 托管的 Web 控制台配置后端机器上的音乐绝对路径、定时扫描并查看索引结果；Flutter 客户端不提供该入口，也不会上传客户端音乐。
- 在线音乐：通过已登录的 `Music.Api` 聚合受控来源，支持去抖、部分失败、短期播放票据、Range 在线播放、封面和同步歌词；Windows/Linux/Android 复用全局播放器，Web 暂不开放需要认证请求头的播放。
- 占位入口：听歌识曲（已声明麦克风权限但未实现）。
- Web：提供响应式界面、真实后端登录与在线搜索；按当前需求不提供本地目录扫描和本地播放。

本地在线搜索联调需先在另一个终端启动项目内的 sidecar clone：

```powershell
go -C go-music-dl run ./cmd/music-dl integration --host 127.0.0.1 --port 8080
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

开发环境默认允许 `netease`、`kugou`、`kuwo`；生产配置仍默认关闭在线音乐功能。

单机容器联调可从 `.env.example` 创建本地 `.env`，再运行：

```powershell
docker compose --env-file .env -f compose.online-music.yml up --detach --build
```

该编排只发布 `Music.Api` 端口，sidecar 保持在 Compose 私有网络。完整的密钥、数据卷、健康检查和升级说明见 [`backend/README.md`](backend/README.md)。

## 技术结构

- Flutter + Riverpod
- Drift/SQLite（Web 使用 `sqlite3.wasm` 和 Drift worker）
- `just_audio` + `audio_service`，Windows/Linux 使用 media_kit 音频后端，Linux 通过 MPRIS 接入桌面媒体控制
- Android 原生 MethodChannel 查询 MediaStore

## 开发与验证

先启动后端：

```powershell
dotnet restore backend/Music.Api/Music.Api.csproj --configfile backend/NuGet.Config
dotnet run --project backend/Music.Api/Music.Api.csproj --urls http://localhost:5080
```

服务器扫描管理页地址为 `http://localhost:5080/admin/scanning`。管理员账号通过后端
`Administration` 配置或同名环境变量设置，与 Flutter 普通账号相互独立。

再启动 Windows 客户端；桌面默认后端地址就是 `http://localhost:5080`：

```powershell
flutter run -d windows --dart-define=MUSIC_API_URL=http://localhost:5080
```

完整配置、Android/Web 地址差异、令牌策略和已知限制见 [`docs/flutter_backend_integration.md`](docs/flutter_backend_integration.md)。

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build web
flutter build windows
```

Android 日常安装不要使用体积较大的通用 Debug APK。K80 Ultra 使用 ARM64 Release：

```powershell
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

当前 ARM64 Release 约 20.5 MB。Debug 包约 170 MB，并会把约 99 MB JIT 资产解压到应用数据目录；升级到本项目的 Release 后会在保留数据库的前提下自动清理这些旧调试资产。扫描所得封面会压缩到最多 256–320 像素，避免音乐库数据库随原始大封面快速膨胀。

Drift 表结构变化后重新生成代码：

```powershell
dart run build_runner build
```

当前 Android 模拟器配置为 1280×2772、480 dpi、x86_64、8 核、12 GB RAM；CPU/RAM 修改在模拟器下次冷启动后生效。ARM64 发布/兼容性由 Redmi K80 Ultra 实机验证。

## 暂未实现

- 服务端音乐文件流式播放（当前服务器扫描只建立索引）
- 多端歌单冲突合并和删除传播（当前同步采用客户端提交覆盖同 ID 歌单）
- 听歌识曲实现
- 在线音乐服务的生产指标导出与告警
- Web 本地文件扫描与播放
