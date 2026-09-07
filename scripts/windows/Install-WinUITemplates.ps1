[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This task requires Windows.' }

& dotnet new install Microsoft.WindowsAppSDK.WinUI.CSharp.Templates@0.0.6-alpha
$templateExit = $LASTEXITCODE
# dotnet new returns 106 when this exact package/version is already installed.
if ($templateExit -eq 106) {
    Write-Output 'The pinned WinUI template is already installed.'
    exit 0
}
if ($templateExit -ne 0) { throw "WinUI template installation failed ($templateExit)." }
