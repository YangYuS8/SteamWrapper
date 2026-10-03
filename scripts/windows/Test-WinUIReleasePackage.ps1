[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIInstallableRelease.ps1')
Test-WinUIReleaseArtifactDirectory -PackageDirectory $PackageDirectory
