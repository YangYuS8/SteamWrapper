# Microsoft Build Tools are system components, installed through the official signed bootstrapper.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This task requires Windows.' }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$components = (Get-Content -LiteralPath (Join-Path $repoRoot '.vsconfig') -Raw | ConvertFrom-Json).components
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$existing = $null
if (Test-Path -LiteralPath $vswhere) {
    $ready = & $vswhere -latest -products '*' -requires $components -property installationPath
    if ($LASTEXITCODE -ne 0) { throw 'vswhere could not inspect the installed components.' }
    if ($ready) {
        Write-Output "MSVC and Windows SDK already installed: $ready"
        return
    }
    $existing = & $vswhere -latest -products Microsoft.VisualStudio.Product.BuildTools -property installationPath
    if ($LASTEXITCODE -ne 0) { throw 'vswhere could not inspect Build Tools.' }
}

# Bootstrapper 18.9.1, resolved from the Microsoft WinGet manifest on 2026-09-07.
$uri = 'https://download.visualstudio.microsoft.com/download/pr/7834fc97-5a8c-4392-a2a9-ed4b98f77180/e1dcfb35b5b7a285cdf3f877d0bc835c5373999ce0fc78b637c7d5fea2966c05/vs_BuildTools.exe'
$sha256 = 'E1DCFB35B5B7A285CDF3F877D0BC835C5373999CE0FC78B637C7D5FEA2966C05'
$downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'SteamWrapper-build-tools'
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
$installer = Join-Path $downloadRoot 'vs_BuildTools-18.9.1.exe'
if (-not (Test-Path -LiteralPath $installer) -or (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $sha256) {
    Invoke-WebRequest -Uri $uri -OutFile $installer
}
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $sha256) {
    throw 'The Microsoft bootstrapper checksum does not match.'
}
$signature = Get-AuthenticodeSignature -LiteralPath $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw 'The bootstrapper does not have the expected valid Microsoft signature.'
}

$installerArguments = @('--quiet', '--wait', '--norestart', '--nocache')
if ($existing) { $installerArguments = @('modify', '--installPath', ('"{0}"' -f $existing)) + $installerArguments }
foreach ($component in $components) { $installerArguments += @('--add', $component) }

Write-Output 'Installing MSVC x64/x86 and Windows SDK 26100. Windows may display its UAC prompt. No automatic restart.'
$parameters = @{
    FilePath = $installer
    ArgumentList = $installerArguments
    WindowStyle = 'Hidden'
    Wait = $true
    PassThru = $true
}
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { $parameters.Verb = 'RunAs' }
$process = Start-Process @parameters
if ($process.ExitCode -eq 3010) {
    throw 'Build Tools installed but Windows requires a restart (3010). Restart manually, then rerun mise run windows:doctor.'
}
if ($process.ExitCode -ne 0) { throw "Build Tools installer failed with exit code $($process.ExitCode)." }
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Installer finished, but vswhere is missing.' }
$installed = & $vswhere -latest -products '*' -requires $components -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installed) { throw 'Installer finished, but the required components were not detected.' }
Write-Output "MSVC and Windows SDK installed: $installed"
