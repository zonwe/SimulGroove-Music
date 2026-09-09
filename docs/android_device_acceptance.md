# Android 真机验收

本流程用于 Redmi K80 Ultra 等 ARM64 真机的发布兼容性与深度功能回归。模拟器结果不能替代本流程，脚本会读取 `ro.kernel.qemu` 和 `ro.boot.qemu` 并拒绝模拟器。

## 前提

- 已通过 USB 或无线调试连接一台真机，并在设备上允许当前电脑调试。
- `adb` 和 `apksigner` 已加入 `PATH`。
- 已生成 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。
- 设备中准备了至少一首可正常播放的音乐、一个损坏或不完整标签的文件，以及可选的同名 LRC。
- 若要验证账号同步，设备能够访问一套测试后端，且不使用生产账号或真实密钥。

先查看人工检查项，此命令不会访问设备或安装 APK：

```powershell
pwsh ./tool/android_device_acceptance.ps1 -ListChecks
```

## 安装与启动预检

只连接一台设备时可直接运行：

```powershell
$buildRevision = git rev-parse HEAD
pwsh ./tool/android_device_acceptance.ps1 -BuildRevision $buildRevision
```

连接多台设备时使用 `adb devices -l` 显示的序列号：

```powershell
pwsh ./tool/android_device_acceptance.ps1 `
  -BuildRevision $buildRevision `
  -Serial "DEVICE_SERIAL"
```

脚本会完成以下自动检查：

- APK 只包含 `arm64-v8a` 原生库，并通过 APK Signature Scheme v2 验证。
- 目标是已授权的真实设备，主 ABI 为 `arm64-v8a`。
- APK 能覆盖安装，包名为 `top.zonwe.simul_groove_player`。
- `MainActivity` 返回成功启动状态，应用进程在启动后仍存活。
- 当前传入的完整提交修订等于检出仓库的 Git HEAD，且工作区不存在实际的未提交、已暂存或未跟踪非忽略内容，避免把脏工作区构建错误归属给该提交；构建工具仅以相同内容重写生成文件时不会被文件时间或 Git 文件系统监控状态误判。
- 记录 APK SHA-256、签名身份、设备型号、Android 版本和已安装版本。

当前开发回归包使用 Android Debug 证书签名，因此可用于真机功能验收，但不能证明应用商店签名准备完成。正式发布签名就绪后增加 `-RequireProductionSignature`，脚本会拒绝 Debug 证书。

脚本默认以 `K80|25060` 匹配制造商、型号和设备代号的组合文本，防止把其他 ARM64 设备误记为本次目标真机。若设备固件报告了不同但已人工核实的正式型号，可显式覆盖 `-ExpectedModelPattern`：

```powershell
pwsh ./tool/android_device_acceptance.ps1 `
  -BuildRevision $buildRevision `
  -Serial "DEVICE_SERIAL" `
  -ExpectedModelPattern "Redmi|25060"
```

## 深度人工回归

自动启动成功后，按 `-ListChecks` 的说明逐项验证：

1. 拒绝和允许通知、媒体权限，确认两条路径都有明确反馈。
2. 授权真实目录，确认首次扫描、封面、歌词和重扫。
3. 执行全设备扫描，确认重复文件与损坏文件不会中断扫描。
4. 确认扫描通知在前台和后台均可见。
5. 验证本地播放、暂停、切歌、进度、循环、随机和队列。
6. 验证通知栏、锁屏、耳机或蓝牙媒体键与音频焦点。
7. 验证真实后端登录恢复，以及歌单、喜欢和均衡器同步。

全部完成后用相同设备再运行一次，跳过重复安装并显式提交所有检查项：

```powershell
pwsh ./tool/android_device_acceptance.ps1 `
  -BuildRevision $buildRevision `
  -Serial "DEVICE_SERIAL" `
  -SkipInstall `
  -ConfirmedCheck permission-flow,folder-scan,device-scan,scan-notification,local-playback,media-controls,account-sync `
  -ConfirmationReference "K80-20260907-01"
```

只有所有检查项和 `ConfirmationReference` 均存在时，证据状态才可能是 `complete`；批次编号只能包含 1 到 64 位字母、数字、点、下划线或连字符，不能写入账号、设备序列号等个人信息。Complete 还必须在同一证据目录中找到七天内生成的 schema v2 Preflight 证据，并确认其仓库提交、设备指纹、候选 APK 与设备安装包哈希完全一致，且 Preflight 确实执行过安装。最终证据会记录前置证据文件，旧版或手工放置的候选 APK 不能单独完成验收。

本地执行 Preflight 和 Complete 时都必须从干净检出运行；若当前目录保留个人文档、生成文件或其他未提交内容，请另建干净 worktree 或 clone 执行验收，不要为了通过门禁删除仍需保留的工作。

结果写入已被忽略的 `build/acceptance/android/`，设备序列号仅保存 SHA-256 截断指纹，不采集音乐文件名、账号、令牌或应用日志。

## GitHub 受保护验收工作流

`.github/workflows/android-device-acceptance.yml` 提供只允许从仓库默认分支手动触发的两阶段真机验收。它使用 `android-k80-acceptance` Environment，以及同时带有 `windows`、`x64` 和 `simulgroove-android-device` 标签的自托管执行器。执行器必须连接目标真机，并预装 Android SDK、`adb`、`apksigner` 和 Flutter 所需构建工具；应为 Environment 配置必需审批人。

在 `android-k80-acceptance` Environment 中配置：

- `ANDROID_ACCEPTANCE_EVIDENCE_DIR` 变量：位于检出工作区之外、可跨工作流运行持久保存证据的专用绝对目录；不得使用文件系统根目录，路径任一级也不得是符号链接或目录联接。
- `ANDROID_EXPECTED_MODEL_PATTERN` 变量：可选，留空时脚本继续使用 `K80|25060`。
- `ANDROID_DEVICE_SERIAL` 密钥：可选；留空时执行器必须只连接一台已授权设备。使用密钥可以避免设备序列号出现在公开的手动输入中。

先选择 `Preflight`，工作流会构建 ARM64 Release APK、把该提交的候选包保存在外部证据目录、验证 ABI 与签名、安装并启动应用，预期生成 `manual_checks_pending` 证据。随后在设备上完成七项人工回归，再从同一提交选择 `Complete`、勾选全部确认项并填写仅含字母、数字、点、下划线或连字符的验收批次编号；工作流会复用同一候选包，通过设备端 SHA-256 证明当前安装包与候选包一致，并要求同一目录中存在匹配的七天内 Preflight 证据。只有脚本生成带前置证据引用的 `complete` 才通过；默认分支在两阶段之间更新时必须从新提交重新执行 Preflight。

完整 JSON 证据保留在自托管执行器的外部目录，不上传到 GitHub。若勾选正式签名要求，脚本会拒绝当前 Android Debug 证书，因此只能在发布签名已经配置后使用。

外部目录可保留历次 Preflight 与 Complete JSON，但每次工作流只接受本次脚本新建且唯一的证据文件，再核对状态、schema、提交与前置证据引用；文件修改时间不会被用来猜测本次结果。
