#ifndef PayloadDir
  #error PayloadDir is required
#endif
#ifndef ReleaseTag
  #error ReleaseTag is required
#endif
#ifndef ProductVersion
  #error ProductVersion is required
#endif
#ifndef HostSha256
  #error HostSha256 is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef Isolated
  #define Isolated 0
#endif
#if Isolated
  #ifndef IsolatedRoot
    #error IsolatedRoot is required for an isolated build
  #endif
  #ifndef IsolatedId
    #error IsolatedId is required for an isolated build
  #endif
  #ifndef IsolatedRootCode
    #error IsolatedRootCode is required for an isolated build
  #endif
  #define MutexSuffix IsolatedId
#else
  #define MutexSuffix "PerUser"
#endif

[Setup]
#if Isolated
AppId=SteamWrapper-Installer-Test-{#IsolatedId}
AppName=SteamWrapper isolated installer test
UninstallDisplayName=SteamWrapper isolated installer test {#IsolatedId}
#else
AppId={{B7DBEC23-E563-4BFB-BE9C-F68D73E4D5BB}
AppName=SteamWrapper
UninstallDisplayName=SteamWrapper
#endif
AppVersion={#ReleaseTag}
VersionInfoVersion={#ProductVersion}.0
VersionInfoTextVersion={#ProductVersion}
VersionInfoProductName=SteamWrapper
VersionInfoProductVersion={#ProductVersion}
VersionInfoProductTextVersion={#ProductVersion}
AppPublisher=SteamWrapper contributors
AppPublisherURL=https://github.com/YangYuS8/SteamWrapper
AppSupportURL=https://github.com/YangYuS8/SteamWrapper/issues
AppUpdatesURL=https://github.com/YangYuS8/SteamWrapper/releases
DefaultDirName={code:InstallRoot}
DisableDirPage=yes
UsePreviousAppDir=no
DefaultGroupName=SteamWrapper
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
SetupArchitecture=x64
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.26100
CloseApplications=no
RestartApplications=no
SetupMutex=SteamWrapper-Setup-{#MutexSuffix}
UninstallDisplayIcon={app}\SteamWrapper.exe
LicenseFile={#PayloadDir}\LICENSE
SetupIconFile={#PayloadDir}\Assets\steamwrapper.ico
OutputDir={#OutputDir}
OutputBaseFilename=SteamWrapper-{#ReleaseTag}-win-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern dynamic
WizardSizePercent=120
Uninstallable=yes
AllowNoIcons=yes
UninstallLogMode=append
DisableStartupPrompt=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[CustomMessages]
english.DesktopIcon=Create a desktop shortcut
chinesesimplified.DesktopIcon=创建桌面快捷方式
english.RetainedData=SteamWrapper installs only Manager. Your profiles, stable Runner, logs, backups and caches are kept when Manager is removed. Steam game files and Launch Options are not changed.
chinesesimplified.RetainedData=SteamWrapper 仅安装管理器。卸载管理器时会保留配置、稳定路径中的 Runner、日志、备份和缓存。安装器不会修改 Steam 游戏文件或启动选项。
english.FixedRoot=This installer uses its fixed per-user program directory. A different directory cannot be selected.
chinesesimplified.FixedRoot=此安装器使用当前用户的固定程序目录，不能选择其他目录。
english.DeploymentFailure=Manager installation could not complete. Close all Manager instances, preserve your data, and run this installer again. Deployment exit code: %1.
chinesesimplified.DeploymentFailure=管理器安装未完成。请关闭所有管理器实例，保留您的数据，然后重新运行此安装器。部署退出代码：%1。
english.DeploymentTimeout=Manager installation did not become ready within the allowed time. No application was force-closed. Run this installer again after existing Manager instances exit.
chinesesimplified.DeploymentTimeout=管理器安装未在允许的时间内就绪。安装器没有强制关闭任何应用。请在现有管理器实例退出后重新运行此安装器。
english.UninstallFailure=Manager could not be removed safely. Close all Manager instances and try again. Your game profiles and Runner have been kept.
chinesesimplified.UninstallFailure=无法安全卸载管理器。请关闭所有管理器实例后重试。您的游戏配置和 Runner 已保留。
english.HostInvalid=The deployment component is missing or changed. Use a complete matching installer to repair Manager before uninstalling.
chinesesimplified.HostInvalid=部署组件缺失或已被更改。请先使用完整且匹配的安装器修复管理器，再进行卸载。
english.LaunchManager=Open SteamWrapper Manager
chinesesimplified.LaunchManager=打开 SteamWrapper 管理器
english.ClientWindowsRequired=This preview requires Windows 11 24H2 or later on a native x64 PC. Windows Server is not a supported player installation target.
chinesesimplified.ClientWindowsRequired=此预览需要原生 x64 电脑上的 Windows 11 24H2 或更高版本。Windows Server 不属于支持的玩家安装目标。
english.LeaseReleaseFailure=The deployment component did not confirm that it released Manager's installation lock. Manager was not opened. Run this installer again after the deployment component exits.
chinesesimplified.LeaseReleaseFailure=部署组件未确认已释放管理器安装锁，因此没有打开管理器。请在部署组件退出后重新运行此安装器。

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; Flags: unchecked

[Files]
; The deployment component alone owns version directories and activation state.
Source: "{#PayloadDir}\*"; DestDir: "{tmp}\payload"; Flags: dontcopy recursesubdirs createallsubdirs
; Inno tracks only its independent maintenance host and its own uninstall files.
Source: "{#PayloadDir}\Deployment\SteamWrapper.exe"; DestDir: "{app}\maintenance"; DestName: "SteamWrapper.Deployment.exe"; Flags: ignoreversion

[Icons]
Name: "{code:StartMenuShortcutRoot}\SteamWrapper"; Filename: "{app}\SteamWrapper.exe"; AppUserModelID: "SteamWrapper.Manager"; Check: CreateStartMenuShortcut
Name: "{code:DesktopShortcutRoot}\SteamWrapper"; Filename: "{app}\SteamWrapper.exe"; AppUserModelID: "SteamWrapper.Manager"; Tasks: desktopicon

[Run]
#if Isolated
; An isolated-only real process probe verifies the Run-phase lease handoff.
Filename: "{app}\SteamWrapper.exe"; Flags: postinstall; Check: ProbeReleasedLease
#endif
Filename: "{app}\SteamWrapper.exe"; Description: "{cm:LaunchManager}"; Flags: nowait postinstall skipifsilent; Check: MayLaunchManager

[Code]
var
  SessionDir, SessionToken, MaintenanceHost: String;
  Prepared, SessionReleased, SetupReleaseFailed: Boolean;

function NotIsolated: Boolean;
begin
#if Isolated
  Result := False;
#else
  Result := True;
#endif
end;

function MayLaunchManager: Boolean;
begin
  Result := NotIsolated and SessionReleased and not SetupReleaseFailed;
end;

function InstallRoot(Param: String): String;
begin
#if Isolated
  Result := '{#IsolatedRootCode}';
#else
  Result := ExpandConstant('{localappdata}\Programs\SteamWrapper');
#endif
end;

function StartMenuShortcutRoot(Param: String): String;
begin
#if Isolated
  Result := ExtractFileDir(InstallRoot('')) + '\shell-fixture\StartMenu';
#else
  Result := ExpandConstant('{userprograms}\SteamWrapper');
#endif
end;

function DesktopShortcutRoot(Param: String): String;
begin
#if Isolated
  Result := ExtractFileDir(InstallRoot('')) + '\shell-fixture\Desktop';
#else
  Result := ExpandConstant('{userdesktop}');
#endif
end;

function CreateStartMenuShortcut: Boolean;
begin
  Result := not WizardNoIcons;
end;

function InitializeSetup: Boolean;
var
  Version: TWindowsVersion;
begin
  Result := True;
#if Isolated
#else
  GetWindowsVersionEx(Version);
  if Version.ProductType <> VER_NT_WORKSTATION then
  begin
    SuppressibleMsgBox(CustomMessage('ClientWindowsRequired'), mbError, MB_OK, IDOK);
    Result := False;
  end;
#endif
end;

function HostArguments(Operation: String): String;
begin
  Result := Operation + ' --language ';
  if ActiveLanguage = 'chinesesimplified' then Result := Result + 'zh-CN'
  else Result := Result + 'en';
#if Isolated
  Result := Result + ' --root ' + AddQuotes(InstallRoot('')) + ' --test-root';
#endif
  Result := Result + ' --lease-session ' + AddQuotes(SessionDir) +
    ' --session-token ' + SessionToken + ' --session-timeout-seconds 300';
end;

#if Isolated
function ProbeReleasedLease: Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  if not Exec(ExpandConstant('{app}\maintenance\SteamWrapper.Deployment.exe'),
    '--repair --root ' + AddQuotes(InstallRoot('')) + ' --test-root',
    ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
  begin
    Log('Isolated Run-phase lease probe failed with exit code ' + IntToStr(ResultCode));
    RaiseException('The isolated Run-phase process could not acquire its own deployment lease.');
  end;
  Log('Isolated Run-phase lease probe passed');
end;
#endif

function ReleaseSession: Boolean;
var
  Attempt: Integer;
  Receipt: AnsiString;
begin
  Result := True;
  if SessionReleased then Exit;
  if (SessionDir <> '') and (SessionToken <> '') then
  begin
    Result := False;
    if not SaveStringToFile(SessionDir + '\release.txt', SessionToken, False) then Exit;
    { Wait for disposal of the exclusive lease before Inno removes its temp tree. }
    if FileExists(SessionDir + '\ready.txt') then
      for Attempt := 1 to 100 do
      begin
        if LoadStringFromFile(SessionDir + '\released.txt', Receipt) and (String(Receipt) = SessionToken) then
        begin
          SessionReleased := True;
          Result := True;
          Sleep(100);
          Exit;
        end;
        Sleep(50);
      end;
    if not FileExists(SessionDir + '\ready.txt') then Result := not Prepared;
  end;
end;

function BeginSession: Boolean;
begin
  SessionReleased := False;
  SessionToken := Lowercase(Copy(GetSHA256OfString(AnsiString(ExpandConstant('{tmp}') + GetDateTimeString('yyyymmddhhnnsszzz', '-', ':'))), 1, 32));
  SessionDir := ExpandConstant('{tmp}\deployment-session-' + SessionToken);
  Result := ForceDirectories(SessionDir);
end;

function WaitForDeployment: String;
var
  Attempt: Integer;
  Receipt: AnsiString;
begin
  Result := CustomMessage('DeploymentTimeout');
  for Attempt := 1 to 600 do
  begin
    if LoadStringFromFile(SessionDir + '\ready.txt', Receipt) and (String(Receipt) = SessionToken) then
    begin
      Result := '';
      Exit;
    end;
    if LoadStringFromFile(SessionDir + '\error.txt', Receipt) then
    begin
      if String(Receipt) = 'Busy' then Result := FmtMessage(CustomMessage('DeploymentFailure'), ['10'])
      else Result := FmtMessage(CustomMessage('DeploymentFailure'), ['11']);
      Exit;
    end;
    if Terminated then Exit;
    Sleep(100);
  end;
end;

procedure InitializeWizard;
begin
  WizardForm.WelcomeLabel2.Caption := CustomMessage('RetainedData');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  Host: String;
begin
  Result := '';
  if Prepared then Exit;
  if not PathSame(ExpandConstant('{app}'), InstallRoot('')) then
  begin
    Result := CustomMessage('FixedRoot');
    Exit;
  end;
#if Isolated
  if GetEnv('STEAMWRAPPER_DEPLOYMENT_TEST') <> '1' then
  begin
    Result := CustomMessage('FixedRoot');
    Exit;
  end;
#endif
  ExtractTemporaryFiles('{tmp}\payload\*');
  Log('Validating the extracted deployment component');
  Host := ExpandConstant('{tmp}\payload\Deployment\SteamWrapper.exe');
  if not FileExists(Host) or (GetSHA256OfFile(Host) <> '{#HostSha256}') then
  begin
    Result := CustomMessage('HostInvalid');
    Exit;
  end;
  if not BeginSession then
  begin
    Result := CustomMessage('DeploymentTimeout');
    Exit;
  end;
  if not Exec(Host, HostArguments('--install --payload ' + AddQuotes(ExpandConstant('{tmp}\payload'))), ExpandConstant('{tmp}'), SW_HIDE, ewNoWait, ResultCode) then
    Result := FmtMessage(CustomMessage('DeploymentFailure'), [IntToStr(ResultCode)])
  else Result := WaitForDeployment;
  Prepared := Result = '';
  if not Prepared then ReleaseSession;
end;

procedure DeinitializeSetup;
var
  Released: Boolean;
begin
  Released := ReleaseSession;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    { Files, shortcuts and registration have completed. Release before [Run]. }
    if not ReleaseSession then
    begin
      SetupReleaseFailed := True;
      RaiseException(CustomMessage('LeaseReleaseFailure'));
    end;
    Log('Deployment registration completed and lease released');
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  if SetupReleaseFailed then Result := 11 else Result := 0;
end;

function InitializeUninstall: Boolean;
begin
  MaintenanceHost := ExpandConstant('{app}\maintenance\SteamWrapper.Deployment.exe');
  Result := PathSame(ExpandConstant('{app}'), InstallRoot('')) and FileExists(MaintenanceHost);
  if Result then Result := GetSHA256OfFile(MaintenanceHost) = '{#HostSha256}';
#if Isolated
  Result := Result and (GetEnv('STEAMWRAPPER_DEPLOYMENT_TEST') = '1');
#endif
  if not Result and not UninstallSilent then MsgBox(CustomMessage('HostInvalid'), mbError, MB_OK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Host, Failure: String;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then Exit;
  Host := ExpandConstant('{tmp}\SteamWrapper.UninstallHost.exe');
  if not FileCopy(MaintenanceHost, Host, False) or (GetSHA256OfFile(Host) <> '{#HostSha256}') or not BeginSession then
    RaiseException(CustomMessage('UninstallFailure'));
  if not Exec(Host, HostArguments('--uninstall'), ExpandConstant('{tmp}'), SW_HIDE, ewNoWait, ResultCode) then
    RaiseException(CustomMessage('UninstallFailure'));
  Failure := WaitForDeployment;
  if Failure <> '' then
  begin
    ReleaseSession;
    RaiseException(CustomMessage('UninstallFailure'));
  end;
end;

procedure DeinitializeUninstall;
var
  Released: Boolean;
begin
  Released := ReleaseSession;
end;
