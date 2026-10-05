[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'Launch', 'ReadEvidence')][string]$Action = 'Prepare',
    [string]$PreparedRoot,
    [string]$BaselineTag = 'v0.2.4-preview.1',
    [string]$Tag = 'v0.2.5-preview.1',
    [string]$BaselineInstallerPath,
    [string]$InstallerPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Windows Sandbox acceptance requires a Windows host.' }
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
    $output = & gh @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw ('GitHub acceptance command failed: ' + ($Arguments[0..1] -join ' ')) }
    return $output.Trim()
}
function Get-PublicRelease([string]$ReleaseTag, [string]$Directory, [string]$CachedInstaller) {
    if ($ReleaseTag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$') { throw 'Expected an explicit preview version tag.' }
    $state = Invoke-AcceptanceGh @('release', 'view', $ReleaseTag, '--repo', 'YangYuS8/SteamWrapper', '--json', 'tagName,isDraft,isPrerelease,assets') | ConvertFrom-Json
    $names = @("SteamWrapper-$ReleaseTag-win-x64-setup.exe", "SteamWrapper-$ReleaseTag-win-x64.zip", 'portable-release.json', 'release.json', 'SHA256SUMS', "$ReleaseTag.en.md", "$ReleaseTag.zh-CN.md")
    if ($state.tagName -cne $ReleaseTag -or $state.isDraft -or -not $state.isPrerelease -or @($state.assets).Count -ne 7 -or
        @($state.assets.name | Sort-Object -Unique).Count -ne 7 -or @($state.assets.name | Where-Object { $_ -cnotin $names }).Count) { throw 'Expected the complete public seven-asset prerelease.' }
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
    if ($metadata.schemaVersion -ne 2 -or $metadata.tag -cne $ReleaseTag -or $metadata.commit -cne $remoteCommit -or
        $metadata.platform -cne 'win-x64' -or -not $metadata.installer -or $metadata.installerAsset.fileName -cne $setupAsset.name -or
        $metadata.installerAsset.bytes -ne $setupAsset.size -or ('sha256:' + $metadata.installerAsset.sha256) -cne $setupAsset.digest) { throw 'The verified installer descriptor and public tag identity differ.' }
    return $metadata
}
function Assert-PreparedInput([string]$Root, $Manifest) {
    if ($Manifest.schemaVersion -ne 1 -or -not $Manifest.sandboxOnly -or $Manifest.runId -cne ([IO.Path]::GetFileName($Root)).Substring('clean-windows-'.Length)) { throw 'Unexpected acceptance manifest identity.' }
    foreach ($item in @($Manifest.baseline, $Manifest.target)) {
        if ($item.fileName -notmatch '^SteamWrapper-v[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+-win-x64-setup\.exe$') { throw 'Unexpected acceptance installer path.' }
        $path = Join-Path (Join-Path $Root 'input') $item.fileName
        $file = Get-Item -LiteralPath $path
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -ne $item.bytes -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.sha256) { throw 'Prepared public installer changed.' }
    }
    $script = Join-Path $Root 'input/Invoke-CleanWindowsGuestAcceptance.ps1'
    if ((Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Manifest.guestScriptSha256) { throw 'Prepared guest acceptance script changed.' }
}

if ($Action -eq 'Prepare') {
    if ($PreparedRoot) { throw 'Prepare creates a fresh acceptance directory; do not provide PreparedRoot.' }
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
    $baseline = Get-PublicRelease $BaselineTag $baselineDirectory $BaselineInstallerPath
    $target = Get-PublicRelease $Tag $targetDirectory $InstallerPath
    if ([Version]$target.version -le [Version]$baseline.version) { throw 'Acceptance requires a genuine newer numeric product version.' }
    $guest = Join-Path $inputRoot 'Invoke-CleanWindowsGuestAcceptance.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1') -Destination $guest
    Copy-Item -LiteralPath (Join-Path $baselineDirectory $baseline.installerAsset.fileName) -Destination $inputRoot
    Copy-Item -LiteralPath (Join-Path $targetDirectory $target.installerAsset.fileName) -Destination $inputRoot
    $manifest = [ordered]@{
        schemaVersion = 1; runId = $runId; sandboxOnly = $true; hostComputerName = $env:COMPUTERNAME
        hostBuild = (Get-CimInstance Win32_OperatingSystem).BuildNumber; preparedAt = [DateTimeOffset]::UtcNow.ToString('O')
        networkingDisabled = $true; guestScriptSha256 = (Get-FileHash -LiteralPath $guest -Algorithm SHA256).Hash.ToLowerInvariant()
        baseline = @{ tag = $BaselineTag; fileName = $baseline.installerAsset.fileName; sha256 = $baseline.installerAsset.sha256; bytes = $baseline.installerAsset.bytes; commit = $baseline.commit }
        target = @{ tag = $Tag; fileName = $target.installerAsset.fileName; sha256 = $target.installerAsset.sha256; bytes = $target.installerAsset.bytes; commit = $target.commit }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $inputRoot 'acceptance-input.json') -Encoding utf8
    $escape = { param($value) [Security.SecurityElement]::Escape($value) }
    $logonCommand = 'powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -Command "& ''C:\AcceptanceInput\Invoke-CleanWindowsGuestAcceptance.ps1'' *> ''C:\AcceptanceOutput\guest-launch.log''"'
    @"
<Configuration>
  <MemoryInMB>8192</MemoryInMB>
  <Networking>Disable</Networking>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <MappedFolders>
    <MappedFolder><HostFolder>$(& $escape $inputRoot)</HostFolder><SandboxFolder>C:\AcceptanceInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$(& $escape $outputRoot)</HostFolder><SandboxFolder>C:\AcceptanceOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>$(& $escape $logonCommand)</Command></LogonCommand>
</Configuration>
"@ | Set-Content -LiteralPath (Join-Path $root 'acceptance.wsb') -Encoding utf8
    Assert-PreparedInput $root ([pscustomobject]$manifest)
    Write-Output "Prepared verified public installers and isolated Sandbox configuration: $root"
    Write-Output "After any required Windows restart: pwsh -NoProfile -File scripts/windows/Test-CleanWindowsAcceptance.ps1 -Action Launch -PreparedRoot `"$root`""
    return
}
if (-not $PreparedRoot) { throw 'Launch and ReadEvidence require the prepared acceptance directory.' }
$root = Resolve-AcceptanceRoot $PreparedRoot
$manifest = Get-Content -LiteralPath (Join-Path $root 'input/acceptance-input.json') -Raw | ConvertFrom-Json
Assert-PreparedInput $root $manifest
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
$evidence | ConvertTo-Json -Depth 12
