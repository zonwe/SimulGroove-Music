# Flutter Music

面向 Android、Windows 和 Web 的私人本地音乐播放器。当前版本先实现 Groove Music 风格的基础体验，并为后续账号后台、同步与在线音乐 API 保留数据结构和入口。

## 当前功能

- Android：通过系统 MediaStore 扫描音乐，支持后台播放、媒体通知、锁屏/耳机媒体控制与音频焦点。
- Windows：选择音乐目录并递归扫描；使用自绘标题栏，主窗口固定为 1280×720，可切换 384×144 置顶悬浮控制窗。
- 常见格式：MP3、FLAC、M4A、AAC、WAV、OGG、OPUS、WMA（最终能否解码也取决于系统/平台解码器）。
- 音乐库：歌曲、专辑、艺术家视图，本地搜索，封面及标签读取。
- 播放：队列、上一首/下一首、进度、暂停/继续、底栏迷你播放器。
- 歌词：读取内嵌歌词或同名 `.lrc`，Android 播放页可切换封面与同步歌词。
- 歌单：新建、删除、添加歌曲并按歌单播放。
- 账号：本地模拟登录，不发送网络请求；数据库已预留远程账号与同步字段。
- 占位入口：听歌识曲（已声明麦克风权限但未实现）和网络搜索（未接第三方 API）。
- Web：提供响应式界面、模拟登录与占位入口；按当前需求不提供本地目录扫描。

## 技术结构

- Flutter + Riverpod
- Drift/SQLite（Web 使用 `sqlite3.wasm` 和 Drift worker）
- `just_audio` + `audio_service`，Windows 使用 media_kit 音频后端
- Android 原生 MethodChannel 查询 MediaStore

## 开发与验证

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build web
flutter build windows
```

Drift 表结构变化后重新生成代码：

```powershell
dart run build_runner build
```

当前 Android 模拟器配置为 1280×2772、480 dpi、x86_64、8 核、12 GB RAM；CPU/RAM 修改在模拟器下次冷启动后生效。ARM64 发布/兼容性由 Redmi K80 Ultra 实机验证。

## 暂未实现

- 真正的账号后端请求、令牌和跨端同步
- 听歌识曲实现
- 网络搜索及各家音乐 API
- Web 本地文件扫描与播放
