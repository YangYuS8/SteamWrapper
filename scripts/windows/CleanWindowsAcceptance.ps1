# Host-only pure helpers. Importing this file does not launch Sandbox or Setup.
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')
. (Join-Path $PSScriptRoot 'WinUIInstallableRelease.ps1')

function Get-CleanWindowsScenario($Manifest) {
    $property=$Manifest.PSObject.Properties['scenario']
    if ($null -eq $property) { return 'PublicUpgrade' }
    if ($property.Value -cnotin @('PublicUpgrade','CandidateFirstInstall','CandidateUpgrade')) { throw 'Unexpected clean Windows acceptance scenario.' }
    return [string]$property.Value
}
function Assert-CleanWindowsScenario($Manifest) {
    $scenario=Get-CleanWindowsScenario $Manifest
    if ($scenario -ceq 'PublicUpgrade') {
        if ($null -ne $Manifest.PSObject.Properties['localCandidate'] -and ($Manifest.localCandidate -isnot [bool] -or $Manifest.localCandidate)) { throw 'Public upgrade cannot use a local candidate.' }
        $baseline=Get-WinUIReleaseTag $Manifest.baseline.tag
        $target=Get-WinUIReleaseTag $Manifest.target.tag
        if ([Version]$target.Version -le [Version]$baseline.Version) { throw 'Acceptance requires a genuine newer numeric product version.' }
    } else {
        if ($Manifest.localCandidate -isnot [bool] -or -not $Manifest.localCandidate -or $Manifest.sourceHeadCommit -cnotmatch '^[a-f0-9]{40}$' -or
            $Manifest.workingCopyDirty -isnot [bool] -or $Manifest.sourceHeadCommit -cne $Manifest.target.commit) { throw 'Candidate first install requires explicit local source provenance.' }
        if ($scenario -ceq 'CandidateFirstInstall') {
            foreach ($key in @('tag','fileName','bytes','sha256','commit')) {
                if ($Manifest.baseline.$key -cne $Manifest.target.$key) { throw 'Candidate first install requires two identical candidate identities.' }
            }
        } else {
            if ([Version](Get-WinUIReleaseTag $Manifest.target.tag).Version -le [Version](Get-WinUIReleaseTag $Manifest.baseline.tag).Version -or
                $Manifest.baselinePublicReleaseSha256 -cnotmatch '^[a-f0-9]{64}$' -or $Manifest.baselinePublicApiSha256 -cnotmatch '^[a-f0-9]{64}$') {
                throw 'Candidate upgrade requires a genuinely older, sealed public baseline.'
            }
        }
    }
}
function Assert-CleanWindowsEvidenceScope($Manifest, $Evidence) {
    if ($null -eq $Manifest.PSObject.Properties['scenario']) { return }
    $scenario=Get-CleanWindowsScenario $Manifest
    $candidate=$scenario -cne 'PublicUpgrade'
    $upgrade=$scenario -cne 'CandidateFirstInstall'
    if ($Evidence.scenario -cne $scenario -or $Evidence.localCandidate -isnot [bool] -or $Evidence.localCandidate -ne $candidate -or
        $Evidence.unpublishedCandidate -isnot [bool] -or $Evidence.unpublishedCandidate -ne $candidate -or
        $Evidence.numericUpgradeTested -isnot [bool] -or $Evidence.numericUpgradeTested -ne $upgrade) {
        throw 'Guest evidence does not match the prepared candidate/public-upgrade scope.'
    }
    if ($candidate -and ($Evidence.sourceHeadCommit -cne $Manifest.sourceHeadCommit -or $Evidence.workingCopyDirty -isnot [bool] -or $Evidence.workingCopyDirty -ne $Manifest.workingCopyDirty)) {
        throw 'Guest candidate evidence differs from its recorded local source provenance.'
    }
    if ($scenario -ceq 'CandidateUpgrade' -and ($Evidence.baselinePublic -isnot [bool] -or -not $Evidence.baselinePublic -or
        $Evidence.stableRunnerUpdated -isnot [bool] -or -not $Evidence.stableRunnerUpdated -or
        $Evidence.baselineRunnerOperationalTested -isnot [bool] -or $Evidence.baselineRunnerOperationalTested)) {
        throw 'Candidate upgrade must verify the new stable Runner without claiming an operational baseline test.'
    }
}
function Read-CleanWindowsCandidateInstaller([string]$Directory, [string]$Tag) {
    $directory=Assert-WinUIReleasePath $Directory ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../target/winui')))
    Assert-CleanWindowsPreparedDirectory $directory
    $identity=Get-WinUIReleaseTag $Tag
    $build=ConvertFrom-WinUIInstallableJson (Read-WinUIReleaseText (Join-Path $directory 'installer-build.json') $directory)
    Assert-WinUIInstallableBuildIdentity $build $Tag $identity.Version
    $name='SteamWrapper-' + $Tag + '-win-x64-setup.exe'
    $null=Assert-WinUIReleasePath (Join-Path $directory $name) $directory
    Assert-WinUIInstallableAsset $build.installer $name $directory 512MB -BuildRecord
    $manifestPath=Join-Path $directory 'deployment-manifest.json'
    $manifestText=Read-WinUIReleaseText $manifestPath $directory 1MB
    $manifest=ConvertFrom-WinUIInstallableJson $manifestText
    $embedded=[pscustomobject]@{bytes=(Get-Item -LiteralPath $manifestPath).Length;sha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant();json=$manifestText}
    $metadata=[pscustomobject]@{tag=$Tag;version=$identity.Version;installerBuild=$build;installerAsset=$build.installer;deploymentManifest=$embedded}
    Assert-WinUIInstallableBinding $metadata ([pscustomobject]@{files=$manifest.files})
    $required=@(Get-WinUIReleaseRequiredFiles)
    foreach($file in $required) { if ($file -notin @($manifest.files.path)) { throw 'Candidate deployment manifest omits a required self-contained payload file.' } }
    return [pscustomobject]@{tag=$Tag;version=$identity.Version;installerAsset=$build.installer;directory=$directory;build=$build;deploymentManifest=$embedded}
}

function Get-CleanWindowsStartupMode($Manifest) {
    $property = $Manifest.PSObject.Properties['startupMode']
    if ($null -eq $property) { return 'LogonCommand' }
    if ($property.Value -cnotin @('LogonCommand', 'AfterLogin')) { throw 'Unexpected acceptance startup mode.' }
    return [string]$property.Value
}

function Assert-CleanWindowsAcceptanceAsset($Asset) {
    $null = Get-WinUIReleaseTag ([string]$Asset.tag)
    if ($Asset.fileName -cne ('SteamWrapper-' + $Asset.tag + '-win-x64-setup.exe') -or
        $Asset.sha256 -isnot [string] -or $Asset.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        ($Asset.bytes -isnot [int] -and $Asset.bytes -isnot [long]) -or $Asset.bytes -lt 1 -or $Asset.bytes -gt 512MB -or
        $Asset.commit -isnot [string] -or $Asset.commit -cnotmatch '^[a-f0-9]{40}$') {
        throw 'Unexpected acceptance installer identity, size or digest.'
    }
}

function Assert-CleanWindowsPublicRelease($State, [string]$Tag) {
    $identity = Get-WinUIReleaseTag $Tag
    $names = @("SteamWrapper-$Tag-win-x64-setup.exe", "SteamWrapper-$Tag-win-x64.zip", 'portable-release.json', 'release.json', 'SHA256SUMS', "$Tag.en.md", "$Tag.zh-CN.md")
    if ($State.tagName -cne $Tag -or $State.isDraft -isnot [bool] -or $State.isDraft -or
        $State.isPrerelease -isnot [bool] -or $State.isPrerelease -ne $identity.Prerelease -or @($State.assets).Count -ne 7 -or
        @($State.assets.name | Sort-Object -Unique).Count -ne 7 -or @($State.assets.name | Where-Object { $_ -cnotin $names }).Count) {
        throw 'Expected the complete public seven-asset release with the matching tag channel.'
    }
}

function Assert-CleanWindowsPublicInstaller($Metadata, $SetupAsset, [string]$Tag, [string]$Commit) {
    $identity = Get-WinUIReleaseTag $Tag
    if ($Metadata.schemaVersion -ne 2 -or $Metadata.tag -cne $Tag -or $Metadata.version -cne $identity.Version -or
        $Commit -cnotmatch '^[a-f0-9]{40}$' -or $Metadata.commit -cne $Commit -or $Metadata.platform -cne 'win-x64' -or
        $Metadata.releaseChannel -cne $identity.Channel -or $Metadata.tagPrerelease -isnot [bool] -or $Metadata.tagPrerelease -ne $identity.Prerelease -or
        $Metadata.githubPrerelease -isnot [bool] -or $Metadata.githubPrerelease -ne $identity.Prerelease -or $Metadata.installer -isnot [bool] -or -not $Metadata.installer -or
        $Metadata.installerAsset.fileName -cne ('SteamWrapper-' + $Tag + '-win-x64-setup.exe') -or $Metadata.installerAsset.fileName -cne $SetupAsset.name -or
        $Metadata.installerAsset.bytes -ne $SetupAsset.size -or ('sha256:' + $Metadata.installerAsset.sha256) -cne $SetupAsset.digest -or
        $Metadata.installerBuild.isolated -isnot [bool] -or $Metadata.installerBuild.isolated -or
        $Metadata.installerBuild.tag -cne $Tag -or $Metadata.installerBuild.version -cne $identity.Version -or $Metadata.installerBuild.platform -cne 'win-x64') {
        throw 'The public production installer descriptor, build or tag identity differ.'
    }
    foreach ($key in @('fileName', 'bytes', 'sha256')) {
        if ($Metadata.installerBuild.installer.$key -cne $Metadata.installerAsset.$key) { throw 'The sealed installer build differs from the public Setup asset.' }
    }
}

function New-CleanWindowsSandboxConfiguration([string]$InputRoot, [string]$OutputRoot, [string]$StartupMode) {
    if ($StartupMode -cnotin @('LogonCommand', 'AfterLogin')) { throw 'Unexpected acceptance startup mode.' }
    $inputXml = [Security.SecurityElement]::Escape($InputRoot)
    $outputXml = [Security.SecurityElement]::Escape($OutputRoot)
    $logon = ''
    if ($StartupMode -ceq 'LogonCommand') {
        # Preserve the existing default command. The explicit alternative waits
        # for an established desktop and invokes the guarded wrapper via wsb.
        $command = 'powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -Command "& ''C:\AcceptanceInput\Invoke-CleanWindowsGuestAcceptance.ps1'' *> ''C:\AcceptanceOutput\guest-launch.log''"'
        $logon = '  <LogonCommand><Command>' + [Security.SecurityElement]::Escape($command) + '</Command></LogonCommand>'
    }
    return @"
<Configuration>
  <vGPU>Disable</vGPU>
  <MemoryInMB>8192</MemoryInMB>
  <Networking>Disable</Networking>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <MappedFolders>
    <MappedFolder><HostFolder>$inputXml</HostFolder><SandboxFolder>C:\AcceptanceInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$outputXml</HostFolder><SandboxFolder>C:\AcceptanceOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
$logon
</Configuration>
"@
}

function Assert-CleanWindowsSandboxConfiguration([string]$Path, [string]$InputRoot, [string]$OutputRoot, [string]$StartupMode) {
    # A correctly sealed WSB can still disagree with its manifest's startup
    # choice or mappings. Compare the parsed configuration with our fixed
    # preparation, ignoring formatting but retaining every setting/element.
    $actual = [xml](Get-Content -LiteralPath $Path -Raw)
    $expected = [xml](New-CleanWindowsSandboxConfiguration $InputRoot $OutputRoot $StartupMode)
    if ($actual.OuterXml -cne $expected.OuterXml) { throw 'Prepared acceptance configuration does not match its startup mode, mappings or isolation settings.' }
}

function Assert-CleanWindowsPreparedDirectory([string]$Path) {
    $current = Get-Item -LiteralPath $Path -Force
    if (-not $current.PSIsContainer) { throw 'Expected a prepared acceptance directory.' }
    while ($null -ne $current) {
        if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Sandbox acceptance paths must not contain links.' }
        $current = $current.Parent
    }
}

function Assert-CleanWindowsPreparedFile([string]$Path, [string]$Hash, [long]$Bytes = -1) {
    if ($Hash -cnotmatch '^[a-f0-9]{64}$') { throw 'Unexpected prepared-file digest.' }
    $current = Get-Item -LiteralPath $Path -Force
    if ($current.PSIsContainer -or ($Bytes -ge 0 -and $current.Length -ne $Bytes)) { throw 'Prepared acceptance file type or size changed.' }
    if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Prepared acceptance files must not contain links.' }
    $current = Get-Item -LiteralPath ([IO.Path]::GetDirectoryName($current.FullName)) -Force
    while ($null -ne $current) {
        if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Prepared acceptance files must not contain links.' }
        $current = $current.Parent
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Hash) { throw 'Prepared acceptance file changed.' }
}

function Get-CleanWindowsExecuteArguments($Manifest, [string]$SandboxId) {
    if ((Get-CleanWindowsStartupMode $Manifest) -cne 'AfterLogin') { throw 'Execute requires a fresh AfterLogin preparation.' }
    if ($SandboxId -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') { throw 'Execute requires an explicit canonical Sandbox UUID from wsb list.' }
    if ($null -eq $Manifest.PSObject.Properties['launchScriptSha256'] -or $Manifest.launchScriptSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Execute requires the verified guest launch wrapper.' }
    $command = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -File C:\AcceptanceInput\Start-CleanWindowsAcceptance.ps1'
    return @('exec', '--id', $SandboxId, '--command', $command, '--run-as', 'ExistingLogin', '--working-directory', 'C:\AcceptanceInput', '--raw')
}

function Assert-CleanWindowsExecuteResult([string]$Raw, [int]$CliExitCode) {
    if ($CliExitCode -ne 0) { throw 'Windows Sandbox CLI execution failed. Keep its session and logs for diagnosis; no process was killed.' }
    try { $response = ConvertFrom-Json -InputObject $Raw -ErrorAction Stop }
    catch { throw 'Windows Sandbox CLI did not return a raw JSON guest exit result.' }
    $property = if ($null -ne $response) { $response.PSObject.Properties['ExitCode'] } else { $null }
    if ($null -eq $property -or ($property.Value -isnot [int] -and $property.Value -isnot [long]) -or $property.Value -ne 0) {
        throw 'Guest execution did not report an integer zero ExitCode. Keep its session and logs for diagnosis; no process was killed.'
    }
}
