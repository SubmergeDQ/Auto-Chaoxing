; Inno Setup 6 安装器定义。
;
; 安装位置可选：默认优先非系统盘（D–Z 中第一个存在的盘，<盘>:\Auto-Chaoxing），
; 没有可用盘才退回用户目录。登录会话与设置写在 <安装目录>\userdata\，
; 所以安装目录必须是当前用户可写的（Program Files 这类只读位置会被拦下）。
;
; 用法（由 tool/package_windows.ps1 -Installer 调用）：
;   ISCC.exe /DMyAppVersion=0.4.6 tool\windows\installer.iss

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
; 目录页保持可见，用户可以在安装时改到任意可写位置；升级沿用上次目录。
DefaultDirName={code:GetDefaultInstallDir}
DisableDirPage=no
UsePreviousAppDir=yes
; 应用正在运行时提示先退出：单实例互斥量自带会话隔离。
AppMutex=Local\Auto-Chaoxing-Single-Instance
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
; 语言文件随仓库提供：Inno Setup 6.5+ 的安装包不再自带非英文翻译，
; 依赖 compiler:Languages 路径会让 CI 编译直接失败。
Name: "chs"; MessagesFile: "ChineseSimplified.isl"

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

[Code]
// 默认装到 D–Z 中第一个存在的盘，避免默认落在 C 盘；没有其它盘才回退用户目录。
function GetDefaultInstallDir(Param: String): String;
var
  I: Integer;
  Drive: String;
begin
  for I := Ord('D') to Ord('Z') do
  begin
    Drive := Chr(I);
    if DirExists(Drive + ':\') then
    begin
      Result := Drive + ':\Auto-Chaoxing';
      Exit;
    end;
  end;
  Result := ExpandConstant('{autopf}\Auto-Chaoxing');
end;

// 数据要写进安装目录，先确认目录能创建、能写。
function IsWritableDir(const Dir: String): Boolean;
var
  Probe: String;
begin
  Result := False;
  if not DirExists(Dir) then
  begin
    if not ForceDirectories(Dir) then
      Exit;
  end;
  Probe := AddBackslash(Dir) + '.acx_write_probe';
  if SaveStringToFile(Probe, 'probe', False) then
  begin
    DeleteFile(Probe);
    Result := True;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    if not IsWritableDir(WizardDirValue) then
    begin
      MsgBox(
        '这个位置当前用户不可写。' + #13#10 + #13#10 +
        '应用会把登录会话与设置保存在安装目录的 userdata 子目录里，' + #13#10 +
        '请选择当前用户可写的位置，例如 D:\Auto-Chaoxing。',
        mbError, MB_OK);
      Result := False;
    end;
  end;
end;
