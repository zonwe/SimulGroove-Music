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
pwsh ./tool/android_device_acceptance.ps1
```

连接多台设备时使用 `adb devices -l` 显示的序列号：

```powershell
pwsh ./tool/android_device_acceptance.ps1 -Serial "DEVICE_SERIAL"
```

脚本会完成以下自动检查：

- APK 只包含 `arm64-v8a` 原生库，并通过 APK Signature Scheme v2 验证。
- 目标是已授权的真实设备，主 ABI 为 `arm64-v8a`。
- APK 能覆盖安装，包名为 `top.zonwe.simul_groove_player`。
- `MainActivity` 返回成功启动状态，应用进程在启动后仍存活。
- 记录 APK SHA-256、签名身份、设备型号、Android 版本和已安装版本。

当前开发回归包使用 Android Debug 证书签名，因此可用于真机功能验收，但不能证明应用商店签名准备完成。正式发布签名就绪后增加 `-RequireProductionSignature`，脚本会拒绝 Debug 证书。

脚本默认以 `K80|25060` 匹配制造商、型号和设备代号的组合文本，防止把其他 ARM64 设备误记为本次目标真机。若设备固件报告了不同但已人工核实的正式型号，可显式覆盖 `-ExpectedModelPattern`：

```powershell
pwsh ./tool/android_device_acceptance.ps1 `
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
  -Serial "DEVICE_SERIAL" `
  -SkipInstall `
  -ConfirmedCheck permission-flow,folder-scan,device-scan,scan-notification,local-playback,media-controls,account-sync `
  -ConfirmationReference "K80-20260907-01"
```

只有所有检查项和 `ConfirmationReference` 均存在时，证据状态才会是 `complete`。结果写入已被忽略的 `build/acceptance/android/`，设备序列号仅保存 SHA-256 截断指纹，不采集音乐文件名、账号、令牌或应用日志。
