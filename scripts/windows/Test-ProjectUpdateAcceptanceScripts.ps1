[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProjectUpdateAcceptance.ps1') -HelpersOnly
$cases=0
function Assert-UpdateTest([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:cases++}
function Reject-UpdateTest([scriptblock]$Operation,[string]$Message){$rejected=$false;try{$null=& $Operation}catch{$rejected=$true};Assert-UpdateTest $rejected $Message}
Assert-UpdateTest (-not (Test-ProjectUpdateElementEnabled $null)) 'A not-yet-rendered UIA element must keep waiting instead of throwing under StrictMode.'
Assert-UpdateTest (-not (Test-ProjectUpdateElementEnabled ([pscustomobject]@{Current=[pscustomobject]@{IsEnabled=$false}}))) 'A disabled UIA element must keep waiting.'
Assert-UpdateTest (Test-ProjectUpdateElementEnabled ([pscustomobject]@{Current=[pscustomobject]@{IsEnabled=$true}})) 'A rendered enabled UIA element must finish the readiness wait.'
$downloadObservation=[pscustomobject]@{busyObserved=$false}
$downloadState=[pscustomobject]@{enabled=$true;action='Download update';status='Version v0.2.6-preview.1 is available'}
Assert-UpdateTest (-not (Test-ProjectUpdateDownloadReady $downloadState @('Verified download ready') @('Download update') $downloadObservation)) 'An initial idle dialog was confused with a completed download failure.'
$downloadState.enabled=$false
Assert-UpdateTest (-not (Test-ProjectUpdateDownloadReady $downloadState @('Verified download ready') @('Download update') $downloadObservation) -and $downloadObservation.busyObserved) 'An active download did not remain pending.'
$downloadState.enabled=$true;$downloadState.status='Unable to connect to the update source.'
Reject-UpdateTest {Test-ProjectUpdateDownloadReady $downloadState @('Verified download ready') @('Download update') $downloadObservation} 'An actual completed download failure kept waiting for a verified installer.'
$downloadState.status='Verified download ready';$downloadState.action='Install update'
Assert-UpdateTest (Test-ProjectUpdateDownloadReady $downloadState @('Verified download ready') @('Download update') $downloadObservation) 'A verified actual download was not accepted as ready.'
$baseline=[pscustomobject]@{tag='v0.2.5-preview.1';fileName='SteamWrapper-v0.2.5-preview.1-win-x64-setup.exe';sha256=('a'*64);bytes=100;commit=('b'*40)}
$target=[pscustomobject]@{tag='v0.2.6-preview.1';fileName='SteamWrapper-v0.2.6-preview.1-win-x64-setup.exe';sha256=('c'*64);bytes=101;commit=('d'*40)}
$manifest=[pscustomobject]@{schemaVersion=1;scenario='PublicProjectUpdate';runId=('e'*32);sandboxOnly=$true;networkingEnabled=$true;localCandidate=$false;source='github';channel='preview';baseline=$baseline;target=$target;feed=[pscustomobject]@{sequence=1;payloadSha256=('f'*64);envelopeSha256=('a'*64);mirrorVerified=$true}}
Assert-ProjectUpdateAcceptanceManifest $manifest;$cases++
$target.tag='v0.2.5-preview.2';$target.fileName='SteamWrapper-v0.2.5-preview.2-win-x64-setup.exe'
Reject-UpdateTest {Assert-ProjectUpdateAcceptanceManifest $manifest} 'Same-numeric preview replacement was accepted as integration upgrade.'
$target.tag='v0.2.6-preview.1';$target.fileName='SteamWrapper-v0.2.6-preview.1-win-x64-setup.exe';$manifest.localCandidate=$true
Reject-UpdateTest {Assert-ProjectUpdateAcceptanceManifest $manifest} 'Local candidate was accepted as public signed network acceptance.'
$manifest.localCandidate=$false;$manifest.source='cnb';$manifest.feed.mirrorVerified=$false
Reject-UpdateTest {Assert-ProjectUpdateAcceptanceManifest $manifest} 'CNB acceptance was allowed without an actual verified mirror.'
$manifest.feed.mirrorVerified=$true;$manifest.channel='stable'
Reject-UpdateTest {Assert-ProjectUpdateAcceptanceManifest $manifest} 'Installed preview selected an unrequested stable feed.'
$manifest.channel='preview'
$state=[pscustomobject]@{name='Download update';automationId='PrimaryButton';processId=0;enabled=$true;controlType='Button'}
Assert-ProjectUpdateUiAction $state @('Download update') 101 101;$cases++
Reject-UpdateTest {Assert-ProjectUpdateUiAction $state @('Install update') 101 101} 'An unrelated primary action was invoked.'
Reject-UpdateTest {Assert-ProjectUpdateUiAction $state @('Download update') 102 101} 'A primary action beneath a foreign window was accepted.'
$state.processId=102
Reject-UpdateTest {Assert-ProjectUpdateUiAction $state @('Download update') 101 101} 'A foreign nonzero provider PID was accepted.'
$trust=[pscustomobject]@{schemaVersion=1;channels=[pscustomobject]@{preview=[pscustomobject]@{sequence=1;digest=('f'*64)}}}
Assert-ProjectUpdateAcceptedFeed $manifest $trust;$cases++
$trust.channels.preview.digest=('a'*64)
Reject-UpdateTest {Assert-ProjectUpdateAcceptedFeed $manifest $trust} 'A different accepted signed payload was claimed as the pinned feed.'
$config=[xml](New-ProjectUpdateSandboxConfiguration 'C:\input & fixture' 'C:\evidence fixture')
Assert-UpdateTest ($config.Configuration.Networking -ceq 'Enable' -and $config.Configuration.vGPU -ceq 'Disable' -and $config.Configuration.ClipboardRedirection -ceq 'Disable' -and $config.Configuration.MemoryInMB -ceq '8192') 'Public integration configuration changed network/software-rendering/privacy bounds.'
Assert-UpdateTest ($null -eq $config.Configuration.SelectSingleNode('LogonCommand') -and @($config.Configuration.MappedFolders.MappedFolder).Count -eq 2) 'Public integration unexpectedly autoran or widened mapped surfaces.'
$definitions=Get-ProjectUpdateCleanHelperDefinitions (Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1')
. $definitions
$standardAccount=$false
Assert-UpdateTest ($null -eq (Get-AcceptanceProcessSecurity ([Diagnostics.Process]::GetCurrentProcess()))) 'Imported helpers unexpectedly claimed standard-account security.'
# Run the imported transitive helper closure with an actual harmless inbox
# Framework child, rather than infer runtime correctness from function names.
$helperRoot=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../target/winui'))) ('public-update-helper-'+[guid]::NewGuid().ToString('N'))
$dataRoot=Join-Path $helperRoot 'data';[IO.Directory]::CreateDirectory((Join-Path $dataRoot 'bin'))|Out-Null
$trustFixture=Join-Path $helperRoot 'trust-state.json'
$trust.channels.preview.digest=$manifest.feed.payloadSha256
[IO.File]::WriteAllText($trustFixture,($trust|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
$trustFixtureHash=(Get-FileHash -LiteralPath $trustFixture).Hash.ToLowerInvariant()
Assert-ProjectUpdatePreservedTrust $trustFixture $trustFixtureHash $manifest;$cases++
[IO.File]::AppendAllText($trustFixture,"`n")
Reject-UpdateTest {Assert-ProjectUpdatePreservedTrust $trustFixture $trustFixtureHash $manifest} 'Changed trust bytes with the same JSON meaning were accepted after installation.'
$trust.channels.preview.digest=('a'*64)
[IO.File]::WriteAllText($trustFixture,($trust|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
$changedTrustHash=(Get-FileHash -LiteralPath $trustFixture).Hash.ToLowerInvariant()
Reject-UpdateTest {Assert-ProjectUpdatePreservedTrust $trustFixture $changedTrustHash $manifest} 'A matching file hash hid a different accepted feed payload.'
[IO.File]::Delete($trustFixture)
Reject-UpdateTest {Assert-ProjectUpdatePreservedTrust $trustFixture $trustFixtureHash $manifest} 'Deleted trust history was accepted after installation or uninstall.'
$compileFile=Join-Path $helperRoot 'CompileFixture.ps1'
[IO.File]::WriteAllText($compileFile,@'
param([string]$Output)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
public static class ProjectUpdateHelperFixture {
    public static int Main() {
        System.Threading.Thread.Sleep(300);
        System.IO.File.WriteAllText(System.Environment.GetEnvironmentVariable("STEAMWRAPPER_PUBLIC_HELPER_MARKER"),System.Environment.CurrentDirectory);
        return 0;
    }
}
"@ -OutputAssembly $Output -OutputType ConsoleApplication
'@,[Text.UTF8Encoding]::new($false))
$fixture=Join-Path $dataRoot 'bin/SteamWrapperRunner.exe'
& (Join-Path $env:windir 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -File $compileFile -Output $fixture
if($LASTEXITCODE -ne 0){throw 'Harmless shared helper fixture compilation failed.'}
$OutputDirectory=$helperRoot;$evidencePath=Join-Path $helperRoot 'evidence.json';$utf8=New-Object Text.UTF8Encoding($false)
$events=New-Object 'Collections.Generic.List[object]';$runnerDiagnostics=New-Object 'Collections.Generic.List[object]';$evidence=[ordered]@{steps=$events;runnerDiagnostics=$runnerDiagnostics}
$marker=Join-Path $helperRoot 'marker.txt';$previousMarker=$env:STEAMWRAPPER_PUBLIC_HELPER_MARKER;$env:STEAMWRAPPER_PUBLIC_HELPER_MARKER=$marker
function Get-Process {
    [CmdletBinding()]param([string[]]$Name)
    # Only the isolated helper's no-Manager guard is mocked. No host window or
    # process is closed, selected, or inferred to be absent by this unit smoke.
    if($Name.Count -eq 1 -and $Name[0] -ceq 'SteamWrapper.Manager'){return @()}
    return Microsoft.PowerShell.Management\Get-Process @PSBoundParameters
}
try{
    Invoke-AcceptanceRunner 'public shared Runner helper smoke' $marker ([Environment]::CurrentDirectory)
    Assert-UpdateTest ($runnerDiagnostics.Count -eq 1 -and $runnerDiagnostics[0].exit.exitCode -eq 0 -and $events.Count -eq 1) 'Actual imported Runner helper closure did not finish normally.'
    Invoke-AcceptanceInstaller $fixture 'harmless installer-helper smoke'
    Assert-UpdateTest ($events.Count -eq 2 -and $events[1].details.exitCode -eq 0) 'Actual imported installer helper closure did not finish normally.'
}finally{$env:STEAMWRAPPER_PUBLIC_HELPER_MARKER=$previousMarker}
Write-Output "Project public-update acceptance regression passed: $cases cases; no project signature creation, network request, product executable or Sandbox run."
