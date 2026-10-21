; SimulGroove Music 的 Windows 安装器（Inno Setup 6）。
;
; 设计约束：
; - 按用户安装（PrivilegesRequired=lowest），安装目录位于
;   %LOCALAPPDATA%\Programs，应用内静默升级不需要 UAC。
; - 安装目录只放程序文件；数据库、设置和缓存位于 %APPDATA% 下，
;   升级/卸载不会动用户数据。
; - CloseApplications=no：升级由应用内更新助手先退出应用再运行安装器；
;   手动运行安装器时由下方的 [Code] 拦截并提示先退出应用。

#define AppName "SimulGroove Music"
#define AppPublisher "top.zonwe"
#define AppExeName "simul_groove_player.exe"

#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif

#ifndef AppBuild
  #define AppBuild "4"
#endif

#ifndef ReleaseDir
  #define ReleaseDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\build\artifacts\windows-installer"
#endif

[Setup]
; AppId 必须永久稳定：Inno 通过它识别“升级”而不是“并存安装”。
AppId={{7C1E5D3A-9B24-4F86-8A15-2D7E4C6B9F30}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename=SimulGrooveMusic-Setup-{#AppVersion}-x64
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
DisableWelcomePage=no
DisableReadyPage=no
UsePreviousAppDir=yes
UsePreviousTasks=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; 新版本可能删除或重命名 Flutter 资源；先清空旧资源目录，避免残留损坏资源。
Type: filesandordirs; Name: "{app}\data\flutter_assets"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
begin
  // 安装器替换 exe 和 DLL 时应用必须已退出。托盘最小化会让窗口隐藏但进程
  // 仍在运行，因此这里按窗口标题检测，而不是只看窗口是否可见。
  if FindWindowByWindowName('SimulGroove Music') <> 0 then
  begin
    if not WizardSilent then
      MsgBox(
        '检测到 SimulGroove Music 正在运行。' + #13#10 +
        '请从托盘菜单选择“退出应用”，然后重新运行安装程序。',
        mbError,
        MB_OK
      );
    Result := False;
  end
  else
    Result := True;
end;
