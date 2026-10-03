[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Commit,
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$PublishDirectory,
    [Parameter(Mandatory)][string]$InstallerDirectory,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIInstallableRelease.ps1')
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $RepositoryRoot 'target/winui/publish' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $RepositoryRoot "target/winui/releases/$Tag-installable" }
New-WinUIInstallableReleasePackage -Tag $Tag -Commit $Commit -RepositoryRoot $RepositoryRoot -PublishDirectory $PublishDirectory -InstallerDirectory $InstallerDirectory -OutputDirectory $OutputDirectory
