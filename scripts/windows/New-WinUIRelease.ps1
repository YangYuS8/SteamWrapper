[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Commit,
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$PublishDirectory,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $RepositoryRoot 'target/winui/publish' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $RepositoryRoot "target/winui/releases/$Tag" }
New-WinUIReleasePackage -Tag $Tag -Commit $Commit -RepositoryRoot $RepositoryRoot -PublishDirectory $PublishDirectory -OutputDirectory $OutputDirectory
