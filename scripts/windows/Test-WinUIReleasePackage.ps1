[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')
Test-WinUIReleasePackageDirectory -PackageDirectory $PackageDirectory
