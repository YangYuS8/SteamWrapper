[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Import only the pure selector helper; this regression does not inspect or run
# a product binary and does not require an MSVC installation.
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-RunnerDependencies.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Runner dependency inspector parsing failed.' }
$helper = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-RunnerDependencyToolVersion' }, $true))
if ($helper.Count -ne 1) { throw 'Expected the one pure Runner dependency tool version helper.' }
. ([scriptblock]::Create($helper[0].Extent.Text))

$officialSuffix = [pscustomobject]@{
    FileMajorPart = 14; FileMinorPart = 29; FileBuildPart = 30159; FilePrivatePart = 0
    FileVersion = '14.29.30159.0 built by: cloudtest'
}
if ((Get-RunnerDependencyToolVersion $officialSuffix) -ne [Version]'14.29.30159.0') { throw 'Official tool display suffix changed its numeric file version.' }

$newest = [pscustomobject]@{
    FileMajorPart = 14; FileMinorPart = 51; FileBuildPart = 36256; FilePrivatePart = 7
    FileVersion = 'Official MSVC tool build'
}
if ((Get-RunnerDependencyToolVersion $newest) -ne [Version]'14.51.36256.7') { throw 'Tool version was not taken from all four numeric file version fields.' }

$older = [pscustomobject]@{
    FileMajorPart = 14; FileMinorPart = 44; FileBuildPart = 35213; FilePrivatePart = 0
    FileVersion = '99.0.0.0'
}
$selected = @($older, $officialSuffix, $newest) | Sort-Object { Get-RunnerDependencyToolVersion $_ } -Descending | Select-Object -First 1
if (-not [object]::ReferenceEquals($selected, $newest)) { throw 'The newest numeric MSVC tool was not selected independently of display text.' }

$newest.FileVersion = $null
if ((Get-RunnerDependencyToolVersion $newest) -ne [Version]'14.51.36256.7') { throw 'An absent display string changed the numeric MSVC tool identity.' }
Write-Output 'PASS: four Runner dependency tool version regressions; official display suffix, numeric components, newest selection and absent display text.'
