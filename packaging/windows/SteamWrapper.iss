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
DisableDirPage=auto
UsePreviousAppDir=yes
DefaultGroupName=SteamWrapper
DisableProgramGroupPage=yes
UsePreviousTasks=yes
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
english.StartMenuIcon=Create a Start menu shortcut
chinesesimplified.StartMenuIcon=创建开始菜单快捷方式
english.DesktopIcon=Create a desktop shortcut
chinesesimplified.DesktopIcon=创建桌面快捷方式
english.RetainedData=Choose a folder and shortcuts for Manager. Game profiles and Runner stay in your Windows user data folder, so Steam launch commands keep working. Updates use the same installation folder. Uninstall keeps your data unless you select specific items to remove.
chinesesimplified.RetainedData=您可以选择管理器的安装目录与快捷方式。游戏配置和 Runner 仍保存在当前用户的数据目录中，Steam 启动命令不会因安装位置改变而失效。更新沿用原安装目录；卸载默认保留数据，您可以选择要清理的部分。
english.ExistingRoot=SteamWrapper is already installed in another folder. Update it in its current folder. To change folders, uninstall Manager first while keeping your data, then install again.
chinesesimplified.ExistingRoot=SteamWrapper 已安装在其他目录。请在原目录更新；如需更换位置，请先卸载管理器并保留数据，再重新安装。
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
english.UninstallChoices=Choose what to remove
chinesesimplified.UninstallChoices=选择要卸载和清理的内容
english.UninstallDescription=Manager, its shortcuts and installation registration will be removed. Everything below is optional and kept by default. Game files and saves are never removed.
chinesesimplified.UninstallDescription=将卸载管理器，并移除它的快捷方式和安装记录。下列内容均可单独选择，默认保留。不会删除游戏文件或存档。
english.RestoreSteam=Restore normal game launches from Steam
chinesesimplified.RestoreSteam=恢复从 Steam 正常启动游戏
english.RemoveProfiles=Delete saved game configurations
chinesesimplified.RemoveProfiles=删除保存的游戏配置
english.RemoveBackups=Delete game configuration backups
chinesesimplified.RemoveBackups=删除游戏配置备份
english.RemoveRunner=Remove Runner (used when launching games from Steam)
chinesesimplified.RemoveRunner=删除 Runner（从 Steam 启动游戏时使用）
english.RemoveSettings=Reset Manager settings, including language preferences
chinesesimplified.RemoveSettings=清除管理器设置（包括语言偏好）
english.RemoveCache=Delete downloaded covers and update installers
chinesesimplified.RemoveCache=删除下载的封面和更新安装包
english.RemoveLogs=Delete diagnostic logs
chinesesimplified.RemoveLogs=删除诊断日志
english.RestoreDescription=To remove game configurations or Runner, first exit Steam normally. Standard SteamWrapper commands can be removed after a backup; customized commands must be restored in Steam. Earlier manually overwritten options cannot be reconstructed. Restoration backups and unknown files are kept.
chinesesimplified.RestoreDescription=删除游戏配置或 Runner 前，请先正常退出 Steam。可在备份后移除标准接管命令；自定义命令需在 Steam 中恢复。无法重建早先手动覆盖且未保存的参数。恢复备份和未知文件会保留。
english.UninstallSelected=Uninstall selected items
chinesesimplified.UninstallSelected=卸载并清理所选内容
english.CancelUninstall=Cancel
chinesesimplified.CancelUninstall=取消
english.SteamBusy=Please exit Steam normally before restoring launch options or deleting game configurations and Runner. No program was closed. Your files were kept.
chinesesimplified.SteamBusy=请正常退出 Steam，再恢复启动选项或删除游戏配置和 Runner。没有关闭任何程序，您的文件已保留。
english.SteamRestore=Some Steam launch options could not be safely restored. Keep game configurations and Runner, or restore customized launch options in Steam and retry. Any restoration backups have been kept.
chinesesimplified.SteamRestore=部分 Steam 启动选项无法安全恢复。请保留游戏配置和 Runner，或在 Steam 中恢复自定义启动选项后重试；已生成的恢复备份会保留。
english.CleanupRetained=Manager was removed. Some selected files were in use, unrecognized, or still needed and were kept. Restoration backups and update verification history are also kept. You can review the remaining SteamWrapper data folder without changing any game files.
chinesesimplified.CleanupRetained=管理器已卸载。部分所选文件因正在使用、无法识别或仍被依赖而保留；恢复备份和更新验证记录也会保留。您可以检查剩余的 SteamWrapper 数据目录，游戏文件未受影响。

[Tasks]
Name: "startmenuicon"; Description: "{cm:StartMenuIcon}"
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; Flags: unchecked

[Files]
; The deployment component alone owns version directories and activation state.
Source: "{#PayloadDir}\*"; DestDir: "{tmp}\payload"; Flags: dontcopy recursesubdirs createallsubdirs
; Inno tracks only its independent maintenance host and its own uninstall files.
Source: "{#PayloadDir}\Deployment\SteamWrapper.exe"; DestDir: "{app}\maintenance"; DestName: "SteamWrapper.Deployment.exe"; Flags: ignoreversion

[Icons]
Name: "{code:StartMenuShortcutRoot}\SteamWrapper"; Filename: "{app}\SteamWrapper.exe"; AppUserModelID: "SteamWrapper.Manager"; Tasks: startmenuicon; Check: CreateStartMenuShortcut
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
  RestoreSteam, RemoveProfiles, RemoveBackups, RemoveRunner: Boolean;
  RemoveSettings, RemoveCache, RemoveLogs, CleanupRetained: Boolean;

function RegisteredInstallRoot: String;
begin
  Result := '';
#if Isolated
  RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamWrapper-Installer-Test-{#IsolatedId}_is1', 'InstallLocation', Result);
#else
  RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7DBEC23-E563-4BFB-BE9C-F68D73E4D5BB}_is1', 'InstallLocation', Result);
#endif
end;

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
  Result := Result + ' --root ' + AddQuotes(ExpandConstant('{app}'));
#if Isolated
  Result := Result + ' --test-root';
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
      else if String(Receipt) = 'SteamBusy' then Result := CustomMessage('SteamBusy')
      else if String(Receipt) = 'SteamRestore' then Result := CustomMessage('SteamRestore')
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
  Host, Existing: String;
begin
  Result := '';
  if Prepared then Exit;
  Existing := RegisteredInstallRoot;
  if (Existing <> '') and not PathSame(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), RemoveBackslashUnlessRoot(Existing)) then
  begin
    Result := CustomMessage('ExistingRoot');
    Exit;
  end;
#if Isolated
  if not PathSame(ExpandConstant('{app}'), InstallRoot('')) then
  begin
    Result := CustomMessage('FixedRoot');
    Exit;
  end;
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

function AddUninstallChoice(Form: TSetupForm; MessageName: String; Y: Integer): TNewCheckBox;
begin
  Result := TNewCheckBox.Create(Form);
  Result.Parent := Form;
  Result.SetBounds(ScaleX(20), ScaleY(Y), Form.ClientWidth - ScaleX(40), ScaleY(24));
  Result.Caption := CustomMessage(MessageName);
  Result.Checked := False;
end;

function ChooseUninstallOptions: Boolean;
var
  Form: TSetupForm;
  Description, Help: TNewStaticText;
  SteamChoice, ProfilesChoice, BackupsChoice, RunnerChoice: TNewCheckBox;
  SettingsChoice, CacheChoice, LogsChoice: TNewCheckBox;
  RemoveButton, CancelButton: TNewButton;
  Choices: String;
begin
  Result := True;
  if UninstallSilent then
  begin
    { No switch means no data deletion. CLI options are explicit, never inherited. }
    Choices := ',' + ExpandConstant('{param:SWCLEANUP|}') + ',';
    RemoveProfiles := Pos(',profiles,', Choices) > 0;
    RemoveBackups := Pos(',profile-backups,', Choices) > 0;
    RemoveRunner := Pos(',runner,', Choices) > 0;
    RemoveSettings := Pos(',settings,', Choices) > 0;
    RemoveCache := Pos(',cache,', Choices) > 0;
    RemoveLogs := Pos(',logs,', Choices) > 0;
    RestoreSteam := ExpandConstant('{param:SWRESTORESTEAM|0}') = '1';
    Exit;
  end;
  Form := CreateCustomForm(ScaleX(550), ScaleY(450), True, True);
  try
    Form.Caption := CustomMessage('UninstallChoices');
    Description := TNewStaticText.Create(Form);
    Description.Parent := Form;
    Description.SetBounds(ScaleX(20), ScaleY(16), Form.ClientWidth - ScaleX(40), ScaleY(58));
    Description.AutoSize := False;
    Description.WordWrap := True;
    Description.Caption := CustomMessage('UninstallDescription');
    SteamChoice := AddUninstallChoice(Form, 'RestoreSteam', 82);
    ProfilesChoice := AddUninstallChoice(Form, 'RemoveProfiles', 110);
    BackupsChoice := AddUninstallChoice(Form, 'RemoveBackups', 138);
    RunnerChoice := AddUninstallChoice(Form, 'RemoveRunner', 166);
    SettingsChoice := AddUninstallChoice(Form, 'RemoveSettings', 194);
    CacheChoice := AddUninstallChoice(Form, 'RemoveCache', 222);
    LogsChoice := AddUninstallChoice(Form, 'RemoveLogs', 250);
    Help := TNewStaticText.Create(Form);
    Help.Parent := Form;
    Help.SetBounds(ScaleX(20), ScaleY(290), Form.ClientWidth - ScaleX(40), ScaleY(94));
    Help.AutoSize := False;
    Help.WordWrap := True;
    Help.Caption := CustomMessage('RestoreDescription');
    RemoveButton := TNewButton.Create(Form);
    RemoveButton.Parent := Form;
    RemoveButton.SetBounds(Form.ClientWidth - ScaleX(325), Form.ClientHeight - ScaleY(46), ScaleX(195), ScaleY(30));
    RemoveButton.Caption := CustomMessage('UninstallSelected');
    RemoveButton.ModalResult := mrOk;
    RemoveButton.Default := True;
    CancelButton := TNewButton.Create(Form);
    CancelButton.Parent := Form;
    CancelButton.SetBounds(Form.ClientWidth - ScaleX(120), Form.ClientHeight - ScaleY(46), ScaleX(100), ScaleY(30));
    CancelButton.Caption := CustomMessage('CancelUninstall');
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    Form.ActiveControl := CancelButton;
    Result := Form.ShowModal = mrOk;
    if Result then
    begin
      RestoreSteam := SteamChoice.Checked;
      RemoveProfiles := ProfilesChoice.Checked;
      RemoveBackups := BackupsChoice.Checked;
      RemoveRunner := RunnerChoice.Checked;
      RemoveSettings := SettingsChoice.Checked;
      RemoveCache := CacheChoice.Checked;
      RemoveLogs := LogsChoice.Checked;
    end;
  finally
    Form.Free;
  end;
end;

function InitializeUninstall: Boolean;
begin
  MaintenanceHost := ExpandConstant('{app}\maintenance\SteamWrapper.Deployment.exe');
  Result := FileExists(MaintenanceHost);
  if Result then Result := GetSHA256OfFile(MaintenanceHost) = '{#HostSha256}';
#if Isolated
  Result := Result and PathSame(ExpandConstant('{app}'), InstallRoot('')) and (GetEnv('STEAMWRAPPER_DEPLOYMENT_TEST') = '1');
#endif
  if not Result and not UninstallSilent then MsgBox(CustomMessage('HostInvalid'), mbError, MB_OK);
  if Result then Result := ChooseUninstallOptions;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Host, Failure, Operation, Choices: String;
  Receipt: AnsiString;
  ResultCode: Integer;
begin
  if CurUninstallStep = usDone then
  begin
    if CleanupRetained and not UninstallSilent then MsgBox(CustomMessage('CleanupRetained'), mbInformation, MB_OK);
    Exit;
  end;
  if CurUninstallStep <> usUninstall then Exit;
  Host := ExpandConstant('{tmp}\SteamWrapper.UninstallHost.exe');
  if not FileCopy(MaintenanceHost, Host, False) or (GetSHA256OfFile(Host) <> '{#HostSha256}') or not BeginSession then
    RaiseException(CustomMessage('UninstallFailure'));
  Operation := '--uninstall';
  if RestoreSteam then Operation := Operation + ' --restore-steam';
  Choices := '';
  if RemoveProfiles then Choices := Choices + 'profiles,';
  if RemoveBackups then Choices := Choices + 'profile-backups,';
  if RemoveRunner then Choices := Choices + 'runner,';
  if RemoveSettings then Choices := Choices + 'settings,';
  if RemoveCache then Choices := Choices + 'cache,';
  if RemoveLogs then Choices := Choices + 'logs,';
  if Choices <> '' then Operation := Operation + ' --cleanup ' + AddQuotes(Choices);
  if not Exec(Host, HostArguments(Operation), ExpandConstant('{tmp}'), SW_HIDE, ewNoWait, ResultCode) then
    RaiseException(CustomMessage('UninstallFailure'));
  Failure := WaitForDeployment;
  if Failure <> '' then
  begin
    ReleaseSession;
    RaiseException(Failure);
  end;
  if LoadStringFromFile(SessionDir + '\cleanup-result.txt', Receipt) then CleanupRetained := String(Receipt) = 'retained';
end;

procedure DeinitializeUninstall;
var
  Released: Boolean;
begin
  Released := ReleaseSession;
end;
