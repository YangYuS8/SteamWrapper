# Seals existing compiled payloads and writes a guest configuration. Never
# starts Sandbox, mounts a volume or runs Setup/Manager/Runner.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BaselinePublishDirectory,[Parameter(Mandatory)][string]$BaselineTag,
    [Parameter(Mandatory)][string]$TargetPublishDirectory,[Parameter(Mandatory)][string]$TargetTag)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'InstallerBoundaryAcceptance.ps1')
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$baselineVersion=Assert-WinUIInstallerTag $BaselineTag; $targetVersion=Assert-WinUIInstallerTag $TargetTag
Assert-InstallerBoundary ([Version]$targetVersion -gt [Version]$baselineVersion) 'Disk-full upgrade acceptance needs a genuinely newer numeric payload.'
$sources=[ordered]@{baseline=(Assert-WinUIInstallerPath $BaselinePublishDirectory);target=(Assert-WinUIInstallerPath $TargetPublishDirectory)}
foreach ($kind in $sources.Keys) { Assert-WinUIInstallerPayloadPrivacy $sources[$kind] }
$run=[Guid]::NewGuid().ToString('N')
$root=Join-Path $repo ('target/winui/installer-boundary-' + $run)
$null=Assert-WinUIInstallerPath $root -Output
Assert-InstallerBoundary (-not (Test-Path -LiteralPath $root)) 'Fresh acceptance root already exists.'
$inputDirectory=Join-Path $root 'input'; $outputDirectory=Join-Path $root 'evidence'
[IO.Directory]::CreateDirectory($inputDirectory) | Out-Null; [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$assets=[Collections.Generic.List[object]]::new()
foreach ($kind in $sources.Keys) {
    $directory=Join-Path $inputDirectory $kind
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $sources[$kind] -Force) { Copy-Item -LiteralPath $entry.FullName -Destination $directory -Recurse }
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'LICENSE') -PathType Leaf)) { Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination (Join-Path $directory 'LICENSE') }
    $tag=if ($kind -ceq 'baseline') {$BaselineTag} else {$TargetTag}
    $version=Assert-WinUIInstallerTag $tag
    foreach ($relative in @('SteamWrapper.Manager.exe','Deployment/SteamWrapper.exe','Runner/SteamWrapperRunner.exe')) {
        $info=[Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $directory $relative))
        Assert-InstallerBoundary ($info.FileVersion -match ('^' + [regex]::Escape($version) + '(?:\.0)?$')) 'The genuine compiled PE version differs from the requested tag; metadata-only numeric fixtures are refused.'
    }
    $null=New-WinUIInstallerManifest -PayloadDirectory $directory -Tag $tag
    foreach ($file in Get-ChildItem -LiteralPath $directory -File -Recurse -Force) {
        $relative=$kind + '/' + [IO.Path]::GetRelativePath($directory,$file.FullName).Replace('\','/')
        Assert-InstallerBoundaryAssetPath $relative
        $assets.Add([ordered]@{path=$relative;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})
    }
}
foreach ($name in @('InstallerBoundaryAcceptance.ps1','Invoke-InstallerDiskFullGuestAcceptance.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $inputDirectory $name) }
$descriptor=[ordered]@{schemaVersion=1;runId=$run;hostComputerName=[Environment]::MachineName;sandboxOnly=$true;networkingDisabled=$true;scenario='NativeAotMidCopyDiskFull';actualInno=$false;localPayloadFixture=$true;manifestsRebuilt=$true;baseline=[ordered]@{tag=$BaselineTag};target=[ordered]@{tag=$TargetTag};assets=$assets.ToArray()}
[IO.File]::WriteAllText((Join-Path $inputDirectory 'manifest.json'),($descriptor | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$configuration=@'
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>Disable</Networking>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MappedFolders>
    <MappedFolder><HostFolder>{INPUT}</HostFolder><SandboxFolder>C:\AcceptanceInput\installer-boundary</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>{OUTPUT}</HostFolder><SandboxFolder>C:\AcceptanceOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -Command &quot;&amp; 'C:\AcceptanceInput\installer-boundary\Invoke-InstallerDiskFullGuestAcceptance.ps1' *&gt; 'C:\AcceptanceOutput\guest-launch.log'&quot;</Command></LogonCommand>
</Configuration>
'@
$configuration=$configuration.Replace('{INPUT}',[Security.SecurityElement]::Escape($inputDirectory)).Replace('{OUTPUT}',[Security.SecurityElement]::Escape($outputDirectory))
[IO.File]::WriteAllText((Join-Path $root 'disk-full.wsb'),$configuration,[Text.UTF8Encoding]::new($false))
Write-Output "Guest disk-full inputs prepared without starting Sandbox: $root"
