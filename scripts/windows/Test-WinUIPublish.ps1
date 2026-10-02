[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$publishRoot = Join-Path $repoRoot 'target/winui'
$output = Join-Path $publishRoot 'publish'
if (-not $SkipBuild) {
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $sentinel = Join-Path $output ('.obsolete-publish-test-' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($sentinel, 'An obsolete dependency from a previous release.')
    try {
        & (Join-Path $PSScriptRoot 'Invoke-WinUI.ps1') -Action Publish
        if (Test-Path -LiteralPath $sentinel) {
            throw 'Regression: publishing left an obsolete file in the release directory.'
        }
        Write-Output 'PASS: actual publish removes obsolete files.'
    } finally {
        # Remove only the unique test file if the old implementation retained it.
        if (Test-Path -LiteralPath $sentinel) { Remove-Item -LiteralPath $sentinel }
    }
}

. (Join-Path $PSScriptRoot 'Complete-WinUIPublish.ps1')
$fixture = Join-Path $publishRoot ('publish-tests/' + [Guid]::NewGuid().ToString('N'))
$previous = Join-Path $fixture 'publish'
$candidate = Join-Path $fixture ('publish-staging-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $previous, $candidate -Force | Out-Null
$oldFile = Join-Path $previous 'previous.txt'
[IO.File]::WriteAllText($oldFile, 'previous release bytes')
$oldHash = (Get-FileHash -LiteralPath $oldFile).Hash

function Assert-PreviousRelease {
    if (-not (Test-Path -LiteralPath $oldFile) -or (Get-FileHash -LiteralPath $oldFile).Hash -ne $oldHash) {
        throw 'The failed publish did not preserve the previous release.'
    }
}

$rejected = $false
try { $null = Complete-WinUIPublish -Root $fixture -Candidate $candidate -RequiredFiles @('ready.txt') }
catch { if ($_.Exception.Message -notlike 'Publish is missing*') { throw }; $rejected = $true }
if (-not $rejected) { throw 'An incomplete candidate was accepted.' }
Assert-PreviousRelease
Write-Output 'PASS: required-file validation failure preserves the previous release.'

$ready = Join-Path $candidate 'ready.txt'
[IO.File]::WriteAllText($ready, 'new release bytes')
# Windows refuses to rename the candidate while a child is opened without delete
# sharing. This exercises failure after the old release was renamed, then rollback.
$held = [IO.FileStream]::new($ready, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$rejected = $false
try {
    try { $null = Complete-WinUIPublish -Root $fixture -Candidate $candidate -RequiredFiles @('ready.txt') }
    catch { $rejected = $true }
} finally { $held.Dispose() }
if (-not $rejected) { throw 'The held candidate unexpectedly replaced the previous release.' }
Assert-PreviousRelease
if (-not (Test-Path -LiteralPath $ready)) { throw 'The failed candidate was not retained.' }
Write-Output 'PASS: a locked candidate restores the previous release and retains the candidate.'

$result = Complete-WinUIPublish -Root $fixture -Candidate $candidate -RequiredFiles @('ready.txt')
if ((Test-Path -LiteralPath $oldFile) -or [IO.File]::ReadAllText((Join-Path $result 'ready.txt')) -ne 'new release bytes') {
    throw 'Successful replacement retained obsolete files or lost the new release.'
}
Write-Output 'PASS: successful replacement contains only the new release.'

$rejected = $false
try { $null = Complete-WinUIPublish -Root (Join-Path $repoRoot 'target/outside-winui-publish-test') -Candidate $candidate -RequiredFiles @('ready.txt') }
catch { if ($_.Exception.Message -notlike 'Publish path is outside*') { throw }; $rejected = $true }
if (-not $rejected) { throw 'An output outside target/winui was accepted.' }
Write-Output 'PASS: paths outside target/winui are rejected before mutation.'
Write-Output "Publish regression fixtures: $fixture"
