# A bounded, guest-only standard-account test controller. Passwords stay in
# memory. No host account, mapped-folder ACL or machine policy is changed.
[CmdletBinding()]
param(
    [switch]$HelpersOnly,
    [switch]$DiagnosticOnly,
    [switch]$AccessCheckOnly,
    [switch]$GuestInteractiveLogon,
    [switch]$ExplorerShortcut,
    [switch]$InstalledShortcut,
    [switch]$WinUiControlProbe,
    [switch]$WDAGPermission,
    [switch]$StandardChild,
    [string]$StandardInputDirectory = 'C:\AcceptanceInput',
    [string]$StandardOutputDirectory = 'C:\AcceptanceOutput'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-StandardAcceptance([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Write-StandardAcceptanceJson([string]$Path,$Value) {
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 15),(New-Object Text.UTF8Encoding($false)))
}
function Assert-StandardAcceptanceMode([bool]$Helpers, [bool]$Diagnostic, [bool]$AccessOnly, [bool]$Child, [bool]$GuestLogon=$false, [bool]$Explorer=$false, [bool]$Installed=$false, [bool]$Control=$false, [bool]$Permission=$false) {
    Assert-StandardAcceptance (-not $AccessOnly -or ($Diagnostic -and -not $Helpers -and -not $Child)) 'AccessCheckOnly requires the dedicated DiagnosticOnly controller; it never executes a child script.'
    Assert-StandardAcceptance (-not $GuestLogon -or (-not $Helpers -and -not $AccessOnly -and -not $Child)) 'GuestInteractiveLogon is an opt-in disposable Sandbox controller action, never a helper/child/read-only action.'
    Assert-StandardAcceptance (-not $Explorer -or ($GuestLogon -and -not $Diagnostic -and -not $Helpers -and -not $AccessOnly -and -not $Child)) 'ExplorerShortcut requires the full disposable standard-user lifecycle with GuestInteractiveLogon.'
    Assert-StandardAcceptance (-not $Installed -or ($GuestLogon -and -not $Explorer -and -not $Diagnostic -and -not $Helpers -and -not $AccessOnly -and -not $Child)) 'InstalledShortcut is a separate full standard-user lane, mutually exclusive with ExplorerShortcut and never a diagnostic or fallback.'
    Assert-StandardAcceptance (-not $Control -or ($Diagnostic -and $GuestLogon -and -not $Helpers -and -not $AccessOnly -and -not $Child -and -not $Explorer -and -not $Installed)) 'WinUiControlProbe is an explicit granted diagnostic controller only; it never installs or falls back from a product test.'
    Assert-StandardAcceptance (-not $Permission -or ($GuestLogon -and $Installed -and -not $Diagnostic -and -not $Helpers -and -not $AccessOnly -and -not $Child -and -not $Explorer -and -not $Control)) 'WDAGPermission is a separate granted installed-shortcut permission lane; it is never a fresh-account, primary-sign-in or Explorer test.'
}
function Assert-StandardAcceptancePreparedControl($Manifest) {
    Assert-StandardAcceptance ($null -ne $Manifest.PSObject.Properties['standardWinUiControl'] -and
        $Manifest.standardWinUiControl -is [bool] -and $Manifest.standardWinUiControl -and
        $null -ne $Manifest.PSObject.Properties['winUiControl']) 'The dedicated control route must be explicitly sealed into its prepared manifest.'
}
function New-StandardAcceptanceAccessDiagnostic($Manifest, $Token, $Before, $Access, $After) {
    Assert-StandardAcceptanceProcessToken $Token $Manifest.expectedStandardUserSid
    Assert-StandardAcceptance ($Token.sessionId -eq $Manifest.standardSessionId) 'The access diagnostic token belongs to another session.'
    foreach ($record in @(@{field='windowStation';name='WinSta0'},@{field='desktop';name='Default'})) {
        $original=$Before.($record.field); $checked=$Access.($record.field).security; $finished=$After.($record.field)
        Assert-StandardAcceptance ($original.name -ceq $record.name -and $checked.name -ceq $record.name -and $finished.name -ceq $record.name -and
            $original.sha256 -cmatch '^[a-f0-9]{64}$' -and $original.bytes -gt 0 -and $original.bytes -le 131072 -and
            $checked.sha256 -ceq $original.sha256 -and $finished.sha256 -ceq $original.sha256) 'Existing WinSta0/Default security changed or AccessCheck examined different bytes.'
    }
    return [ordered]@{
        schemaVersion=1;runId=$Manifest.runId;result='observed';mode='AccessCheckOnly';token=$Token
        childResumed=$false;standardAccountLifecycleTested=$false;productionInstallerExecuted=$false
        desktopAclChanged=$false;windowStationAclChanged=$false;before=$Before;access=$Access;after=$After
        scope='Read-only owner/group/DACL/mandatory-label descriptors and AccessCheck; USER32 initialization and UI were not executed.'
    }
}
function Get-StandardAcceptancePaths([string]$RunId) {
    Assert-StandardAcceptance ($RunId -cmatch '^[a-f0-9]{32}$') 'Expected the exact prepared acceptance run ID.'
    $root = 'C:\Users\Public\SteamWrapperAcceptance-' + $RunId
    return [pscustomobject]@{ root=$root; input=$root + '\input'; output=$root + '\evidence'; userName='SwAcc-' + $RunId.Substring(0,14) }
}
function Get-StandardPermissionPaths([string]$RunId) {
    $null=Get-StandardAcceptancePaths $RunId
    $root='C:\Users\Public\SteamWrapperPermissionAcceptance-'+$RunId
    return [pscustomobject]@{root=$root;input=$root+'\input';output=$root+'\evidence';userName='WDAGUtilityAccount'}
}
function Assert-StandardPermissionPrivileges($Token) {
    Assert-StandardAcceptance ($null -ne $Token.PSObject.Properties['privileges'] -and @($Token.privileges).Count -le 128) 'Missing bounded actual token privilege observation.'
    $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($privilege in @($Token.privileges)) {
        Assert-StandardAcceptance ($privilege.name -cmatch '^Se[A-Za-z]+Privilege$' -and $privilege.enabled -is [bool] -and $seen.Add([string]$privilege.name)) 'Unexpected or duplicate privilege observation.'
        if($privilege.name -cin @('SeDebugPrivilege','SeBackupPrivilege','SeRestorePrivilege','SeTakeOwnershipPrivilege','SeLoadDriverPrivilege','SeTcbPrivilege','SeImpersonatePrivilege')) {
            Assert-StandardAcceptance (-not $privilege.enabled) 'The permission token retains an active administrative privilege.'
        }
    }
}
function Assert-StandardPermissionChildContext($Context,$Manifest,[string]$InputPath,[string]$OutputPath) {
    Assert-StandardAcceptanceCommonContext $Context $Manifest
    $paths=Get-StandardPermissionPaths $Manifest.runId
    Assert-StandardAcceptance ($Manifest.accountMode -ceq 'WDAGStandardPermission' -and $Manifest.wdagPermissionOptIn -is [bool] -and $Manifest.wdagPermissionOptIn -and
        $Manifest.expectedStandardUserName -ceq 'WDAGUtilityAccount' -and $Manifest.permissionOriginalPrimarySid -cmatch '^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-504$' -and
        $Manifest.expectedStandardUserSid -ceq $Manifest.permissionOriginalPrimarySid -and
        $InputPath -ceq $paths.input -and $OutputPath -ceq $paths.output -and $Manifest.standardInputDirectory -ceq $paths.input -and $Manifest.standardOutputDirectory -ceq $paths.output -and
        $Context.userName -ceq 'WDAGUtilityAccount' -and $Context.profile -ieq 'C:\Users\WDAGUtilityAccount' -and
        $Context.sessionId -eq $Manifest.standardSessionId -and $Context.accountAdministratorMember -is [bool] -and -not $Context.accountAdministratorMember -and
        $Context.accountUsersMember -is [bool] -and $Context.accountUsersMember -and
        $Manifest.standardExpectedLogonSid -cmatch '^S-1-5-5-[0-9]+-[0-9]+$' -and $Context.token.logonSid -ceq $Manifest.standardExpectedLogonSid) 'The permission child is not the explicitly sealed original WDAG SID/native profile with a new ordinary logon.'
    Assert-StandardAcceptanceProcessToken $Context.token $Manifest.expectedStandardUserSid
    Assert-StandardPermissionPrivileges $Context.token
}
function Assert-StandardAcceptanceScopedChildContext($Context,$Manifest,[string]$InputPath,[string]$OutputPath) {
    if($Manifest.accountMode -ceq 'WDAGStandardPermission'){Assert-StandardPermissionChildContext $Context $Manifest $InputPath $OutputPath}
    else {Assert-StandardAcceptanceChildContext $Context $Manifest $InputPath $OutputPath}
}
function Quote-StandardAcceptanceArgument([string]$Value) {
    Assert-StandardAcceptance (-not [string]::IsNullOrWhiteSpace($Value) -and
        -not $Value.Contains('"') -and -not $Value.Contains([string][char]13) -and -not $Value.Contains([string][char]10)) 'Unsafe standard-user child command argument.'
    return '"' + $Value.TrimEnd('\') + '"'
}
function Assert-StandardAcceptanceCommonContext($Context, $Manifest) {
    Assert-StandardAcceptance ($Manifest.schemaVersion -eq 1 -and $Manifest.sandboxOnly -is [bool] -and $Manifest.sandboxOnly -and
        $Manifest.networkingDisabled -is [bool] -and $Manifest.networkingDisabled -and
        -not [string]::IsNullOrWhiteSpace([string]$Manifest.hostComputerName) -and
        $Context.computerName -ine $Manifest.hostComputerName) 'Refusing an unexpected manifest or its development host.'
    Assert-StandardAcceptance ($Context.interactive -eq $true -and $Context.sessionId -gt 0 -and
        $Context.manufacturer -ceq 'Microsoft Corporation' -and $Context.model -ceq 'Virtual Machine' -and
        $Context.productType -eq 1 -and $Context.build -ge 26100 -and $Context.x64 -eq $true) 'A connected native x64 Windows 11 Sandbox client is required.'
    Assert-StandardAcceptance ($Context.profile -ieq $Context.nativeProfile -and $Context.localAppData -ieq $Context.nativeLocalAppData -and
        -not $Context.machineDotnetExists -and -not $Context.dotnetOnPath -and @($Context.overrides).Count -eq 0) 'Refusing redirected AppData, an SDK/runtime or test overrides.'
}
function Assert-StandardAcceptanceControllerContext($Context, $Manifest, [string]$InputPath, [string]$OutputPath) {
    Assert-StandardAcceptanceCommonContext $Context $Manifest
    $null=Get-StandardAcceptancePaths $Manifest.runId
    Assert-StandardAcceptance ($InputPath -ceq 'C:\AcceptanceInput' -and $OutputPath -ceq 'C:\AcceptanceOutput' -and
        $Context.userName -ieq 'WDAGUtilityAccount' -and $Context.profile -ieq 'C:\Users\WDAGUtilityAccount' -and
        $Context.token.administratorEnabled -eq $true) 'Account creation is allowed only in the dedicated WDAG Sandbox controller.'
}
function Assert-StandardAcceptanceChildContext($Context, $Manifest, [string]$InputPath, [string]$OutputPath) {
    Assert-StandardAcceptanceCommonContext $Context $Manifest
    $paths=Get-StandardAcceptancePaths $Manifest.runId
    Assert-StandardAcceptance ($Manifest.accountMode -ceq 'StandardUser' -and $Manifest.expectedStandardUserName -ceq $paths.userName -and
        $Manifest.expectedStandardUserSid -cmatch '^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-[0-9]+$' -and
        $Manifest.standardInputDirectory -ceq $paths.input -and $Manifest.standardOutputDirectory -ceq $paths.output -and
        $InputPath -ceq $paths.input -and $OutputPath -ceq $paths.output -and
        $Context.userName -ceq $paths.userName -and $Context.profile -ieq ('C:\Users\' + $paths.userName) -and
        $Context.sessionId -eq $Manifest.standardSessionId -and $Context.accountAdministratorMember -is [bool] -and -not $Context.accountAdministratorMember) 'The child is not the exact fresh standard account and native profile.'
    Assert-StandardAcceptance ($Context.accountUsersMember -is [bool] -and $Context.accountUsersMember) 'The fresh standard account must belong to the ordinary Builtin Users group.'
    Assert-StandardAcceptanceProcessToken $Context.token $Manifest.expectedStandardUserSid
    if($null -ne $Manifest.PSObject.Properties['standardExpectedLogonSid']) {
        Assert-StandardAcceptance ($Manifest.standardExpectedLogonSid -cmatch '^S-1-5-5-[0-9]+-[0-9]+$' -and $Context.token.logonSid -ceq $Manifest.standardExpectedLogonSid) 'The child did not retain the exact granted logon SID.'
    }
}
function Assert-StandardAcceptanceProcessToken($Token, [string]$ExpectedSid) {
    Assert-StandardAcceptance ($Token.userSid -ceq $ExpectedSid -and $Token.elevated -is [bool] -and -not $Token.elevated -and
        $Token.elevationType -eq 1 -and $Token.integritySid -ceq 'S-1-16-8192' -and
        $Token.administratorPresent -is [bool] -and -not $Token.administratorPresent -and
        $Token.administratorEnabled -is [bool] -and -not $Token.administratorEnabled -and
        $Token.administratorDenyOnly -is [bool] -and -not $Token.administratorDenyOnly -and
        $Token.usersPresent -is [bool] -and $Token.usersPresent -and $Token.usersEnabled -is [bool] -and $Token.usersEnabled -and
        $Token.usersDenyOnly -is [bool] -and -not $Token.usersDenyOnly -and
        $Token.uiAccess -is [bool] -and -not $Token.uiAccess -and $Token.appContainer -is [bool] -and -not $Token.appContainer -and $Token.type -eq 1) 'A real standard-account Medium, non-elevated primary token is required; a filtered administrator is not accepted.'
}
function Get-StandardAcceptanceControllerOwnedLocations($Context) {
    Assert-StandardAcceptance ($Context.userName -ieq 'WDAGUtilityAccount' -and $Context.nativeProfile -ieq 'C:\Users\WDAGUtilityAccount' -and
        $Context.nativeLocalAppData -ieq 'C:\Users\WDAGUtilityAccount\AppData\Local') 'The two-user separation snapshot is restricted to the native disposable WDAG profile.'
    return @(
        [pscustomobject]@{name='data';path=(Join-Path $Context.nativeLocalAppData 'SteamWrapper')},
        [pscustomobject]@{name='program';path=(Join-Path $Context.nativeLocalAppData 'Programs\SteamWrapper')},
        [pscustomobject]@{name='registration';path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7DBEC23-E563-4BFB-BE9C-F68D73E4D5BB}_is1'},
        [pscustomobject]@{name='startMenu';path=(Join-Path $Context.nativeProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SteamWrapper\SteamWrapper.lnk')},
        [pscustomobject]@{name='desktop';path=(Join-Path $Context.nativeProfile 'Desktop\SteamWrapper.lnk')}
    )
}
function Get-StandardAcceptanceControllerSeparation($Context) {
    return @(foreach($location in Get-StandardAcceptanceControllerOwnedLocations $Context) {
        [pscustomobject]@{name=$location.name;path=$location.path;present=[bool](Test-Path -LiteralPath $location.path)}
    })
}
function Assert-StandardAcceptanceControllerSeparation($Before,$After,$Context) {
    $expected=Get-StandardAcceptanceControllerOwnedLocations $Context
    Assert-StandardAcceptance (@($Before).Count -eq 5 -and @($After).Count -eq 5) 'The two-user separation snapshot is incomplete.'
    foreach($location in $expected) {
        foreach($snapshot in @($Before,$After)) {
            $matches=@($snapshot | Where-Object name -CEQ $location.name)
            Assert-StandardAcceptance ($matches.Count -eq 1 -and $matches[0].path -ieq $location.path -and
                $matches[0].present -is [bool] -and -not $matches[0].present) 'Use a fresh Sandbox: an owned WDAG data/program/registration/shortcut location exists or changed during the standard-user lifecycle.'
        }
    }
}
function Assert-StandardAcceptanceShellProvenance($Observation,$Context,$Manifest,[string]$Program,[string]$Tag) {
    Assert-StandardAcceptanceChildContext $Context $Manifest $Manifest.standardInputDirectory $Manifest.standardOutputDirectory
    Assert-StandardAcceptance ($Tag -cmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$' -and
        $Program -ieq (Join-Path $Context.nativeLocalAppData 'Programs\SteamWrapper')) 'The Explorer smoke targets only the standard account first default installation.'
    $shortcut=Join-Path $Context.nativeProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SteamWrapper\SteamWrapper.lnk'
    Assert-StandardAcceptance (Test-StandardAcceptanceAddressObservation $Observation.addressControl ([IO.Path]::GetDirectoryName($shortcut))) 'The actual Explorer address edit/parent did not prove the shortcut folder.'
    $expected=@{explorer='C:\Windows\explorer.exe';launcher=(Join-Path $Program 'SteamWrapper.exe');manager=(Join-Path $Program ('versions\'+$Tag+'\SteamWrapper.Manager.exe'))}
    foreach($kind in @('explorer','launcher','manager')) {
        $process=$Observation.$kind
        Assert-StandardAcceptance ($process.processId -gt 0 -and $process.path -ieq $expected[$kind]) 'An observed Explorer/Launcher/Manager process is missing or outside the verified installed paths.'
        Assert-StandardAcceptanceProcessToken $process.token $Manifest.expectedStandardUserSid
        Assert-StandardAcceptance ($process.token.sessionId -eq $Context.sessionId -and
            $Manifest.standardExpectedLogonSid -cmatch '^S-1-5-5-[0-9]+-[0-9]+$' -and
            $process.token.logonSid -ceq $Manifest.standardExpectedLogonSid) 'A shell-launched process changed the real standard-account logon or session.'
    }
    Assert-StandardAcceptance ($Observation.explorer.processId -ne $Observation.launcher.processId -and $Observation.launcher.processId -ne $Observation.manager.processId -and
        $Observation.launcher.parentProcessId -eq $Observation.explorer.processId -and $Observation.manager.parentProcessId -eq $Observation.launcher.processId -and
        $Observation.windowProcessId -eq $Observation.explorer.processId -and
        ($Observation.itemProviderProcessId -eq 0 -or $Observation.itemProviderProcessId -eq $Observation.explorer.processId) -and
        $Observation.folder -ieq [IO.Path]::GetDirectoryName($shortcut) -and $Observation.shortcut -ieq $shortcut -and
        $Observation.invokedThroughUi -is [bool] -and $Observation.invokedThroughUi) 'The actual owned Explorer window/shortcut invocation and Explorer-to-Launcher-to-Manager ancestry were not all observed.'
}
function Assert-StandardAcceptanceInstalledShortcutProvenance($Observation,$Context,$Manifest,[string]$Program,[string]$Tag) {
    Assert-StandardAcceptanceScopedChildContext $Context $Manifest $Manifest.standardInputDirectory $Manifest.standardOutputDirectory
    Assert-StandardAcceptance ($Tag -cmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$' -and
        $Program -ieq (Join-Path $Context.nativeLocalAppData 'Programs\SteamWrapper')) 'The installed-shortcut lane requires this exact standard profile first installation.'
    $shortcut=Join-Path $Context.nativeProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SteamWrapper\SteamWrapper.lnk'
    Assert-StandardAcceptance ($Observation.shortcut -ieq $shortcut -and $Observation.shellRoute -ceq 'standard-token installed shortcut' -and
        $Observation.ordinaryExplorerTested -is [bool] -and -not $Observation.ordinaryExplorerTested) 'The separately requested native shortcut launch was missing or misrepresented as ordinary Explorer.'
    foreach($record in @(@{kind='launcher';path=(Join-Path $Program 'SteamWrapper.exe')},@{kind='manager';path=(Join-Path $Program ('versions\'+$Tag+'\SteamWrapper.Manager.exe'))})) {
        $process=$Observation.($record.kind)
        Assert-StandardAcceptance ($process.processId -gt 0 -and $process.path -ieq $record.path) 'The shortcut-launched product process is outside the verified installation.'
        Assert-StandardAcceptanceProcessToken $process.token $Manifest.expectedStandardUserSid
        if($Manifest.accountMode -ceq 'WDAGStandardPermission'){Assert-StandardPermissionPrivileges $process.token}
        Assert-StandardAcceptance ($process.token.sessionId -eq $Context.sessionId -and $process.token.logonSid -ceq $Manifest.standardExpectedLogonSid) 'The shortcut-launched product escaped its exact standard logon/session.'
    }
    Assert-StandardAcceptance ($Observation.invokerProcessId -gt 0 -and $Observation.returnedLauncherProcessId -eq $Observation.launcher.processId -and
        $Observation.launcher.parentProcessId -eq $Observation.invokerProcessId -and $Observation.manager.parentProcessId -eq $Observation.launcher.processId -and
        $Observation.manager.processId -ne $Observation.launcher.processId) 'The actual returned launcher and child Manager ancestry were not observed for the standard-token shortcut request.'
}
function Wait-StandardAcceptanceShell([scriptblock]$Condition,[string]$Description) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while($timer.ElapsedMilliseconds -lt 60000) {
        $result=& $Condition
        if($null -ne $result -and $result -ne $false) {return $result}
        Start-Sleep -Milliseconds 100
    }
    throw ('Standard-account shell smoke timed out: '+$Description+'. No process was killed or direct-launch fallback used.')
}
function Test-StandardAcceptanceAddressObservation($Address,[string]$Folder) {
    $names=@('Address',(-join @([char]0x5730,[char]0x5740)))
    $editName=$false;$parentName=$false
    foreach($name in $names) {
        if($Address.name -ceq $name) {$editName=$true}
        if($Address.parentName -ceq $name -or $Address.parentName.StartsWith($name+':',[StringComparison]::Ordinal)) {$parentName=$true}
    }
    return $editName -and $parentName -and $Address.controlType -ceq 'ControlType.Edit' -and
        $Address.parentControlType -ceq 'ControlType.ComboBox' -and $Address.value.TrimEnd('\') -ieq $Folder
}
function Find-StandardAcceptanceExplorerWindow($Context,$Manifest,[string]$Folder,$Diagnostic) {
    $observed=New-Object 'System.Collections.Generic.List[object]'
    foreach($process in [Diagnostics.Process]::GetProcessesByName('explorer')) {
        try {
            $identity=[SteamWrapperStandardAcceptance.Native]::ObserveProcess($process.Id)
            if($identity.token.userSid -cne $Manifest.expectedStandardUserSid -or $identity.token.logonSid -cne $Manifest.standardExpectedLogonSid) {continue}
            Assert-StandardAcceptanceProcessToken $identity.token $Manifest.expectedStandardUserSid
            Assert-StandardAcceptance ($identity.token.sessionId -eq $Context.sessionId -and $identity.path -ieq 'C:\Windows\explorer.exe') 'The observed standard Explorer changed its native executable/session.'
            $conditions=New-Object System.Windows.Automation.AndCondition -ArgumentList @(
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,$process.Id)),
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'CabinetWClass')))
            $windows=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,$conditions)
            Assert-StandardAcceptance ($windows.Count -le 8) 'Too many owned standard Explorer windows.'
            foreach($window in $windows) {
                $edits=$window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit)))
                Assert-StandardAcceptance ($edits.Count -le 32) 'Too many address/search edits in the owned Explorer window.'
                $values=@();$exactFolder=$false
                foreach($edit in $edits) {
                    $pattern=$null
                    if($edit.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)) {
                        $value=[string]([System.Windows.Automation.ValuePattern]$pattern).Current.Value
                        $parent=[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($edit)
                        Assert-StandardAcceptance ($null -ne $parent -and $value.Length -le 4096 -and $edit.Current.Name.Length -le 1024 -and $parent.Current.Name.Length -le 1024) 'The owned Explorer address/search observation exceeds its bound.'
                        $address=[pscustomobject]@{name=$edit.Current.Name;automationId=$edit.Current.AutomationId;value=$value;controlType=$edit.Current.ControlType.ProgrammaticName;
                            parentName=$parent.Current.Name;parentAutomationId=$parent.Current.AutomationId;parentControlType=$parent.Current.ControlType.ProgrammaticName}
                        $values += $address
                        if(Test-StandardAcceptanceAddressObservation $address $Folder) {$exactFolder=$true;$Diagnostic['exactAddressControl']=$address}
                    }
                }
                $observed.Add([ordered]@{process=$identity;windowName=$window.Current.Name;addressValues=$values;exactFolderObserved=$exactFolder})
                if($exactFolder) {$Diagnostic['ownedWindows']=$observed.ToArray();return [pscustomobject]@{Window=$window;Identity=$identity}}
            }
        } catch {$observed.Add([ordered]@{processId=$process.Id;readError=$_.Exception.GetBaseException().Message})}
        finally {$process.Dispose()}
    }
    $Diagnostic['ownedWindows']=$observed.ToArray()
    return $null
}
function Start-StandardAcceptanceInstalledShortcutManager($Context,$Manifest,[string]$Program,[string]$Tag) {
    Assert-StandardAcceptanceScopedChildContext $Context $Manifest $Manifest.standardInputDirectory $Manifest.standardOutputDirectory
    Assert-StandardAcceptance ($Manifest.standardInstalledShortcut -is [bool] -and $Manifest.standardInstalledShortcut -and
        -not $Manifest.standardExplorerShortcut -and $Manifest.scenario -ceq 'CandidateFirstInstall' -and
        $Program -ieq (Join-Path $Context.nativeLocalAppData 'Programs\SteamWrapper')) 'The native shortcut helper requires its separate opted-in standard first-install lane.'
    $shortcut=Join-Path $Context.nativeProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SteamWrapper\SteamWrapper.lnk'
    Assert-StandardAcceptanceRegularPath $shortcut $false
    $observer=New-Object SteamWrapperStandardAcceptance.LauncherObserver((Join-Path $Program 'SteamWrapper.exe'))
    $launcher=$null;$manager=$null;$success=$false
    $diagnostic=[ordered]@{shellRoute='standard-token installed shortcut';ordinaryExplorerTested=$false;shortcut=$shortcut;stage='ShellExecute installed Start-menu shortcut';failure=$null}
    $diagnosticPath=Join-Path $Manifest.standardOutputDirectory 'standard-shortcut.log'
    Write-StandardAcceptanceJson $diagnosticPath $diagnostic
    try {
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$shortcut;$start.UseShellExecute=$true
        $launcher=[Diagnostics.Process]::Start($start)
        Assert-StandardAcceptance ($null -ne $launcher) 'The native installed shortcut did not return an actual new launcher process; no direct fallback was used.'
        $launcherIdentity=Wait-StandardAcceptanceShell {$observer.snapshot} 'actual shortcut launcher token/parent'
        $expected=Join-Path $Program ('versions\'+$Tag+'\SteamWrapper.Manager.exe')
        $manager=Wait-StandardAcceptanceShell {
            foreach($candidate in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Manager')) {
                $keep=$false
                try {
                    $null=$candidate.Handle
                    if($candidate.MainModule.FileName -ieq $expected -and $candidate.MainWindowHandle -ne [IntPtr]::Zero) {$keep=$true;return $candidate}
                } catch { } finally {if(-not $keep) {$candidate.Dispose()}}
            };return $null
        } 'Manager created from the standard-token installed shortcut'
        $observation=[ordered]@{shellRoute=$diagnostic.shellRoute;ordinaryExplorerTested=$false;shortcut=$shortcut;invokerProcessId=[Diagnostics.Process]::GetCurrentProcess().Id;
            returnedLauncherProcessId=$launcher.Id;launcher=$launcherIdentity;manager=[SteamWrapperStandardAcceptance.Native]::ObserveProcess($manager.Id)}
        Assert-StandardAcceptanceInstalledShortcutProvenance ([pscustomobject]$observation) $Context $Manifest $Program $Tag
        $diagnostic.stage='Actual standard shortcut Launcher/Manager provenance observed';$diagnostic['provenance']=$observation
        $success=$true
        return [pscustomobject]@{Process=$manager;Observation=$observation}
    } catch {
        $diagnostic.failure=[ordered]@{type=$_.Exception.GetBaseException().GetType().FullName;message=$_.Exception.GetBaseException().Message;line=$_.InvocationInfo.ScriptLineNumber;stack=$_.ScriptStackTrace}
        throw
    } finally {
        try {$observer.Dispose()} finally {
            if($null -ne $launcher) {$launcher.Dispose()}
            if(-not $success -and $null -ne $manager) {$manager.Dispose()}
            Write-StandardAcceptanceJson $diagnosticPath $diagnostic
        }
    }
}
function Start-StandardAcceptanceExplorerManager($Context,$Manifest,[string]$Program,[string]$Tag) {
    Assert-StandardAcceptanceChildContext $Context $Manifest $Manifest.standardInputDirectory $Manifest.standardOutputDirectory
    Assert-StandardAcceptance ($Manifest.standardExplorerShortcut -is [bool] -and $Manifest.standardExplorerShortcut -and
        $Manifest.scenario -ceq 'CandidateFirstInstall' -and $Tag -cmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$' -and
        $Program -ieq (Join-Path $Context.nativeLocalAppData 'Programs\SteamWrapper')) 'The shell helper requires the opted-in first installation in this exact standard user profile.'
    $shortcut=Join-Path $Context.nativeProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SteamWrapper\SteamWrapper.lnk'
    $folder=[IO.Path]::GetDirectoryName($shortcut)
    Assert-StandardAcceptanceRegularPath $shortcut $false
    Assert-StandardAcceptance ($folder -ieq (Join-Path ([Environment]::GetFolderPath('Programs')) 'SteamWrapper')) 'The installed shortcut is outside the current native Start-menu folder.'
    $linkReader=New-Object -ComObject WScript.Shell
    try {
        $link=$linkReader.CreateShortcut($shortcut)
        Assert-StandardAcceptance ($link.TargetPath -ieq (Join-Path $Program 'SteamWrapper.exe') -and [string]::IsNullOrEmpty($link.Arguments)) 'The real installed shortcut changed its target or arguments.'
    } finally {if($null -ne $linkReader) {[Runtime.InteropServices.Marshal]::FinalReleaseComObject($linkReader) | Out-Null}}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName='C:\Windows\explorer.exe';$start.Arguments='/separate,'+(Quote-StandardAcceptanceArgument $folder)
    $start.UseShellExecute=$false;$start.WorkingDirectory=$folder
    $explorerStart=$null;$observer=$null;$window=$null;$explorerIdentity=$null;$manager=$null;$success=$false
    $shellDiagnostic=[ordered]@{stage='Start exact native Explorer';requestedFolder=$folder;ownedWindows=@();failure=$null}
    $shellDiagnosticPath=Join-Path $Manifest.standardOutputDirectory 'standard-explorer.log'
    Write-StandardAcceptanceJson $shellDiagnosticPath $shellDiagnostic
    try {
        $explorerStart=[Diagnostics.Process]::Start($start)
        $shellDiagnostic['requestedExplorerProcessId']=$explorerStart.Id
        $shellDiagnostic.stage='Find exact standard Explorer window/address through UIA';Write-StandardAcceptanceJson $shellDiagnosticPath $shellDiagnostic
        $owned=Wait-StandardAcceptanceShell {Find-StandardAcceptanceExplorerWindow $Context $Manifest $folder $shellDiagnostic} 'an actual same-logon Explorer window exposing the exact Start-menu folder path'
        $window=$owned.Window;$explorerIdentity=$owned.Identity
        $handle=[IntPtr][long]$window.Current.NativeWindowHandle
        Assert-StandardAcceptanceProcessToken $explorerIdentity.token $Manifest.expectedStandardUserSid
        Assert-StandardAcceptance ($explorerIdentity.path -ieq 'C:\Windows\explorer.exe' -and
            $explorerIdentity.token.logonSid -ceq $Manifest.standardExpectedLogonSid -and $explorerIdentity.token.sessionId -eq $Context.sessionId) 'The real Explorer window delegated to another account/logon/session; no shortcut was invoked.'
        Assert-StandardAcceptance ($window.Current.ProcessId -eq $explorerIdentity.processId) 'The Explorer UIA root belongs to a foreign process.'
        $shellDiagnostic.stage='Invoke exact installed shortcut through owned Explorer UIA';Write-StandardAcceptanceJson $shellDiagnosticPath $shellDiagnostic
        $nameConditions=New-Object System.Windows.Automation.OrCondition -ArgumentList @(
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'SteamWrapper')),
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'SteamWrapper.lnk')))
        $conditions=New-Object System.Windows.Automation.AndCondition -ArgumentList @($nameConditions,
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
        $item=Wait-StandardAcceptanceShell {
            $matches=$window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$conditions)
            Assert-StandardAcceptance ($matches.Count -le 1) 'More than one installed shortcut item was exposed by the owned Explorer window.'
            if($matches.Count -eq 1) {return $matches[0]};return $null
        } 'the exact installed shortcut item in the verified Explorer window'
        $provider=[int]$item.Current.ProcessId
        Assert-StandardAcceptance (($provider -eq 0 -or $provider -eq $explorerIdentity.processId) -and $item.Current.IsEnabled) 'The shortcut UIA provider belongs to a foreign root or is disabled.'
        $observer=New-Object SteamWrapperStandardAcceptance.LauncherObserver((Join-Path $Program 'SteamWrapper.exe'))
        ([System.Windows.Automation.InvokePattern]$item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
        $launcherIdentity=Wait-StandardAcceptanceShell {$observer.snapshot} 'actual short-lived launcher token and process ancestry'
        $expectedManager=Join-Path $Program ('versions\'+$Tag+'\SteamWrapper.Manager.exe')
        $manager=Wait-StandardAcceptanceShell {
            foreach($candidate in [Diagnostics.Process]::GetProcessesByName('SteamWrapper.Manager')) {
                $keep=$false
                try {
                    $null=$candidate.Handle
                    if($candidate.MainModule.FileName -ieq $expectedManager -and $candidate.MainWindowHandle -ne [IntPtr]::Zero) {$keep=$true;return $candidate}
                } catch { } finally {if(-not $keep) {$candidate.Dispose()}}
            };return $null
        } 'the Manager window created by the Explorer-invoked installed launcher'
        $observation=[ordered]@{folder=$folder;addressControl=$shellDiagnostic.exactAddressControl;shortcut=$shortcut;windowProcessId=$window.Current.ProcessId;itemProviderProcessId=$provider;invokedThroughUi=$true;
            explorer=$explorerIdentity;launcher=$launcherIdentity;manager=[SteamWrapperStandardAcceptance.Native]::ObserveProcess($manager.Id)}
        Assert-StandardAcceptanceShellProvenance ([pscustomobject]$observation) $Context $Manifest $Program $Tag
        $shellDiagnostic.stage='Actual Explorer/Launcher/Manager provenance observed';$shellDiagnostic['provenance']=$observation
        $success=$true
        return [pscustomobject]@{Process=$manager;Observation=$observation}
    } catch {
        $shellDiagnostic.failure=[ordered]@{type=$_.Exception.GetBaseException().GetType().FullName;message=$_.Exception.GetBaseException().Message;scriptLine=$_.InvocationInfo.ScriptLineNumber;scriptStack=$_.ScriptStackTrace}
        throw
    } finally {
        try {
            if($null -ne $window -and $null -ne $explorerIdentity) {
                Assert-StandardAcceptance ($window.Current.ProcessId -eq $explorerIdentity.processId) 'Refusing to close a foreign Explorer window.'
                $current=[SteamWrapperStandardAcceptance.Native]::ObserveProcess($explorerIdentity.processId)
                Assert-StandardAcceptance ($current.path -ieq $explorerIdentity.path -and $current.token.userSid -ceq $Manifest.expectedStandardUserSid -and
                    $current.token.logonSid -ceq $Manifest.standardExpectedLogonSid) 'Refusing to close an Explorer window after its identity changed.'
                ([System.Windows.Automation.WindowPattern]$window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)).Close()
                $null=Wait-StandardAcceptanceShell {-not [SteamWrapperStandardAcceptance.Native]::IsWindow($handle)} 'normal close of the owned Explorer window'
                if($success) {$observation['explorerNormalCloseRequested']=$true;$observation['explorerWindowClosed']=$true}
            }
        } finally {
            if($null -ne $observer) {$observer.Dispose()}
            if($null -ne $explorerStart) {$explorerStart.Dispose()}
            if(-not $success -and $null -ne $manager) {$manager.Dispose()}
            Write-StandardAcceptanceJson $shellDiagnosticPath $shellDiagnostic
        }
    }
}
function Assert-StandardAcceptanceRegularPath([string]$Path, [bool]$Directory) {
    $item=Get-Item -LiteralPath $Path -Force
    Assert-StandardAcceptance (($Directory -and $item -is [IO.DirectoryInfo]) -or (-not $Directory -and $item -is [IO.FileInfo])) 'Unexpected standard-user input/output file type.'
    $ancestor=$item
    while ($null -ne $ancestor) {
        Assert-StandardAcceptance (-not ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Standard-account acceptance paths must not contain links.'
        $ancestor=if ($ancestor -is [IO.DirectoryInfo]) {$ancestor.Parent} else {$ancestor.Directory}
    }
}
function Read-StandardAcceptanceManifest([string]$Directory) {
    return Read-StandardAcceptanceJson (Join-Path $Directory 'acceptance-input.json')
}
function Read-StandardAcceptanceJson([string]$Path) {
    Assert-StandardAcceptanceRegularPath $Path $false
    Assert-StandardAcceptance ((Get-Item -LiteralPath $Path).Length -le 2MB) 'The acceptance JSON exceeds its read limit.'
    # Inbox PowerShell 5.1 otherwise interprets our UTF8-without-BOM output
    # using ANSI, which can consume the quote after a trailing Chinese byte.
    return [IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) | ConvertFrom-Json
}
function Assert-StandardAcceptanceSealedFile([string]$Path, [string]$Hash, [long]$Bytes=-1) {
    Assert-StandardAcceptanceRegularPath $Path $false
    $file=Get-Item -LiteralPath $Path
    Assert-StandardAcceptance ($Hash -cmatch '^[a-f0-9]{64}$' -and $file.Length -gt 0 -and $file.Length -le 512MB -and
        ($Bytes -lt 0 -or $file.Length -eq $Bytes) -and
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Hash) 'A sealed standard-account acceptance input changed.'
}
function Get-StandardAcceptanceSealedInputs($Manifest, [string]$ControllerHash) {
    $files=@(
        [pscustomobject]@{name='Invoke-CleanWindowsGuestAcceptance.ps1';hash=$Manifest.guestScriptSha256;bytes=-1},
        [pscustomobject]@{name='Start-CleanWindowsAcceptance.ps1';hash=$Manifest.launchScriptSha256;bytes=-1},
        [pscustomobject]@{name='StandardUserAcceptance.ps1';hash=$ControllerHash;bytes=-1}
    )
    foreach($asset in @($Manifest.baseline,$Manifest.target)) {
        Assert-StandardAcceptance ($asset.fileName -cmatch '^SteamWrapper-v[0-9A-Za-z.-]+-win-x64-setup\.exe$' -and $asset.bytes -gt 0 -and $asset.bytes -le 512MB) 'Unexpected standard-account installer input.'
        $existing=@($files | Where-Object name -CEQ $asset.fileName)
        Assert-StandardAcceptance ($existing.Count -eq 0 -or ($existing[0].hash -ceq $asset.sha256 -and $existing[0].bytes -eq $asset.bytes)) 'Duplicate installer names disagree on their sealed bytes.'
        $files += [pscustomobject]@{name=$asset.fileName;hash=$asset.sha256;bytes=$asset.bytes}
    }
    if($null -ne $Manifest.PSObject.Properties['candidateBuildSha256']) {
        $files += [pscustomobject]@{name='installer-build.json';hash=$Manifest.candidateBuildSha256;bytes=-1}
        $files += [pscustomobject]@{name='deployment-manifest.json';hash=$Manifest.candidateDeploymentManifestSha256;bytes=-1}
    }
    if($Manifest.scenario -ceq 'CandidateUpgrade') {
        $files += [pscustomobject]@{name='baseline-release.json';hash=$Manifest.baselinePublicReleaseSha256;bytes=-1}
        $files += [pscustomobject]@{name='baseline-api.json';hash=$Manifest.baselinePublicApiSha256;bytes=-1}
    }
    if($null -ne $Manifest.PSObject.Properties['winUiControl']) {
        Assert-StandardAcceptance ($Manifest.winUiControl.bytes -gt 0 -and $Manifest.winUiControl.bytes -le 256MB) 'The developer control payload exceeds its bound.'
        $files += [pscustomobject]@{name='Invoke-StandardWinUiControlProbe.ps1';hash=$Manifest.winUiControl.driverSha256;bytes=-1}
        $files += [pscustomobject]@{name='standard-winui-control.json';hash=$Manifest.winUiControl.inventorySha256;bytes=-1}
        $files += [pscustomobject]@{name='standard-winui-control.zip';hash=$Manifest.winUiControl.sha256;bytes=$Manifest.winUiControl.bytes}
    }
    foreach($file in $files) {Assert-StandardAcceptance ($file.hash -cmatch '^[a-f0-9]{64}$') 'A standard-account handoff dependency lacks its prepared hash.'}
    return @($files | Sort-Object -Property name -Unique)
}
function New-StandardAcceptanceGuestAcl([string]$UserSid, [string]$ControllerSid, [bool]$Writable, [bool]$Directory=$true) {
    $acl=if($Directory){New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier($ControllerSid)))
    foreach($grant in @(
        @{sid='S-1-5-18';rights=[Security.AccessControl.FileSystemRights]::FullControl},
        @{sid='S-1-5-32-544';rights=[Security.AccessControl.FileSystemRights]::FullControl},
        @{sid=$UserSid;rights=$(if($Writable){[Security.AccessControl.FileSystemRights]::Modify}else{[Security.AccessControl.FileSystemRights]::ReadAndExecute})}
    )) {
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $rule=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($grant.sid)), $grant.rights,
            $inheritance,
            [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    return $acl
}
function Initialize-StandardAcceptanceNative {
    if ('SteamWrapperStandardAcceptance.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
namespace SteamWrapperStandardAcceptance {
public sealed class TokenSnapshot {
    public string userSid, integritySid, logonSid;
    public bool elevated, administratorPresent, administratorEnabled, administratorDenyOnly, uiAccess, appContainer;
    public bool usersPresent,usersEnabled,usersDenyOnly;
    public int elevationType, type, sessionId;
    public PrivilegeSnapshot[] privileges;
}
public sealed class PrivilegeSnapshot {public string name;public uint attributes;public bool enabled;}
public sealed class ProcessSnapshot {
    public int processId,parentProcessId;
    public string path;
    public TokenSnapshot token;
}
// Observe the short-lived installed launcher without instrumenting product
// bytes or starting anything. Retain its handle before it can exit.
public sealed class LauncherObserver : IDisposable {
    readonly string path,name;
    readonly DateTime earliest;
    readonly Thread worker;
    volatile bool stopping;
    public volatile ProcessSnapshot snapshot;
    public string lastError;
    Process retained;
    public LauncherObserver(string executable) {
        path=System.IO.Path.GetFullPath(executable);name=System.IO.Path.GetFileNameWithoutExtension(path);earliest=DateTime.UtcNow;
        worker=new Thread(Observe);worker.IsBackground=true;worker.Start();
    }
    void Observe() {
        try { ObserveBounded(); } catch(Exception error) {lastError=error.GetType().FullName+": "+error.Message;}
    }
    void ObserveBounded() {
        Stopwatch deadline=Stopwatch.StartNew();
        while(!stopping && deadline.ElapsedMilliseconds<60000) {
            Process[] candidates=Process.GetProcessesByName(name);
            if(candidates.Length>64) {lastError="Too many same-name launcher processes.";return;}
            foreach(Process candidate in candidates) {
                bool keep=false;
                try {
                    IntPtr handle=candidate.Handle;
                    if(candidate.StartTime.ToUniversalTime()<earliest || !string.Equals(candidate.MainModule.FileName,path,StringComparison.OrdinalIgnoreCase)) continue;
                    ProcessSnapshot observed=Native.ObserveProcess(candidate.Id);
                    retained=candidate;keep=true;snapshot=observed;
                    foreach(Process unused in candidates) if(unused!=candidate) unused.Dispose();
                    return;
                } catch(Exception error) {lastError=error.GetType().FullName+": "+error.Message;}
                finally {if(!keep) candidate.Dispose();}
            }
            Thread.Sleep(10);
        }
    }
    public void Dispose() {
        stopping=true;
        if(!worker.Join(3000)) throw new TimeoutException("The read-only launcher observer did not stop; no observed process was terminated.");
        if(retained!=null) {retained.Dispose();retained=null;}
    }
}
public sealed class ChildHandle : IDisposable {
    internal IntPtr handle, thread;
    public int ProcessId;
    public void Resume() {
        if(thread==IntPtr.Zero) throw new InvalidOperationException("The owned child has no suspended thread handle.");
        uint previous=Native.ResumeThread(thread);
        if(previous!=1) throw new Win32Exception(Marshal.GetLastWin32Error(),"The owned child did not have the exact expected suspend count; no further thread action was taken.");
        Native.CloseHandle(thread); thread=IntPtr.Zero;
    }
    public int Wait(int milliseconds) {
        uint result=Native.WaitForSingleObject(handle,(uint)milliseconds);
        if(result==258) throw new TimeoutException("The standard-user child did not finish; no process was killed.");
        if(result!=0) throw new Win32Exception(Marshal.GetLastWin32Error(),"WaitForSingleObject failed.");
        uint code; if(!Native.GetExitCodeProcess(handle,out code)) throw new Win32Exception(Marshal.GetLastWin32Error(),"GetExitCodeProcess failed.");
        return unchecked((int)code);
    }
    public void Dispose() {
        if(thread!=IntPtr.Zero) { Native.CloseHandle(thread); thread=IntPtr.Zero; }
        if(handle!=IntPtr.Zero) { Native.CloseHandle(handle); handle=IntPtr.Zero; }
    }
}
public sealed class ObjectSecuritySnapshot {
    public string name, sha256, sddl;
    public int bytes;
}
public sealed class ObjectAccessSnapshot {
    public ObjectSecuritySnapshot security;
    public bool maximumAllowed;
    public uint grantedAccess;
    public Dictionary<string,bool> rights;
    public string engine="AuthzAccessCheck";
}
public sealed class DesktopSecuritySnapshot {
    public ObjectSecuritySnapshot windowStation, desktop;
}
public sealed class DesktopAccessSnapshot {
    public ObjectAccessSnapshot windowStation, desktop;
}
public static class Native {
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct ProcessEntry {
        public uint size,usage,pid;public UIntPtr heap;public uint module,threads,parent;public int priority;public uint flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string executable;
    }
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint processId);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool Process32FirstW(IntPtr snapshot,ref ProcessEntry entry);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool Process32NextW(IntPtr snapshot,ref ProcessEntry entry);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
    public static int WindowProcessId(IntPtr window) {
        uint processId; if(window==IntPtr.Zero || GetWindowThreadProcessId(window,out processId)==0) throw new InvalidOperationException("The observed Explorer window has no real process.");
        return checked((int)processId);
    }
    public static ProcessSnapshot ObserveProcess(int processId) {
        if(processId<=0) throw new ArgumentOutOfRangeException("processId");
        using(Process process=Process.GetProcessById(processId)) {
            IntPtr retained=process.Handle;
            ProcessSnapshot value=new ProcessSnapshot();value.processId=processId;value.path=process.MainModule.FileName;value.token=GetToken(processId);
            IntPtr snapshot=CreateToolhelp32Snapshot(2,0);
            if(snapshot==new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Process ancestry snapshot failed.");
            try {
                ProcessEntry entry=new ProcessEntry();entry.size=(uint)Marshal.SizeOf(typeof(ProcessEntry));
                if(Process32FirstW(snapshot,ref entry)) do {
                    if(entry.pid==(uint)processId) {value.parentProcessId=checked((int)entry.parent);return value;}
                } while(Process32NextW(snapshot,ref entry));
                throw new InvalidOperationException("The observed process exited before its actual parent was read.");
            } finally {CloseHandle(snapshot);}
        }
    }
    [StructLayout(LayoutKind.Sequential)] struct GenericMapping { public uint read,write,execute,all; }
    [StructLayout(LayoutKind.Sequential)] struct AuthorizationRequest { public uint desired; public IntPtr self,types; public uint typeCount; public IntPtr arguments; }
    [StructLayout(LayoutKind.Sequential)] struct AuthorizationReply { public uint count; public IntPtr granted,sacl,error; }
    [StructLayout(LayoutKind.Sequential)] struct SidAttributes { public IntPtr sid; public uint attributes; }
    [StructLayout(LayoutKind.Sequential)] struct GroupsFirst { public uint count; public SidAttributes first; }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct UserInfo {
        [MarshalAs(UnmanagedType.LPWStr)] public string name, password;
        public uint passwordAge, privilege;
        [MarshalAs(UnmanagedType.LPWStr)] public string home, comment;
        public uint flags;
        [MarshalAs(UnmanagedType.LPWStr)] public string script;
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Startup {
        public int cb;
        public string reserved, desktop, title;
        public uint x,y,xSize,ySize,xCount,yCount,fill,flags;
        public ushort show,reservedSize;
        public IntPtr reservedBytes,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process,thread; public uint pid,tid; }
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr buffer,uint length,out uint needed);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr descriptor,uint revision,uint information,out IntPtr value,out uint characters);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr pointer);
    [DllImport("authz.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool AuthzInitializeResourceManager(uint flags,IntPtr check,IntPtr groups,IntPtr free,string name,out IntPtr manager);
    [DllImport("authz.dll",SetLastError=true)] static extern bool AuthzInitializeContextFromToken(uint flags,IntPtr token,IntPtr manager,IntPtr expiration,ulong identifier,IntPtr arguments,out IntPtr context);
    [DllImport("authz.dll",SetLastError=true)] static extern bool AuthzAccessCheck(uint flags,IntPtr context,ref AuthorizationRequest request,IntPtr audit,IntPtr descriptor,
        IntPtr optional,uint count,ref AuthorizationReply reply,IntPtr result);
    [DllImport("authz.dll")] static extern bool AuthzFreeContext(IntPtr context);
    [DllImport("authz.dll")] static extern bool AuthzFreeResourceManager(IntPtr manager);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int processId);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    [DllImport("kernel32.dll",SetLastError=true)] internal static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
    [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint ResumeThread(IntPtr thread);
    [DllImport("netapi32.dll",CharSet=CharSet.Unicode)] static extern uint NetUserAdd(string server,uint level,ref UserInfo info,out uint parameter);
    [DllImport("netapi32.dll",CharSet=CharSet.Unicode)] static extern uint NetUserGetLocalGroups(string server,string user,uint level,uint flags,out IntPtr buffer,uint maximum,out uint count,out uint total);
    [DllImport("netapi32.dll",CharSet=CharSet.Unicode)] static extern uint NetLocalGroupAddMembers(string server,string group,uint level,ref IntPtr member,uint count);
    [DllImport("netapi32.dll",CharSet=CharSet.Unicode)] static extern uint NetLocalGroupDelMembers(string server,string group,uint level,ref IntPtr member,uint count);
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct PasswordInfo {[MarshalAs(UnmanagedType.LPWStr)]public string password;}
    [DllImport("netapi32.dll",CharSet=CharSet.Unicode)] static extern uint NetUserSetInfo(string server,string user,uint level,ref PasswordInfo info,out uint parameter);
    [StructLayout(LayoutKind.Sequential)] struct Luid {public uint low;public int high;}
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool LookupPrivilegeNameW(string system,ref Luid luid,StringBuilder name,ref uint length);
    [DllImport("netapi32.dll")] static extern uint NetApiBufferFree(IntPtr buffer);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessWithLogonW(
        string user,string domain,string password,uint logonFlags,string application,StringBuilder command,uint creationFlags,
        IntPtr environment,string directory,ref Startup startup,out ProcessInfo process);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr GetProcessWindowStation();
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr GetThreadDesktop(uint threadId);
    [DllImport("user32.dll",SetLastError=true)] static extern bool GetUserObjectSecurity(IntPtr handle,ref uint information,IntPtr descriptor,uint bytes,out uint needed);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetUserObjectSecurity(IntPtr handle,ref uint information,IntPtr descriptor);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenWindowStationW(string name,bool inherit,uint access);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenDesktopW(string name,uint flags,bool inherit,uint access);
    [DllImport("user32.dll")] static extern bool CloseWindowStation(IntPtr station);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool GetUserObjectInformationW(IntPtr handle,int index,StringBuilder value,uint bytes,out uint needed);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr handle);
    static IntPtr Information(IntPtr token,int kind) {
        uint length; GetTokenInformation(token,kind,IntPtr.Zero,0,out length);
        if(length==0 || length>131072) throw new Win32Exception(Marshal.GetLastWin32Error(),"Unexpected token information size.");
        IntPtr buffer=Marshal.AllocHGlobal((int)length);
        if(!GetTokenInformation(token,kind,buffer,length,out length)) { int error=Marshal.GetLastWin32Error(); Marshal.FreeHGlobal(buffer); throw new Win32Exception(error,"GetTokenInformation failed."); }
        return buffer;
    }
    static int Scalar(IntPtr token,int kind) { IntPtr b=Information(token,kind); try { return Marshal.ReadInt32(b); } finally { Marshal.FreeHGlobal(b); } }
    static string SidInformation(IntPtr token,int kind) { IntPtr b=Information(token,kind); try { return new SecurityIdentifier(Marshal.ReadIntPtr(b)).Value; } finally { Marshal.FreeHGlobal(b); } }
    public static TokenSnapshot GetToken(int processId) {
        IntPtr process=processId==0 ? GetCurrentProcess() : OpenProcess(0x1000,false,processId);
        if(process==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed.");
        IntPtr token=IntPtr.Zero;
        try {
            if(!OpenProcessToken(process,8,out token)) throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcessToken failed.");
            TokenSnapshot value=new TokenSnapshot();
            value.userSid=SidInformation(token,1); value.integritySid=SidInformation(token,25);
            value.elevated=Scalar(token,20)!=0; value.elevationType=Scalar(token,18); value.type=Scalar(token,8);
            value.sessionId=Scalar(token,12); value.uiAccess=Scalar(token,26)!=0; value.appContainer=Scalar(token,29)!=0;
            IntPtr groups=Information(token,2);
            try {
                int count=Marshal.ReadInt32(groups); if(count<0 || count>4096) throw new InvalidOperationException("Unexpected token group count.");
                int offset=(int)Marshal.OffsetOf(typeof(GroupsFirst),"first"), size=Marshal.SizeOf(typeof(SidAttributes));
                for(int i=0;i<count;i++) {
                    SidAttributes group=(SidAttributes)Marshal.PtrToStructure(IntPtr.Add(groups,offset+i*size),typeof(SidAttributes));
                    if((group.attributes&0xC0000000u)==0xC0000000u) {
                        if(value.logonSid!=null) throw new InvalidOperationException("More than one logon SID was returned.");
                        value.logonSid=new SecurityIdentifier(group.sid).Value;
                    }
                    if(new SecurityIdentifier(group.sid).Value=="S-1-5-32-544") {
                        value.administratorPresent=true; value.administratorEnabled=(group.attributes&4)!=0; value.administratorDenyOnly=(group.attributes&16)!=0;
                    }
                    if(new SecurityIdentifier(group.sid).Value=="S-1-5-32-545") {
                        value.usersPresent=true; value.usersEnabled=(group.attributes&4)!=0; value.usersDenyOnly=(group.attributes&16)!=0;
                    }
                }
            } finally { Marshal.FreeHGlobal(groups); }
            IntPtr privileges=Information(token,3);
            try {
                int count=Marshal.ReadInt32(privileges);if(count<0 || count>128)throw new InvalidOperationException("Unexpected token privilege count.");
                value.privileges=new PrivilegeSnapshot[count];
                for(int i=0;i<count;i++) {
                    IntPtr entry=IntPtr.Add(privileges,4+i*12);Luid luid=new Luid();luid.low=unchecked((uint)Marshal.ReadInt32(entry));luid.high=Marshal.ReadInt32(entry,4);
                    uint length=256;StringBuilder name=new StringBuilder((int)length);
                    if(!LookupPrivilegeNameW(null,ref luid,name,ref length))throw new Win32Exception(Marshal.GetLastWin32Error(),"Read-only privilege name query failed.");
                    PrivilegeSnapshot privilege=new PrivilegeSnapshot();privilege.name=name.ToString();privilege.attributes=unchecked((uint)Marshal.ReadInt32(entry,8));privilege.enabled=(privilege.attributes&2)!=0;value.privileges[i]=privilege;
                }
            } finally {Marshal.FreeHGlobal(privileges);}
            return value;
        } finally { if(token!=IntPtr.Zero) CloseHandle(token); if(processId!=0) CloseHandle(process); }
    }
    public static bool AccountIsAdministrator(string name) {
        return AccountHasLocalGroup(name,"S-1-5-32-544");
    }
    public static bool AccountIsUsersMember(string name) {
        return AccountHasLocalGroup(name,"S-1-5-32-545");
    }
    public static string[] DirectLocalGroups(string name) {
        IntPtr buffer=IntPtr.Zero;uint count,total;uint status=NetUserGetLocalGroups(null,name,0,0,out buffer,0xffffffff,out count,out total);
        try {
            if(status!=0 || count!=total || count>64)throw new Win32Exception((int)status,"A complete direct local-group snapshot failed.");
            List<string> groups=new List<string>();
            for(int i=0;i<count;i++) {
                string alias=Marshal.PtrToStringUni(Marshal.ReadIntPtr(buffer,i*IntPtr.Size));
                SecurityIdentifier sid=(SecurityIdentifier)new NTAccount(alias).Translate(typeof(SecurityIdentifier));
                string resolved=((NTAccount)sid.Translate(typeof(NTAccount))).Value;
                if(!string.Equals(resolved.Substring(resolved.LastIndexOf('\\')+1),alias,StringComparison.OrdinalIgnoreCase) || groups.Contains(sid.Value))throw new InvalidOperationException("A direct alias did not round-trip uniquely.");
                groups.Add(sid.Value);
            }
            groups.Sort(StringComparer.Ordinal);return groups.ToArray();
        } finally {if(buffer!=IntPtr.Zero)NetApiBufferFree(buffer);}
    }
    public static bool PermissionGroupsEqual(string[] actual,string[] expected) {
        if(actual==null || expected==null || actual.Length>64 || expected.Length>64)throw new InvalidOperationException("Unbounded direct-group snapshot.");
        HashSet<string> a=new HashSet<string>(StringComparer.Ordinal),b=new HashSet<string>(StringComparer.Ordinal);
        foreach(string sid in actual)if(!a.Add(new SecurityIdentifier(sid).Value))throw new InvalidOperationException("Duplicate direct group.");
        foreach(string sid in expected)if(!b.Add(new SecurityIdentifier(sid).Value))throw new InvalidOperationException("Duplicate expected group.");
        return a.SetEquals(b);
    }
    static void AssertWDAGPermissionController(string sid) {
        if(Environment.UserName!="WDAGUtilityAccount" || !string.Equals(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),@"C:\Users\WDAGUtilityAccount",StringComparison.OrdinalIgnoreCase) ||
            !Regex.IsMatch(sid,"^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-504$") || GetToken(0).userSid!=sid || !GetToken(0).administratorEnabled ||
            ((SecurityIdentifier)new NTAccount(Environment.MachineName,"WDAGUtilityAccount").Translate(typeof(SecurityIdentifier))).Value!=sid)
            throw new InvalidOperationException("Guest-only permission scaffolding requires the original WDAG native SID/profile and retained administrator controller token.");
    }
    public sealed class GuestPermissionLease {
        public string userSid;public string[] before,expected,restored;public bool groupsChanged,passwordChanged,restorationComplete;
        internal GuestPermissionLease(string sid) {AssertWDAGPermissionController(sid);userSid=sid;before=DirectLocalGroups("WDAGUtilityAccount");expected=(string[])before.Clone();if(Array.IndexOf(before,"S-1-5-32-544")<0)throw new InvalidOperationException("The initial primary WDAG account is not an administrator.");}
        void Change(string sid,bool add) {
            if(!PermissionGroupsEqual(DirectLocalGroups("WDAGUtilityAccount"),expected))throw new InvalidOperationException("Concurrent guest membership change; refusing to overwrite it.");
            string translated=((NTAccount)new SecurityIdentifier(sid).Translate(typeof(NTAccount))).Value;string alias=translated.Substring(translated.LastIndexOf('\\')+1);
            byte[] bytes=new byte[new SecurityIdentifier(userSid).BinaryLength];new SecurityIdentifier(userSid).GetBinaryForm(bytes,0);GCHandle pinned=GCHandle.Alloc(bytes,GCHandleType.Pinned);
            try {
                IntPtr member=pinned.AddrOfPinnedObject();uint result=add?NetLocalGroupAddMembers(null,alias,0,ref member,1):NetLocalGroupDelMembers(null,alias,0,ref member,1);
                if(result!=0)throw new Win32Exception((int)result,"A bounded guest membership operation failed.");
                List<string> next=new List<string>(expected);if(add)next.Add(sid);else next.Remove(sid);next.Sort(StringComparer.Ordinal);expected=next.ToArray();groupsChanged=!PermissionGroupsEqual(expected,before);
                if(!PermissionGroupsEqual(DirectLocalGroups("WDAGUtilityAccount"),expected))throw new InvalidOperationException("Guest membership changed concurrently after the operation.");
            } finally {pinned.Free();}
        }
        public void Demote(string password) {
            AssertWDAGPermissionController(userSid);if(passwordChanged || groupsChanged || string.IsNullOrEmpty(password))throw new InvalidOperationException("Permission lease is not fresh.");
            PasswordInfo info=new PasswordInfo();info.password=password;uint parameter,status;
            try {status=NetUserSetInfo(null,"WDAGUtilityAccount",1003,ref info,out parameter);}finally{info.password=null;}
            if(status!=0)throw new Win32Exception((int)status,"The disposable guest password could not be set.");passwordChanged=true;
            if(Array.IndexOf(expected,"S-1-5-32-545")<0)Change("S-1-5-32-545",true);
            Change("S-1-5-32-544",false);
            if(AccountIsAdministrator("WDAGUtilityAccount") || !AccountIsUsersMember("WDAGUtilityAccount"))throw new InvalidOperationException("The guest permission role is not an ordinary Users account.");
        }
        public void Restore() {
            AssertWDAGPermissionController(userSid);
            if(!PermissionGroupsEqual(DirectLocalGroups("WDAGUtilityAccount"),expected))throw new InvalidOperationException("Concurrent guest membership change; exact restoration refused.");
            foreach(string sid in before)if(Array.IndexOf(expected,sid)<0)Change(sid,true);
            foreach(string sid in (string[])expected.Clone())if(Array.IndexOf(before,sid)<0)Change(sid,false);
            restored=DirectLocalGroups("WDAGUtilityAccount");restorationComplete=PermissionGroupsEqual(restored,before);groupsChanged=!restorationComplete;
            if(!restorationComplete)throw new InvalidOperationException("Guest groups did not restore exactly.");
        }
    }
    public static GuestPermissionLease OpenGuestPermissionLease(string sid){return new GuestPermissionLease(sid);}
    static bool AccountHasLocalGroup(string name,string expected) {
        // NetUserGetLocalGroups returns unqualified local alias names.
        // Builtin aliases belong to BUILTIN, not the computer's SAM domain.
        SecurityIdentifier expectedSid=new SecurityIdentifier(expected);
        NTAccount expectedAccount=(NTAccount)expectedSid.Translate(typeof(NTAccount));
        string full=expectedAccount.Value, alias=full.Substring(full.LastIndexOf('\\')+1);
        if(((SecurityIdentifier)expectedAccount.Translate(typeof(SecurityIdentifier))).Value!=expected) throw new InvalidOperationException("Builtin alias resolution did not round-trip to its exact SID.");
        IntPtr buffer=IntPtr.Zero; uint count,total;
        uint status=NetUserGetLocalGroups(null,name,0,1,out buffer,0xffffffff,out count,out total);
        try {
            if(status!=0 || count!=total || count>1024) throw new Win32Exception((int)status,"A complete local-account group query failed.");
            for(int i=0;i<count;i++) {
                string group=Marshal.PtrToStringUni(Marshal.ReadIntPtr(buffer,i*IntPtr.Size));
                if(string.Equals(group,alias,StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        } finally { if(buffer!=IntPtr.Zero) NetApiBufferFree(buffer); }
    }
    public static void AddFreshAccountToUsers(string name,string sid) {
        if(!Regex.IsMatch(name,"^SwAcc-[a-f0-9]{14}$") || ((SecurityIdentifier)new NTAccount(Environment.MachineName,name).Translate(typeof(SecurityIdentifier))).Value!=sid)
            throw new InvalidOperationException("Only the exact newly created bounded acceptance account may join Users.");
        SecurityIdentifier user=new SecurityIdentifier(sid); byte[] bytes=new byte[user.BinaryLength]; user.GetBinaryForm(bytes,0);
        GCHandle pinned=GCHandle.Alloc(bytes,GCHandleType.Pinned);
        try {
            string translated=((NTAccount)new SecurityIdentifier("S-1-5-32-545").Translate(typeof(NTAccount))).Value;
            string group=translated.Substring(translated.LastIndexOf('\\')+1); IntPtr member=pinned.AddrOfPinnedObject();
            uint result=NetLocalGroupAddMembers(null,group,0,ref member,1);
            if(result!=0 && result!=1378) throw new Win32Exception((int)result,"The fresh acceptance account could not join the ordinary Users group; no other group or policy was changed.");
        } finally { pinned.Free(); }
    }
    public static string AddNormalUser(string name,string password) {
        UserInfo info=new UserInfo(); info.name=name; info.password=password; info.privilege=1;
        info.comment="Disposable SteamWrapper Sandbox acceptance"; info.flags=0x10201;
        uint parameter; uint status;
        try { status=NetUserAdd(null,1,ref info,out parameter); } finally { info.password=null; }
        if(status!=0) throw new Win32Exception((int)status,"NetUserAdd failed; no policy was changed.");
        return ((SecurityIdentifier)new NTAccount(Environment.MachineName,name).Translate(typeof(SecurityIdentifier))).Value;
    }
    public static ChildHandle StartChild(string name,string password,string application,string command,string directory,bool suspended) {
        Startup startup=new Startup(); startup.cb=Marshal.SizeOf(typeof(Startup)); startup.desktop=@"WinSta0\Default";
        ProcessInfo process;
        if(!CreateProcessWithLogonW(name,".",password,1,application,new StringBuilder(command),0x08000000u | (suspended ? 4u : 0u),IntPtr.Zero,directory,ref startup,out process))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"CreateProcessWithLogonW failed; desktop or logon rights were not widened.");
        ChildHandle child=new ChildHandle(); child.handle=process.process; child.ProcessId=(int)process.pid;
        if(suspended) child.thread=process.thread; else CloseHandle(process.thread);
        return child;
    }
    static byte[] SecurityBytes(IntPtr handle) {
        // LABEL_SECURITY_INFORMATION requires only READ_CONTROL. Full SACL
        // access/privilege changes are deliberately unnecessary here.
        uint information=0x17, needed;
        bool first=GetUserObjectSecurity(handle,ref information,IntPtr.Zero,0,out needed);
        int error=Marshal.GetLastWin32Error();
        if(first || error!=122 || needed==0 || needed>131072) throw new Win32Exception(error,"Unexpected user-object descriptor size.");
        IntPtr buffer=Marshal.AllocHGlobal((int)needed);
        try {
            uint written;
            if(!GetUserObjectSecurity(handle,ref information,buffer,needed,out written)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Read-only user-object security query failed.");
            if(written==0 || written>needed) throw new InvalidOperationException("Unexpected user-object descriptor length.");
            byte[] value=new byte[written]; Marshal.Copy(buffer,value,0,(int)written); return value;
        } finally { Marshal.FreeHGlobal(buffer); }
    }
    static ObjectSecuritySnapshot DescribeSecurity(IntPtr handle,byte[] bytes) {
        ObjectSecuritySnapshot value=new ObjectSecuritySnapshot(); value.name=ObjectName(handle); value.bytes=bytes.Length;
        using(SHA256 sha=SHA256.Create()) value.sha256=BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
        value.sddl=DescriptorString(bytes); return value;
    }
    static void RequireDefaultDesktop() {
        if(WindowStationName()!="WinSta0" || DesktopName()!="Default") throw new InvalidOperationException("The controller is not on the exact existing WinSta0\\Default desktop.");
    }
    public static DesktopSecuritySnapshot ReadInteractiveSecurity() {
        RequireDefaultDesktop();
        return ReadCurrentSecurity();
    }
    public static DesktopSecuritySnapshot ReadCurrentSecurity() {
        IntPtr station=GetProcessWindowStation(), desktop=GetThreadDesktop(GetCurrentThreadId());
        DesktopSecuritySnapshot value=new DesktopSecuritySnapshot();
        value.windowStation=DescribeSecurity(station,SecurityBytes(station)); value.desktop=DescribeSecurity(desktop,SecurityBytes(desktop)); return value;
    }
    static bool Check(byte[] bytes,IntPtr token,uint desired,GenericMapping mapping,out uint granted) {
        // Authz uses the exact primary token with TOKEN_QUERY only. Cross-user
        // TOKEN_DUPLICATE/IMPERSONATE privileges are neither needed nor enabled.
        // Generic ACE masks are mapped only in this in-memory SD copy.
        RawSecurityDescriptor descriptor=new RawSecurityDescriptor(bytes,0);
        if(descriptor.DiscretionaryAcl!=null) foreach(GenericAce ace in descriptor.DiscretionaryAcl) {
            KnownAce known=ace as KnownAce; if(known==null) continue;
            uint mask=unchecked((uint)known.AccessMask);
            if((mask&0x80000000u)!=0) mask=(mask&~0x80000000u)|mapping.read;
            if((mask&0x40000000u)!=0) mask=(mask&~0x40000000u)|mapping.write;
            if((mask&0x20000000u)!=0) mask=(mask&~0x20000000u)|mapping.execute;
            if((mask&0x10000000u)!=0) mask=(mask&~0x10000000u)|mapping.all;
            known.AccessMask=unchecked((int)mask);
        }
        byte[] copy=new byte[descriptor.BinaryLength]; descriptor.GetBinaryForm(copy,0);
        GCHandle pinned=GCHandle.Alloc(copy,GCHandleType.Pinned);
        IntPtr manager=IntPtr.Zero, context=IntPtr.Zero, output=Marshal.AllocHGlobal(12);
        try {
            if(!AuthzInitializeResourceManager(1,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,"SteamWrapper read-only desktop diagnostic",out manager))
                throw new Win32Exception(Marshal.GetLastWin32Error(),"AuthzInitializeResourceManager(NO_AUDIT) failed; privileges were not enabled.");
            if(!AuthzInitializeContextFromToken(0,token,manager,IntPtr.Zero,0,IntPtr.Zero,out context))
                throw new Win32Exception(Marshal.GetLastWin32Error(),"AuthzInitializeContextFromToken(TOKEN_QUERY only) failed.");
            AuthorizationRequest request=new AuthorizationRequest(); request.desired=desired;
            AuthorizationReply reply=new AuthorizationReply(); reply.count=1; reply.granted=output; reply.sacl=IntPtr.Add(output,4); reply.error=IntPtr.Add(output,8);
            for(int i=0;i<3;i++) Marshal.WriteInt32(output,i*4,0);
            if(!AuthzAccessCheck(0,context,ref request,IntPtr.Zero,pinned.AddrOfPinnedObject(),IntPtr.Zero,0,ref reply,IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(),"Read-only AuthzAccessCheck failed.");
            int error=Marshal.ReadInt32(reply.error); granted=unchecked((uint)Marshal.ReadInt32(reply.granted));
            if(error!=0 && error!=5) throw new Win32Exception(error,"AuthzAccessCheck returned an unexpected per-object error.");
            return error==0;
        } finally {
            if(context!=IntPtr.Zero) AuthzFreeContext(context); if(manager!=IntPtr.Zero) AuthzFreeResourceManager(manager);
            Marshal.FreeHGlobal(output); pinned.Free();
        }
    }
    static ObjectAccessSnapshot CheckObject(IntPtr handle,IntPtr token,bool station) {
        byte[] bytes=SecurityBytes(handle); GenericMapping mapping=new GenericMapping();
        bool interactive=station && ObjectName(handle)=="WinSta0";
        mapping.read=station ? (interactive ? 0x20303u : 0x20103u) : 0x20041u;
        mapping.write=station ? (interactive ? 0x2001Cu : 0x2000Cu) : 0x200BEu;
        mapping.execute=station ? 0x20060u : 0x20100u; mapping.all=station ? (interactive ? 0xF037Fu : 0xF016Fu) : 0xF01FFu;
        ObjectAccessSnapshot value=new ObjectAccessSnapshot(); value.security=DescribeSecurity(handle,bytes);
        uint granted; value.maximumAllowed=Check(bytes,token,0x02000000,mapping,out granted); value.grantedAccess=granted;
        value.rights=new Dictionary<string,bool>();
        string[] names=station ? new string[]{"readControl","enumerateDesktops","readAttributes","clipboard","createDesktop","writeAttributes","globalAtoms","exitWindows","enumerateStation","readScreen"}
            : new string[]{"readControl","readObjects","createWindow","createMenu","hookControl","journalRecord","journalPlayback","enumerateDesktop","writeObjects","switchDesktop"};
        uint[] masks=station ? new uint[]{0x20000,1,2,4,8,16,32,64,256,512} : new uint[]{0x20000,1,2,4,8,16,32,64,128,256};
        for(int i=0;i<names.Length;i++) value.rights[names[i]]=Check(bytes,token,masks[i],mapping,out granted);
        return value;
    }
    public static DesktopAccessSnapshot CheckInteractiveAccess(int processId) {
        RequireDefaultDesktop();
        return CheckCurrentAccess(processId);
    }
    public static DesktopAccessSnapshot CheckCurrentAccess(int processId) {
        IntPtr process=OpenProcess(0x1000,false,processId), primary=IntPtr.Zero;
        if(process==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed for the suspended child.");
        try {
            if(!OpenProcessToken(process,8,out primary))
                throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcessToken(TOKEN_QUERY only) failed for the exact suspended child; privileges were not enabled.");
            DesktopAccessSnapshot value=new DesktopAccessSnapshot();
            value.windowStation=CheckObject(GetProcessWindowStation(),primary,true);
            value.desktop=CheckObject(GetThreadDesktop(GetCurrentThreadId()),primary,false); return value;
        } finally {
            if(primary!=IntPtr.Zero) CloseHandle(primary); CloseHandle(process);
        }
    }
    public static bool ProbeQueryOnlyAuthorization() {
        IntPtr primary=IntPtr.Zero;
        try {
            if(!OpenProcessToken(GetCurrentProcess(),8,out primary)) throw new Win32Exception(Marshal.GetLastWin32Error(),"The query-only primary-token fixture could not open.");
            string sid=SidInformation(primary,1);
            RawSecurityDescriptor descriptor=new RawSecurityDescriptor("O:"+sid+"G:"+sid+"D:P(A;;0x2;;;"+sid+")");
            byte[] bytes=new byte[descriptor.BinaryLength]; descriptor.GetBinaryForm(bytes,0);
            GenericMapping mapping=new GenericMapping(); uint granted;
            return Check(bytes,primary,2,mapping,out granted) && granted==2 && !Check(bytes,primary,4,mapping,out granted) && granted==0;
        } finally {
            if(primary!=IntPtr.Zero) CloseHandle(primary);
        }
    }
    static void RequireLogonSid(string sid) {
        if(sid==null || !Regex.IsMatch(sid,"^S-1-5-5-[0-9]+-[0-9]+$")) throw new InvalidOperationException("Only an exact transient logon SID is allowed; account/group/broad SIDs are refused.");
        new SecurityIdentifier(sid);
    }
    static byte[] DescriptorBytes(RawSecurityDescriptor descriptor) {
        byte[] bytes=new byte[descriptor.BinaryLength]; descriptor.GetBinaryForm(bytes,0); return bytes;
    }
    static string DescriptorString(byte[] bytes) {
        IntPtr buffer=Marshal.AllocHGlobal(bytes.Length), value=IntPtr.Zero;
        try {
            Marshal.Copy(bytes,0,buffer,bytes.Length); uint characters;
            // .NET GetSddlForm(All) omits LABEL_SECURITY_INFORMATION and can
            // silently hide mandatory labels. Request 0x17 explicitly.
            if(!ConvertSecurityDescriptorToStringSecurityDescriptorW(buffer,1,0x17,out value,out characters))
                throw new Win32Exception(Marshal.GetLastWin32Error(),"The complete descriptor/mandatory-label string query failed.");
            if(characters==0 || characters>262144) throw new InvalidOperationException("Unexpected descriptor string size.");
            return Marshal.PtrToStringUni(value);
        } finally { if(value!=IntPtr.Zero) LocalFree(value); Marshal.FreeHGlobal(buffer); }
    }
    static byte[] AceBytes(GenericAce ace) { byte[] bytes=new byte[ace.BinaryLength]; ace.GetBinaryForm(bytes,0); return bytes; }
    static bool EqualBytes(byte[] left,byte[] right) {
        if(left==null || right==null) return left==right;
        if(left.Length!=right.Length) return false;
        for(int i=0;i<left.Length;i++) if(left[i]!=right[i]) return false;
        return true;
    }
    static byte[] AclBytes(RawAcl acl) { if(acl==null) return null; byte[] bytes=new byte[acl.BinaryLength]; acl.GetBinaryForm(bytes,0); return bytes; }
    static byte[] AppendGuestLogonAce(byte[] bytes,string sid,bool station) {
        RequireLogonSid(sid);
        RawSecurityDescriptor descriptor=new RawSecurityDescriptor(bytes,0);
        if(descriptor.DiscretionaryAcl==null || descriptor.DiscretionaryAcl.Count>4096) throw new InvalidOperationException("A bounded non-NULL existing desktop DACL is required.");
        foreach(GenericAce ace in descriptor.DiscretionaryAcl) {
            KnownAce known=ace as KnownAce;
            if(known!=null && known.SecurityIdentifier.Value==sid) throw new InvalidOperationException("This logon SID already has a desktop ACE; a fresh logon is required.");
        }
        descriptor.DiscretionaryAcl.InsertAce(descriptor.DiscretionaryAcl.Count,new CommonAce(AceFlags.None,AceQualifier.AccessAllowed,
            station ? 0x2037F : 0x201FF,new SecurityIdentifier(sid),false,null));
        return DescriptorBytes(descriptor);
    }
    public static string AddGuestLogonAce(string original,string sid,bool station) {
        return DescriptorString(AppendGuestLogonAce(DescriptorBytes(new RawSecurityDescriptor(original)),sid,station));
    }
    public static bool VerifyGuestLogonAce(string original,string granted,string sid,bool station) {
        RequireLogonSid(sid);
        RawSecurityDescriptor before=new RawSecurityDescriptor(original), after=new RawSecurityDescriptor(granted);
        if(before.ControlFlags!=after.ControlFlags || before.Owner==null || after.Owner==null || before.Owner.Value!=after.Owner.Value ||
            before.Group==null || after.Group==null || before.Group.Value!=after.Group.Value || !EqualBytes(AclBytes(before.SystemAcl),AclBytes(after.SystemAcl)) ||
            before.DiscretionaryAcl==null || after.DiscretionaryAcl==null || before.DiscretionaryAcl.Revision!=after.DiscretionaryAcl.Revision ||
            after.DiscretionaryAcl.Count!=before.DiscretionaryAcl.Count+1) throw new InvalidOperationException("The guest grant changed a label, owner, group, descriptor flags or unrelated ACE count.");
        for(int i=0;i<before.DiscretionaryAcl.Count;i++) if(!EqualBytes(AceBytes(before.DiscretionaryAcl[i]),AceBytes(after.DiscretionaryAcl[i])))
            throw new InvalidOperationException("The guest grant changed an original ACE.");
        byte[] expected=AceBytes(new CommonAce(AceFlags.None,AceQualifier.AccessAllowed,station ? 0x2037F : 0x201FF,new SecurityIdentifier(sid),false,null));
        if(!EqualBytes(expected,AceBytes(after.DiscretionaryAcl[before.DiscretionaryAcl.Count]))) throw new InvalidOperationException("The guest grant is not the exact non-inherited minimal logon ACE.");
        return true;
    }
    static void SetDacl(IntPtr handle,byte[] descriptor) {
        IntPtr buffer=Marshal.AllocHGlobal(descriptor.Length);
        try {
            Marshal.Copy(descriptor,0,buffer,descriptor.Length); uint information=4;
            if(!SetUserObjectSecurity(handle,ref information,buffer)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Guest-only desktop DACL update failed; privileges, labels and machine policies were not changed.");
        } finally { Marshal.FreeHGlobal(buffer); }
    }
    public sealed class GuestDesktopLease : IDisposable {
        IntPtr station,desktop;
        byte[] originalStation,originalDesktop;
        string sid;
        public DesktopSecuritySnapshot before,granted,restored;
        public bool stationChanged,desktopChanged,everStationChanged,everDesktopChanged,restorationComplete;
        internal GuestDesktopLease(DesktopSecuritySnapshot expected) {
            RequireDefaultDesktop();
            if(!string.Equals(Environment.UserName,"WDAGUtilityAccount",StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),@"C:\Users\WDAGUtilityAccount",StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Guest desktop scaffolding is available only to the disposable WDAG controller.");
            station=OpenWindowStationW("WinSta0",false,ControllerStationRights());
            if(station==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"The controller cannot open WinSta0 for the scoped guest lease.");
            try {
                desktop=OpenDesktopW("Default",0,false,0x60081);
                if(desktop==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"The controller cannot open Default for the scoped guest lease.");
                originalStation=SecurityBytes(station); originalDesktop=SecurityBytes(desktop);
                before=Snapshots(originalStation,originalDesktop);
                if(expected.windowStation.name!="WinSta0" || expected.desktop.name!="Default" || before.windowStation.sha256!=expected.windowStation.sha256 || before.desktop.sha256!=expected.desktop.sha256)
                    throw new InvalidOperationException("Existing desktop security changed before the guest lease opened.");
            } catch { Dispose(); throw; }
        }
        DesktopSecuritySnapshot Snapshots(byte[] stationBytes,byte[] desktopBytes) {
            DesktopSecuritySnapshot value=new DesktopSecuritySnapshot(); value.windowStation=DescribeSecurity(station,stationBytes); value.desktop=DescribeSecurity(desktop,desktopBytes); return value;
        }
        public void Grant(int processId,string expectedUserSid,string expectedLogonSid) {
            TokenSnapshot token=GetToken(processId); RequireLogonSid(expectedLogonSid);
            if(sid!=null || token.userSid!=expectedUserSid || token.logonSid!=expectedLogonSid || token.integritySid!="S-1-16-8192" || token.elevated || token.elevationType!=1 ||
                token.administratorPresent || !token.usersPresent || !token.usersEnabled || token.usersDenyOnly || token.sessionId!=GetToken(0).sessionId)
                throw new InvalidOperationException("A fresh genuine standard Users token in this exact guest session is required before adding its transient logon ACE.");
            if(!EqualBytes(SecurityBytes(station),originalStation) || !EqualBytes(SecurityBytes(desktop),originalDesktop)) throw new InvalidOperationException("Existing guest desktop security changed before the grant.");
            sid=expectedLogonSid;
            SetDacl(station,AppendGuestLogonAce(originalStation,sid,true)); stationChanged=true; everStationChanged=true;
            SetDacl(desktop,AppendGuestLogonAce(originalDesktop,sid,false)); desktopChanged=true; everDesktopChanged=true;
            granted=Snapshots(SecurityBytes(station),SecurityBytes(desktop));
            VerifyGuestLogonAce(before.windowStation.sddl,granted.windowStation.sddl,sid,true);
            VerifyGuestLogonAce(before.desktop.sddl,granted.desktop.sddl,sid,false);
        }
        public void Restore() {
            // Check both objects before restoring either. A concurrent change
            // refuses restoration; the caller must stop the disposable VM.
            byte[] stationNow=SecurityBytes(station), desktopNow=SecurityBytes(desktop);
            if(stationChanged) VerifyGuestLogonAce(before.windowStation.sddl,DescribeSecurity(station,stationNow).sddl,sid,true);
            else if(!EqualBytes(stationNow,originalStation)) throw new InvalidOperationException("Concurrent WinSta0 security change; refusing to overwrite it.");
            if(desktopChanged) VerifyGuestLogonAce(before.desktop.sddl,DescribeSecurity(desktop,desktopNow).sddl,sid,false);
            else if(!EqualBytes(desktopNow,originalDesktop)) throw new InvalidOperationException("Concurrent Default security change; refusing to overwrite it.");
            if(desktopChanged) { SetDacl(desktop,originalDesktop); if(!EqualBytes(SecurityBytes(desktop),originalDesktop)) throw new InvalidOperationException("Default descriptor did not restore exactly."); desktopChanged=false; }
            if(stationChanged) { SetDacl(station,originalStation); if(!EqualBytes(SecurityBytes(station),originalStation)) throw new InvalidOperationException("WinSta0 descriptor did not restore exactly."); stationChanged=false; }
            restored=Snapshots(SecurityBytes(station),SecurityBytes(desktop)); restorationComplete=true;
        }
        public void Dispose() { if(desktop!=IntPtr.Zero) { CloseDesktop(desktop); desktop=IntPtr.Zero; } if(station!=IntPtr.Zero) { CloseWindowStation(station); station=IntPtr.Zero; } }
    }
    public static GuestDesktopLease OpenGuestDesktopLease(DesktopSecuritySnapshot expected) { return new GuestDesktopLease(expected); }
    public static bool ProbeLeaseHandleNames() {
        string stationName=WindowStationName(),desktopName=DesktopName();
        IntPtr station=OpenWindowStationW(stationName,false,ControllerStationRights()),desktop=IntPtr.Zero;
        if(station==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"Read-only controller station handle probe failed.");
        try {
            desktop=OpenDesktopW(desktopName,0,false,0x60081);
            if(desktop==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"Read-only controller desktop handle probe failed.");
            return ObjectName(station)==stationName && ObjectName(desktop)==desktopName;
        } finally {if(desktop!=IntPtr.Zero) CloseDesktop(desktop);CloseWindowStation(station);}
    }
    // READ_CONTROL|WRITE_DAC plus WINSTA_READATTRIBUTES for the actual name
    // query. This opens an owned controller handle; it changes no descriptor.
    static uint ControllerStationRights() {return 0x60002;}
    static string ObjectName(IntPtr handle) {
        if(handle==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"Desktop/window-station handle is unavailable.");
        StringBuilder value=new StringBuilder(256); uint needed;
        if(!GetUserObjectInformationW(handle,2,value,512,out needed)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Desktop/window-station name query failed.");
        return value.ToString();
    }
    public static string WindowStationName() { return ObjectName(GetProcessWindowStation()); }
    public static string DesktopName() { return ObjectName(GetThreadDesktop(GetCurrentThreadId())); }
    public static void AssertInputDesktopReadable() {
        IntPtr desktop=OpenInputDesktop(0,false,0x41);
        if(desktop==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"The standard account cannot read/enumerate the input desktop; it did not change any permissions.");
        CloseDesktop(desktop);
    }
}
}
'@
}
function Get-StandardAcceptanceContext {
    Initialize-StandardAcceptanceNative
    $computer=Get-CimInstance Win32_ComputerSystem
    $os=Get-CimInstance Win32_OperatingSystem
    $overrides=@(Get-ChildItem Env: | Where-Object { $_.Name -cin @('STEAMWRAPPER_E2E_ROOT','STEAMWRAPPER_DEPLOYMENT_TEST','STEAM_DIR') -or $_.Name -like 'STEAMWRAPPER_DEPLOYMENT_*' } | Where-Object { -not [string]::IsNullOrEmpty($_.Value) } | Select-Object -ExpandProperty Name)
    $dotnetDirectories=@('C:\Program Files\dotnet','C:\Program Files (x86)\dotnet',(Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet')) | Where-Object {Test-Path -LiteralPath $_}
    return [pscustomobject]@{
        computerName=$env:COMPUTERNAME; userName=$env:USERNAME; profile=$env:USERPROFILE; nativeProfile=[Environment]::GetFolderPath('UserProfile')
        localAppData=$env:LOCALAPPDATA; nativeLocalAppData=[Environment]::GetFolderPath('LocalApplicationData')
        interactive=[Environment]::UserInteractive; sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
        manufacturer=$computer.Manufacturer; model=$computer.Model; build=[int]$os.BuildNumber; productType=[int]$os.ProductType; x64=[Environment]::Is64BitProcess
        machineDotnetExists=@($dotnetDirectories).Count -ne 0; dotnetOnPath=$null -ne (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue)
        overrides=$overrides; token=[SteamWrapperStandardAcceptance.Native]::GetToken(0)
        accountUsersMember=[SteamWrapperStandardAcceptance.Native]::AccountIsUsersMember($env:USERNAME)
    }
}
Assert-StandardAcceptanceMode $HelpersOnly $DiagnosticOnly $AccessCheckOnly $StandardChild $GuestInteractiveLogon $ExplorerShortcut $InstalledShortcut $WinUiControlProbe $WDAGPermission
if ($HelpersOnly) { return }

# Refuse a development host before reading input, making a file or calling
# NetUserAdd. Full context validation follows this inexpensive first guard.
if (-not $StandardChild) {
    Assert-StandardAcceptance ($env:USERNAME -ieq 'WDAGUtilityAccount' -and $env:USERPROFILE -ieq 'C:\Users\WDAGUtilityAccount' -and
        $PSScriptRoot -ieq 'C:\AcceptanceInput' -and $StandardInputDirectory -ceq 'C:\AcceptanceInput' -and
        $StandardOutputDirectory -ceq 'C:\AcceptanceOutput') 'The standard-account controller may run only from the dedicated WDAG Sandbox input.'
}
$manifest=Read-StandardAcceptanceManifest $StandardInputDirectory
$permissionChild=[bool]$StandardChild -and $manifest.accountMode -ceq 'WDAGStandardPermission'
$paths=if($WDAGPermission -or $permissionChild){Get-StandardPermissionPaths $manifest.runId}else{Get-StandardAcceptancePaths $manifest.runId}
$context=Get-StandardAcceptanceContext
$controllerHash=[string]$manifest.standardControllerSha256
Assert-StandardAcceptanceSealedFile $PSCommandPath $controllerHash
if ($StandardChild) {
    $context | Add-Member -NotePropertyName accountAdministratorMember -NotePropertyValue ([SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator($env:USERNAME))
    Assert-StandardAcceptanceScopedChildContext $context $manifest $StandardInputDirectory $StandardOutputDirectory
    Assert-StandardAcceptanceRegularPath $StandardOutputDirectory $true
    Assert-StandardAcceptance (@(Get-ChildItem -LiteralPath $StandardOutputDirectory -Force).Count -eq 0) 'Standard-account diagnostic output is not fresh.'
    $diagnostic=[ordered]@{schemaVersion=1;runId=$manifest.runId;result='running';standardAccount=$true;freshStandardAccount=(-not $permissionChild);primaryStandardSignInTested=$false;twoUserGuiTested=$false;permissionAccount=$permissionChild;context=$context;desktop=$null;productionInstallerExecuted=$false}
    $diagnosticPath=Join-Path $StandardOutputDirectory 'standard-user-diagnostic.json'
    try {
        $station=[SteamWrapperStandardAcceptance.Native]::WindowStationName()
        $desktop=[SteamWrapperStandardAcceptance.Native]::DesktopName()
        [SteamWrapperStandardAcceptance.Native]::AssertInputDesktopReadable()
        Assert-StandardAcceptance ($station -ceq 'WinSta0' -and $desktop -ceq 'Default') 'The standard account did not reach the exact connected acceptance desktop.'
        $diagnostic.desktop=[ordered]@{windowStation=$station;name=$desktop;inputDesktopReadable=$true}
        $diagnostic.result='passed'; Write-StandardAcceptanceJson $diagnosticPath $diagnostic
        if($null -ne $manifest.PSObject.Properties['standardWinUiControl'] -and $manifest.standardWinUiControl) {
            Assert-StandardAcceptance ([bool]$DiagnosticOnly -and $manifest.standardWinUiControl -is [bool]) 'The control child must stay in its dedicated diagnostic mode.'
            & (Join-Path $StandardInputDirectory 'Invoke-StandardWinUiControlProbe.ps1') -Role StandardUser -InputDirectory $StandardInputDirectory -OutputDirectory $StandardOutputDirectory
        } elseif (-not $DiagnosticOnly) {
            Assert-StandardAcceptanceSealedFile (Join-Path $StandardInputDirectory 'Invoke-CleanWindowsGuestAcceptance.ps1') $manifest.guestScriptSha256
            & (Join-Path $StandardInputDirectory 'Invoke-CleanWindowsGuestAcceptance.ps1') -InputDirectory $StandardInputDirectory -OutputDirectory $StandardOutputDirectory *> (Join-Path $StandardOutputDirectory 'guest-launch.log')
        }
    } catch {
        $diagnostic.result='failed'; $diagnostic.failureType=$_.Exception.GetBaseException().GetType().FullName
        $diagnostic.failureMessage=$_.Exception.GetBaseException().Message
        Write-StandardAcceptanceJson $diagnosticPath $diagnostic
        throw
    }
    return
}

Assert-StandardAcceptanceControllerContext $context $manifest $StandardInputDirectory $StandardOutputDirectory
Assert-StandardAcceptanceRegularPath $StandardInputDirectory $true
Assert-StandardAcceptanceRegularPath $StandardOutputDirectory $true
Assert-StandardAcceptance (-not (Test-Path -LiteralPath $paths.root) -and ($WDAGPermission -or -not (Test-Path -LiteralPath ('C:\Users\' + $paths.userName)))) 'This run already has a guest handoff root or fresh-account profile; start a fresh Sandbox.'
Assert-StandardAcceptanceRegularPath 'C:\Users\Public' $true
$existingOutput=@(Get-ChildItem -LiteralPath $StandardOutputDirectory -Force)
Assert-StandardAcceptance (@($existingOutput | Where-Object { $_.PSIsContainer -or $_.Name -cne 'guest-launch.log' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $_.Length -gt 16384 }).Count -eq 0) 'The standard-account controller requires fresh mapped output.'
$sealedFiles=Get-StandardAcceptanceSealedInputs $manifest $controllerHash
foreach($file in $sealedFiles) { Assert-StandardAcceptanceSealedFile (Join-Path $StandardInputDirectory $file.name) $file.hash $file.bytes }
if($WinUiControlProbe){Assert-StandardAcceptancePreparedControl $manifest}
if($ExplorerShortcut -or $InstalledShortcut) {Assert-StandardAcceptance ($manifest.scenario -ceq 'CandidateFirstInstall') 'The shortcut smoke requires the fresh first-install candidate scenario.'}
$isolationBefore=if(-not $DiagnosticOnly){Get-StandardAcceptanceControllerSeparation $context}else{$null}
if(-not $DiagnosticOnly) {Assert-StandardAcceptanceControllerSeparation $isolationBefore $isolationBefore $context}
$report=[ordered]@{schemaVersion=1;runId=$manifest.runId;result='running';mode=$(if($AccessCheckOnly){'AccessCheckOnly'}elseif($DiagnosticOnly){'DiagnosticOnly'}else{'Lifecycle'});environment='Windows Sandbox';controller=$context;accountCreated=$false;standardUserName=$paths.userName;standardUserSid=$null;childProcessId=$null;childResumed=$false;childExitCode=$null;childHexExitCode=$null;guestInteractiveLogon=[bool]$GuestInteractiveLogon;desktopAclChanged=$false;windowStationAclChanged=$false;desktopAclTemporarilyChanged=$false;mappedFolderAclChanged=$false;machinePolicyChanged=$false;productionInstallerExecuted=$(if($DiagnosticOnly){$false}else{$null});failure=$null}
$report['explorerShortcutRequested']=[bool]$ExplorerShortcut
$report['installedShortcutRequested']=[bool]$InstalledShortcut
$report['winUiControlRequested']=[bool]$WinUiControlProbe
$report['permissionAccountRequested']=[bool]$WDAGPermission
$report['freshStandardAccount']=(-not [bool]$WDAGPermission)
$report['primaryStandardSignInTested']=$false
$report['twoUserGuiTested']=$false
if($WDAGPermission){$report.mode='WDAGStandardPermission';$report['twoUserSeparationTested']=$false;$report['originalGuestPasswordRestored']=$false;$report['guestPasswordDisposalRequired']=$true}
if($WinUiControlProbe){$report.mode='EmptyWinUiControl';Assert-StandardAcceptance ($null -ne $manifest.PSObject.Properties['winUiControl']) 'Missing sealed developer control fixture.'}
$report['controllerSeparationBefore']=$isolationBefore
$reportPath=Join-Path $StandardOutputDirectory 'standard-controller.json'
$password=$null; $child=$null; $desktopLease=$null; $permissionLease=$null; $completionReady=$false
try {
    Write-StandardAcceptanceJson $reportPath $report
    if($WinUiControlProbe) {
        $manifest | Add-Member -NotePropertyName standardWinUiControl -NotePropertyValue $true -Force
        # The same sealed control must first succeed under the original WDAG
        # identity. A failed control baseline cannot create a second account.
        & (Join-Path $StandardInputDirectory 'Invoke-StandardWinUiControlProbe.ps1') -Role WDAG -InputDirectory $StandardInputDirectory -OutputDirectory $StandardOutputDirectory
        $report['wdagControl']=Read-StandardAcceptanceJson (Join-Path $StandardOutputDirectory 'control-wdag.log')
        Assert-StandardAcceptance ($report.wdagControl.result -ceq 'passed') 'The WDAG control baseline did not pass.'
        Write-StandardAcceptanceJson $reportPath $report
    }
    $random=New-Object byte[] 48; $rng=New-Object Security.Cryptography.RNGCryptoServiceProvider
    try {$rng.GetBytes($random); $password=[Convert]::ToBase64String($random) + 'aA1!'} finally {$rng.Dispose(); [Array]::Clear($random,0,$random.Length)}
    if($WDAGPermission) {
        $sid=$context.token.userSid
        $report['apiStage']='Snapshot original WDAG direct memberships';Write-StandardAcceptanceJson $reportPath $report
        $permissionLease=[SteamWrapperStandardAcceptance.Native]::OpenGuestPermissionLease($sid)
        $report['permissionScaffolding']=$permissionLease;$report.apiStage='Set disposable guest password and ordinary WDAG membership';Write-StandardAcceptanceJson $reportPath $report
        $permissionLease.Demote($password)
        $report.apiStage='Original WDAG SID now has an ordinary Users role';Write-StandardAcceptanceJson $reportPath $report
    } else {
        $sid=[SteamWrapperStandardAcceptance.Native]::AddNormalUser($paths.userName,$password)
        $report.accountCreated=$true
    }
    $report.standardUserSid=$sid
    Assert-StandardAcceptance (-not [SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator($paths.userName)) 'The new Sandbox account unexpectedly belongs to Administrators.'
    $report['usersMembershipBefore']=if($WDAGPermission){'S-1-5-32-545' -cin $permissionLease.before}else{[SteamWrapperStandardAcceptance.Native]::AccountIsUsersMember($paths.userName)}
    $report['usersMembershipAdded']=-not $report.usersMembershipBefore
    if(-not $report.usersMembershipBefore -and -not $WDAGPermission) {[SteamWrapperStandardAcceptance.Native]::AddFreshAccountToUsers($paths.userName,$sid)}
    $report['usersMembershipAfter']=[SteamWrapperStandardAcceptance.Native]::AccountIsUsersMember($paths.userName)
    Assert-StandardAcceptance ($report.usersMembershipAfter -and -not [SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator($paths.userName)) 'The fresh guest account is not an ordinary Users member without Administrator membership.'
    [IO.Directory]::CreateDirectory($paths.input) | Out-Null
    [IO.Directory]::CreateDirectory($paths.output) | Out-Null
    # Only this guest-local handoff tree receives the new account SID. The
    # optional desktop lease below uses its transient logon SID only.
    foreach($record in @(@{path=$paths.root;writable=$false},@{path=$paths.output;writable=$true})) {
        $inputOwner=if($WDAGPermission){'S-1-5-32-544'}else{$context.token.userSid}
        Set-Acl -LiteralPath $record.path -AclObject (New-StandardAcceptanceGuestAcl $sid $inputOwner $record.writable)
    }
    if($WDAGPermission){Set-Acl -LiteralPath $paths.input -AclObject (New-StandardAcceptanceGuestAcl $sid 'S-1-5-32-544' $false)}
    foreach($file in $sealedFiles) {
        Copy-Item -LiteralPath (Join-Path $StandardInputDirectory $file.name) -Destination (Join-Path $paths.input $file.name)
        Assert-StandardAcceptanceSealedFile (Join-Path $paths.input $file.name) $file.hash $file.bytes
    }
    $manifest | Add-Member -NotePropertyName accountMode -NotePropertyValue $(if($WDAGPermission){'WDAGStandardPermission'}else{'StandardUser'}) -Force
    if($WDAGPermission) {
        $manifest | Add-Member -NotePropertyName wdagPermissionOptIn -NotePropertyValue $true -Force
        $manifest | Add-Member -NotePropertyName permissionOriginalPrimarySid -NotePropertyValue $sid -Force
    }
    $manifest | Add-Member -NotePropertyName expectedStandardUserName -NotePropertyValue $paths.userName -Force
    $manifest | Add-Member -NotePropertyName expectedStandardUserSid -NotePropertyValue $sid -Force
    $manifest | Add-Member -NotePropertyName standardInputDirectory -NotePropertyValue $paths.input -Force
    $manifest | Add-Member -NotePropertyName standardOutputDirectory -NotePropertyValue $paths.output -Force
    $manifest | Add-Member -NotePropertyName standardSessionId -NotePropertyValue $context.sessionId -Force
    $manifest | Add-Member -NotePropertyName standardExplorerShortcut -NotePropertyValue ([bool]$ExplorerShortcut) -Force
    $manifest | Add-Member -NotePropertyName standardInstalledShortcut -NotePropertyValue ([bool]$InstalledShortcut) -Force
    $manifest | Add-Member -NotePropertyName standardWinUiControl -NotePropertyValue ([bool]$WinUiControlProbe) -Force
    Write-StandardAcceptanceJson (Join-Path $paths.input 'acceptance-input.json') $manifest
    if($WDAGPermission) {
        # Same-SID controller/child need an administrator owner on every
        # sealed file, including the newly written manifest; RX alone does
        # not remove an owner's implicit ability to change its DACL.
        foreach($file in Get-ChildItem -LiteralPath $paths.input -Force) {Set-Acl -LiteralPath $file.FullName -AclObject (New-StandardAcceptanceGuestAcl $sid 'S-1-5-32-544' $false $false)}
    }
    foreach($file in Get-ChildItem -LiteralPath $paths.input -Force) { $file.Attributes=$file.Attributes -bor [IO.FileAttributes]::ReadOnly }
    $inboxPowerShell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $command=(Quote-StandardAcceptanceArgument $inboxPowerShell) + ' -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -File ' +
        (Quote-StandardAcceptanceArgument (Join-Path $paths.input 'StandardUserAcceptance.ps1')) + ' -StandardChild -StandardInputDirectory ' +
        (Quote-StandardAcceptanceArgument $paths.input) + ' -StandardOutputDirectory ' + (Quote-StandardAcceptanceArgument $paths.output)
    if($DiagnosticOnly) {$command += ' -DiagnosticOnly'}
    Assert-StandardAcceptance ($command.Length -le 1023) 'The standard-user child command exceeds the native API limit.'
    $suspended=$AccessCheckOnly -or $GuestInteractiveLogon
    if($suspended) {$report['apiStage']='ReadInteractiveSecurity'}
    $before=if($suspended){[SteamWrapperStandardAcceptance.Native]::ReadInteractiveSecurity()}else{$null}
    if($suspended) {$report['desktopSecurityBefore']=$before; $report.apiStage='CreateProcessWithLogonW(CREATE_SUSPENDED)'; Write-StandardAcceptanceJson $reportPath $report}
    $child=[SteamWrapperStandardAcceptance.Native]::StartChild($paths.userName,$password,$inboxPowerShell,$command,$paths.input,$suspended)
    $report.childResumed=-not $suspended
    $report.childProcessId=$child.ProcessId; Write-StandardAcceptanceJson $reportPath $report
    if($AccessCheckOnly) {
        $report.apiStage='GetToken(TOKEN_QUERY)'; Write-StandardAcceptanceJson $reportPath $report
        $token=[SteamWrapperStandardAcceptance.Native]::GetToken($child.ProcessId)
        $report['childToken']=$token; $report.apiStage='AuthzAccessCheck(TOKEN_QUERY only)'; Write-StandardAcceptanceJson $reportPath $report
        $access=[SteamWrapperStandardAcceptance.Native]::CheckInteractiveAccess($child.ProcessId)
        $report['desktopAccess']=$access; $report.apiStage='ReadInteractiveSecurity(after)'; Write-StandardAcceptanceJson $reportPath $report
        $after=[SteamWrapperStandardAcceptance.Native]::ReadInteractiveSecurity()
        $observation=New-StandardAcceptanceAccessDiagnostic $manifest $token $before $access $after
        Write-StandardAcceptanceJson (Join-Path $StandardOutputDirectory 'standard-desktop-access.json') $observation
        $report.result='observed'; $report.apiStage='ObservationComplete'; Write-StandardAcceptanceJson $reportPath $report
        Write-Output 'Read-only standard-account desktop access observed. The child remains suspended, no script/installer/UI ran, and the existing descriptors were unchanged; stop this disposable Sandbox to discard the account and child.'
        return
    }
    if($GuestInteractiveLogon) {
        $report.apiStage='Verify suspended standard Users token'; Write-StandardAcceptanceJson $reportPath $report
        $token=[SteamWrapperStandardAcceptance.Native]::GetToken($child.ProcessId)
        Assert-StandardAcceptanceProcessToken $token $sid
        if($WDAGPermission){Assert-StandardPermissionPrivileges $token}
        Assert-StandardAcceptance ($token.sessionId -eq $context.sessionId -and $token.logonSid -cmatch '^S-1-5-5-[0-9]+-[0-9]+$') 'The suspended child has no exact fresh logon SID in this guest session.'
        $report['childToken']=$token; $report.apiStage='Grant exact guest logon desktop ACE'; Write-StandardAcceptanceJson $reportPath $report
        $desktopLease=[SteamWrapperStandardAcceptance.Native]::OpenGuestDesktopLease($before)
        $report['desktopScaffolding']=$desktopLease
        $desktopLease.Grant($child.ProcessId,$sid,$token.logonSid)
        $report.desktopAclChanged=$true; $report.windowStationAclChanged=$true; $report.desktopAclTemporarilyChanged=$true
        $access=[SteamWrapperStandardAcceptance.Native]::CheckInteractiveAccess($child.ProcessId)
        Assert-StandardAcceptance ($access.windowStation.maximumAllowed -and ($access.windowStation.grantedAccess -band 0x2037f) -eq 0x2037f -and
            $access.desktop.maximumAllowed -and ($access.desktop.grantedAccess -band 0x201ff) -eq 0x201ff) 'The exact guest logon ACE did not supply the required desktop object rights.'
        $report['desktopAccessGranted']=$access
        $manifest | Add-Member -NotePropertyName standardExpectedLogonSid -NotePropertyValue $token.logonSid -Force
        $childManifest=Get-Item -LiteralPath (Join-Path $paths.input 'acceptance-input.json') -Force
        $childManifest.Attributes=$childManifest.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
        try {Write-StandardAcceptanceJson $childManifest.FullName $manifest} finally {$childManifest.Attributes=$childManifest.Attributes -bor [IO.FileAttributes]::ReadOnly}
        $report.apiStage='Resume exact owned child'; Write-StandardAcceptanceJson $reportPath $report
        $child.Resume(); $report.childResumed=$true; Write-StandardAcceptanceJson $reportPath $report
    }
    $report.childExitCode=$child.Wait($(if($DiagnosticOnly){180000}else{900000}))
    $unsigned=if($report.childExitCode -lt 0){[long]$report.childExitCode + 4294967296L}else{[long]$report.childExitCode}
    $report.childHexExitCode='0x{0:X8}' -f $unsigned
    $exports=@(Get-ChildItem -LiteralPath $paths.output -Force)
    Assert-StandardAcceptance ($exports.Count -le 64 -and ($exports | Measure-Object -Property Length -Sum).Sum -le 64MB) 'The standard-account evidence exceeds its export limits.'
    foreach($file in $exports) {
        Assert-StandardAcceptanceRegularPath $file.FullName $false
        Assert-StandardAcceptance ($file.Name -cmatch '^(?:evidence\.json|standard-user-diagnostic\.json|guest-launch\.log|[A-Za-z0-9][A-Za-z0-9._-]{0,100}\.(?:log|png))$' -and $file.Length -le 16MB) 'Unexpected standard-account evidence file.'
        $name=if($file.Name -ceq 'guest-launch.log'){'standard-user-launch.log'}else{$file.Name}
        $destination=Join-Path $StandardOutputDirectory $name
        Assert-StandardAcceptance (-not (Test-Path -LiteralPath $destination)) 'Refusing to overwrite mapped evidence.'
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
    Assert-StandardAcceptance ($report.childExitCode -eq 0) 'The real standard-account child failed; inspect its retained diagnostics and guest scaffolding. No host account or machine policy was changed.'
    $diagnostic=Read-StandardAcceptanceJson (Join-Path $paths.output 'standard-user-diagnostic.json')
    if($WinUiControlProbe) {
        $report['standardControl']=Read-StandardAcceptanceJson (Join-Path $paths.output 'control-standarduser.log')
        Assert-StandardAcceptance ($report.standardControl.result -ceq 'passed' -and $report.standardControl.productionInstallerExecuted -eq $false) 'The true standard-account empty control did not complete normally.'
    }
    Assert-StandardAcceptance ($diagnostic.runId -ceq $manifest.runId -and $diagnostic.result -ceq 'passed' -and $diagnostic.standardAccount -eq $true) 'The standard-account token/desktop diagnostic did not pass.'
    if(-not $DiagnosticOnly) {
        $finished=Read-StandardAcceptanceJson (Join-Path $paths.output 'evidence.json')
        Assert-StandardAcceptance ($finished.runId -ceq $manifest.runId -and $finished.result -ceq 'passed') 'The real standard-account lifecycle did not finish.'
        if($ExplorerShortcut) {
            Assert-StandardAcceptance ($finished.standardExplorerShortcut.explorerNormalCloseRequested -is [bool] -and
                $finished.standardExplorerShortcut.explorerNormalCloseRequested -and $finished.standardExplorerShortcut.explorerWindowClosed -is [bool] -and
                $finished.standardExplorerShortcut.explorerWindowClosed) 'The genuine standard-token Explorer shortcut smoke did not complete and close normally.'
            Assert-StandardAcceptanceShellProvenance $finished.standardExplorerShortcut $diagnostic.context $manifest $finished.installationLocations[0] $manifest.baseline.tag
        }
        if($InstalledShortcut) {
            Assert-StandardAcceptanceInstalledShortcutProvenance $finished.standardInstalledShortcut $diagnostic.context $manifest $finished.installationLocations[0] $manifest.baseline.tag
        }
        $report.productionInstallerExecuted=$true
    }
    $completionReady=$true; Write-StandardAcceptanceJson $reportPath $report
} catch {
    $base=$_.Exception.GetBaseException()
    $report.result='failed'; $report.failure=[ordered]@{type=$base.GetType().FullName;message=$base.Message;win32Error=$(if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null});apiStage=$(if($null -ne $report['apiStage']){$report.apiStage}else{$null});script=$_.InvocationInfo.ScriptName;line=$_.InvocationInfo.ScriptLineNumber}
    Write-StandardAcceptanceJson $reportPath $report
    throw
} finally {
    $password=$null
    try {
        if($null -ne $desktopLease) {
            try {
                $report.apiStage='Restore exact guest desktop descriptors'
                $report.desktopAclTemporarilyChanged=$desktopLease.everStationChanged -or $desktopLease.everDesktopChanged
                $desktopLease.Restore()
                $report.desktopAclChanged=$false; $report.windowStationAclChanged=$false
                $report.apiStage='Guest desktop descriptors restored exactly'
            } catch {
                $base=$_.Exception.GetBaseException()
                $report.result='failed'; $report.desktopAclChanged=$desktopLease.desktopChanged; $report.windowStationAclChanged=$desktopLease.stationChanged
                $report['desktopRestorationFailure']=[ordered]@{type=$base.GetType().FullName;message=$base.Message}
                throw
            } finally {
                try {Write-StandardAcceptanceJson $reportPath $report} finally {$desktopLease.Dispose()}
            }
        }
    } finally {
        try {
            if(-not $DiagnosticOnly -and -not $WDAGPermission) {
                $report['controllerSeparationAfter']=Get-StandardAcceptanceControllerSeparation $context
                try {
                    Assert-StandardAcceptanceControllerSeparation $isolationBefore $report.controllerSeparationAfter $context
                    $report['twoUserSeparationPassed']=$true
                } catch {$report.result='failed';$report['twoUserSeparationPassed']=$false;throw}
                finally {Write-StandardAcceptanceJson $reportPath $report}
            }
        } finally {
            try {
                if($null -ne $permissionLease) {
                    try {$permissionLease.Restore();$report['guestGroupsRestoredExactly']=$permissionLease.restorationComplete}
                    catch {$report.result='failed';$report['guestGroupsRestoredExactly']=$false;$report['guestGroupsRestorationFailure']=$_.Exception.GetBaseException().Message;throw}
                    finally {Write-StandardAcceptanceJson $reportPath $report}
                }
            } finally {if($null -ne $child) {$child.Dispose()}}
        }
    }
}
if($completionReady) {
    if($GuestInteractiveLogon) {Assert-StandardAcceptance $desktopLease.restorationComplete 'The guest desktop lease did not restore exactly.'}
    if($WDAGPermission){Assert-StandardAcceptance $permissionLease.restorationComplete 'The guest permission membership lease did not restore exactly.'}
    $report.result='passed'; Write-StandardAcceptanceJson $reportPath $report
    Write-Output ('Standard-account ' + $report.mode + ' passed; inspect the retained Sandbox evidence and exact desktop restoration. The disposable account/profile disappear when this Sandbox stops.')
}
