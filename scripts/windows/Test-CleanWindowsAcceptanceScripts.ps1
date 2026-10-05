[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$entry = Join-Path $PSScriptRoot 'Test-CleanWindowsAcceptance.ps1'
$rejected = $false
try { $null = & $entry -Action Prepare -StartupMode AfterLogin -BaselineTag 'v01.2.3' -Tag 'v0.2.5' }
catch { $rejected = $_.Exception.Message -match 'strict.*SemVer' }
if (-not $rejected) { throw 'After-login preparation must reject an invalid release tag before network access or Sandbox execution.' }
. (Join-Path $PSScriptRoot 'CleanWindowsAcceptance.ps1')
$cases = 1
function Assert-AcceptanceScript([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:cases++
}
function Assert-AcceptanceScriptReject([scriptblock]$Operation, [string]$Message) {
    $blocked = $false
    try { $null = & $Operation } catch { $blocked = $true }
    Assert-AcceptanceScript $blocked $Message
}
$inputPath = "C:\fixture & unicode input"
$outputPath = "C:\fixture output"
$after = [xml](New-CleanWindowsSandboxConfiguration $inputPath $outputPath AfterLogin)
$default = [xml](New-CleanWindowsSandboxConfiguration $inputPath $outputPath LogonCommand)
Assert-AcceptanceScript ($null -eq $after.Configuration.SelectSingleNode('LogonCommand')) 'AfterLogin still launched an automatic guest command.'
Assert-AcceptanceScript ($default.Configuration.LogonCommand.Command -ceq 'powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -Command "& ''C:\AcceptanceInput\Invoke-CleanWindowsGuestAcceptance.ps1'' *> ''C:\AcceptanceOutput\guest-launch.log''"') 'The default LogonCommand changed.'
foreach ($config in @($after, $default)) {
    $vGpu=$config.Configuration.SelectSingleNode('vGPU')
    Assert-AcceptanceScript ($null -ne $vGpu -and $vGpu.InnerText -ceq 'Disable') 'Clean acceptance must disable vGPU for the verified software-rendered Sandbox startup.'
    Assert-AcceptanceScript ($config.Configuration.Networking -ceq 'Disable' -and $config.Configuration.ClipboardRedirection -ceq 'Disable' -and
        $config.Configuration.AudioInput -ceq 'Disable' -and $config.Configuration.VideoInput -ceq 'Disable' -and $config.Configuration.PrinterRedirection -ceq 'Disable') 'A startup choice widened Sandbox sharing.'
    $maps = @($config.Configuration.MappedFolders.MappedFolder)
    Assert-AcceptanceScript ($maps.Count -eq 2 -and $maps[0].HostFolder -ceq $inputPath -and $maps[0].SandboxFolder -ceq 'C:\AcceptanceInput' -and $maps[0].ReadOnly -ceq 'true' -and
        $maps[1].HostFolder -ceq $outputPath -and $maps[1].SandboxFolder -ceq 'C:\AcceptanceOutput' -and $maps[1].ReadOnly -ceq 'false') 'Sandbox mappings or XML path escaping changed.'
}
$legacy = [pscustomobject]@{ schemaVersion=1 }
Assert-AcceptanceScript ((Get-CleanWindowsStartupMode $legacy) -ceq 'LogonCommand') 'Existing preparations lost their default startup behavior.'
$manifest = [pscustomobject]@{ startupMode='AfterLogin'; launchScriptSha256=('a' * 64) }
$sandboxUuid = '12345678-1234-1234-1234-1234567890ab'
$arguments = @(Get-CleanWindowsExecuteArguments $manifest $sandboxUuid)
Assert-AcceptanceScript ($arguments.Count -eq 10 -and $arguments[0] -ceq 'exec' -and $arguments[2] -ceq $sandboxUuid -and $arguments[6] -ceq 'ExistingLogin' -and $arguments[9] -ceq '--raw' -and
    $arguments[4] -ceq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -File C:\AcceptanceInput\Start-CleanWindowsAcceptance.ps1') 'Execute did not select the fixed guest wrapper under ExistingLogin.'
Assert-AcceptanceScriptReject { Get-CleanWindowsExecuteArguments $legacy $sandboxUuid } 'Execute accepted the default automatic preparation.'
Assert-AcceptanceScriptReject { Get-CleanWindowsExecuteArguments $manifest 'not-a-sandbox; powershell.exe' } 'Execute accepted an unsafe Sandbox ID.'
Assert-AcceptanceScriptReject { Get-CleanWindowsExecuteArguments ([pscustomobject]@{ startupMode='AfterLogin' }) $sandboxUuid } 'Execute accepted an unverified wrapper.'
Assert-CleanWindowsExecuteResult '{"ExitCode":0}' 0
$cases++
Assert-AcceptanceScriptReject { Assert-CleanWindowsExecuteResult '{"ExitCode":1}' 0 } 'A failed guest exit was accepted because the Sandbox CLI itself exited zero.'
Assert-AcceptanceScriptReject { Assert-CleanWindowsExecuteResult '{"ExitCode":0}' 1 } 'A failed Sandbox CLI was accepted.'
foreach($raw in @('{"ExitCode":"0"}','{"ExitCode":false}','{}','null','[]','not JSON')) {
    Assert-AcceptanceScriptReject { Assert-CleanWindowsExecuteResult $raw 0 } 'An absent or non-integer guest exit code was accepted.'
}
$root = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) ('target/winui/clean-acceptance-script-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$fixture = Join-Path $root 'sealed-fixture.exe'
[IO.File]::WriteAllText($fixture, 'not executable: immutable Setup hash fixture')
$hash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
$length = (Get-Item -LiteralPath $fixture).Length
$candidateDirectory=Join-Path $root 'candidate-installer'
[IO.Directory]::CreateDirectory($candidateDirectory) | Out-Null
$candidateSetup=Join-Path $candidateDirectory 'SteamWrapper-v0.2.6-win-x64-setup.exe'
[IO.File]::WriteAllBytes($candidateSetup,[IO.File]::ReadAllBytes($fixture))
$candidateFiles=@((@(Get-WinUIReleaseRequiredFiles) + @('SteamWrapper.Deployment.dll','Deployment/SteamWrapper.exe','LICENSE','THIRD_PARTY_NOTICES.md','LICENSES/index.json')) | Sort-Object -Unique | ForEach-Object {[pscustomobject]@{path=$_;bytes=1;sha256=('a' * 64)}})
$candidateDeployment=[ordered]@{schemaVersion=1;appId='SteamWrapper';tag='v0.2.6';version='0.2.6';deploymentProtocol=1;profileContract=2;runnerContract=2;managerExecutable='SteamWrapper.Manager.exe';files=$candidateFiles}
$candidateManifestPath=Join-Path $candidateDirectory 'deployment-manifest.json'
[IO.File]::WriteAllText($candidateManifestPath,($candidateDeployment | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$candidateBuild=[ordered]@{schemaVersion=1;tag='v0.2.6';version='0.2.6';platform='win-x64';isolated=$false;deploymentManifestSha256=(Get-FileHash -LiteralPath $candidateManifestPath).Hash.ToLowerInvariant();payloadFiles=$candidateFiles.Count;installer=[ordered]@{fileName=[IO.Path]::GetFileName($candidateSetup);bytes=$length;sha256=$hash;signed=$false;canonicalIconFrames=1}}
$candidateBuildPath=Join-Path $candidateDirectory 'installer-build.json'
[IO.File]::WriteAllText($candidateBuildPath,($candidateBuild | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$candidatePreparation=& $entry -Action Prepare -StartupMode AfterLogin -CandidateInstallerDirectory $candidateDirectory -Tag 'v0.2.6' | Out-String
Assert-AcceptanceScript ($candidatePreparation -match 'CandidateFirstInstall') 'An explicit candidate preparation did not record its unpublished first-install scope.'
$candidateRoot=($candidatePreparation -split "`r?`n" | Where-Object {$_ -match '^Prepared CandidateFirstInstall'} | Select-Object -First 1) -replace '^Prepared CandidateFirstInstall installers and isolated Sandbox configuration: ',''
$candidateInput=Get-Content -LiteralPath (Join-Path $candidateRoot 'input/acceptance-input.json') -Raw | ConvertFrom-Json
Assert-CleanWindowsScenario $candidateInput
Assert-AcceptanceScript ($candidateInput.localCandidate -and $candidateInput.baseline.tag -ceq $candidateInput.target.tag -and $candidateInput.sourceHeadCommit -cmatch '^[a-f0-9]{40}$' -and $candidateInput.workingCopyDirty -is [bool]) 'Candidate source/scenario provenance was not recorded.'
$candidateEvidence=[pscustomobject]@{scenario='CandidateFirstInstall';localCandidate=$true;unpublishedCandidate=$true;numericUpgradeTested=$false;sourceHeadCommit=$candidateInput.sourceHeadCommit;workingCopyDirty=$candidateInput.workingCopyDirty}
Assert-CleanWindowsEvidenceScope $candidateInput $candidateEvidence
$cases++
$candidateEvidence.numericUpgradeTested=$true
Assert-AcceptanceScriptReject { Assert-CleanWindowsEvidenceScope $candidateInput $candidateEvidence } 'An unpublished first-install candidate claimed a numeric upgrade pass.'
$candidateEvidence.numericUpgradeTested=$false
$candidateEvidence.unpublishedCandidate=$false
Assert-AcceptanceScriptReject { Assert-CleanWindowsEvidenceScope $candidateInput $candidateEvidence } 'An unpublished candidate claimed official public release scope.'
$xamlRecord=@($candidateFiles | Where-Object path -CEQ 'Microsoft.UI.Xaml.dll')[0]
$originalManifestBytes=[IO.File]::ReadAllBytes($candidateManifestPath)
$originalManifestDigest=$candidateBuild.deploymentManifestSha256
try {
    # The Windows App SDK's actual deployed filename casing differs from the
    # generic required-file list, while Windows resolves it case-insensitively.
    $xamlRecord.path='Microsoft.ui.xaml.dll'
    [IO.File]::WriteAllText($candidateManifestPath,($candidateDeployment | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    $candidateBuild.deploymentManifestSha256=(Get-FileHash -LiteralPath $candidateManifestPath).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($candidateBuildPath,($candidateBuild | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    $sdkCasedCandidate=Read-CleanWindowsCandidateInstaller $candidateDirectory 'v0.2.6'
    Assert-AcceptanceScript ($sdkCasedCandidate.tag -ceq 'v0.2.6') 'Candidate rejected the actual Windows SDK filename casing.'
} finally {
    $xamlRecord.path='Microsoft.UI.Xaml.dll'
    [IO.File]::WriteAllBytes($candidateManifestPath,$originalManifestBytes)
    $candidateBuild.deploymentManifestSha256=$originalManifestDigest
    [IO.File]::WriteAllText($candidateBuildPath,($candidateBuild | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
Assert-AcceptanceScriptReject { & $entry -Action Prepare -CandidateInstallerDirectory $candidateDirectory } 'A candidate was accepted without an explicit Tag.'
Assert-AcceptanceScriptReject { & $entry -Action Prepare -CandidateInstallerDirectory $candidateDirectory -Tag 'v0.2.6' -BaselineTag 'v0.2.4-preview.1' } 'A first-install candidate mixed public-upgrade options.'
$candidateBuild.isolated=$true
try {
    [IO.File]::WriteAllText($candidateBuildPath,($candidateBuild | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    Assert-AcceptanceScriptReject { Read-CleanWindowsCandidateInstaller $candidateDirectory 'v0.2.6' } 'An isolated Setup was admitted to the production candidate lane.'
} finally { $candidateBuild.isolated=$false; [IO.File]::WriteAllText($candidateBuildPath,($candidateBuild | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false)) }
Assert-AcceptanceScriptReject { Read-CleanWindowsCandidateInstaller $candidateDirectory 'v0.2.7' } 'Candidate metadata was accepted under a different explicit version.'
$originalCandidateManifest=[IO.File]::ReadAllBytes($candidateManifestPath)
try {
    [IO.File]::AppendAllText($candidateManifestPath,' ')
    Assert-AcceptanceScriptReject { Read-CleanWindowsCandidateInstaller $candidateDirectory 'v0.2.6' } 'Candidate accepted a changed deployment-manifest hash.'
} finally { [IO.File]::WriteAllBytes($candidateManifestPath,$originalCandidateManifest) }
try {
    [IO.File]::AppendAllText($candidateSetup,'tamper')
    Assert-AcceptanceScriptReject { Read-CleanWindowsCandidateInstaller $candidateDirectory 'v0.2.6' } 'Candidate accepted changed Setup bytes.'
} finally { [IO.File]::WriteAllBytes($candidateSetup,[IO.File]::ReadAllBytes($fixture)) }
Assert-CleanWindowsPreparedFile $fixture $hash $length
Assert-AcceptanceScriptReject { Assert-CleanWindowsPreparedFile $fixture ('a' * 64) $length } 'A changed prepared file was accepted.'
Assert-AcceptanceScriptReject { Assert-CleanWindowsPreparedFile $fixture $hash ($length + 1) } 'A wrong prepared file length was accepted.'
$linkedInput=Join-Path $root 'linked-input'
$actualInput=Join-Path $root 'actual-input'
[IO.Directory]::CreateDirectory($actualInput) | Out-Null
[IO.File]::WriteAllBytes((Join-Path $actualInput 'sealed-fixture.exe'),[IO.File]::ReadAllBytes($fixture))
try {
    New-Item -ItemType Junction -Path $linkedInput -Target $actualInput | Out-Null
    Assert-AcceptanceScriptReject { Assert-CleanWindowsPreparedFile (Join-Path $linkedInput 'sealed-fixture.exe') $hash $length } 'Prepared installer validation accepted a linked ancestor.'
} finally { [IO.Directory]::Delete($linkedInput) }
$asset = [pscustomobject]@{ tag='v0.2.6'; fileName='SteamWrapper-v0.2.6-win-x64-setup.exe'; sha256=$hash; bytes=$length; commit=('b' * 40) }
Assert-CleanWindowsAcceptanceAsset $asset
$cases++
$asset.fileName='../outside.exe'
Assert-AcceptanceScriptReject { Assert-CleanWindowsAcceptanceAsset $asset } 'A path outside the canonical installer name was accepted.'
$asset.fileName='SteamWrapper-v0.2.6-win-x64-setup.exe'
$asset.tag='v0.2.6-preview.1'
Assert-AcceptanceScriptReject { Assert-CleanWindowsAcceptanceAsset $asset } 'A mismatched installer tag was accepted.'
$asset.tag='v0.2.6'
$asset.commit='main'
Assert-AcceptanceScriptReject { Assert-CleanWindowsAcceptanceAsset $asset } 'An unresolved source commit was accepted.'
$stableNames = @('SteamWrapper-v0.2.6-win-x64-setup.exe', 'SteamWrapper-v0.2.6-win-x64.zip', 'portable-release.json', 'release.json', 'SHA256SUMS', 'v0.2.6.en.md', 'v0.2.6.zh-CN.md')
$release = [pscustomobject]@{ tagName='v0.2.6'; isDraft=$false; isPrerelease=$false; assets=@($stableNames | ForEach-Object { [pscustomobject]@{name=$_} }) }
Assert-CleanWindowsPublicRelease $release 'v0.2.6'
$cases++
$release.isPrerelease=$true
Assert-AcceptanceScriptReject { Assert-CleanWindowsPublicRelease $release 'v0.2.6' } 'A prerelease mislabeled as stable was accepted.'
$release.isPrerelease=$false
$release.isDraft=$true
Assert-AcceptanceScriptReject { Assert-CleanWindowsPublicRelease $release 'v0.2.6' } 'A draft release was accepted.'
$release.isDraft=$false
$release.assets[0].name='SteamWrapper-isolated-test.exe'
Assert-AcceptanceScriptReject { Assert-CleanWindowsPublicRelease $release 'v0.2.6' } 'An unexpected public release asset was accepted.'
$setupAsset = [pscustomobject]@{name='SteamWrapper-v0.2.6-win-x64-setup.exe';size=$length;digest=('sha256:' + $hash)}
$installerRecord = [pscustomobject]@{fileName=$setupAsset.name;bytes=$length;sha256=$hash}
$metadata = [pscustomobject]@{
    schemaVersion=2;tag='v0.2.6';version='0.2.6';commit=('b' * 40);platform='win-x64';releaseChannel='stable';tagPrerelease=$false;githubPrerelease=$false;installer=$true
    installerAsset=$installerRecord;installerBuild=[pscustomobject]@{tag='v0.2.6';version='0.2.6';platform='win-x64';isolated=$false;installer=$installerRecord}
}
Assert-CleanWindowsPublicInstaller $metadata $setupAsset 'v0.2.6' ('b' * 40)
$cases++
$metadata.installerBuild.isolated=$true
Assert-AcceptanceScriptReject { Assert-CleanWindowsPublicInstaller $metadata $setupAsset 'v0.2.6' ('b' * 40) } 'An isolated test installer was admitted as production Setup.'
$metadata.installerBuild.isolated=$false
$metadata.releaseChannel='preview'
Assert-AcceptanceScriptReject { Assert-CleanWindowsPublicInstaller $metadata $setupAsset 'v0.2.6' ('b' * 40) } 'Installer metadata with the wrong channel was accepted.'
$metadata.releaseChannel='stable'
Assert-AcceptanceScriptReject { Assert-CleanWindowsPublicInstaller $metadata $setupAsset 'v0.2.6' ('c' * 40) } 'Installer metadata from a different public commit was accepted.'

# Exercise the actual inbox-compatible guest asset parser without running its
# guarded installer body. Only inert text fixtures are copied here.
$parseTokens=$null
$parseErrors=$null
$guestPath=Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1'
$guestAst=[Management.Automation.Language.Parser]::ParseFile($guestPath,[ref]$parseTokens,[ref]$parseErrors)
Assert-AcceptanceScript ($parseErrors.Count -eq 0) 'Guest script parsing failed.'
foreach($functionName in @('Assert-Acceptance','Read-AcceptanceAsset','Test-AcceptanceInboxRuntimePackage','Get-AcceptancePayloadRuntimeModules','Assert-AcceptanceManualAppIdAction','Get-AcceptanceExitDiagnostic','Read-AcceptanceBoundedDiagnosticFile','Get-AcceptanceNumericVersion','Get-AcceptanceScenario')) {
    $definition=$guestAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName},$true)
    Assert-AcceptanceScript ($null -ne $definition) ('Missing pure guest helper: ' + $functionName)
    . ([scriptblock]::Create($definition.Extent.Text))
}
Assert-AcceptanceScript ((Get-AcceptanceScenario $candidateInput) -ceq 'CandidateFirstInstall') 'Inbox-compatible guest scenario validation rejected a correctly marked candidate.'
foreach($change in @(@{key='scenario';value='PublicUpgrade'},@{key='scenario';value='SomethingElse'},@{key='localCandidate';value=$false},@{key='workingCopyDirty';value='true'},@{key='sourceHeadCommit';value=('a' * 40)})) {
    $original=$candidateInput.($change.key)
    try {
        $candidateInput.($change.key)=$change.value
        Assert-AcceptanceScriptReject { Assert-CleanWindowsScenario $candidateInput } 'Host admitted an ambiguous candidate/public-upgrade scenario.'
        Assert-AcceptanceScriptReject { Get-AcceptanceScenario $candidateInput } 'Guest admitted an ambiguous candidate/public-upgrade scenario.'
    } finally { $candidateInput.($change.key)=$original }
}
$originalTarget=$candidateInput.target.sha256
try {
    $candidateInput.target.sha256=('b' * 64)
    Assert-AcceptanceScriptReject { Assert-CleanWindowsScenario $candidateInput } 'Host accepted non-identical first-install candidates.'
    Assert-AcceptanceScriptReject { Get-AcceptanceScenario $candidateInput } 'Guest accepted non-identical first-install candidates.'
} finally { $candidateInput.target.sha256=$originalTarget }
$publicScenario=[pscustomobject]@{baseline=[pscustomobject]@{tag='v0.2.4-preview.1'};target=[pscustomobject]@{tag='v0.2.6'}}
Assert-CleanWindowsScenario $publicScenario
Assert-AcceptanceScript ((Get-AcceptanceScenario $publicScenario) -ceq 'PublicUpgrade') 'Legacy public preparations lost their genuine upgrade scenario.'
$publicScenario.target.tag='v0.2.4-preview.2'
Assert-AcceptanceScriptReject { Assert-CleanWindowsScenario $publicScenario } 'Host allowed a synthetic equal-numeric public upgrade.'
Assert-AcceptanceScriptReject { Get-AcceptanceScenario $publicScenario } 'Guest allowed a synthetic equal-numeric public upgrade.'
$diagnosticFixture=Join-Path $root 'bounded-diagnostic.log'
[IO.File]::WriteAllText($diagnosticFixture,('A' * 32768))
$logDiagnostic=Read-AcceptanceBoundedDiagnosticFile $diagnosticFixture 16
Assert-AcceptanceScript ($logDiagnostic.present -and $logDiagnostic.bytes -eq 32768 -and $logDiagnostic.capturedBytes -eq 16 -and $logDiagnostic.truncated -and $logDiagnostic.text -ceq ('A' * 16)) 'Diagnostic log capture exceeded its requested limit or lost truncation evidence.'
$logDiagnostic=Read-AcceptanceBoundedDiagnosticFile (Join-Path $root 'absent-diagnostic.log')
Assert-AcceptanceScript (-not $logDiagnostic.present -and $logDiagnostic.capturedBytes -eq 0 -and $null -eq $logDiagnostic.readError) 'A missing pre-entrypoint Runner log masked the actual process failure.'
Assert-AcceptanceScriptReject { Read-AcceptanceBoundedDiagnosticFile $diagnosticFixture 16385 } 'Diagnostic log capture accepted an unbounded read limit.'
$exitDiagnostic=Get-AcceptanceExitDiagnostic 0
Assert-AcceptanceScript ($exitDiagnostic.observed -and $exitDiagnostic.exitCode -eq 0 -and $exitDiagnostic.unsignedExitCode -eq 0 -and $exitDiagnostic.hexExitCode -ceq '0x00000000') 'Normal exit-code diagnostics changed a verified zero exit.'
$exitDiagnostic=Get-AcceptanceExitDiagnostic (-1073741819)
Assert-AcceptanceScript ($exitDiagnostic.observed -and $exitDiagnostic.exitCode -eq -1073741819 -and $exitDiagnostic.unsignedExitCode -eq 3221225477 -and $exitDiagnostic.hexExitCode -ceq '0xC0000005') 'Native nonzero exit diagnostics lost signed/unsigned code identity.'
foreach($unobserved in @($null,$false,'0')) {
    $exitDiagnostic=Get-AcceptanceExitDiagnostic $unobserved
    Assert-AcceptanceScript (-not $exitDiagnostic.observed -and $null -eq $exitDiagnostic.unsignedExitCode -and $null -eq $exitDiagnostic.hexExitCode) 'An unavailable or non-integer process exit was converted into successful zero.'
}
$inboxPackage=[pscustomobject]@{Name='Microsoft.WindowsAppRuntime.CBS.1.6';Version='6000.900.156.100';Publisher='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US';SignatureKind=4;NonRemovable=$true;InstallLocation='C:\Windows\SystemApps\Microsoft.WindowsAppRuntime.CBS_8wekyb3d8bbwe';IsFramework=$true}
Assert-AcceptanceScript (Test-AcceptanceInboxRuntimePackage $inboxPackage) 'Verified Windows inbox CBS runtime was rejected.'
$inboxPackage.Name='Microsoft.WindowsAppRuntime.CBS.2'
$inboxPackage.InstallLocation='C:\Windows\SystemApps\Microsoft.WindowsAppRuntime.CBS.2_8wekyb3d8bbwe'
Assert-AcceptanceScript (Test-AcceptanceInboxRuntimePackage $inboxPackage) 'Verified second-generation inbox CBS runtime was rejected.'
foreach($change in @(
    @{key='InstallLocation';value='C:\Program Files\WindowsApps\Microsoft.WindowsAppRuntime.CBS.2_8wekyb3d8bbwe'},
    @{key='InstallLocation';value='C:\Windows\SystemAppsElsewhere\Microsoft.WindowsAppRuntime.CBS.2_8wekyb3d8bbwe'},
    @{key='SignatureKind';value=3},@{key='NonRemovable';value=$false},@{key='NonRemovable';value='true'},
    @{key='Publisher';value='CN=Someone Else'},@{key='Name';value='Microsoft.WindowsAppRuntime.1.6'},@{key='IsFramework';value=$false}
)) {
    $original=$inboxPackage.($change.key)
    try { $inboxPackage.($change.key)=$change.value; Assert-AcceptanceScript (-not (Test-AcceptanceInboxRuntimePackage $inboxPackage)) 'An external or unverified App Runtime was accepted as an inbox OS component.' }
    finally { $inboxPackage.($change.key)=$original }
}
$payloadRoot='C:\fixture\versions\v0.2.6'
$moduleFixtures=@([pscustomobject]@{ModuleName='Microsoft.UI.Xaml.dll';FileName=(Join-Path $payloadRoot 'Microsoft.UI.Xaml.dll')},[pscustomobject]@{ModuleName='coreclr.dll';FileName=(Join-Path $payloadRoot 'coreclr.dll')})
$modulePaths=Get-AcceptancePayloadRuntimeModules $moduleFixtures $payloadRoot
Assert-AcceptanceScript ($modulePaths.Count -eq 2 -and $modulePaths['coreclr.dll'] -ceq $moduleFixtures[1].FileName) 'Verified payload runtime module paths were not retained.'
$moduleFixtures[0].FileName='C:\Windows\SystemApps\Microsoft.WindowsAppRuntime.CBS_8wekyb3d8bbwe\Microsoft.UI.Xaml.dll'
Assert-AcceptanceScriptReject { Get-AcceptancePayloadRuntimeModules $moduleFixtures $payloadRoot } 'Manager was allowed to load WinUI from the OS instead of its version payload.'
$moduleFixtures[0].FileName=Join-Path $payloadRoot 'Microsoft.UI.Xaml.dll'
$moduleFixtures[1].FileName='C:\Program Files\dotnet\shared\coreclr.dll'
Assert-AcceptanceScriptReject { Get-AcceptancePayloadRuntimeModules $moduleFixtures $payloadRoot } 'Manager was allowed to load the machine .NET runtime.'
$moduleFixtures[1].FileName=Join-Path $payloadRoot 'coreclr.dll'
Assert-AcceptanceScriptReject { Get-AcceptancePayloadRuntimeModules @($moduleFixtures[0]) $payloadRoot } 'Manager runtime module evidence was allowed to omit coreclr.dll.'
$manualFixture=[pscustomobject]@{name='Enter AppID manually';processId=1900;automationId='SecondaryButton';enabled=$true}
Assert-AcceptanceManualAppIdAction $manualFixture 1900 1900
$cases++
$manualFixture.processId=0
Assert-AcceptanceManualAppIdAction $manualFixture 1900 1900
$cases++
$manualFixture.name=(-join @([char]0x624b,[char]0x52a8,[char]0x586b,[char]0x5199)) + ' AppID'
Assert-AcceptanceManualAppIdAction $manualFixture 1900 1900
$cases++
Assert-AcceptanceScriptReject { Assert-AcceptanceManualAppIdAction $manualFixture 1800 1900 } 'An anonymous WinUI child beneath a foreign root was accepted.'
Assert-AcceptanceScriptReject { Assert-AcceptanceManualAppIdAction $manualFixture 0 1900 } 'An unverified zero-PID root was accepted.'
$manualFixture.processId=1901
Assert-AcceptanceScriptReject { Assert-AcceptanceManualAppIdAction $manualFixture 1900 1900 } 'A nonzero foreign child process was accepted.'
$manualFixture.processId=0
foreach($change in @(@{key='name';value='Something else'},@{key='name';value='enter appid manually'},@{key='automationId';value='ForeignButton'},@{key='enabled';value=$false})) {
    $original=$manualFixture.($change.key)
    try { $manualFixture.($change.key)=$change.value; Assert-AcceptanceScriptReject { Assert-AcceptanceManualAppIdAction $manualFixture 1900 1900 } 'An unexpected or disabled manual AppID child was accepted.' }
    finally { $manualFixture.($change.key)=$original }
}
$InputDirectory=Join-Path $root 'guest-input'
$taskRoot=Join-Path $root 'guest-copy'
[IO.Directory]::CreateDirectory($InputDirectory) | Out-Null
[IO.Directory]::CreateDirectory($taskRoot) | Out-Null
foreach($guestTag in @('v0.2.4-preview.1','v0.2.6','v0.2.6-rc.1')) {
    $guestFile=Join-Path $InputDirectory ('SteamWrapper-' + $guestTag + '-win-x64-setup.exe')
    [IO.File]::WriteAllText($guestFile,'inert guest asset parser fixture')
    $guestAsset=[pscustomobject]@{tag=$guestTag;fileName=[IO.Path]::GetFileName($guestFile);bytes=(Get-Item -LiteralPath $guestFile).Length;sha256=(Get-FileHash -LiteralPath $guestFile -Algorithm SHA256).Hash.ToLowerInvariant()}
    $copied=Read-AcceptanceAsset $guestAsset
    Assert-AcceptanceScript ((Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $guestAsset.sha256) 'Guest did not preserve a stable/prerelease asset hash.'
}
$guestAsset.tag='v01.2.6'
$guestAsset.fileName='SteamWrapper-v01.2.6-win-x64-setup.exe'
Assert-AcceptanceScriptReject { Read-AcceptanceAsset $guestAsset } 'Guest accepted a leading-zero version.'
$guestAsset.tag='v0.2.6-01'
$guestAsset.fileName='SteamWrapper-v0.2.6-01-win-x64-setup.exe'
Assert-AcceptanceScriptReject { Read-AcceptanceAsset $guestAsset } 'Guest accepted a leading-zero prerelease.'

# Validate the real Execute entry before its CLI lookup. An invalid UUID is
# deliberately retained throughout, so these tests cannot reach wsb even if
# its official installation completes concurrently.
$prepared=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) ('target/winui/clean-windows-' + [Guid]::NewGuid().ToString('N'))
$preparedInput=Join-Path $prepared 'input'
[IO.Directory]::CreateDirectory($preparedInput) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $prepared 'evidence')) | Out-Null
$preparedManifest=[ordered]@{schemaVersion=1;runId=([IO.Path]::GetFileName($prepared)).Substring('clean-windows-'.Length);sandboxOnly=$true;startupMode='AfterLogin'}
foreach($pair in @(@{key='baseline';tag='v0.2.4-preview.1'},@{key='target';tag='v0.2.6'})) {
    $path=Join-Path $preparedInput ('SteamWrapper-' + $pair.tag + '-win-x64-setup.exe')
    [IO.File]::WriteAllText($path,'inert prepared asset fixture')
    $preparedManifest[$pair.key]=@{tag=$pair.tag;fileName=[IO.Path]::GetFileName($path);sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $path).Length;commit=('b' * 40)}
}
foreach($record in @(@{name='Invoke-CleanWindowsGuestAcceptance.ps1';key='guestScriptSha256'},@{name='Start-CleanWindowsAcceptance.ps1';key='launchScriptSha256'})) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $record.name) -Destination $preparedInput
    $preparedManifest[$record.key]=(Get-FileHash -LiteralPath (Join-Path $preparedInput $record.name) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$configuration=Join-Path $prepared 'acceptance.wsb'
New-CleanWindowsSandboxConfiguration $preparedInput (Join-Path $prepared 'evidence') AfterLogin | Set-Content -LiteralPath $configuration -Encoding utf8
$preparedManifest.configurationSha256=(Get-FileHash -LiteralPath $configuration -Algorithm SHA256).Hash.ToLowerInvariant()
$preparedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $preparedInput 'acceptance-input.json') -Encoding utf8
$uuidRejected=$false
try { $null=& $entry -Action Execute -PreparedRoot $prepared -SandboxId 'invalid-id' } catch { $uuidRejected=$_.Exception.Message -match 'canonical Sandbox UUID' }
Assert-AcceptanceScript $uuidRejected 'Execute did not finish prepared-file validation before refusing the explicit invalid UUID.'
foreach($changed in @($configuration,(Join-Path $preparedInput 'Start-CleanWindowsAcceptance.ps1'),(Join-Path $preparedInput 'Invoke-CleanWindowsGuestAcceptance.ps1'))) {
    $original=[IO.File]::ReadAllBytes($changed)
    try {
        [IO.File]::AppendAllText($changed,'tamper')
        $tamperRejected=$false
        try { $null=& $entry -Action Execute -PreparedRoot $prepared -SandboxId 'invalid-id' } catch { $tamperRejected=$_.Exception.Message -match 'Prepared acceptance file changed' }
        Assert-AcceptanceScript $tamperRejected 'Execute accepted changed configuration or guest scripts before CLI dispatch.'
    } finally { [IO.File]::WriteAllBytes($changed,$original) }
}
# A manifest must not select manual execution for an automatic WSB, even
# when that configuration's own byte digest has been correctly resealed.
$originalConfiguration=[IO.File]::ReadAllBytes($configuration)
try {
    New-CleanWindowsSandboxConfiguration $preparedInput (Join-Path $prepared 'evidence') LogonCommand | Set-Content -LiteralPath $configuration -Encoding utf8
    $preparedManifest.configurationSha256=(Get-FileHash -LiteralPath $configuration -Algorithm SHA256).Hash.ToLowerInvariant()
    $preparedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $preparedInput 'acceptance-input.json') -Encoding utf8
    $modeRejected=$false
    try { $null=& $entry -Action Execute -PreparedRoot $prepared -SandboxId 'invalid-id' } catch { $modeRejected=$_.Exception.Message -match 'configuration does not match' }
    Assert-AcceptanceScript $modeRejected 'Execute accepted a sealed automatic WSB under an AfterLogin manifest.'
} finally {
    [IO.File]::WriteAllBytes($configuration,$originalConfiguration)
    $preparedManifest.configurationSha256=(Get-FileHash -LiteralPath $configuration -Algorithm SHA256).Hash.ToLowerInvariant()
    $preparedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $preparedInput 'acceptance-input.json') -Encoding utf8
}
# The reverse mismatch and a correctly resealed sharing change must likewise
# be rejected by semantic validation before any Sandbox CLI lookup.
try {
    $preparedManifest.startupMode='LogonCommand'
    $preparedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $preparedInput 'acceptance-input.json') -Encoding utf8
    $modeRejected=$false
    try { $null=& $entry -Action Execute -PreparedRoot $prepared -SandboxId 'invalid-id' } catch { $modeRejected=$_.Exception.Message -match 'configuration does not match' }
    Assert-AcceptanceScript $modeRejected 'An automatic manifest accepted a WSB with no automatic guest command.'
    $preparedManifest.startupMode='AfterLogin'
    $sharedConfiguration=(New-CleanWindowsSandboxConfiguration $preparedInput (Join-Path $prepared 'evidence') AfterLogin).Replace('<ClipboardRedirection>Disable</ClipboardRedirection>','<ClipboardRedirection>Enable</ClipboardRedirection>')
    $sharedConfiguration | Set-Content -LiteralPath $configuration -Encoding utf8
    $preparedManifest.configurationSha256=(Get-FileHash -LiteralPath $configuration -Algorithm SHA256).Hash.ToLowerInvariant()
    $preparedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $preparedInput 'acceptance-input.json') -Encoding utf8
    $sharingRejected=$false
    try { $null=& $entry -Action Execute -PreparedRoot $prepared -SandboxId 'invalid-id' } catch { $sharingRejected=$_.Exception.Message -match 'configuration does not match' }
    Assert-AcceptanceScript $sharingRejected 'A resealed WSB widened sharing outside its prepared isolation policy.'
} finally {
    [IO.File]::WriteAllBytes($configuration,$originalConfiguration)
    $preparedManifest.startupMode='AfterLogin'
    $preparedManifest.configurationSha256=(Get-FileHash -LiteralPath $configuration -Algorithm SHA256).Hash.ToLowerInvariant()
    $preparedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $preparedInput 'acceptance-input.json') -Encoding utf8
}
# Mapped evidence must not escape through a junction. The outside destination
# is another disposable fixture, never a user directory or real installation.
$evidenceDirectory=Join-Path $prepared 'evidence'
$outsideEvidence=Join-Path $root 'junction-output'
[IO.Directory]::CreateDirectory($outsideEvidence) | Out-Null
[IO.Directory]::Delete($evidenceDirectory)
try {
    New-Item -ItemType Junction -Path $evidenceDirectory -Target $outsideEvidence | Out-Null
    $linkRejected=$false
    try { $null=& $entry -Action Execute -PreparedRoot $prepared -SandboxId 'invalid-id' } catch { $linkRejected=$_.Exception.Message -match 'paths must not contain links' }
    Assert-AcceptanceScript $linkRejected 'Execute accepted an evidence directory redirected outside its dedicated run root.'
} finally {
    if ((Get-Item -LiteralPath $evidenceDirectory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($evidenceDirectory) }
    [IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
}
# Execute the actual wrapper under inbox PowerShell: its host refusal must
# happen before mapped-path access, logging, guest execution or Setup.
$wrapperOutput = & powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Start-CleanWindowsAcceptance.ps1') 2>&1 | Out-String
Assert-AcceptanceScript ($LASTEXITCODE -ne 0 -and $wrapperOutput -match 'only in the dedicated interactive Windows Sandbox') 'The after-login wrapper did not refuse the development host.'
$guestHostOutput = & powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1') 2>&1 | Out-String
Assert-AcceptanceScript ($LASTEXITCODE -ne 0 -and $guestHostOutput -match 'only for Windows Sandbox WDAGUtilityAccount') 'The guest acceptance script did not refuse the development host before reading mapped paths.'
$guestOutput = & powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1') -ValidateHelpers 2>&1 | Out-String
Assert-AcceptanceScript ($LASTEXITCODE -eq 0 -and ($guestOutput | ConvertFrom-Json).productionInstallerExecuted -eq $false) 'Inbox PowerShell helpers failed or claimed installer execution.'
$helperResult=$guestOutput | ConvertFrom-Json
Assert-AcceptanceScript ($helperResult.processExitObservation.expectedExitCode -eq 7 -and $helperResult.processExitObservation.retainedExitCode -eq 7 -and $helperResult.processExitObservation.originalExitCode -eq 7) 'Retained inbox Framework process observation did not preserve the harmless child actual exit code.'
[ordered]@{ passed=$true; cases=$cases; productionInstallerExecuted=$false; sandboxExecuted=$false; actualSandboxCliTested=$false; cleanWindowsClient=$false; outputRoot=$root } | ConvertTo-Json
