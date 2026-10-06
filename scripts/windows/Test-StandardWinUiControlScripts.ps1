[CmdletBinding()]param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'StandardUserAcceptance.ps1') -HelpersOnly
. (Join-Path $PSScriptRoot 'Invoke-StandardWinUiControlProbe.ps1') -HelpersOnly
. (Join-Path $PSScriptRoot 'Prepare-StandardWinUiControl.ps1') -HelpersOnly
$cases=0
function Assert-ControlTest([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:cases++}
function Assert-ControlReject([scriptblock]$Operation,[string]$Message){$rejected=$false;try{$null=& $Operation}catch{$rejected=$true};Assert-ControlTest $rejected $Message}
$required=@('SteamWrapper.WinUiControl.exe','SteamWrapper.WinUiControl.dll','SteamWrapper.WinUiControl.pri','Microsoft.UI.Xaml.dll','coreclr.dll')
$inventory=[pscustomobject]@{schemaVersion=1;kind='EmptyWinUiControl';developerOnly=$true;fileName='standard-winui-control.zip';sha256=('a'*64);bytes=500;executable=$required[0];resources='empty';files=@($required | ForEach-Object {[pscustomobject]@{path=$_;bytes=100;sha256=('b'*64)}})}
Assert-StandardWinUiControlInventory $inventory;$cases++
foreach($name in @('../bad.exe','folder/../bad.exe','/bad.exe','C:/bad.exe','folder\bad.exe','folder//bad.exe','folder/./bad.exe','bad.exe/','')){Assert-ControlReject {Assert-StandardWinUiControlEntry $name 1} 'An unsafe control archive entry was accepted.'}
foreach($bytes in @(0,-1,134217729)){Assert-ControlReject {Assert-StandardWinUiControlEntry 'control.exe' $bytes} 'An oversized or empty ZIP entry was accepted.'}
foreach($mutation in @(@{name='developerOnly';value=$false},@{name='kind';value='Release'},@{name='resources';value='product'},@{name='executable';value='SteamWrapper.Manager.exe'},@{name='sha256';value=('A'*64)},@{name='bytes';value=268435457})) {
 $copy=$inventory | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy.($mutation.name)=$mutation.value
 Assert-ControlReject {Assert-StandardWinUiControlInventory $copy} 'An unexpected/unsealed developer fixture was accepted.'
}
$copy=$inventory | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy.files+=[pscustomobject]@{path=$required[0].ToUpperInvariant();bytes=100;sha256=('c'*64)}
Assert-ControlReject {Assert-StandardWinUiControlInventory $copy} 'Case-ambiguous duplicate ZIP entries were accepted.'
$copy=$inventory | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy.files=@($copy.files | Select-Object -Skip 1)
Assert-ControlReject {Assert-StandardWinUiControlInventory $copy} 'Missing executable dependency was accepted.'
$managerPath=Join-Path $PSScriptRoot '..\..\apps\manager-winui\SteamWrapper.Manager\SteamWrapper.Manager.csproj'
$manager=[xml](Get-Content -LiteralPath $managerPath -Raw)
$generated=[xml](Get-StandardWinUiControlProject $manager)
foreach($name in @('TargetFramework','TargetPlatformMinVersion','WindowsAppSDKSelfContained','SelfContained','WindowsPackageType','UseWinUI','WinUISDKReferences','EnableMsixTooling')) {
 Assert-ControlTest ($generated.Project.PropertyGroup.$name -ceq $manager.Project.PropertyGroup.$name) ('The control changed the actual Manager runtime property '+$name+'.')
}
Assert-ControlTest ($generated.SelectNodes('/Project/ItemGroup/ProjectReference').Count -eq 0) 'The empty control acquired a product reference.'
foreach($reference in $generated.SelectNodes('/Project/ItemGroup/PackageReference')) {
 $pin=@($manager.SelectNodes('/Project/ItemGroup/PackageReference') | Where-Object Include -CEQ $reference.Include)
 Assert-ControlTest ($pin.Count -eq 1 -and $pin[0].Version -ceq $reference.Version) 'The control SDK pin differs from the actual Manager.'
}
$broken=[xml]$manager.OuterXml;$node=$broken.SelectSingleNode('/Project/PropertyGroup/WindowsAppSDKSelfContained');$null=$node.ParentNode.RemoveChild($node)
Assert-ControlReject {Get-StandardWinUiControlProject $broken} 'A missing self-contained property silently fell back to a framework-dependent control.'
$runId='0123456789abcdef0123456789abcdef'
$manifest=[pscustomobject]@{runId=$runId;expectedStandardUserSid='S-1-5-21-111-222-333-1000'}
$token=[pscustomobject]@{userSid=$manifest.expectedStandardUserSid;logonSid='S-1-5-5-0-123';sessionId=1;elevated=$false;elevationType=1;integritySid='S-1-16-8192';administratorPresent=$false;administratorEnabled=$false;administratorDenyOnly=$false;usersPresent=$true;usersEnabled=$true;usersDenyOnly=$false;uiAccess=$false;appContainer=$false;type=1}
$context=[pscustomobject]@{token=$token;sessionId=1;userName='SwAcc-0123456789abcd'}
$observation=[pscustomobject]@{path='C:\Users\fixture\control.exe';processId=100;parentProcessId=[Diagnostics.Process]::GetCurrentProcess().Id;token=$token}
Assert-StandardWinUiControlObservation $observation $context $manifest 'StandardUser' $observation.path;$cases++
foreach($mutation in @(@{name='userSid';value='S-1-5-21-111-222-333-1001'},@{name='logonSid';value='S-1-5-5-0-124'},@{name='sessionId';value=2},@{name='elevated';value=$true},@{name='administratorPresent';value=$true})) {
 $copy=$observation | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy.token.($mutation.name)=$mutation.value
 Assert-ControlReject {Assert-StandardWinUiControlObservation $copy $context $manifest 'StandardUser' $observation.path} 'A different or elevated control process was accepted.'
}
$copy=$observation | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy.parentProcessId++
Assert-ControlReject {Assert-StandardWinUiControlObservation $copy $context $manifest 'StandardUser' $observation.path} 'A delegated control parent was accepted.'
$stageNames=@('main-entry','before-com-wrappers','after-com-wrappers','before-Start','callback-entry','before-dispatcher-context','after-dispatcher-context','before-new-App','app-body-entry','InitializeComponent-entered','InitializeComponent-complete','app-body-complete','after-new-App','OnLaunched','window-created','window-activated','normal-close-request','window-closed','Start-returned','normal-exit')
$stages=@($stageNames | ForEach-Object {[pscustomobject]@{stage=$_;runId=$runId;role='StandardUser';processId=100;exception=$null}})
Assert-StandardWinUiControlStages $stages $manifest 'StandardUser' 100;$cases++
Assert-ControlReject {Assert-StandardWinUiControlStages ($stages | Where-Object stage -CNE 'window-closed') $manifest 'StandardUser' 100} 'A missing normal window close was reported as a passed control.'
$copy=$stages | ConvertTo-Json -Depth 5 | ConvertFrom-Json;$copy[8].exception='System.Runtime.InteropServices.COMException: catastrophic failure'
Assert-ControlReject {Assert-StandardWinUiControlStages $copy $manifest 'StandardUser' 100} 'A constructor exception was reported as a passed control.'
Assert-ControlReject {& (Join-Path $PSScriptRoot 'Invoke-StandardWinUiControlProbe.ps1')} 'The live control driver did not refuse this host before files or GUI.'
foreach($file in @('Prepare-StandardWinUiControl.ps1','Invoke-StandardWinUiControlProbe.ps1')) {
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)
 Assert-ControlTest ($errors.Count -eq 0) ('Control helper parse failed: '+$file)
}
Write-Output ('WinUI control script gate passed: '+$cases+' checks; no account, GUI or installer was executed.')
