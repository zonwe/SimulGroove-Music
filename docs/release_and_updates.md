# 发布、Windows 安装器与应用内更新

本文说明 SimulGroove Music 的 Windows 安装器、Android APK 分发，以及客户端内置的更新检查与安装流程。发布产物统一通过 GitHub Releases 分发，客户端读取同一 Release 中的 `latest.json`。

## 1. 总体结构

```text
tag v1.1.0 / 手动触发
        │
        ├─ Windows 构建 ─→ Inno Setup 安装器 ─┐
        ├─ Android 构建 ─→ 三个 ABI 的 APK ───┤
        │                                     ▼
        └──────────────────────→ latest.json + SHA256SUMS
                                              │
                                      GitHub Release
                                              │
                 客户端 GET .../releases/latest/download/latest.json
                                              │
                 检查版本 → 下载 → SHA-256 校验 → 安装
```

- 客户端不硬编码具体版本号；版本号来自 `pubspec.yaml` 的 `x.y.z+build`。
- `latest.json` 是唯一更新契约。GitHub 的 `releases/latest/download/<asset>` 是稳定地址，会自动指向最新正式 Release。
- 自建分发可以在构建时覆盖清单地址：

  ```powershell
  flutter build windows --release --dart-define=UPDATE_MANIFEST_URL=https://example.com/simulgroove/latest.json
  ```

  清单与安装包都必须使用 HTTPS；安装包哈希始终按清单校验。

## 2. 版本号与发布规则

1. 修改 `pubspec.yaml`：

   ```yaml
   version: 1.1.0+5
   ```

   - `1.1.0` 是语义版本，对应 Git tag `v1.1.0`。
   - `5` 是构建号：Windows 资源版本与 Android `versionName` 中的 `+build` 都取自它；Flutter 还会按 ABI 给 Android `versionCode` 加千位偏移。**每次发布必须递增**，否则 Android 会拒绝安装降级包。
2. 打 tag 或手动运行 `.github/workflows/release.yml`。工作流会校验 `pubspec.yaml` 的版本与 tag/输入一致。
3. 发布说明优先读取 `docs/releases/v<version>.md`；没有时使用工作流输入或自动生成的简短说明。

## 3. Windows 安装器

### 3.1 行为

- 使用 Inno Setup 6，脚本位于 `build_command/installer/simul_groove_music.iss`。
- `PrivilegesRequired=lowest`：按当前用户安装到 `%LOCALAPPDATA%\Programs\SimulGroove Music`，不触发 UAC。
- 安装目录只包含程序文件。Drift 数据库默认位于 `%USERPROFILE%\Documents\flutter_music.sqlite`（跟随系统 Documents / OneDrive 重定向）；其他应用支持数据位于 `%APPDATA%\top.zonwe\SimulGroove Music`。升级和卸载都不会删除用户数据。
- 同一 `AppId` 的安装器会原地升级；`UsePreviousAppDir=yes` 复用用户选择的安装目录。
- 桌面快捷方式为可选任务，开始菜单快捷方式默认创建。
- 安装时若检测到主窗口仍在运行，会提示先退出。托盘最小化会隐藏窗口但进程仍在运行，因此必须从托盘菜单选择“退出应用”。

> **不要随意修改 `windows/runner/Runner.rc` 中的 `CompanyName` / `ProductName`。**
> `path_provider` 用它们生成应用支持目录（当前为 `%APPDATA%\top.zonwe\SimulGroove Music`），封面缓存等数据可能落在那里。Drift 数据库本身在 Documents，不会因此移动；如果要改标识，仍需迁移旧支持目录。

### 3.2 本地构建

先安装 Inno Setup 6（任选其一）：

```powershell
winget install --id JRSoftware.InnoSetup -e
```

然后：

```powershell
flutter build windows --release
powershell -ExecutionPolicy Bypass -File build_command/build_installer.ps1
```

脚本会从 `pubspec.yaml` 读取版本，输出：

```text
build\artifacts\windows-installer\SimulGrooveMusic-Setup-1.1.0-x64.exe
```

也可以显式指定版本或工具路径：

```powershell
powershell -ExecutionPolicy Bypass -File build_command/build_installer.ps1 -Version 1.1.0 -BuildNumber 4 -IsccPath "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

`build_command/build.ps1` 在检测到 Inno Setup 时会追加“Windows 安装包”步骤；未安装时该步骤跳过，不影响其他目标。

### 3.3 代码签名

安装器和 exe 目前未做 Authenticode 签名，首次运行会触发 SmartScreen“未知发布者”。正式分发建议配置证书，并在 Inno Setup 中增加 `SignTool`/`SignedUninstaller`；未签名不影响应用内更新的哈希校验，但用户仍会看到系统警告。

## 4. Windows 应用内更新

### 4.1 流程

1. 设置页的“自动检查更新”默认开启（可手动关闭）；启动后最多每 24 小时检查一次 GitHub Release，发现新版本时先提示。“自动下载更新”默认关闭，只有显式开启后才在后台下载并校验，随后请求安装确认。设置页也可手动检查。
2. 读取 `latest.json`，选择 `windows-x64` 资产，按 `x.y.z` 分段与构建号比较。
3. 开启自动下载时，在后台下载到 `%TEMP%\SimulGrooveMusic\updates`，同时计算 SHA-256，并显示不阻塞操作的后台下载提示；未开启时等待用户在对话框中点击下载。
4. 下载完成后比较清单中的 `size` 与 `sha256`；不匹配立即删除，并在更新对话框中给出重试入口。
5. 用户确认后生成更新助手 `apply-update-<时间戳>.cmd`，由它：
   - 等待当前进程退出；
   - 以 `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=...` 运行安装器；
   - 成功后重新启动应用；失败时写入 `update-failed.txt` 并重启旧版本。
6. 应用确认助手已启动后，走正常退出流程（保存播放快照）并退出。

助手脚本中的路径不直接写入 `.cmd`，而是通过环境变量传给 `cmd.exe`，避免中文用户名路径被批处理代码页错误解码。路径必须是 Windows 绝对路径，安装器/主程序必须以 `.exe` 结尾，并拒绝引号与换行。安装包路径来自清单 URL，且必须位于受信任主机（`github.com`、`objects.githubusercontent.com`、`release-assets.githubusercontent.com`，或清单自身主机）。

SHA-256 只能证明下载内容与清单一致，信任根仍是 HTTPS 更新源；Windows 安装器未签名时无法校验发布者身份，正式分发建议启用 Authenticode。

### 4.2 解压版限制

只有安装版（目录中存在 `unins000.exe`）才允许应用内静默升级。解压版不会在启动时自动下载安装器，而是在更新对话框中提示“复制下载链接”，由用户手动下载安装；安装版后续可按需开启自动下载。

### 4.3 失败处理

- `%TEMP%\SimulGrooveMusic\updates\update-failed.txt` 保存安装器退出码与日志路径。
- 下次启动时窗口会显示失败提示；日志文件为同目录的 `update-install-<时间戳>.log`。
- 更新包校验失败、清单 404、网络超时都会在设置页给出可读错误，不会静默退出应用。
- 启动检查失败也会记录本次尝试时间，最多每 24 小时自动重试一次；设置页的手动检查不受间隔限制。

## 5. Android 应用内更新

### 5.1 流程

1. 通过 `Abi.current()` 选择 `android-arm64-v8a`、`android-armeabi-v7a` 或 `android-x86_64` 资产。
2. 开启“自动下载更新”时，启动检查会在后台把匹配 ABI 的 APK 下载到应用缓存 `SimulGrooveMusic/updates`，校验大小与 SHA-256，然后弹出安装确认；默认关闭时只提示版本，等用户点击后才下载。
3. Dart 通过 MethodChannel `top.zonwe.simul_groove_player/updater` 调用原生 `installApk`。
4. Kotlin 校验 APK 位于更新缓存目录，使用 `FileProvider` 生成 `content://` URI，并打开系统安装界面。
5. Android 8+ 若未授予“安装未知应用”，会跳转到本应用的授权页并返回错误；授权后重试即可。

Android **不允许普通应用静默安装**，用户必须在系统安装界面确认。签名校验、降级拒绝和覆盖安装由 Android 系统完成。

### 5.2 稳定签名（必需）

Android 只允许用与已安装版本相同的证书签名的新版 APK 覆盖安装。CI 每次生成的 debug 证书并不稳定，因此正式发布必须配置固定 keystore：

1. 生成密钥（会打印 GitHub Secrets 所需的 base64）：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tool/generate_android_keystore.ps1 `
     -Alias simulgroove `
     -StorePassword "your-store-password" `
     -KeyPassword "your-store-password"
   ```

2. 离线备份 `android/app/simulgroove-release.jks` 和密码。**丢失后已安装用户无法再通过应用内更新升级。**
3. 在 GitHub 仓库 Secrets 中配置：

   | Secret | 值 |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | 脚本输出的 base64 |
   | `ANDROID_KEY_ALIAS` | `simulgroove` |
   | `ANDROID_KEY_PASSWORD` | key 密码（PKCS12 通常与 store 密码相同） |
   | `ANDROID_STORE_PASSWORD` | store 密码 |

4. 本地构建时复制 `android/key.properties.example` 为 `android/key.properties` 并填写；该文件与 `*.jks` 已被 `.gitignore` 忽略。

没有 `key.properties` 时 Gradle 继续使用 debug 签名，只能用于本地调试；这样的 APK 不能与其他构建互相更新。

> **从 v1.0.0 升级要先处理签名。** v1.0.0 使用开发机的 debug 证书；如果 1.1.0 使用新的发布密钥签名，Android 会以“签名不一致”拒绝覆盖安装，必须先卸载旧版（会清除应用内的音乐库索引、设置和播放快照）再安装 1.1.0。若要保留数据，可把原来的 `%USERPROFILE%\.android\debug.keystore`（密码通常为 `android`，别名 `androiddebugkey`，且证书仍在有效期内）配置为发布密钥——仅私人设备可接受；或先通过账号同步备份歌单/喜欢/均衡器，再重新扫描本地音乐。确认签名策略后，后续版本保持同一密钥即可持续自更新。

### 5.3 ABI 与版本号

- 发布工作流使用 `flutter build apk --release --split-per-abi` 生成三个 APK。
- 客户端只会下载与当前进程 ABI 匹配的 APK；模拟器通常对应 `android-x86_64`。
- Android 系统按 `versionCode` 比较版本，`pubspec.yaml` 的 `+build` 必须递增。
- Flutter 会按 ABI 给 `versionCode` 加千位偏移（arm64 的构建号 4 对应 2004，armeabi 对应 1004，x86_64 对应 4004）。应用内更新比较的是 `versionName` 中的 `+build`；Gradle 已把 `+<build>` 写入 `versionName`，因此 `package_info_plus` 返回 `1.1.0+4`，不会把 ABI 偏移误当成构建号。

## 6. `latest.json` 契约

示例（Windows + Android）：

```json
{
  "schemaVersion": 1,
  "channel": "stable",
  "version": "1.1.0",
  "buildNumber": 4,
  "publishedAt": "2026-10-21T00:00:00Z",
  "notes": "新增 Windows 安装器与 Android 应用内更新。",
  "assets": {
    "windows-x64": {
      "url": "https://github.com/zonwe/SimulGroove-Music/releases/download/v1.1.0/SimulGroove-Music-v1.1.0-windows-x64-setup.exe",
      "size": 32000000,
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "kind": "installer"
    },
    "android-arm64-v8a": {
      "url": "https://github.com/zonwe/SimulGroove-Music/releases/download/v1.1.0/SimulGroove-Music-v1.1.0-android-arm64-v8a.apk",
      "size": 25000000,
      "sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
      "kind": "apk"
    }
  }
}
```

校验规则：

- `schemaVersion` 必须为 `1`。
- 资产地址必须为 HTTPS，且主机在受信任列表内。
- `size` 为正整数，上限 1 GiB。
- `sha256` 为 64 位十六进制字符串；下载后必须完全一致。
- `kind` 只接受 `installer`、`apk`、`portable`。
- 版本号 `1.1.0` 与 `buildNumber: 4` 一起参与比较；只比较构建号更大的同版本也算更新。

## 7. 发布清单生成

工作流会自动调用：

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_update_manifest.ps1 `
  -Version 1.1.0 `
  -BuildNumber 4 `
  -InstallerPath "dist\SimulGroove-Music-v1.1.0-windows-x64-setup.exe" `
  -AndroidArm64Apk "dist\SimulGroove-Music-v1.1.0-android-arm64-v8a.apk" `
  -AndroidArmV7Apk "dist\SimulGroove-Music-v1.1.0-android-armeabi-v7a.apk" `
  -AndroidX64Apk "dist\SimulGroove-Music-v1.1.0-android-x86_64.apk" `
  -NotesFile "docs/releases/v1.1.0.md" `
  -OutputPath "dist\latest.json"
```

手工发布时注意：

- Release 资产文件名必须与 `latest.json` 中的 URL 完全一致。
- `latest.json` 必须上传到该 Release；`releases/latest/download/latest.json` 才能取到。
- 预览版应使用 `prerelease`，GitHub 的 `latest` 不会指向预览版；客户端目前只支持稳定渠道。

## 8. 发布步骤（检查表）

1. 备份并确认 Android 发布密钥仍可用。若要覆盖 v1.0.0 的 debug 签名安装，必须复用原 debug keystore；否则 Android 会要求先卸载旧版（会清除应用数据）才能安装新签名版本。
2. 修改 `pubspec.yaml` 的 `version: x.y.z+build`，递增 build。
3. 在 `docs/releases/vx.y.z.md` 写发布说明（可选，工作流会优先使用）。
4. 本地验证：

   ```powershell
   dart format --output=none --set-exit-if-changed lib test
   flutter analyze
   flutter test
   flutter build windows --release
   powershell -ExecutionPolicy Bypass -File build_command/build_installer.ps1
   flutter build apk --release --split-per-abi
   ```

5. 推送 tag：

   ```powershell
   git tag v1.1.0
   git push origin v1.1.0
   ```

   或在 Actions 中手动运行 `Release` 并填写版本号。
6. 确认 Release 包含安装器、便携 zip、三个 APK、`latest.json`、`SHA256SUMS.txt`。
7. 安装旧版后点击“检查更新”，验证下载、校验、安装或 Android 系统安装界面。

## 9. 已知限制

- Linux 与 Web 未实现应用内更新；Linux 仍按发行包手工升级。
- Windows 便携版不自动下载安装器，只能手动更新。
- Android 必须允许“安装未知应用”，且不能静默安装；开启自动下载时也只自动完成检查与下载，安装仍需用户在系统界面确认。
- 开启“自动下载更新”后不会检测计费网络；需要节省流量时保持默认关闭，或关闭自动检查后手动检查。
- 未配置稳定 Android 密钥时，CI 发布任务会直接失败，避免发布不可自更新的 APK。
- 安装器和 exe 未做 Authenticode 签名，SmartScreen 会提示未知发布者。

## 10. 故障排查

| 现象 | 排查 |
| --- | --- |
| 检查更新提示 404 | Release 是否上传了 `latest.json`；是否误发成 prerelease |
| 提示哈希校验失败 | 清单与资产不匹配；重新生成 `latest.json`，不要手工改哈希 |
| Windows 提示解压版 | 目录中没有 `unins000.exe`；改用安装器安装一次 |
| 安装器提示应用正在运行 | 从托盘菜单退出应用，而不是点窗口关闭 |
| Android 提示签名不一致 | 新 APK 与已安装版本证书不同；恢复原 keystore 并重新构建 |
| Android 无法打开安装界面 | 在系统设置中允许本应用安装未知应用 |
| Android 提示降级 | `pubspec.yaml` 的 `+build` 没有递增 |
| 更新后用户数据“消失” | 检查是否换了 Windows 用户、改了 Documents/OneDrive 重定向，或修改了 `Runner.rc` 的 `CompanyName`/`ProductName`（影响支持目录，不是数据库） |
