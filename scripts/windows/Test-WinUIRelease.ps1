[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Commit,
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')
$plan = Get-WinUIReleasePlan -Tag $Tag -Commit $Commit -RepositoryRoot $RepositoryRoot
Write-Output "Release preflight passed: $($plan.Tag), commit $($plan.Commit), Windows x64 unsigned preview."
