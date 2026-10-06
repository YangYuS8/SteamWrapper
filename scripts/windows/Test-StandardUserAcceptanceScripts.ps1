[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$helper = Join-Path $PSScriptRoot 'StandardUserAcceptance.ps1'
if (-not (Test-Path -LiteralPath $helper)) { throw 'Missing real standard-account acceptance guards and controller.' }
. $helper -HelpersOnly
$cases = 0
function Assert-StandardTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:cases++
}
function Assert-StandardTestReject([scriptblock]$Operation, [string]$Message) {
    $rejected = $false
    try { $null = & $Operation } catch { $rejected = $true }
    Assert-StandardTest $rejected $Message
}
$runId = '0123456789abcdef0123456789abcdef'
$paths = Get-StandardAcceptancePaths $runId
$sealedCandidate=[pscustomobject]@{
    scenario='CandidateUpgrade'; guestScriptSha256=('a'*64);launchScriptSha256=('b'*64)
    candidateBuildSha256=('c'*64);candidateDeploymentManifestSha256=('d'*64)
    baselinePublicReleaseSha256=('e'*64);baselinePublicApiSha256=('f'*64)
    baseline=[pscustomobject]@{fileName='SteamWrapper-v0.2.5-preview.1-win-x64-setup.exe';sha256=('0'*64);bytes=50}
    target=[pscustomobject]@{fileName='SteamWrapper-v0.2.6-win-x64-setup.exe';sha256=('1'*64);bytes=60}
}
$sealed=Get-StandardAcceptanceSealedInputs $sealedCandidate ('2'*64)
Assert-StandardTest ($sealed.Count -eq 9 -and @($sealed | Where-Object name -CEQ 'baseline-release.json').Count -eq 1 -and
    @($sealed | Where-Object name -CEQ 'baseline-api.json').Count -eq 1 -and
    ($sealed | Where-Object name -CEQ 'baseline-release.json').hash -ceq $sealedCandidate.baselinePublicReleaseSha256 -and
    ($sealed | Where-Object name -CEQ 'baseline-api.json').hash -ceq $sealedCandidate.baselinePublicApiSha256) 'The standard-user sealed/copy handoff omits the clean guest CandidateUpgrade public-baseline dependency closure.'
foreach ($missing in @('baselinePublicReleaseSha256','baselinePublicApiSha256')) {
    $broken=$sealedCandidate | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $broken.PSObject.Properties.Remove($missing)
    Assert-StandardTestReject { Get-StandardAcceptanceSealedInputs $broken ('2'*64) } 'CandidateUpgrade accepted unpinned public baseline provenance.'
}
$controlCandidate=$sealedCandidate | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$controlCandidate | Add-Member -NotePropertyName winUiControl -NotePropertyValue ([pscustomobject]@{driverSha256=('3'*64);inventorySha256=('4'*64);sha256=('5'*64);bytes=80})
$controlFiles=Get-StandardAcceptanceSealedInputs $controlCandidate ('2'*64)
Assert-StandardTest ($controlFiles.Count -eq 12 -and @($controlFiles | Where-Object name -CEQ 'standard-winui-control.zip').Count -eq 1 -and
    ($controlFiles | Where-Object name -CEQ 'standard-winui-control.zip').bytes -eq 80) 'The control ZIP, inventory or guest driver was omitted from the sealed standard handoff.'
foreach($name in @('driverSha256','inventorySha256','sha256')) {
    $broken=$controlCandidate | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$broken.winUiControl.($name)=''
    Assert-StandardTestReject {Get-StandardAcceptanceSealedInputs $broken ('2'*64)} 'An unpinned WinUI control dependency was accepted.'
}
$controlCandidate | Add-Member -NotePropertyName standardWinUiControl -NotePropertyValue $true
Assert-StandardAcceptancePreparedControl $controlCandidate;$cases++
foreach($value in @($false,'true',1)) {
    $broken=$controlCandidate | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$broken.standardWinUiControl=$value
    Assert-StandardTestReject {Assert-StandardAcceptancePreparedControl $broken} 'A missing or nominal control route flag was accepted instead of the sealed boolean opt-in.'
}
$broken=$controlCandidate | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$broken.PSObject.Properties.Remove('standardWinUiControl')
Assert-StandardTestReject {Assert-StandardAcceptancePreparedControl $broken} 'The control route required only an in-memory flag despite a missing prepared disk flag.'
Assert-StandardAcceptanceMode $false $true $true $false
$cases++
Assert-StandardAcceptanceMode $false $true $false $false $true
$cases++
Assert-StandardAcceptanceMode $false $false $false $false $true $true
$cases++
Assert-StandardAcceptanceMode $false $false $false $false $true $false $true
$cases++
Assert-StandardAcceptanceMode $false $true $false $false $true $false $false $true
$cases++
Assert-StandardAcceptanceMode $false $false $false $false $true $false $true $false $true
$cases++
foreach($mode in @(@($false,$false,$false,$false,$false,$false,$false,$false,$true),@($false,$true,$false,$false,$true,$false,$false,$false,$true),@($false,$false,$false,$false,$true,$true,$false,$false,$true))) {
    Assert-StandardTestReject {Assert-StandardAcceptanceMode $mode[0] $mode[1] $mode[2] $mode[3] $mode[4] $mode[5] $mode[6] $mode[7] $mode[8]} 'The separate WDAG permission lane accepted an ungranted, diagnostic or Explorer route.'
}
foreach($mode in @(@($false,$false,$false,$false,$true,$false,$false,$true),@($false,$true,$false,$false,$false,$false,$false,$true),@($true,$true,$false,$false,$true,$false,$false,$true),@($false,$true,$true,$false,$false,$false,$false,$true),@($false,$true,$false,$true,$false,$false,$false,$true))) {
    Assert-StandardTestReject {Assert-StandardAcceptanceMode $mode[0] $mode[1] $mode[2] $mode[3] $mode[4] $mode[5] $mode[6] $mode[7]} 'The WinUI control GUI probe was accepted outside its dedicated granted diagnostic controller.'
}
foreach($mode in @(@($false,$true,$false,$false,$true,$false,$true),@($false,$false,$false,$false,$false,$false,$true),@($false,$false,$false,$false,$true,$true,$true))) {
    Assert-StandardTestReject {Assert-StandardAcceptanceMode $mode[0] $mode[1] $mode[2] $mode[3] $mode[4] $mode[5] $mode[6]} 'The separate installed-shortcut lane accepted a diagnostic, ungranted or Explorer-fallback route.'
}
foreach($mode in @(@($false,$true,$false,$false,$true,$true),@($false,$false,$false,$false,$false,$true),@($true,$false,$false,$false,$true,$true),@($false,$false,$false,$true,$true,$true))) {
    Assert-StandardTestReject {Assert-StandardAcceptanceMode $mode[0] $mode[1] $mode[2] $mode[3] $mode[4] $mode[5]} 'Explorer shortcut GUI was accepted in a diagnostic/helper/child or non-granted controller route.'
}
foreach ($mode in @(@($true,$true,$false,$false,$true),@($false,$true,$true,$false,$true),@($false,$true,$false,$true,$true))) {
    Assert-StandardTestReject { Assert-StandardAcceptanceMode $mode[0] $mode[1] $mode[2] $mode[3] $mode[4] } 'Temporary guest interactive-logon scaffolding was accepted outside its exact opt-in controller mode.'
}
foreach ($mode in @(
    @($false,$false,$true,$false), @($true,$true,$true,$false), @($false,$true,$true,$true)
)) {
    Assert-StandardTestReject { Assert-StandardAcceptanceMode $mode[0] $mode[1] $mode[2] $mode[3] } 'The read-only access diagnostic was accepted outside its dedicated controller mode.'
}
Assert-StandardTest ($paths.userName -ceq 'SwAcc-0123456789abcd' -and $paths.userName.Length -eq 20) 'The disposable account identity is not bounded and tied to this run.'
Assert-StandardTest ($paths.root -ceq ('C:\Users\Public\SteamWrapperAcceptance-' + $runId)) 'The guest-local handoff root changed.'
foreach ($invalid in @('', 'not-a-run-id', '0123456789ABCDEF0123456789ABCDEF', '../0123456789abcdef0123456789abcdef')) {
    Assert-StandardTestReject { Get-StandardAcceptancePaths $invalid } 'An unsafe handoff identity was accepted.'
}
$guestPath=Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1'
$parseTokens=$null; $parseErrors=$null
$guestAst=[Management.Automation.Language.Parser]::ParseFile($guestPath,[ref]$parseTokens,[ref]$parseErrors)
foreach($name in @('Assert-Acceptance','Get-AcceptanceAccountMode')) {
    $definition=$guestAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
    Assert-StandardTest ($null -ne $definition) ('The production guest does not recognize a bounded real standard-account mode: ' + $name)
    Invoke-Expression $definition.Extent.Text
}
Assert-StandardTest ((Get-AcceptanceAccountMode 'C:\AcceptanceInput' 'C:\AcceptanceOutput' 'WDAGUtilityAccount' 'C:\Users\WDAGUtilityAccount' 'C:\AcceptanceInput') -ceq 'WDAG') 'The original WDAG lane changed.'
Assert-StandardTest ((Get-AcceptanceAccountMode $paths.input $paths.output $paths.userName ('C:\Users\' + $paths.userName) $paths.input) -ceq 'StandardUser') 'The production guest rejected the bounded standard-account input/profile.'
Assert-StandardTestReject { Get-AcceptanceAccountMode $paths.input $paths.output 'WDAGUtilityAccount' 'C:\Users\WDAGUtilityAccount' $paths.input } 'WDAG was accepted in the standard lane.'
Assert-StandardTestReject { Get-AcceptanceAccountMode $paths.input 'C:\AcceptanceOutput' $paths.userName ('C:\Users\' + $paths.userName) $paths.input } 'Standard guest was accepted with mapped output.'
Assert-StandardTestReject { Get-AcceptanceAccountMode $paths.input $paths.output $paths.userName ('C:\Users\' + $paths.userName) 'C:\repo' } 'The standard guest script was permitted to run from an unsealed host/repository root.'
$manifest = [pscustomobject]@{
    schemaVersion=1; sandboxOnly=$true; networkingDisabled=$true; runId=$runId; hostComputerName='HOST'
    accountMode='StandardUser'; expectedStandardUserName=$paths.userName; expectedStandardUserSid='S-1-5-21-111-222-333-1002'
    standardInputDirectory=$paths.input; standardOutputDirectory=$paths.output; standardSessionId=1
}
$controller = [pscustomobject]@{
    computerName='SANDBOX'; userName='WDAGUtilityAccount'; profile='C:\Users\WDAGUtilityAccount'; nativeProfile='C:\Users\WDAGUtilityAccount'
    localAppData='C:\Users\WDAGUtilityAccount\AppData\Local'; nativeLocalAppData='C:\Users\WDAGUtilityAccount\AppData\Local'
    interactive=$true; sessionId=1; manufacturer='Microsoft Corporation'; model='Virtual Machine'; build=26100; productType=1; x64=$true
    machineDotnetExists=$false; dotnetOnPath=$false; overrides=@(); token=[pscustomobject]@{administratorEnabled=$true}
}
Assert-StandardAcceptanceControllerContext $controller $manifest 'C:\AcceptanceInput' 'C:\AcceptanceOutput'
$cases++
$permissionPaths=Get-StandardPermissionPaths $runId
Assert-StandardTest ((Get-AcceptanceAccountMode $permissionPaths.input $permissionPaths.output 'WDAGUtilityAccount' 'C:\Users\WDAGUtilityAccount' $permissionPaths.input) -ceq 'WDAGStandardPermission') 'The independent WDAG permission handoff did not have its distinct bounded route.'
Assert-StandardTestReject {Get-AcceptanceAccountMode $permissionPaths.input $paths.output 'WDAGUtilityAccount' 'C:\Users\WDAGUtilityAccount' $permissionPaths.input} 'The permission route accepted a fresh-account output directory.'
Assert-StandardTestReject {Get-AcceptanceAccountMode $permissionPaths.input $permissionPaths.output $paths.userName ('C:\Users\'+$paths.userName) $permissionPaths.input} 'A different account was accepted as the primary WDAG permission route.'
$permissionManifest=[pscustomobject]@{schemaVersion=1;sandboxOnly=$true;networkingDisabled=$true;runId=$runId;hostComputerName='HOST';accountMode='WDAGStandardPermission';wdagPermissionOptIn=$true;expectedStandardUserName='WDAGUtilityAccount';expectedStandardUserSid='S-1-5-21-111-222-333-504';permissionOriginalPrimarySid='S-1-5-21-111-222-333-504';standardInputDirectory=$permissionPaths.input;standardOutputDirectory=$permissionPaths.output;standardSessionId=1;standardExpectedLogonSid='S-1-5-5-0-124'}
$permissionContext=$controller | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$permissionContext.token=[pscustomobject]@{userSid=$permissionManifest.expectedStandardUserSid;logonSid=$permissionManifest.standardExpectedLogonSid;sessionId=1;elevated=$false;elevationType=1;integritySid='S-1-16-8192';administratorPresent=$false;administratorEnabled=$false;administratorDenyOnly=$false;usersPresent=$true;usersEnabled=$true;usersDenyOnly=$false;uiAccess=$false;appContainer=$false;type=1;privileges=@([pscustomobject]@{name='SeChangeNotifyPrivilege';enabled=$true;attributes=3})}
$permissionContext | Add-Member -NotePropertyName accountAdministratorMember -NotePropertyValue $false
$permissionContext | Add-Member -NotePropertyName accountUsersMember -NotePropertyValue $true
Assert-StandardAcceptanceScopedChildContext $permissionContext $permissionManifest $permissionPaths.input $permissionPaths.output;$cases++
$permissionFileAcl=New-StandardAcceptanceGuestAcl $permissionManifest.expectedStandardUserSid 'S-1-5-32-544' $false $false
Assert-StandardTest ($permissionFileAcl -is [Security.AccessControl.FileSecurity] -and $permissionFileAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq 'S-1-5-32-544') 'The same-SID sealed file retains a low-user owner or a directory-only descriptor.'
$permissionFileRules=@($permissionFileAcl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier]))
$lowRules=@($permissionFileRules | Where-Object {$_.IdentityReference.Value -ceq $permissionManifest.expectedStandardUserSid})
$allowedInputRights=[Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [Security.AccessControl.FileSystemRights]::Synchronize
Assert-StandardTest ($lowRules.Count -eq 1 -and $lowRules[0].FileSystemRights -eq $allowedInputRights -and $lowRules[0].InheritanceFlags -eq [Security.AccessControl.InheritanceFlags]::None) 'The same-SID sealed file grants child write/owner/ACL rights or file inheritance.'
Assert-StandardTestReject {Assert-StandardAcceptanceChildContext $permissionContext $permissionManifest $permissionPaths.input $permissionPaths.output} 'The original fresh-account guard was weakened to accept the WDAG role fixture.'
foreach($mutation in @(@{name='wdagPermissionOptIn';value=$false},@{name='permissionOriginalPrimarySid';value='S-1-5-21-111-222-333-1000'},@{name='standardExpectedLogonSid';value='S-1-5-5-0-125'},@{name='accountMode';value='StandardUser'})) {
    $copy=$permissionManifest | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy.($mutation.name)=$mutation.value
    Assert-StandardTestReject {Assert-StandardAcceptanceScopedChildContext $permissionContext $copy $permissionPaths.input $permissionPaths.output} 'A nominal opt-in, different primary SID/logon or misleading fresh-account mode was accepted.'
}
foreach($name in @('SeDebugPrivilege','SeBackupPrivilege','SeRestorePrivilege','SeTakeOwnershipPrivilege','SeLoadDriverPrivilege','SeTcbPrivilege','SeImpersonatePrivilege')) {
    $copy=$permissionContext.token | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy.privileges+=[pscustomobject]@{name=$name;enabled=$true;attributes=2}
    Assert-StandardTestReject {Assert-StandardPermissionPrivileges $copy} 'The permission token retained an active administrative privilege.'
}
foreach ($mutation in @(
    @{name='computerName';value='HOST'}, @{name='userName';value='admin'}, @{name='profile';value='C:\Users\admin'},
    @{name='nativeLocalAppData';value='C:\private\LocalCache'}, @{name='interactive';value=$false}, @{name='sessionId';value=0},
    @{name='manufacturer';value='Other'}, @{name='model';value='Development host'}, @{name='build';value=26000},
    @{name='productType';value=3}, @{name='x64';value=$false}, @{name='machineDotnetExists';value=$true},
    @{name='dotnetOnPath';value=$true}, @{name='overrides';value=@('STEAMWRAPPER_DEPLOYMENT_TEST')}
)) {
    $copy = $controller | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $copy.($mutation.name) = $mutation.value
    Assert-StandardTestReject { Assert-StandardAcceptanceControllerContext $copy $manifest 'C:\AcceptanceInput' 'C:\AcceptanceOutput' } ('Controller accepted an unsafe ' + $mutation.name + '.')
}
Assert-StandardTestReject { Assert-StandardAcceptanceControllerContext $controller $manifest 'C:\repo' 'C:\AcceptanceOutput' } 'Controller accepted a host/repository input root.'
$child = $controller | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$child.userName=$paths.userName; $child.profile='C:\Users\' + $paths.userName; $child.nativeProfile=$child.profile
$child.localAppData=$child.profile + '\AppData\Local'; $child.nativeLocalAppData=$child.localAppData
$child | Add-Member -NotePropertyName accountAdministratorMember -NotePropertyValue $false
$child | Add-Member -NotePropertyName accountUsersMember -NotePropertyValue $true
$child.token=[pscustomobject]@{userSid=$manifest.expectedStandardUserSid; elevated=$false; elevationType=1; integritySid='S-1-16-8192'; administratorPresent=$false; administratorEnabled=$false; administratorDenyOnly=$false; usersPresent=$true;usersEnabled=$true;usersDenyOnly=$false;logonSid='S-1-5-5-0-345'; uiAccess=$false; appContainer=$false; type=1}
Assert-StandardAcceptanceChildContext $child $manifest $paths.input $paths.output
$cases++
$token=$child.token | ConvertTo-Json | ConvertFrom-Json
$token | Add-Member -NotePropertyName sessionId -NotePropertyValue 1
$manifest | Add-Member -NotePropertyName standardExpectedLogonSid -NotePropertyValue $token.logonSid
$child.token=$token
$shellProgram=Join-Path $child.nativeLocalAppData 'Programs\SteamWrapper'
$shellShortcut=Join-Path $child.nativeProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SteamWrapper\SteamWrapper.lnk'
$address=[pscustomobject]@{name='Address';controlType='ControlType.Edit';parentName='Address';parentControlType='ControlType.ComboBox';value=[IO.Path]::GetDirectoryName($shellShortcut);automationId='observed-address-id'}
Assert-StandardTest (Test-StandardAcceptanceAddressObservation $address ([IO.Path]::GetDirectoryName($shellShortcut))) 'An actual address edit and address ComboBox did not prove the requested folder.'
foreach($change in @('search','parentSearch','parentPane','wrongFolder')) {
    $wrongAddress=$address | ConvertTo-Json | ConvertFrom-Json
    switch($change) {
        'search' {$wrongAddress.name='Search SteamWrapper'}
        'parentSearch' {$wrongAddress.parentName='Search SteamWrapper'}
        'parentPane' {$wrongAddress.parentControlType='ControlType.Pane'}
        'wrongFolder' {$wrongAddress.value='C:\Users\WDAGUtilityAccount\Desktop'}
    }
    Assert-StandardTest (-not (Test-StandardAcceptanceAddressObservation $wrongAddress ([IO.Path]::GetDirectoryName($shellShortcut)))) 'A search box or unrelated parent/address was accepted as actual folder navigation.'
}
$shell=[pscustomobject]@{
    folder=[IO.Path]::GetDirectoryName($shellShortcut);addressControl=$address;shortcut=$shellShortcut;windowProcessId=101;itemProviderProcessId=0;invokedThroughUi=$true
    explorer=[pscustomobject]@{processId=101;parentProcessId=55;path='C:\Windows\explorer.exe';token=$token}
    launcher=[pscustomobject]@{processId=102;parentProcessId=101;path=(Join-Path $shellProgram 'SteamWrapper.exe');token=$token}
    manager=[pscustomobject]@{processId=103;parentProcessId=102;path=(Join-Path $shellProgram 'versions\v0.2.7\SteamWrapper.Manager.exe');token=$token}
}
Assert-StandardAcceptanceShellProvenance $shell $child $manifest $shellProgram 'v0.2.7'
$cases++
$installed=[pscustomobject]@{shortcut=$shellShortcut;shellRoute='standard-token installed shortcut';ordinaryExplorerTested=$false;invokerProcessId=55;returnedLauncherProcessId=102;
    launcher=$shell.launcher;manager=$shell.manager}
$installed.launcher=$shell.launcher | ConvertTo-Json -Depth 4 | ConvertFrom-Json
$installed.launcher.parentProcessId=55
Assert-StandardAcceptanceInstalledShortcutProvenance $installed $child $manifest $shellProgram 'v0.2.7'
$cases++
foreach($change in @('foreignShortcut','otherUser','otherLogon','otherSession','launcherParent','managerParent','returnedOtherLauncher','claimedExplorer')) {
    $wrongShortcut=$installed | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    switch($change) {
        'foreignShortcut' {$wrongShortcut.shortcut='C:\Users\WDAGUtilityAccount\Desktop\SteamWrapper.lnk'}
        'otherUser' {$wrongShortcut.launcher.token.userSid='S-1-5-21-111-222-333-1001'}
        'otherLogon' {$wrongShortcut.manager.token.logonSid='S-1-5-5-0-999'}
        'otherSession' {$wrongShortcut.manager.token.sessionId=2}
        'launcherParent' {$wrongShortcut.launcher.parentProcessId=999}
        'managerParent' {$wrongShortcut.manager.parentProcessId=999}
        'returnedOtherLauncher' {$wrongShortcut.returnedLauncherProcessId=999}
        'claimedExplorer' {$wrongShortcut.ordinaryExplorerTested=$true}
    }
    Assert-StandardTestReject {Assert-StandardAcceptanceInstalledShortcutProvenance $wrongShortcut $child $manifest $shellProgram 'v0.2.7'} ('The separate installed shortcut lane accepted missing/foreign provenance: '+$change)
}
foreach($change in @('launcherParent','managerParent','windowProcess','foreignProvider','otherUser','otherLogon','otherSession','admin','otherPath','noUi','otherFolder','searchAddress')) {
    $wrong=$shell | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    switch($change) {
        'launcherParent' {$wrong.launcher.parentProcessId=999}
        'managerParent' {$wrong.manager.parentProcessId=999}
        'windowProcess' {$wrong.windowProcessId=999}
        'foreignProvider' {$wrong.itemProviderProcessId=999}
        'otherUser' {$wrong.explorer.token.userSid='S-1-5-21-111-222-333-1001'}
        'otherLogon' {$wrong.launcher.token.logonSid='S-1-5-5-0-999'}
        'otherSession' {$wrong.manager.token.sessionId=2}
        'admin' {$wrong.manager.token.administratorPresent=$true}
        'otherPath' {$wrong.launcher.path='C:\fixture\SteamWrapper.exe'}
        'noUi' {$wrong.invokedThroughUi=$false}
        'otherFolder' {$wrong.folder='C:\Users\WDAGUtilityAccount\Desktop'}
        'searchAddress' {$wrong.addressControl.name='Search SteamWrapper'}
    }
    Assert-StandardTestReject {Assert-StandardAcceptanceShellProvenance $wrong $child $manifest $shellProgram 'v0.2.7'} ('The shell gate accepted missing or foreign actual provenance: '+$change)
}
$separation=@(
    [pscustomobject]@{name='data';path='C:\Users\WDAGUtilityAccount\AppData\Local\SteamWrapper';present=$false},
    [pscustomobject]@{name='program';path='C:\Users\WDAGUtilityAccount\AppData\Local\Programs\SteamWrapper';present=$false},
    [pscustomobject]@{name='registration';path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7DBEC23-E563-4BFB-BE9C-F68D73E4D5BB}_is1';present=$false},
    [pscustomobject]@{name='startMenu';path='C:\Users\WDAGUtilityAccount\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SteamWrapper\SteamWrapper.lnk';present=$false},
    [pscustomobject]@{name='desktop';path='C:\Users\WDAGUtilityAccount\Desktop\SteamWrapper.lnk';present=$false}
)
Assert-StandardAcceptanceControllerSeparation $separation $separation $controller
$cases++
foreach($index in 0..4) {
    $changed=$separation | ConvertTo-Json | ConvertFrom-Json;$changed[$index].present=$true
    Assert-StandardTestReject {Assert-StandardAcceptanceControllerSeparation $separation $changed $controller} 'The fresh standard-user lifecycle changed an owned WDAG data/program/registration/shortcut location.'
}
$changed=$separation | ConvertTo-Json | ConvertFrom-Json;$changed[0].path='C:\Users\admin\AppData\Local\SteamWrapper'
Assert-StandardTestReject {Assert-StandardAcceptanceControllerSeparation $separation $changed $controller} 'The two-user separation check accepted another root.'
$station=[pscustomobject]@{name='WinSta0';sha256=('a'*64);bytes=256;sddl='fixture'}
$desktop=[pscustomobject]@{name='Default';sha256=('b'*64);bytes=256;sddl='fixture'}
$before=[pscustomobject]@{windowStation=$station;desktop=$desktop}
$access=[pscustomobject]@{windowStation=[pscustomobject]@{security=$station;maximumAllowed=$true;grantedAccess=131847};desktop=[pscustomobject]@{security=$desktop;maximumAllowed=$false;grantedAccess=0}}
$observation=New-StandardAcceptanceAccessDiagnostic $manifest $token $before $access $before
Assert-StandardTest ($observation.result -ceq 'observed' -and -not $observation.childResumed -and -not $observation.standardAccountLifecycleTested -and
    -not $observation.productionInstallerExecuted -and -not $observation.desktopAclChanged) 'A DACL observation was presented as an executed standard-user lifecycle.'
foreach ($change in @('windowStation','desktop')) {
    $after=$before | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $after.$change.sha256=('c'*64)
    Assert-StandardTestReject { New-StandardAcceptanceAccessDiagnostic $manifest $token $before $access $after } 'A change to an existing desktop/window-station descriptor was accepted.'
}
$wrongAccess=$access | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$wrongAccess.desktop.security.sha256=('c'*64)
Assert-StandardTestReject { New-StandardAcceptanceAccessDiagnostic $manifest $token $before $wrongAccess $before } 'AccessCheck was accepted against different object security bytes.'
$wrongBefore=$before | ConvertTo-Json -Depth 5 | ConvertFrom-Json
$wrongBefore.desktop.name='Winlogon'
Assert-StandardTestReject { New-StandardAcceptanceAccessDiagnostic $manifest $token $wrongBefore $access $wrongBefore } 'An unrelated existing desktop was accepted.'
$wrongToken=$token | ConvertTo-Json | ConvertFrom-Json
$wrongToken.sessionId=2
Assert-StandardTestReject { New-StandardAcceptanceAccessDiagnostic $manifest $wrongToken $before $access $before } 'The access diagnostic accepted a token from another session.'
foreach ($mutation in @(
    @{name='userSid';value='S-1-5-21-111-222-333-1001'}, @{name='elevated';value=$true}, @{name='elevationType';value=2},
    @{name='integritySid';value='S-1-16-12288'}, @{name='administratorPresent';value=$true},
    @{name='administratorEnabled';value=$true}, @{name='administratorDenyOnly';value=$true},
    @{name='usersPresent';value=$false}, @{name='usersEnabled';value=$false}, @{name='usersDenyOnly';value=$true},
    @{name='uiAccess';value=$true}, @{name='appContainer';value=$true}, @{name='type';value=2}
)) {
    $copy=$child | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $copy.token.($mutation.name)=$mutation.value
    Assert-StandardTestReject { Assert-StandardAcceptanceChildContext $copy $manifest $paths.input $paths.output } ('A different or restricted-admin token was accepted: ' + $mutation.name)
}
$copy=$child | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $copy.accountAdministratorMember=$true
Assert-StandardTestReject { Assert-StandardAcceptanceChildContext $copy $manifest $paths.input $paths.output } 'A filtered administrator account was called a real standard account.'
$copy=$child | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $copy.nativeProfile='C:\Users\WDAGUtilityAccount'
Assert-StandardTestReject { Assert-StandardAcceptanceChildContext $copy $manifest $paths.input $paths.output } 'A standard SID with the WDAG profile was accepted.'
Assert-StandardTestReject { Assert-StandardAcceptanceChildContext $child $manifest 'C:\AcceptanceInput' $paths.output } 'The standard user was permitted to reuse host-mapped input.'
Assert-StandardTestReject { Assert-StandardAcceptanceChildContext $child $manifest $paths.input 'C:\AcceptanceOutput' } 'The standard user was permitted to change host-mapped output ACLs.'
$copy=$child | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $copy.sessionId=2
Assert-StandardTestReject { Assert-StandardAcceptanceChildContext $copy $manifest $paths.input $paths.output } 'A different desktop session was accepted.'
foreach($writable in @($false,$true)) {
    $acl=New-StandardAcceptanceGuestAcl $manifest.expectedStandardUserSid 'S-1-5-21-111-222-333-1001' $writable
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    $userRule=@($rules | Where-Object {$_.IdentityReference.Value -ceq $manifest.expectedStandardUserSid})
    $expected=if($writable){[Security.AccessControl.FileSystemRights]::Modify}else{[Security.AccessControl.FileSystemRights]::ReadAndExecute}
    Assert-StandardTest ($acl.AreAccessRulesProtected -and $rules.Count -eq 3 -and $userRule.Count -eq 1 -and
        ($userRule[0].FileSystemRights -band $expected) -eq $expected -and
        -not ($userRule[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::ChangePermissions) -and
        -not ($userRule[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::TakeOwnership)) 'The handoff ACL granted broader permissions or inherited broad Public-directory rights.'
    if(-not $writable) {
        Assert-StandardTest (-not ($userRule[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::WriteData)) 'Standard user could modify sealed handoff input.'
    }
}
$fixtureRoot=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) ('target/winui/standard-user-script-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$utf8Caption='Microsoft Windows 11 '+(-join @([char]0x4e13,[char]0x4e1a,[char]0x7248))
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'acceptance-input.json'),([ordered]@{caption=$utf8Caption;runId=$runId} | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
$decoded=Read-StandardAcceptanceManifest $fixtureRoot
Assert-StandardTest ($decoded.caption -ceq $utf8Caption -and $decoded.runId -ceq $runId) 'UTF8 without BOM lost a trailing Chinese character/quote in the actual persistent JSON reader.'
$fixtureFile=Join-Path $fixtureRoot 'sealed.txt'
[IO.File]::WriteAllText($fixtureFile,'standard-user sealed-input fixture')
$hash=(Get-FileHash -LiteralPath $fixtureFile).Hash.ToLowerInvariant()
$length=(Get-Item -LiteralPath $fixtureFile).Length
Assert-StandardAcceptanceSealedFile $fixtureFile $hash $length
$cases++
Assert-StandardTestReject { Assert-StandardAcceptanceSealedFile $fixtureFile ('a' * 64) $length } 'Changed sealed input bytes were accepted.'
Assert-StandardTestReject { Assert-StandardAcceptanceSealedFile $fixtureFile $hash ($length+1) } 'Changed sealed input size was accepted.'
$linked=Join-Path $fixtureRoot 'linked'
$actual=Join-Path $fixtureRoot 'actual'
[IO.Directory]::CreateDirectory($actual) | Out-Null
[IO.File]::WriteAllText((Join-Path $actual 'sealed.txt'),'standard-user sealed-input fixture')
try {
    New-Item -ItemType Junction -Path $linked -Target $actual | Out-Null
    Assert-StandardTestReject { Assert-StandardAcceptanceSealedFile (Join-Path $linked 'sealed.txt') $hash $length } 'A linked input ancestor was accepted.'
} finally { [IO.Directory]::Delete($linked) }
$quote=Quote-StandardAcceptanceArgument ('C:\Users\Public\fixture ' + [char]0x4e2d + [char]0x6587)
Assert-StandardTest ($quote.StartsWith('"') -and $quote.EndsWith('"')) 'Unicode child paths were not quoted.'
foreach($invalid in @('C:\unsafe"path', ('C:\unsafe' + [char]10 + 'path'))) {
    Assert-StandardTestReject { Quote-StandardAcceptanceArgument $invalid } 'Unsafe child command characters were accepted.'
}
$hostRefused=$false
try { $null=& $helper -DiagnosticOnly } catch { $hostRefused=$true }
Assert-StandardTest $hostRefused 'Controller did not refuse the development host before creating accounts or files.'
$hostGuestLogonRefused=$false
try { $null=& $helper -DiagnosticOnly -GuestInteractiveLogon } catch { $hostGuestLogonRefused=$true }
Assert-StandardTest $hostGuestLogonRefused 'Guest desktop scaffolding did not refuse the development host before account or DACL changes.'
$hostShellRefused=$false
try {$null=& $helper -GuestInteractiveLogon -ExplorerShortcut} catch {$hostShellRefused=$true}
Assert-StandardTest $hostShellRefused 'Explorer full acceptance did not refuse the host before creating an account or GUI.'
Initialize-StandardAcceptanceNative
Assert-StandardTest ([SteamWrapperStandardAcceptance.Native]::ProbeLeaseHandleNames()) 'The exact controller lease handle rights do not permit its read-only station/desktop name queries.'
$originalSddl='O:BAG:SYD:P(A;;GA;;;SY)(A;;GR;;;BA)S:(ML;;NW;;;ME)'
foreach ($isStation in @($true,$false)) {
    $grantedSddl=[SteamWrapperStandardAcceptance.Native]::AddGuestLogonAce($originalSddl,'S-1-5-5-0-345',$isStation)
    Assert-StandardTest ([SteamWrapperStandardAcceptance.Native]::VerifyGuestLogonAce($originalSddl,$grantedSddl,'S-1-5-5-0-345',$isStation)) 'The exact guest logon ACE did not preserve the original descriptor components.'
    $grantedDescriptor=New-Object Security.AccessControl.RawSecurityDescriptor($grantedSddl)
    $ace=$grantedDescriptor.DiscretionaryAcl[$grantedDescriptor.DiscretionaryAcl.Count-1]
    Assert-StandardTest ($ace.SecurityIdentifier.Value -ceq 'S-1-5-5-0-345' -and $ace.AceFlags -eq 0 -and
        $ace.AccessMask -eq $(if($isStation){0x2037f}else{0x201ff}) -and -not ($ace.AccessMask -band 0xd0000)) 'The logon ACE granted inherited or administrative object rights.'
    foreach ($invalid in @('S-1-1-0','S-1-5-32-545','S-1-5-32-544',$manifest.expectedStandardUserSid,'')) {
        Assert-StandardTestReject { [SteamWrapperStandardAcceptance.Native]::AddGuestLogonAce($originalSddl,$invalid,$isStation) } 'A broad, persistent-account or malformed SID was granted desktop access.'
    }
    Assert-StandardTestReject { [SteamWrapperStandardAcceptance.Native]::AddGuestLogonAce($grantedSddl,'S-1-5-5-0-345',$isStation) } 'An existing logon grant was silently duplicated.'
    foreach ($changed in @($grantedSddl.Replace(';;;ME',';;;HI'),$grantedSddl.Replace('O:BA','O:SY'),$grantedSddl.Replace(';;;BA',';;;WD'))) {
        Assert-StandardTestReject { [SteamWrapperStandardAcceptance.Native]::VerifyGuestLogonAce($originalSddl,$changed,'S-1-5-5-0-345',$isStation) } 'A label, owner or unrelated ACE modification was accepted as bounded logon scaffolding.'
    }
}
Assert-StandardTest ([SteamWrapperStandardAcceptance.Native]::ProbeQueryOnlyAuthorization()) 'Read-only DACL authorization failed with a primary token opened for TOKEN_QUERY only, or granted rights that the fixture denies.'
$observed=[SteamWrapperStandardAcceptance.Native]::GetToken(0)
Assert-StandardTest ([SteamWrapperStandardAcceptance.Native]::PermissionGroupsEqual(@('S-1-5-32-544','S-1-5-32-545'),@('S-1-5-32-545','S-1-5-32-544'))) 'Exact membership CAS depends on enumeration order.'
Assert-StandardTest (-not [SteamWrapperStandardAcceptance.Native]::PermissionGroupsEqual(@('S-1-5-32-545'),@('S-1-5-32-544','S-1-5-32-545'))) 'A concurrent group difference was accepted for exact restoration.'
Assert-StandardTestReject {[SteamWrapperStandardAcceptance.Native]::PermissionGroupsEqual(@('S-1-5-32-545','S-1-5-32-545'),@('S-1-5-32-545'))} 'A duplicate direct membership snapshot was accepted.'
Assert-StandardTestReject {[SteamWrapperStandardAcceptance.Native]::OpenGuestPermissionLease($observed.userSid)} 'Guest permission mutation did not refuse this development host before SAM operations.'
Assert-StandardTest (@($observed.privileges).Count -gt 0 -and @($observed.privileges | Where-Object {$_.name -cnotmatch '^Se[A-Za-z]+Privilege$'}).Count -eq 0) 'The read-only actual token privilege enumeration failed.'
Assert-StandardTest (@([SteamWrapperStandardAcceptance.Native]::DirectLocalGroups([Environment]::UserName)).Count -gt 0) 'The read-only direct local-group snapshot failed on actual localized builtin aliases.'
Assert-StandardTest ([SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator([Environment]::UserName) -eq $observed.administratorPresent) 'Read-only builtin Administrators alias membership did not match the current native token.'
Assert-StandardTest ([SteamWrapperStandardAcceptance.Native]::AccountIsUsersMember([Environment]::UserName) -is [bool]) 'Read-only builtin Users alias membership lookup failed.'
Assert-StandardTest ($observed.type -eq 1 -and $observed.userSid -match '^S-1-' -and $observed.integritySid -match '^S-1-16-' -and
    $observed.elevated -is [bool] -and $observed.elevationType -ge 1 -and $observed.elevationType -le 3) 'The read-only native current-process token query failed.'
$nativeProcess=[SteamWrapperStandardAcceptance.Native]::ObserveProcess([Diagnostics.Process]::GetCurrentProcess().Id)
Assert-StandardTest ($nativeProcess.processId -eq [Diagnostics.Process]::GetCurrentProcess().Id -and $nativeProcess.parentProcessId -gt 0 -and
    $nativeProcess.path -ieq [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -and $nativeProcess.token.userSid -ceq $observed.userSid) 'The native process path/token/actual parent query failed.'
# A harmless inbox PowerShell child proves the observer retains real identity
# before a short-lived process exits. It is not a standard-account result.
$observer=New-Object SteamWrapperStandardAcceptance.LauncherObserver('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')
$probeStart=New-Object Diagnostics.ProcessStartInfo
$probeStart.FileName='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$probeStart.UseShellExecute=$false;$probeStart.CreateNoWindow=$true
$probeStart.Arguments='-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 750; exit 7"'
$probe=$null
try {
    $probe=[Diagnostics.Process]::Start($probeStart)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($null -eq $observer.snapshot -and $watch.ElapsedMilliseconds -lt 5000) {Start-Sleep -Milliseconds 10}
    Assert-StandardTest ($null -ne $observer.snapshot -and $observer.snapshot.processId -eq $probe.Id -and
        $observer.snapshot.parentProcessId -eq [Diagnostics.Process]::GetCurrentProcess().Id -and $observer.snapshot.token.userSid -ceq $observed.userSid) 'The bounded observer missed the actual short-lived process/token/parent or observed a stale process.'
    Assert-StandardTest ($probe.WaitForExit(5000) -and $probe.ExitCode -eq 7) 'The harmless observer fixture did not finish normally; it was not killed.'
} finally {try {$observer.Dispose()} finally {if($null -ne $probe) {$probe.Dispose()}}}
$nativeBefore=[SteamWrapperStandardAcceptance.Native]::ReadCurrentSecurity()
$nativeAccess=[SteamWrapperStandardAcceptance.Native]::CheckCurrentAccess([Diagnostics.Process]::GetCurrentProcess().Id)
$nativeAfter=[SteamWrapperStandardAcceptance.Native]::ReadCurrentSecurity()
foreach ($name in @('windowStation','desktop')) {
    Assert-StandardTest ($nativeBefore.$name.bytes -gt 0 -and $nativeBefore.$name.sha256 -cmatch '^[a-f0-9]{64}$' -and
        $nativeAfter.$name.sha256 -ceq $nativeBefore.$name.sha256 -and $nativeAccess.$name.security.sha256 -ceq $nativeBefore.$name.sha256 -and
        $nativeAccess.$name.maximumAllowed -is [bool] -and $nativeAccess.$name.rights.Count -eq 10) 'Read-only native descriptor/AccessCheck diagnostics failed or changed existing security.'
}
Write-Output ('Standard-account acceptance script gate passed: ' + $cases + ' checks; no user, GUI or installer was created/executed.')
