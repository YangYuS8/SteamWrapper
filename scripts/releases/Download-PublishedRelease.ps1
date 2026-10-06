[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string]$EnvelopePath,
    [string]$TrustPath = (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json'),
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$VerificationPath,
    [string]$GhExecutable = 'gh'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PublicReleaseDownload.ps1')
Get-PublishedReleasePackage @PSBoundParameters
