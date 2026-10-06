[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'Launch', 'Execute', 'ReadEvidence')][string]$Action = 'Prepare',
    [ValidateSet('LogonCommand', 'AfterLogin')][string]$StartupMode = 'LogonCommand',
    [string]$SandboxId,
    [string]$PreparedRoot,
    [string]$BaselineTag = 'v0.2.4-preview.1',
    [string]$Tag = 'v0.2.5-preview.1',
    [string]$BaselineInstallerPath,
    [string]$InstallerPath,
    [string]$CandidateInstallerDirectory,
    [string]$TrustPath = (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json'),
    [string]$GhExecutable = 'gh'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Windows Sandbox acceptance requires a Windows host.' }
. (Join-Path $PSScriptRoot 'CleanWindowsAcceptance.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$prefix = Join-Path $repo 'target/winui/clean-windows-'

function Resolve-AcceptanceRoot([string]$Value) {
    $full = [IO.Path]::GetFullPath($Value)
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        $full.Substring($prefix.Length) -notmatch '^[a-f0-9]{32}$') {
        throw 'Expected a dedicated target/winui/clean-windows-<run-id> directory.'
    }
    $current = Get-Item -LiteralPath $full
    while ($null -ne $current) {
        if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Sandbox acceptance paths must not contain links.' }
        $current = $current.Parent
    }
    return $full
}
function Invoke-AcceptanceGh([string[]]$Arguments) {
    $global:LASTEXITCODE = 0
    $output = & $GhExecutable @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw ('GitHub acceptance command failed: ' + ($Arguments[0..1] -join ' ')) }
    if ([Text.Encoding]::UTF8.GetByteCount($output) -gt 2MB) { throw 'Public acceptance API response exceeds its bounded limit.' }
    return $output.Trim()
}
function Get-PublicRelease([string]$ReleaseTag, [string]$Directory, [string]$CachedInstaller, [switch]$BaselineOnly) {
    $identity=Get-WinUIReleaseTag $ReleaseTag
    if ([Version]$identity.Version -ge [Version]'0.2.8') {
        $remoteCommit=Invoke-AcceptanceGh @('api', "repos/YangYuS8/SteamWrapper/commits/$ReleaseTag", '--jq', '.sha')
        $stateText=Invoke-AcceptanceGh @('api', "repos/YangYuS8/SteamWrapper/releases/tags/$ReleaseTag", '--method', 'GET')
        $state=ConvertFrom-WinUIInstallableJson $stateText
        [IO.Directory]::CreateDirectory($Directory) | Out-Null
        $options=@{ReleaseState=$state;Tag=$ReleaseTag;Commit=$remoteCommit}
        if ($BaselineOnly) {$options.BaselineOnly=$true} else {
            $envelope=Join-Path $Directory 'SteamWrapper-update.json'
            $null=Invoke-AcceptanceGh @('release','download',('update-' + $identity.Channel),'--repo','YangYuS8/SteamWrapper','--pattern','SteamWrapper-update.json','--dir',$Directory)
            $options.EnvelopePath=$envelope; $options.TrustPath=$TrustPath
        }
        $metadata=New-WinUIPublicInstallerDescriptor @options
        $setupAsset=@($state.assets | Where-Object name -CEQ $metadata.installerAsset.fileName)[0]
        $setupPath=Join-Path $Directory $setupAsset.name
        if ($CachedInstaller) {
            $cached=Get-Item -LiteralPath $CachedInstaller
            if ($cached.PSIsContainer -or ($cached.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'A cached public installer must be a regular file.'}
            Copy-Item -LiteralPath $cached.FullName -Destination $setupPath
        } else {$null=Invoke-AcceptanceGh @('release','download',$ReleaseTag,'--repo','YangYuS8/SteamWrapper','--pattern',$setupAsset.name,'--dir',$Directory)}
        Assert-CleanWindowsPreparedFile $setupPath $metadata.installerAsset.sha256 $metadata.installerAsset.bytes
        if ((Invoke-AcceptanceGh @('api', "repos/YangYuS8/SteamWrapper/commits/$ReleaseTag", '--jq', '.sha')) -cne $remoteCommit) {throw 'Public acceptance tag moved during download.'}
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Directory 'public-installer.json') -Encoding utf8NoBOM
        $stateText | Set-Content -LiteralPath (Join-Path $Directory 'public-api.json') -Encoding utf8NoBOM
        $metadata | Add-Member acceptancePublicApi $state
        return $metadata
    }
    $state = Invoke-AcceptanceGh @('release', 'view', $ReleaseTag, '--repo', 'YangYuS8/SteamWrapper', '--json', 'tagName,isDraft,isPrerelease,assets') | ConvertFrom-Json
    Assert-CleanWindowsPublicRelease $state $ReleaseTag
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $selected = @($state.assets | Where-Object { $_.name -ceq "SteamWrapper-$ReleaseTag-win-x64-setup.exe" -or $_.name -ceq 'release.json' })
    foreach ($asset in $selected) {
        $path = Join-Path $Directory $asset.name
        $limit = if ($asset.name -ceq 'release.json') { 2MB } else { 512MB }
        if ($asset.size -lt 1 -or $asset.size -gt $limit -or $asset.digest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'The public acceptance asset has an invalid size or digest.' }
        if ($CachedInstaller -and $asset.name -cne 'release.json') {
            $cached = Get-Item -LiteralPath $CachedInstaller
            if ($cached.PSIsContainer -or ($cached.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'A cached public installer must be a regular file.' }
            Copy-Item -LiteralPath $cached.FullName -Destination $path
        } else {
            $null = Invoke-AcceptanceGh @('release', 'download', $ReleaseTag, '--repo', 'YangYuS8/SteamWrapper', '--pattern', $asset.name, '--dir', $Directory)
        }
        if ($asset.digest -notmatch '^sha256:[a-f0-9]{64}$' -or (Get-Item -LiteralPath $path).Length -ne $asset.size -or
            ('sha256:' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) -cne $asset.digest) { throw 'Public release download does not match the GitHub asset digest and size.' }
    }
    # This gate executes Setup, not the portable ZIP. Its bytes and descriptor
    # are pinned to the public API; full seven-asset inspection is release CI.
    $metadata = Get-Content -LiteralPath (Join-Path $Directory 'release.json') -Raw | ConvertFrom-Json
    $remoteCommit = Invoke-AcceptanceGh @('api', "repos/YangYuS8/SteamWrapper/commits/$ReleaseTag", '--jq', '.sha')
    $setupAsset = @($selected | Where-Object name -CNE 'release.json')[0]
    Assert-CleanWindowsPublicInstaller $metadata $setupAsset $ReleaseTag $remoteCommit
    $metadata | Add-Member -NotePropertyName acceptancePublicApi -NotePropertyValue $state
    return $metadata
}
function Assert-PreparedInput([string]$Root, $Manifest) {
    if ($Manifest.schemaVersion -ne 1 -or -not $Manifest.sandboxOnly -or $Manifest.runId -cne ([IO.Path]::GetFileName($Root)).Substring('clean-windows-'.Length)) { throw 'Unexpected acceptance manifest identity.' }
    Assert-CleanWindowsPreparedDirectory (Join-Path $Root 'evidence')
    foreach ($item in @($Manifest.baseline, $Manifest.target)) {
        Assert-CleanWindowsAcceptanceAsset $item
        $path = Join-Path (Join-Path $Root 'input') $item.fileName
        Assert-CleanWindowsPreparedFile $path $item.sha256 $item.bytes
    }
    Assert-CleanWindowsScenario $Manifest
    if ((Get-CleanWindowsScenario $Manifest) -cne 'PublicUpgrade') {
        Assert-CleanWindowsPreparedFile (Join-Path $Root 'input/installer-build.json') $Manifest.candidateBuildSha256
        Assert-CleanWindowsPreparedFile (Join-Path $Root 'input/deployment-manifest.json') $Manifest.candidateDeploymentManifestSha256
        $candidate=Read-CleanWindowsCandidateInstaller (Join-Path $Root 'input') $Manifest.target.tag
        foreach($key in @('fileName','bytes','sha256')) { if ($candidate.installerAsset.$key -cne $Manifest.target.$key) { throw 'Prepared candidate differs from its sealed installer build.' } }
    }
    if ((Get-CleanWindowsScenario $Manifest) -ceq 'CandidateUpgrade') {
        Assert-CleanWindowsSealedPublicRecord -Root $Root -Manifest $Manifest -Role baseline -TrustPath $TrustPath
    }
    foreach($role in @('baseline','target')) {
        if ($null -ne $Manifest.PSObject.Properties[$role + 'PublicAssetLayout'] -and -not ($role -ceq 'baseline' -and (Get-CleanWindowsScenario $Manifest) -ceq 'CandidateUpgrade')) {Assert-CleanWindowsSealedPublicRecord -Root $Root -Manifest $Manifest -Role $role -TrustPath $TrustPath}
    }
    $script = Join-Path $Root 'input/Invoke-CleanWindowsGuestAcceptance.ps1'
    Assert-CleanWindowsPreparedFile $script $Manifest.guestScriptSha256
    $mode = Get-CleanWindowsStartupMode $Manifest
    if ($mode -ceq 'AfterLogin' -or $null -ne $Manifest.PSObject.Properties['launchScriptSha256']) {
        Assert-CleanWindowsPreparedFile (Join-Path $Root 'input/Start-CleanWindowsAcceptance.ps1') $Manifest.launchScriptSha256
    }
    if ($mode -ceq 'AfterLogin' -or $null -ne $Manifest.PSObject.Properties['configurationSha256']) {
        Assert-CleanWindowsPreparedFile (Join-Path $Root 'acceptance.wsb') $Manifest.configurationSha256
    }
    Assert-CleanWindowsSandboxConfiguration (Join-Path $Root 'acceptance.wsb') (Join-Path $Root 'input') (Join-Path $Root 'evidence') $mode
}

if ($Action -eq 'Prepare') {
    if ($PreparedRoot) { throw 'Prepare creates a fresh acceptance directory; do not provide PreparedRoot.' }
    if ($SandboxId) { throw 'Prepare does not execute an existing Sandbox.' }
    $targetIdentity = Get-WinUIReleaseTag $Tag
    $candidateUpgrade=[bool]$CandidateInstallerDirectory -and $PSBoundParameters.ContainsKey('BaselineTag')
    if ($CandidateInstallerDirectory) {
        if (-not $PSBoundParameters.ContainsKey('Tag') -or $InstallerPath -or ($BaselineInstallerPath -and -not $candidateUpgrade)) { throw 'A candidate requires an explicit Tag; a cached public baseline also requires an explicit BaselineTag.' }
        $candidate=Read-CleanWindowsCandidateInstaller $CandidateInstallerDirectory $Tag
        if ($candidateUpgrade -and [Version]$targetIdentity.Version -le [Version](Get-WinUIReleaseTag $BaselineTag).Version) { throw 'Candidate upgrade requires a genuine newer numeric product version.' }
        $sourceHead=(& git -C $repo rev-parse HEAD | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $sourceHead -cnotmatch '^[a-f0-9]{40}$') { throw 'Cannot record the exact local candidate source HEAD.' }
        $dirtyStatus=& git -C $repo status --porcelain
        if ($LASTEXITCODE -ne 0) { throw 'Cannot record the candidate working-copy state.' }
        $workingCopyDirty=@($dirtyStatus).Count -ne 0
    } else {
        $baselineIdentity = Get-WinUIReleaseTag $BaselineTag
        if ([Version]$targetIdentity.Version -le [Version]$baselineIdentity.Version) { throw 'Acceptance requires a genuine newer numeric product version.' }
    }
    $runId = [Guid]::NewGuid().ToString('N')
    $root = $prefix + $runId
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $root = Resolve-AcceptanceRoot $root
    $inputRoot = Join-Path $root 'input'
    $outputRoot = Join-Path $root 'evidence'
    [IO.Directory]::CreateDirectory($inputRoot) | Out-Null
    [IO.Directory]::CreateDirectory($outputRoot) | Out-Null
    $baselineDirectory = Join-Path $root 'packages/baseline'
    $targetDirectory = Join-Path $root 'packages/target'
    if ($CandidateInstallerDirectory) {
        $targetDirectory=$candidate.directory
        $target=[pscustomobject]@{tag=$Tag;version=$candidate.version;commit=$sourceHead;installerAsset=$candidate.installerAsset}
        if ($candidateUpgrade) {
            $baseline=Get-PublicRelease $BaselineTag $baselineDirectory $BaselineInstallerPath -BaselineOnly
        } else {
            $baselineDirectory=$candidate.directory; $BaselineTag=$Tag; $baseline=$target
        }
    } else {
        $baseline = Get-PublicRelease $BaselineTag $baselineDirectory $BaselineInstallerPath -BaselineOnly
        $target = Get-PublicRelease $Tag $targetDirectory $InstallerPath
        if ([Version]$target.version -le [Version]$baseline.version) { throw 'Acceptance requires a genuine newer numeric product version.' }
    }
    $guest = Join-Path $inputRoot 'Invoke-CleanWindowsGuestAcceptance.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1') -Destination $guest
    $wrapper = Join-Path $inputRoot 'Start-CleanWindowsAcceptance.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-CleanWindowsAcceptance.ps1') -Destination $wrapper
    Copy-Item -LiteralPath (Join-Path $baselineDirectory $baseline.installerAsset.fileName) -Destination $inputRoot
    if ($target.installerAsset.fileName -cne $baseline.installerAsset.fileName) { Copy-Item -LiteralPath (Join-Path $targetDirectory $target.installerAsset.fileName) -Destination $inputRoot }
    $manifest = [ordered]@{
        schemaVersion = 1; runId = $runId; sandboxOnly = $true; hostComputerName = $env:COMPUTERNAME
        hostBuild = (Get-CimInstance Win32_OperatingSystem).BuildNumber; preparedAt = [DateTimeOffset]::UtcNow.ToString('O')
        networkingDisabled = $true; startupMode = $StartupMode
        scenario = $(if ($candidateUpgrade) {'CandidateUpgrade'} elseif ($CandidateInstallerDirectory) {'CandidateFirstInstall'} else {'PublicUpgrade'}); localCandidate = [bool]$CandidateInstallerDirectory
        guestScriptSha256 = (Get-FileHash -LiteralPath $guest -Algorithm SHA256).Hash.ToLowerInvariant()
        launchScriptSha256 = (Get-FileHash -LiteralPath $wrapper -Algorithm SHA256).Hash.ToLowerInvariant()
        baseline = @{ tag = $BaselineTag; fileName = $baseline.installerAsset.fileName; sha256 = $baseline.installerAsset.sha256; bytes = $baseline.installerAsset.bytes; commit = $baseline.commit }
        target = @{ tag = $Tag; fileName = $target.installerAsset.fileName; sha256 = $target.installerAsset.sha256; bytes = $target.installerAsset.bytes; commit = $target.commit }
    }
    if ($CandidateInstallerDirectory) {
        $manifest.sourceHeadCommit=$sourceHead; $manifest.workingCopyDirty=$workingCopyDirty; $manifest.candidateInstallerBuild=$candidate.build
        foreach($file in @('installer-build.json','deployment-manifest.json')) { Copy-Item -LiteralPath (Join-Path $candidate.directory $file) -Destination $inputRoot }
        $manifest.candidateBuildSha256=(Get-FileHash -LiteralPath (Join-Path $inputRoot 'installer-build.json')).Hash.ToLowerInvariant()
        $manifest.candidateDeploymentManifestSha256=(Get-FileHash -LiteralPath (Join-Path $inputRoot 'deployment-manifest.json')).Hash.ToLowerInvariant()
        if ($candidateUpgrade) {
            if ($null -eq $baseline.PSObject.Properties['publicAssetLayout']) {
                Copy-Item -LiteralPath (Join-Path $baselineDirectory 'release.json') -Destination (Join-Path $inputRoot 'baseline-release.json')
                $baseline.acceptancePublicApi | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $inputRoot 'baseline-api.json') -Encoding utf8
                $manifest.baselinePublicReleaseSha256=(Get-FileHash -LiteralPath (Join-Path $inputRoot 'baseline-release.json')).Hash.ToLowerInvariant()
                $manifest.baselinePublicApiSha256=(Get-FileHash -LiteralPath (Join-Path $inputRoot 'baseline-api.json')).Hash.ToLowerInvariant()
            }
        }
    }
    foreach($entry in @(@{role='baseline';metadata=$baseline;directory=$baselineDirectory},@{role='target';metadata=$target;directory=$targetDirectory})) {
        if ($null -eq $entry.metadata.PSObject.Properties['publicAssetLayout']) {continue}
        $role=$entry.role
        $manifest[$role + 'PublicAssetLayout']=3
        Copy-Item -LiteralPath (Join-Path $entry.directory 'public-installer.json') -Destination (Join-Path $inputRoot "$role-public-installer.json")
        Copy-Item -LiteralPath (Join-Path $entry.directory 'public-api.json') -Destination (Join-Path $inputRoot "$role-api.json")
        $manifest[$role + 'PublicReleaseSha256']=(Get-FileHash -LiteralPath (Join-Path $inputRoot "$role-public-installer.json")).Hash.ToLowerInvariant()
        $manifest[$role + 'PublicApiSha256']=(Get-FileHash -LiteralPath (Join-Path $inputRoot "$role-api.json")).Hash.ToLowerInvariant()
        if ($role -ceq 'target') {
            Copy-Item -LiteralPath (Join-Path $entry.directory 'SteamWrapper-update.json') -Destination (Join-Path $inputRoot 'target-signed-update.json')
            $manifest.targetPublicEnvelopeSha256=(Get-FileHash -LiteralPath (Join-Path $inputRoot 'target-signed-update.json')).Hash.ToLowerInvariant()
        }
    }
    New-CleanWindowsSandboxConfiguration $inputRoot $outputRoot $StartupMode | Set-Content -LiteralPath (Join-Path $root 'acceptance.wsb') -Encoding utf8
    $manifest.configurationSha256 = (Get-FileHash -LiteralPath (Join-Path $root 'acceptance.wsb') -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $inputRoot 'acceptance-input.json') -Encoding utf8
    Assert-PreparedInput $root ([pscustomobject]$manifest)
    Write-Output "Prepared $($manifest.scenario) installers and isolated Sandbox configuration: $root"
    Write-Output "After any required Windows restart: pwsh -NoProfile -File scripts/windows/Test-CleanWindowsAcceptance.ps1 -Action Launch -PreparedRoot `"$root`""
    if ($StartupMode -ceq 'AfterLogin') {
        Write-Output 'Once the Sandbox desktop is connected, use wsb list to identify its UUID, then run Execute with that explicit SandboxId. This does not bypass the guest guards.'
    }
    return
}
if (-not $PreparedRoot) { throw 'Launch, Execute and ReadEvidence require the prepared acceptance directory.' }
$root = Resolve-AcceptanceRoot $PreparedRoot
$manifest = Get-Content -LiteralPath (Join-Path $root 'input/acceptance-input.json') -Raw | ConvertFrom-Json
Assert-PreparedInput $root $manifest
if ($Action -eq 'Execute') {
    $arguments = Get-CleanWindowsExecuteArguments $manifest $SandboxId
    if (@(Get-ChildItem -LiteralPath (Join-Path $root 'evidence') -Force).Count -ne 0) { throw 'Execute requires a fresh output directory; do not repeat or overwrite an acceptance run.' }
    $cli = Get-Command -Name wsb.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $cli) { throw 'Windows Sandbox CLI is unavailable. Finish the official Sandbox app installation/update and any required restart; no guest or installer was run on the host.' }
    $raw = & $cli.Source @arguments | Out-String
    Assert-CleanWindowsExecuteResult $raw $LASTEXITCODE
    Write-Output "Guest process reported ExitCode 0; inspect matching evidence under $root/evidence. This alone is not an acceptance pass."
    return
}
if ($Action -eq 'Launch') {
    $sandbox = Join-Path $env:windir 'System32/WindowsSandbox.exe'
    if (-not (Test-Path -LiteralPath $sandbox)) { throw 'Windows Sandbox is unavailable. Enable Containers-DisposableClientVM and complete the required restart.' }
    if (Test-Path -LiteralPath (Join-Path $root 'evidence/evidence.json')) { throw 'This acceptance directory already has guest evidence. Prepare a new run rather than overwrite it.' }
    $process = Start-Process -FilePath $sandbox -ArgumentList ('"' + (Join-Path $root 'acceptance.wsb') + '"') -WindowStyle Hidden -PassThru
    Write-Output "Sandbox started (PID $($process.Id)); read evidence under $root/evidence. A started process is not an acceptance pass."
    return
}
$evidence = Get-Content -LiteralPath (Join-Path $root 'evidence/evidence.json') -Raw | ConvertFrom-Json
if ($evidence.runId -cne $manifest.runId -or $evidence.result -cne 'passed' -or -not $evidence.cleanWindowsClient -or $evidence.environment -cne 'Windows Sandbox') { throw 'Guest acceptance did not establish a passed, matching clean Sandbox run. Inspect the retained evidence.' }
Assert-CleanWindowsEvidenceScope $manifest $evidence
$evidence | ConvertTo-Json -Depth 12
