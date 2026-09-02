# SimulGroove Music 改进计划（第二轮）

> 生成于 2026-09-03，同日完成一轮执行（8 个提交，见文末"执行进展"）。上一轮计划（`IMPROVEMENT_PLAN.md`）的 11 项中，P0 全部 3 项、P1 的 4/5/6/7（部分）、P2 的 11 项已完成，共 9 个提交（见文末清单）。
> 执行后基线：Flutter 111 项测试、后端 51 项测试、`flutter analyze`、`flutter build web`、`flutter build windows --debug` 全部通过；后端 `/health` 与 OpenAPI 启动冒烟正常；Windows 调试版实机启动并核对歌单/设置/账号页渲染正常。

## P0 优先处理

### 1. ✅ 已完成（e6f8c9ba）修复 `docs/` 被 .gitignore 误伤，接口文档从未入库

- **位置**：`.gitignore:13`（`docs/`）
- **问题**：这行来自 Flutter 模板，本意是排除 dartdoc 生成的 API 文档目录（dartdoc 输出已由同文件 `**/doc/api/` 覆盖）。但仓库把 `docs/api.md`、`docs/flutter_backend_integration.md` 等真实文档也放在 `docs/` 下，导致 AGENTS.md 明确要求同步维护的接口契约文档从未进入版本控制。
- **结果**：删除误伤规则，四份文档入库。

### 2. CI 已建立但从未真实运行过（需推送后验证，本地无法完成）

- **位置**：`.github/workflows/ci.yml`
- **问题**：工作流的所有命令都已在本地验证通过，但 YAML 本身尚未经过 GitHub Actions 首次运行验证（`subosito/flutter-action` 的 stable 通道需要满足 `sdk: ^3.12.2`，若上游 stable 落后需要改为固定 `flutter-version`）。
- **建议**：推送到 GitHub 后观察首次运行；失败时优先怀疑 Flutter 版本与 `flutter build web` 的耗时（可加 `--release` 之外的缓存策略或拆成独立 job）。
- **验证**：GitHub 仓库 Actions 页面两条 job 全绿；之后故意提交一个格式错误确认能拦截。

### 3. 🔶 部分完成 本轮 UI 改动的手工回归验证

- **位置**：账号页（新增服务器地址输入）、音乐库（右键/按钮菜单合并、批量加入歌单）、设置页（文件迁移）。
- **已完成**：Windows 调试版实机启动冒烟——应用正常启动，歌单页显示真实数据，设置页各区块（外观/播放界面/音效/扫描位置/音乐与同步）与账号页（登录态资料卡）渲染正常，导航无崩溃。
- **仍开放**：
  - 账号页：空地址引导 → 填地址登录 → 重启后地址回显与持久化（需要可用的后端实例）。
  - 音乐库：列表按钮菜单与右键菜单条目/行为一致；多选批量加入歌单一次写入；重复加入同一首歌的移到末尾语义。
  - 设置页：窄屏布局无溢出；快捷键区块录制流程。
  - Android 真机验证账号页与在线播放。

## P1 近期处理

### 4. 拆分剩余巨型页面（上轮第 7 条遗留）

### 4. ✅ 已完成（a2178920、a513a2b0、48904c6e）拆分剩余巨型页面

- **结果**：
  - `now_playing_page.dart`（787→304 行）——播放模式纯函数、歌词面板、双栏视图、标题/歌手行、底部控制行各自独立成文件，原导入路径的公共 API 通过 export 保留。
  - `equalizer_view.dart`（864→504 行）——曲线画笔、频段滑杆、前级控制、预设选择器独立成文件；预设菜单动作改为枚举。
  - `online_search_page.dart`（1076→约 400 行）——结果区状态分支/列表/分页/批量工具条抽为 `online_search_results.dart`，右键菜单抽为 `online_track_context_menu.dart`（动作经回调交还页面）。
- **后续候选**（未列入本轮）：结果行操作与歌单选择器在 library_page 与 online_search 之间仍有相似语义，可继续下沉共享。

### 5. ✅ 已完成（3fedd3d1）后端 AuthService 拆分

- **结果**：`refresh_tokens` 持久化抽为 `IRefreshTokenStore`/`SqliteRefreshTokenStore`（建表、插入、查询、轮换标记、按用户撤销），方法接收调用方连接与事务以保持原子性；令牌哈希计算留在 AuthService。新增 `SqliteDatabasePath` 统一路径解析（`Data/` 下三个 Store 的同款逻辑可后续收敛）。新增 `RefreshTokenStoreTests` 4 个集成测试，后端测试 47→51。

### 6. 🔶 大部分完成（4990a8d1）MusicAudioHandler 职责进一步拆分

- **结果**：均衡器拆为 `EqualizerController`（状态 + 平台效果链应用，Android 共享实例随迁）；设置解析抽为 `parseEqualizerSettings` 纯函数，消除启动恢复与均衡器界面的重复实现；音量/静音抽为 `resolveVolumeChange`/`resolveMuteToggle` 纯状态机。新增 11 个单测。handler 保留原公开 API 作薄委托，调用方无感。
- **遗留**：`AudioPlayer` 构造注入未做——`just_audio.AudioPlayer` 是具体类且构造即触碰平台通道，仅注入无法无头测试；需先抽一个播放器操作接口（PlayerAdapter）才有意义，留待下一轮评估。

### 7. 错误文案上移出数据层（保持原评估：暂缓）

- **现状**：`http_backend_gateway.dart` 与 `http_online_music_gateway.dart` 的错误码→中文映射仍留在数据层。确认只做中文的前提下，这是结构调整而非 i18n 需求，收益主要是让数据层可复用于未来的多语言/桌面端错误上报。
- **建议**：若短期内不做多语言，可降级为"在 `BackendException`/`OnlineMusicException` 上补充 `code` 覆盖率并保证 UI 有兜底文案"，暂不移动字符串。

## P2 择机处理

### 8. ✅ 已完成（ca104311）扫描链路的静默捕获补日志

- **结果**：`library_scanner_io.dart` 6 处 `catch (_)` 全部接入 `AppLog.debug`，记录文件路径与原因，保留"单文件损坏不中断整库扫描"的降级语义。

### 9. 后端启动 fail-fast 写法（评估后保留）

- **位置**：`backend/Music.Api/Program.cs` 启动时强制解析单例。这是有意的 fail-fast，已保留；本轮AuthService 改为工厂注册后该机制同时验证了新的 DI 图（启动冒烟通过）。

### 10. 🔶 部分完成（51929b53）依赖升级

- **结果**：常规版本已升级——`drift 2.34.4`、`flutter_riverpod 3.4.2`、`audio_metadata_reader 1.7.1`、`image 4.9.2`（测试工具链传递依赖随解析器重排）。
- **仍开放**：跨大版本 `flutter_secure_storage 10→11`、`permission_handler 12→13`（需评估 breaking，建议独立提交 + Android/桌面实机验证）；升级 `just_audio` 前先核对 `third_party/just_audio_media_kit` 补丁。

### 11. ✅ 已完成（ca104311）后端剩余编译警告

- **结果**：删除零引用的 `Tools/JsonTool.cs`（唯一警告来源）及未使用的 using，后端构建零警告。

### 12. 平台边界（延续上一轮的已知限制，非本轮引入）

- Web 不支持本地扫描/本地播放与在线播放（认证头限制）；听歌识曲仍是占位页；`ios/`、`macos/` 只是脚手架。
- 服务器扫描结果仍只读，不能直接播放。

## 建议推进顺序（下一轮）

1. 第 2 条：推送验证 CI（唯一未闭环的 P0）。
2. 第 3 条剩余手工回归（需后端实例与 Android 真机）。
3. 跨大版本依赖升级评估；播放器操作接口抽象（解锁 handler 无头测试）。
4. `Data/` 三个 Store 与 `SqliteDatabasePath` 的路径解析收敛；错误文案结构调整。

## 本轮已完成清单（供对照）

| 上轮条目 | 状态 | 提交 |
| --- | --- | --- |
| P0-1 移除硬编码 IP | ✅ 完成（默认空串 + AppSettings `backend.base_url` + 账号页输入与引导 + 文档） | `4e20fe08` |
| P0-2 收紧 CORS | ✅ 完成（`CorsOriginPolicy` + `Cors:AllowedOrigins` + 回环兜底 + 测试重写） | `3a3fe7f4` |
| P0-3 最小 CI | ✅ 完成（flutter/backend 两条 job + web 冒烟） | `29b524f5` |
| P1-4 核心逻辑测试 | ✅ 完成（`playback_queue_logic.dart` 19 用例 + 同步合并 6 用例；未引入 mocktail，理由见提交说明） | `9f03c0c6` |
| P1-5 日志底线 | ✅ 完成（`AppLog` + 启动/均衡器/通知链路 + 可选增强降级注释） | `8306466a`、`8279a7a5` |
| P1-6 library_page 重复与 N+1 | ✅ 完成（共享菜单 + `addExistingTracksToPlaylist` 单事务批量；注意 drift `batch.replaceAll` 只更新不插入的坑，已在代码注释） | `240c69a5` |
| P1-7 拆分巨型页面 | 🔶 部分完成（settings_page 完成；online_search/equalizer/now_playing 遗留 → 本文第 4 条） | `debdb29c` |
| P2-8 错误文案上移 | ⏸ 遗留 → 本文第 7 条 | — |
| P2-9 拆分 MusicAudioHandler | 🔶 部分完成（纯函数已抽出；均衡器/音量/注入遗留 → 本文第 6 条） | `9f03c0c6` |
| P2-10 AuthService 拆分 | ⏸ 遗留 → 本文第 5 条 | — |
| P2-11 杂项清理 | ✅ 完成（pubspec 清理；`app_icon.ico` 确认为托盘必需保留；Program.cs fail-fast 评估后保留 → 本文第 9 条） | `8c4ead71` |

### 验证记录

- 通过：`flutter analyze`（0 问题）、`flutter test`（100 项）、`dotnet test -c Release`（47 项）、`flutter build web`、`flutter build windows --debug`。
- 待确认：CI 首次线上运行（本文第 2 条）。
- 未执行：Android/Linux 构建、后端 `/health` 手工探活、Docker compose 校验（本轮未触及 Docker 相关文件）。

## 执行进展（2026-09-03，V2 计划落地，按批次提交）

| 批次 | 内容 | 提交 |
| --- | --- | --- |
| A | P0-1 删除误伤的 `docs/` 忽略规则，四份文档入库 | `e6f8c9ba` |
| B | P2-8 扫描 6 处降级路径接入 AppLog；P2-11 删除零引用 JsonTool.cs，后端零警告 | `ca104311` |
| C | P2-10 常规依赖升级（drift/riverpod/audio_metadata_reader/image） | `51929b53` |
| D | P1-4 拆分 now_playing_page（787→304 行 + 5 个模块） | `a2178920` |
| E | P1-4 拆分 equalizer_view（864→504 行 + 4 个组件） | `a513a2b0` |
| F | P1-4 拆分 online_search_page（1076→约 400 行 + 2 个模块） | `48904c6e` |
| G | P1-5 AuthService 拆分 RefreshTokenStore + 4 个集成测试 + 启动冒烟 | `3fedd3d1` |
| H | P1-6 均衡器控制器、设置解析去重、音量状态机 + 11 个单测 | `4990a8d1` |

### 执行后验证记录

- 通过：`flutter analyze`（0 问题）、`flutter test`（111 项）、`dotnet test -c Release`（51 项）、`flutter build web`、`flutter build windows --debug`。
- 通过：后端运行时冒烟（`/health` 200、`/openapi.json` 200；`/health/ready` 503 为本地无 sidecar 的预期行为）。
- 通过：Windows 调试版实机启动，歌单/设置/账号页渲染与导航正常（真机深度回归路径见第 3 条）。
- 未执行：CI 首次线上运行（需推送）、Android/Linux 构建、跨大版本依赖升级。
