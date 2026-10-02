[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [string]$PublishDirectory,
    [string]$DeploymentDirectory,
    [string]$OutputDirectory,
    [string]$Compiler,
    [string]$IsolatedRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Building a Windows installer requires Windows.' }
. (Join-Path $PSScriptRoot '../../packaging/windows/WinUIInstaller.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$version = Assert-WinUIInstallerTag $Tag
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $repoRoot 'target/winui/publish' }
if (-not $DeploymentDirectory) { $DeploymentDirectory = Join-Path $PublishDirectory 'Deployment' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "target/winui/installers/$Tag" }
$publish = Assert-WinUIInstallerPath $PublishDirectory
$deployment = Assert-WinUIInstallerPath $DeploymentDirectory
$output = Assert-WinUIInstallerPath $OutputDirectory -Output
if ((Test-Path -LiteralPath $output) -and @(Get-ChildItem -LiteralPath $output -Force | Select-Object -First 1).Count) { throw 'Installer output directory is not empty; preserve sealed artifacts and choose a fresh output directory.' }
# Reject private input names before copying any bytes into installer staging.
Assert-WinUIInstallerPayloadPrivacy $publish
Assert-WinUIInstallerPayloadPrivacy $deployment
$hostPath = Join-Path $deployment 'SteamWrapper.exe'
if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { throw 'The self-contained deployment Host SteamWrapper.exe is missing.' }
if (-not $Compiler) { $Compiler = & (Join-Path $PSScriptRoot 'Install-WinUIInstallerToolchain.ps1') }
$compilerPath = (Resolve-Path -LiteralPath $Compiler).Path
$toolchainPin = Get-Content -LiteralPath (Join-Path $repoRoot 'packaging/windows/inno-toolchain.json') -Raw | ConvertFrom-Json
$compilerSignature = Get-AuthenticodeSignature -LiteralPath $compilerPath
if ($compilerSignature.Status -ne 'Valid' -or $compilerSignature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne $toolchainPin.publisher) { throw 'The selected compiler does not have the pinned official publisher signature.' }
$compilerVersion = (& $compilerPath --version).Trim()
if ($LASTEXITCODE -ne 0 -or $compilerVersion -ne '7.1.0') { throw 'Installer builds require the pinned Inno Setup 7.1.0 compiler.' }
$staging = Join-Path $repoRoot ('target/winui/installer-staging-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $staging 'payload'
$null = Assert-WinUIInstallerPath $staging -Output
[IO.Directory]::CreateDirectory($payload) | Out-Null
foreach ($entry in Get-ChildItem -LiteralPath $publish -Force) { Copy-Item -LiteralPath $entry.FullName -Destination $payload -Recurse -Force }
$payloadHost = Join-Path $payload 'Deployment/SteamWrapper.exe'
if (Test-Path -LiteralPath $payloadHost) {
    if ((Get-FileHash -LiteralPath $payloadHost -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash) { throw 'The published deployment Host differs from the selected verified component.' }
} else {
    [IO.Directory]::CreateDirectory((Join-Path $payload 'Deployment')) | Out-Null
    Copy-Item -LiteralPath $hostPath -Destination $payloadHost
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $payload 'LICENSE') -Force
$manifestPath = New-WinUIInstallerManifest -PayloadDirectory $payload -Tag $Tag
[IO.Directory]::CreateDirectory($output) | Out-Null
$arguments = @('--quiet', '--no-ide-signtools', "--define=PayloadDir=$payload", "--define=ReleaseTag=$Tag", "--define=ProductVersion=$version", "--define=OutputDir=$output", ('--define=HostSha256=' + (Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToLowerInvariant()))
if ($IsolatedRoot) {
    $isolated = Assert-WinUIInstallerPath $IsolatedRoot -Output
    if ($isolated -match '["\r\n]') { throw 'Isolated installer roots cannot contain quotes or newlines.' }
    # Installation identity stays constant across upgrades of this same isolated root.
    $id = [Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($isolated.ToUpperInvariant()))).Substring(0, 16)
    $arguments += @('--define=Isolated=1', "--define=IsolatedRoot=$isolated", ("--define=IsolatedRootCode=" + $isolated.Replace("'", "''")), "--define=IsolatedId=$id")
}
$arguments += (Join-Path $repoRoot 'packaging/windows/SteamWrapper.iss')
& $compilerPath @arguments
if ($LASTEXITCODE -ne 0) { throw "Inno compiler failed with exit code $LASTEXITCODE." }
$setup = Join-Path $output "SteamWrapper-$Tag-win-x64-setup.exe"
if (-not (Test-Path -LiteralPath $setup)) { throw 'The compiler did not produce the expected setup executable.' }
$inspection = & (Join-Path $PSScriptRoot 'Test-WinUIInstallerArtifact.ps1') -SetupPath $setup
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$metadata = [ordered]@{ schemaVersion = 1; tag = $Tag; version = $version; platform = 'win-x64'; installer = [ordered]@{ fileName = [IO.Path]::GetFileName($setup); bytes = $inspection.bytes; sha256 = $inspection.sha256; signed = $false; canonicalIconFrames = $inspection.canonicalIconFrames }; isolated = [bool]$IsolatedRoot; deploymentManifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant(); payloadFiles = $manifest.files.Count }
[IO.File]::WriteAllText((Join-Path $output 'installer-build.json'), ($metadata | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $output 'deployment-manifest.json') -Force
Write-Host "Unsigned WinUI installer built and hashed: $setup"
return $setup
