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
$child.token=[pscustomobject]@{userSid=$manifest.expectedStandardUserSid; elevated=$false; elevationType=1; integritySid='S-1-16-8192'; administratorPresent=$false; administratorEnabled=$false; administratorDenyOnly=$false; uiAccess=$false; appContainer=$false; type=1}
Assert-StandardAcceptanceChildContext $child $manifest $paths.input $paths.output
$cases++
foreach ($mutation in @(
    @{name='userSid';value='S-1-5-21-111-222-333-1001'}, @{name='elevated';value=$true}, @{name='elevationType';value=2},
    @{name='integritySid';value='S-1-16-12288'}, @{name='administratorPresent';value=$true},
    @{name='administratorEnabled';value=$true}, @{name='administratorDenyOnly';value=$true},
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
Initialize-StandardAcceptanceNative
$observed=[SteamWrapperStandardAcceptance.Native]::GetToken(0)
Assert-StandardTest ($observed.type -eq 1 -and $observed.userSid -match '^S-1-' -and $observed.integritySid -match '^S-1-16-' -and
    $observed.elevated -is [bool] -and $observed.elevationType -ge 1 -and $observed.elevationType -le 3) 'The read-only native current-process token query failed.'
Write-Output ('Standard-account acceptance script gate passed: ' + $cases + ' checks; no user, GUI or installer was created/executed.')
