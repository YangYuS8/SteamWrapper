# Inbox PowerShell 5.1 wrapper for an already connected Sandbox desktop.
# This file never falls back to executing the guest or Setup on the host.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:USERNAME -ine 'WDAGUtilityAccount' -or $env:USERPROFILE.TrimEnd('\') -ine 'C:\Users\WDAGUtilityAccount' -or
    -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0 -or
    $PSScriptRoot -ine 'C:\AcceptanceInput') { throw 'After-login acceptance may run only in the dedicated interactive Windows Sandbox.' }
$manifest = Get-Content -LiteralPath 'C:\AcceptanceInput\acceptance-input.json' -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.sandboxOnly -ne $true -or $manifest.networkingDisabled -ne $true -or
    $manifest.startupMode -cne 'AfterLogin' -or [string]::IsNullOrWhiteSpace([string]$manifest.hostComputerName) -or
    $env:COMPUTERNAME -ieq $manifest.hostComputerName) { throw 'Refusing an unexpected after-login acceptance manifest or its input host.' }
foreach ($name in @('STEAMWRAPPER_E2E_ROOT', 'STEAMWRAPPER_DEPLOYMENT_TEST', 'STEAM_DIR')) {
    if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) { throw 'Unexpected test environment override.' }
}
if (@(Get-ChildItem Env: | Where-Object Name -like 'STEAMWRAPPER_DEPLOYMENT_*').Count -ne 0) { throw 'Unexpected deployment environment override.' }
foreach ($record in @(
    @{ Path = $PSCommandPath; Hash = $manifest.launchScriptSha256 },
    @{ Path = 'C:\AcceptanceInput\Invoke-CleanWindowsGuestAcceptance.ps1'; Hash = $manifest.guestScriptSha256 }
)) {
    $file = Get-Item -LiteralPath $record.Path -Force
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $record.Hash -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.Hash) {
        throw 'The prepared guest launch wrapper or acceptance script changed.'
    }
}
if (-not (Test-Path -LiteralPath 'C:\AcceptanceOutput' -PathType Container) -or
    @(Get-ChildItem -LiteralPath 'C:\AcceptanceOutput' -Force).Count -ne 0) { throw 'After-login execution requires a fresh mapped output directory.' }
# Creating this log after the guards gives the host a bootstrap marker even
# when the guest fails one of its stricter client/product prerequisites.
try {
    & 'C:\AcceptanceInput\Invoke-CleanWindowsGuestAcceptance.ps1' *> 'C:\AcceptanceOutput\guest-launch.log'
} catch {
    $_ | Out-String | Add-Content -LiteralPath 'C:\AcceptanceOutput\guest-launch.log'
    throw
}
