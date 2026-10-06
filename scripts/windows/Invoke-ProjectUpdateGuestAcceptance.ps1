# Actual signed public-network UI-to-installer acceptance. Fresh Sandbox only;
# inbox PowerShell 5.1, no SDK, fixture keys or staged target installer.
[CmdletBinding()]
param([string]$InputDirectory='C:\AcceptanceInput',[string]$OutputDirectory='C:\AcceptanceOutput')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($InputDirectory -cne 'C:\AcceptanceInput' -or $OutputDirectory -cne 'C:\AcceptanceOutput' -or $env:USERNAME -ine 'WDAGUtilityAccount' -or
    $env:USERPROFILE.TrimEnd('\') -ine 'C:\Users\WDAGUtilityAccount' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Public update product acceptance requires the dedicated interactive Windows Sandbox WDAG mappings.'}
. (Join-Path $InputDirectory 'ProjectUpdateAcceptance.ps1') -HelpersOnly
function Read-ProjectGuestJson([string]$Path,[long]$Limit=2097152){
    $file=Get-Item -LiteralPath $Path -Force;Assert-ProjectUpdateAcceptance (-not $file.PSIsContainer -and -not($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $file.Length -gt 0 -and $file.Length -le $Limit) 'Guest JSON is not a bounded regular file.'
    return [IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)|ConvertFrom-Json
}
$inputManifest=Read-ProjectGuestJson (Join-Path $InputDirectory 'update-input.json') 262144
Assert-ProjectUpdateAcceptanceManifest $inputManifest
Assert-ProjectUpdateAcceptance (-not[string]::IsNullOrWhiteSpace([string]$inputManifest.hostComputerName) -and $env:COMPUTERNAME -ine $inputManifest.hostComputerName) 'Refusing public Setup acceptance on the input host.'
foreach($folder in @($InputDirectory,$OutputDirectory)){
    $ancestor=Get-Item -LiteralPath $folder -Force
    while($null -ne $ancestor){Assert-ProjectUpdateAcceptance (-not($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Acceptance mapping has a linked ancestor.';$ancestor=$ancestor.Parent}
}
foreach($pair in @(@('ProjectUpdateAcceptance.ps1','ProjectUpdateAcceptanceSha256'),@('Invoke-ProjectUpdateGuestAcceptance.ps1','Invoke-ProjectUpdateGuestAcceptanceSha256'),@('Invoke-CleanWindowsGuestAcceptance.ps1','Invoke-CleanWindowsGuestAcceptanceSha256'),@('baseline-release.json','baselineMetadataSha256'),@('target-release.json','targetMetadataSha256'),@('signed-public-feed.json','unused'))){
    $path=Join-Path $InputDirectory $pair[0];$file=Get-Item -LiteralPath $path -Force
    $expected=if($pair[0] -ceq 'signed-public-feed.json'){$inputManifest.feed.envelopeSha256}else{$inputManifest.($pair[1])}
    Assert-ProjectUpdateAcceptance (-not $file.PSIsContainer -and -not($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $file.Length -gt 0 -and $file.Length -le 2MB -and $expected -cmatch '^[a-f0-9]{64}$' -and (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ceq $expected) ('Pinned public acceptance input changed: '+$pair[0])
}
Assert-ProjectUpdateAcceptance (-not(Test-Path -LiteralPath (Join-Path $InputDirectory $inputManifest.target.fileName))) 'The target installer must come from the actual Manager network download, never a staged candidate.'
. (Get-ProjectUpdateCleanHelperDefinitions (Join-Path $InputDirectory 'Invoke-CleanWindowsGuestAcceptance.ps1'))
$standardAccount=$false
$computer=Get-CimInstance Win32_ComputerSystem;$os=Get-CimInstance Win32_OperatingSystem
Assert-Acceptance ($computer.Manufacturer -ceq 'Microsoft Corporation' -and $computer.Model -ceq 'Virtual Machine' -and $os.ProductType -eq 1 -and [int]$os.BuildNumber -ge 26100 -and [Environment]::Is64BitProcess) 'Expected a native x64 Windows 11 24H2-or-later Sandbox client.'
Assert-Acceptance ($env:LOCALAPPDATA -ieq [Environment]::GetFolderPath('LocalApplicationData')) 'AppData is redirected.'
foreach($name in @('STEAMWRAPPER_E2E_ROOT','STEAMWRAPPER_DEPLOYMENT_TEST','STEAM_DIR')){Assert-Acceptance ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) ('Unexpected test override: '+$name)}
Assert-Acceptance (@(Get-ChildItem Env:|Where-Object Name -like 'STEAMWRAPPER_DEPLOYMENT_*').Count -eq 0) 'Unexpected deployment test override.'
$dataRoot=Join-Path $env:LOCALAPPDATA 'SteamWrapper';$defaultProgram=Join-Path $env:LOCALAPPDATA 'Programs\SteamWrapper'
$registration='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7DBEC23-E563-4BFB-BE9C-F68D73E4D5BB}_is1'
foreach($path in @($dataRoot,$defaultProgram,$registration,'HKCU:\Software\Valve\Steam','C:\Program Files (x86)\Steam')){Assert-Acceptance (-not(Test-Path -LiteralPath $path)) 'Use a fresh Sandbox without Steam or product data.'}
Assert-Acceptance (@(Get-Process -Name steam,SteamWrapper,SteamWrapper.Manager,SteamWrapperRunner -ErrorAction SilentlyContinue).Count -eq 0) 'Guest already contains Steam or product processes.'
Assert-Acceptance (@(Get-ChildItem -LiteralPath $OutputDirectory -Force|Where-Object {$_ -isnot [IO.FileInfo] -or $_.Name -cne 'guest-launch.log' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count -eq 0) 'Acceptance output is not fresh.'
$taskRoot=Join-Path $env:TEMP ('SteamWrapperPublicUpdate-'+$inputManifest.runId);Assert-Acceptance (-not(Test-Path -LiteralPath $taskRoot)) 'Guest work directory is not fresh.'
$events=New-Object 'Collections.Generic.List[object]';$ownedManagers=New-Object 'Collections.Generic.List[object]';$managerCloseDiagnostics=New-Object 'Collections.Generic.List[object]';$runnerDiagnostics=New-Object 'Collections.Generic.List[object]';$warnings=New-Object 'Collections.Generic.List[string]'
$utf8=New-Object Text.UTF8Encoding($false);$evidencePath=Join-Path $OutputDirectory 'evidence.json'
$evidence=[ordered]@{schemaVersion=1;runId=$inputManifest.runId;scenario='PublicProjectUpdate';result='running';startedAt=[DateTime]::UtcNow.ToString('o');source=$inputManifest.source;channel=$inputManifest.channel;baselineTag=$inputManifest.baseline.tag;targetTag=$inputManifest.target.tag
    environment='Windows Sandbox';cleanWindowsClient=$true;standardUser=$false;independentIsoVm=$false;build=$os.BuildNumber;hostBuild=$inputManifest.hostBuild
    signedPublicNetwork=$false;actualUiInstallation=$false;numericUpgradeTested=$false;baselineRunnerOperationalTested=$false;realSteam=$false;gameFilesTouched=$false
    baselineRunnerLimitation='Baseline Runner is deliberately preserved until explicit profile saving after update and is not executed by this gate. Historical public 0.2.5 has a separately proven missing-VC runtime defect; no runtime is installed to conceal that result.'
    steps=$events;ownedManagers=$ownedManagers;managerCloseDiagnostics=$managerCloseDiagnostics;runnerDiagnostics=$runnerDiagnostics;warnings=$warnings}
function Invoke-ProjectPrimary($Manager,[string[]]$Names){
    $button=Wait-AcceptanceElement $Manager.Window 'PrimaryButton'
    $state=[pscustomobject]@{name=$button.Current.Name;automationId=$button.Current.AutomationId;processId=$button.Current.ProcessId;enabled=$button.Current.IsEnabled;controlType=$button.Current.ControlType.ProgrammaticName.Replace('ControlType.','')}
    Assert-ProjectUpdateUiAction $state $Names $Manager.Window.Current.ProcessId $Manager.Process.Id
    Invoke-AcceptanceElement $button
}
function Attach-ProjectUpdatedManager{
    $expected=Join-Path $defaultProgram ('versions\'+$inputManifest.target.tag+'\SteamWrapper.Manager.exe')
    $process=Wait-Acceptance {
        foreach($candidate in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Manager')){
            try{if($candidate.MainModule.FileName -ieq $expected -and $candidate.MainWindowHandle -ne [IntPtr]::Zero){Retain-AcceptanceProcessHandle $candidate;return $candidate}}catch{}
            $candidate.Dispose()
        }
    } 'Manager automatically restarted by actual update handoff' 120
    $window=[System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
    Assert-Acceptance ($window.Current.ProcessId -eq $process.Id) 'Automatic restart window has another process owner.'
    $null=Wait-Acceptance {Test-ProjectUpdateElementEnabled (Find-AcceptanceElement $window 'AddGame')} 'updated Manager initialization'
    $modules=Get-AcceptancePayloadRuntimeModules @($process.Modules) ([IO.Path]::GetDirectoryName($expected))
    $ownedManagers.Add([ordered]@{processId=$process.Id;path=$expected;automaticUpdateRestart=$true})
    Record-Acceptance 'actual update handoff automatically restarted native Manager' ([ordered]@{processId=$process.Id;path=$expected;payloadRuntimeModules=$modules})
    return [pscustomobject]@{Process=$process;Window=$window}
}
Write-AcceptanceEvidence
try{
    [IO.Directory]::CreateDirectory($taskRoot)|Out-Null
    $dotnet=@(@('C:\Program Files\dotnet','C:\Program Files (x86)\dotnet',(Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'))|Where-Object {Test-Path -LiteralPath $_})
    $packages=@(Get-AppxPackage -Name '*WindowsAppRuntime*' -ErrorAction SilentlyContinue|Select-Object Name,Version,Publisher,SignatureKind,NonRemovable,InstallLocation,IsFramework)
    $external=@($packages|Where-Object {-not(Test-AcceptanceInboxRuntimePackage $_ (Join-Path $env:windir 'SystemApps'))})
    $evidence.runtimeInventoryBeforeInstallation=[ordered]@{dotnetDirectories=$dotnet;dotnetOnPath=[bool](Get-Command dotnet -ErrorAction SilentlyContinue);windowsAppRuntimePackages=$packages;externalWindowsAppRuntimePackages=$external}
    Assert-Acceptance ($dotnet.Count -eq 0 -and -not $evidence.runtimeInventoryBeforeInstallation.dotnetOnPath -and $external.Count -eq 0) 'Guest has a machine SDK/runtime or external Windows App Runtime.'
    Record-Acceptance 'fresh SDK-free public-network client' ([ordered]@{realSteam=$false;externalToolchainInstalled=$false;networkingRequired=$true})
    Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
    $baselineSetup=Read-AcceptanceAsset $inputManifest.baseline
    $chinese=[string][char]0x4e2d+[char]0x6587;$profileName='Public update fixture '+$chinese;$gameDirectory=Join-Path $taskRoot ('Harmless game '+$chinese)
    [IO.Directory]::CreateDirectory($gameDirectory)|Out-Null;$fixtureExe=Join-Path $gameDirectory 'AcceptanceFixture.exe';$marker=Join-Path $gameDirectory 'runner-completed.txt'
    Add-Type -TypeDefinition @'
public static class SteamWrapperPublicUpdateFixture {
    public static int Main() { System.Threading.Thread.Sleep(300);System.IO.File.WriteAllText("runner-completed.txt",System.Environment.CurrentDirectory,new System.Text.UTF8Encoding(false));return 0; }
}
'@ -OutputAssembly $fixtureExe -OutputType ConsoleApplication
    $fixtureSha=(Get-FileHash -LiteralPath $fixtureExe).Hash.ToLowerInvariant()
    Invoke-AcceptanceInstaller $baselineSetup 'actual-public-baseline-install' @('/TASKS="startmenuicon,desktopicon"')
    $null=Read-AcceptanceInstallation $defaultProgram $inputManifest.baseline.tag
    $manager=Start-AcceptanceManager $defaultProgram $inputManifest.baseline.tag 'public-baseline-Manager'
    Invoke-AcceptanceElement (Wait-AcceptanceElement $manager.Window 'AddGame');$manual=Wait-AcceptanceElement $manager.Window 'SecondaryButton'
    Assert-AcceptanceManualAppIdAction ([pscustomobject]@{name=$manual.Current.Name;processId=$manual.Current.ProcessId;automationId=$manual.Current.AutomationId;enabled=$manual.Current.IsEnabled}) $manager.Window.Current.ProcessId $manager.Process.Id
    Invoke-AcceptanceElement $manual
    Set-AcceptanceValue $manager.Window 'ProfileName' $profileName;Set-AcceptanceValue $manager.Window 'AppId' '487';Set-AcceptanceValue $manager.Window 'GameDirectory' $gameDirectory;Set-AcceptanceValue $manager.Window 'Target' 'AcceptanceFixture.exe'
    Invoke-AcceptanceElement (Wait-AcceptanceElement $manager.Window 'SaveProfile');$null=Wait-Acceptance {Test-ProjectUpdateElementEnabled (Find-AcceptanceElement $manager.Window 'SaveProfile')} 'baseline profile save'
    $expectedLaunch='"'+(Join-Path $dataRoot 'bin\SteamWrapperRunner.exe')+'" --appid "487" -- %command%'
    Assert-Acceptance (([System.Windows.Automation.ValuePattern](Wait-AcceptanceElement $manager.Window 'LaunchOptions').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value -ceq $expectedLaunch) 'Baseline launch options are not the shared stable Runner command.'
    Record-Acceptance 'actual baseline native UI profile saved' ([ordered]@{launchOptions=$expectedLaunch;historicalRunnerExecuted=$false})
    Invoke-AcceptanceElement (Wait-AcceptanceElement $manager.Window 'Updates')
    # The source combo is inside a collapsed expander; first wait for the
    # visible dialog action, then expand source settings before reading it.
    $null=Wait-Acceptance {Test-ProjectUpdateElementEnabled (Find-AcceptanceElement $manager.Window 'CheckUpdates')} 'update dialog initialized' 90
    $automatic=Wait-AcceptanceElement $manager.Window 'AutomaticUpdateChecks'
    Assert-Acceptance (([System.Windows.Automation.TogglePattern]$automatic.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)).Current.ToggleState -eq [System.Windows.Automation.ToggleState]::Off) 'Automatic checks are unexpectedly enabled.'
    $expander=Wait-AcceptanceElement $manager.Window 'UpdateSourceOptions';([System.Windows.Automation.ExpandCollapsePattern]$expander.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)).Expand()
    $combo=Wait-AcceptanceElement $manager.Window 'UpdateSource';([System.Windows.Automation.ExpandCollapsePattern]$combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)).Expand()
    $sourceName=if($inputManifest.source -ceq 'github'){'GitHub'}else{'CNB'}
    $choice=Wait-Acceptance {$manager.Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.AndCondition -ArgumentList @((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$sourceName)),(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))))} 'explicit official update source item'
    ([System.Windows.Automation.SelectionItemPattern]$choice.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
    $null=Wait-Acceptance {(Test-ProjectUpdateElementEnabled (Find-AcceptanceElement $manager.Window 'CheckUpdates')) -and (Read-ProjectGuestJson (Join-Path $dataRoot 'ui-settings.json')).updateSource -ceq $inputManifest.source} 'source preference saved through UI'
    Invoke-AcceptanceElement (Wait-AcceptanceElement $manager.Window 'CheckUpdates')
    $null=Wait-Acceptance {$status=Find-AcceptanceElement $manager.Window 'UpdateStatus';(Test-ProjectUpdateElementEnabled (Find-AcceptanceElement $manager.Window 'PrimaryButton')) -and $null -ne $status -and $status.Current.Name.Contains($inputManifest.target.tag)} 'genuine newer public update offered' 90
    $trustPath=Join-Path $dataRoot 'updates\trust-state.json';Assert-ProjectUpdateAcceptedFeed $inputManifest (Read-ProjectGuestJson $trustPath)
    Record-Acceptance 'actual Manager accepted pinned project-signed public feed' ([ordered]@{sourceSelectedThroughUi=$inputManifest.source;sequence=$inputManifest.feed.sequence;payloadSha256=$inputManifest.feed.payloadSha256;numericUpgrade=$true})
    Invoke-ProjectPrimary $manager @($inputManifest.uiTexts.UpdateDownload)
    $downloadObservation=[pscustomobject]@{busyObserved=$false}
    $null=Wait-Acceptance {
        $status=Find-AcceptanceElement $manager.Window 'UpdateStatus';$primary=Find-AcceptanceElement $manager.Window 'PrimaryButton'
        if($null -eq $status -or $null -eq $primary){return $false}
        $state=[pscustomobject]@{enabled=$primary.Current.IsEnabled;action=$primary.Current.Name;status=$status.Current.Name}
        Test-ProjectUpdateDownloadReady $state @($inputManifest.uiTexts.UpdateReady) @($inputManifest.uiTexts.UpdateDownload) $downloadObservation
    } 'verified real network installer download ready' 900
    $cached=Join-Path $dataRoot ('cache\updates\setup-'+$inputManifest.target.sha256+'.exe')
    Assert-Acceptance ((Get-Item -LiteralPath $cached).Length -eq $inputManifest.target.bytes -and (Get-FileHash -LiteralPath $cached).Hash.ToLowerInvariant() -ceq $inputManifest.target.sha256) 'The actual UI download does not match the signed public installer.'
    Assert-ProjectUpdateAcceptedFeed $inputManifest (Read-ProjectGuestJson $trustPath)
    $trustHash=(Get-FileHash -LiteralPath $trustPath).Hash.ToLowerInvariant()
    $preserved=Get-AcceptanceDataHashes;$before=Read-AcceptanceInstallation $defaultProgram $inputManifest.baseline.tag
    Capture-AcceptanceWindow $manager.Window 'public-update-download-ready'
    Record-Acceptance 'actual UI downloaded exact public Setup' ([ordered]@{bytes=$inputManifest.target.bytes;sha256=$inputManifest.target.sha256;cache=$cached;stagedTargetInstaller=$false;trustStateSha256=$trustHash})
    Invoke-ProjectPrimary $manager @($inputManifest.uiTexts.UpdateInstall)
    # This second PrimaryButton belongs to the explicit installation confirmation.
    $null=Wait-Acceptance {$title=$manager.Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,[string]$inputManifest.uiTexts.UpdateInstallTitle[0])));if($null -ne $title){return $true};$title=$manager.Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,[string]$inputManifest.uiTexts.UpdateInstallTitle[1])));$null -ne $title} 'actual installation confirmation dialog'
    Invoke-ProjectPrimary $manager @($inputManifest.uiTexts.UpdateInstall)
    $helper=Wait-Acceptance {
        foreach($candidate in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Update')){
            try{if($candidate.MainModule.FileName -imatch ('^'+[regex]::Escape((Join-Path $dataRoot 'cache\updates'))+'\\handoff-[a-f0-9]{32}\\SteamWrapper\.Update\.exe$')){Retain-AcceptanceProcessHandle $candidate;return $candidate}}catch{}
            $candidate.Dispose()
        }
    } 'actual verified one-shot update helper'
    $helperPath=$helper.MainModule.FileName
    Assert-Acceptance ((Get-FileHash -LiteralPath $helperPath).Hash.ToLowerInvariant() -ceq $before.launcherSha256) 'UI handoff helper differs from the installed verified NativeAOT host.'
    Assert-Acceptance ($manager.Process.WaitForExit(45000)) 'Originating Manager did not close normally; no process was killed.'
    $exit=Get-AcceptanceExitDiagnostic $manager.Process.ExitCode;$managerCloseDiagnostics.Add([ordered]@{processId=$manager.Process.Id;closedByActualUpdateUi=$true;exit=$exit})
    Assert-Acceptance ($exit.observed -and $exit.exitCode -eq 0) 'Originating Manager did not report a normal actual exit.';$manager.Process.Dispose()
    Assert-Acceptance ($helper.WaitForExit(300000) -and $helper.ExitCode -eq 0) 'Actual UI installer handoff failed or timed out; processes and diagnostics are preserved.'
    Record-Acceptance 'actual UI handoff waited for normal Manager exit and executed Setup' ([ordered]@{helper=$helperPath;helperExitCode=$helper.ExitCode;parentExitCode=$exit.exitCode;installationLog=(Join-Path $dataRoot 'cache\updates\installation.log')});$helper.Dispose()
    Assert-Acceptance (Test-Path -LiteralPath (Join-Path $dataRoot 'cache\updates\installation.log') -PathType Leaf) 'The actual installer handoff did not produce its fixed Inno installation log.'
    $manager=Attach-ProjectUpdatedManager;$after=Read-AcceptanceInstallation $defaultProgram $inputManifest.target.tag
    Assert-Acceptance ($after.healthy -and $after.previous.tag -ceq $inputManifest.baseline.tag) 'Target was not healthy with the actual baseline retained.'
    Assert-AcceptanceDataHashes $preserved
    Assert-ProjectUpdatePreservedTrust $trustPath $trustHash $inputManifest
    Record-Acceptance 'public upgrade preserved profile preferences and old stable Runner bytes' ([ordered]@{healthy=$true;previous=$after.previous.tag;preserved=$preserved;trustStateSha256=$trustHash})
    $notice=Wait-Acceptance {
        $status=Find-AcceptanceElement $manager.Window 'Status';if($null -eq $status){return $false}
        $texts=@([string]$status.Current.Name)+@($status.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)|ForEach-Object {[string]$_.Current.Name})
        @($texts|Where-Object {$_ -cin @($inputManifest.uiTexts.RunnerUpdate)}).Count -gt 0
    } 'player-visible startup notice for retained older Runner'
    Record-Acceptance 'updated Manager explains the explicit Runner update to the player' ([ordered]@{visibleStartupNotice=$true;oldRunnerPreserved=$true})
    $profiles=Wait-AcceptanceElement $manager.Window 'Profiles'
    $configured=Wait-Acceptance {$profiles.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.AndCondition -ArgumentList @((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$profileName)),(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))))} 'retained public upgrade profile'
    ([System.Windows.Automation.SelectionItemPattern]$configured.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
    $null=Wait-Acceptance {Test-ProjectUpdateElementEnabled (Find-AcceptanceElement $manager.Window 'SaveProfile')} 'retained profile editor ready'
    Invoke-AcceptanceElement (Wait-AcceptanceElement $manager.Window 'SaveProfile')
    $bundle=Read-ProjectGuestJson (Join-Path $defaultProgram ('versions\'+$inputManifest.target.tag+'\Runner\runner-manifest.json'))
    $targetMeta=Read-ProjectGuestJson (Join-Path $InputDirectory 'target-release.json');$deployment=$targetMeta.deploymentManifest.json|ConvertFrom-Json;$runnerRecord=@($deployment.files|Where-Object path -IEQ 'Runner/SteamWrapperRunner.exe')[0]
    Assert-Acceptance ($bundle.sha256 -ceq $runnerRecord.sha256) 'Target bundled Runner differs from the public sealed inventory.'
    $null=Wait-Acceptance {(Test-ProjectUpdateElementEnabled (Find-AcceptanceElement $manager.Window 'SaveProfile')) -and (Get-FileHash -LiteralPath (Join-Path $dataRoot 'bin\SteamWrapperRunner.exe')).Hash.ToLowerInvariant() -ceq $bundle.sha256} 'explicit stable Runner update after saving retained profile'
    foreach($key in @('profiles.toml','ui-settings.json')){Assert-Acceptance ((Get-FileHash -LiteralPath (Join-Path $dataRoot $key)).Hash.ToLowerInvariant() -ceq $preserved[$key]) 'Explicit Runner update changed prior player configuration bytes.'}
    $newLaunch=Wait-AcceptanceElement $manager.Window 'LaunchOptions';Assert-Acceptance (([System.Windows.Automation.ValuePattern]$newLaunch.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value -ceq $expectedLaunch) 'Runner update changed stable Launch Options.'
    $preserved=Get-AcceptanceDataHashes;Close-AcceptanceManager $manager
    Invoke-AcceptanceRunner 'actual public update repaired Runner works headlessly' $marker $gameDirectory
    Invoke-AcceptanceInstaller (Join-Path $defaultProgram 'unins000.exe') 'public-upgrade-default-uninstall-keeps-data'
    Assert-AcceptanceDataHashes $preserved;Assert-Acceptance (-not(Test-Path -LiteralPath $registration) -and -not(Test-Path -LiteralPath (Join-Path $defaultProgram 'SteamWrapper.exe'))) 'Default uninstall retained Manager registration or launcher.'
    Assert-ProjectUpdatePreservedTrust $trustPath $trustHash $inputManifest
    Assert-Acceptance ((Get-FileHash -LiteralPath $fixtureExe).Hash.ToLowerInvariant() -ceq $fixtureSha) 'Uninstall changed harmless fixture bytes.'
    $evidence.signedPublicNetwork=$true;$evidence.actualUiInstallation=$true;$evidence.numericUpgradeTested=$true;$evidence.stableRunnerExplicitlyUpdated=$true;$evidence.updateTrustStatePreserved=$true;$evidence.result='passed';$evidence.completedAt=[DateTime]::UtcNow.ToString('o');Write-AcceptanceEvidence
    Write-Output 'Actual signed public-network native UI download, normal exit, real installer handoff and healthy restart acceptance passed; no standard-user, independent ISO or real Steam claim.'
}catch{$evidence.result='failed';$evidence.error=$_.Exception.Message;$evidence.completedAt=[DateTime]::UtcNow.ToString('o');Write-AcceptanceEvidence;throw}
