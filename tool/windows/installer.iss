; Inno Setup 6 安装器定义。
;
; 安装到用户目录（lowest 权限）：Program Files 普通用户不可写，
; 自动更新覆盖文件会失败。放用户目录后，更新脚本不需要管理员权限。
;
; 用法（由 tool/package_windows.ps1 -Installer 调用）：
;   ISCC.exe /DMyAppVersion=0.3.8 tool\windows\installer.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "Auto-Chaoxing"
#define MyAppPublisher "SubmergeDQ"
#define MyAppExeName "auto_chaoxing.exe"

[Setup]
AppId={{6F1B2A54-9C3E-4D7A-8B21-5E0D7C4A9F13}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; lowest + autopf 会落到 %LOCALAPPDATA%\Programs，自动更新可写。
DefaultDirName={autopf}\Auto-Chaoxing
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=auto-chaoxing-setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 应用已退出才安装；万一还在运行，让 Restart Manager 帮忙关闭，
; 避免「装完还是旧版本」——运行中的 exe 写不进去。
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "chs"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
  Flags: nowait postinstall skipifsilent
