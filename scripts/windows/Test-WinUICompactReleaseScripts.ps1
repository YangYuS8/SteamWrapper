[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIInstallableRelease.TestFixtures.ps1')
. (Join-Path $PSScriptRoot 'WinUIInstallableRelease.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root = Join-Path $repoRoot ('target/winui/compact-release-tests/' + [Guid]::NewGuid().ToString('N'))
foreach ($tag in @('v0.2.7', 'v0.2.8', 'v0.2.8-rc.1')) {
    $fixture = New-WinUIInstallableReleaseTestFixture -Root (Join-Path $root $tag) -Tag $tag
    $package = New-WinUIInstallableReleasePackage -Tag $tag -Commit $fixture.Commit -RepositoryRoot $fixture.RepositoryRoot -PublishDirectory $fixture.PublishDirectory -InstallerDirectory $fixture.InstallerDirectory -OutputDirectory $fixture.OutputDirectory
    $metadata = Test-WinUIReleaseArtifactDirectory $package.Directory
    $legacy = $tag -ceq 'v0.2.7'
    $expectedSchema = if ($legacy) { 2 } else { 3 }
    if ($metadata.schemaVersion -ne $expectedSchema -or @(Get-ChildItem -LiteralPath $package.Directory).Count -ne 7) { throw "$tag must retain seven internal assets and schema $expectedSchema." }
    $publicNames = @(Get-WinUIPublicReleaseAssetNames $metadata)
    $expectedCount = if ($legacy) { 7 } else { 3 }
    if ($publicNames.Count -ne $expectedCount) { throw "$tag must select exactly $expectedCount public assets." }
    $sumLines = @([IO.File]::ReadAllLines($package.Checksums) | Where-Object { $_ -ne '' })
    $expectedSums = if ($legacy) { 6 } else { 2 }
    if ($sumLines.Count -ne $expectedSums) { throw "$tag checksum inventory must list exactly $expectedSums assets." }
    if (-not $legacy) {
        foreach ($name in @($metadata.archive.fileName, $metadata.installerAsset.fileName, 'SHA256SUMS')) { if ($name -cnotin $publicNames) { throw 'Compact public assets omit a required player download.' } }
        $notes = Join-Path $package.Directory "$tag.zh-CN.md"
        $original = [IO.File]::ReadAllBytes($notes)
        try {
            [IO.File]::AppendAllText($notes, 'tampered note')
            $rejected = $false
            try { $null = Test-WinUIReleaseArtifactDirectory $package.Directory } catch { $rejected = $true }
            if (-not $rejected) { throw 'Compact internal validation accepted changed bilingual notes.' }
        } finally { [IO.File]::WriteAllBytes($notes, $original) }
        $null = Test-WinUIReleaseArtifactDirectory $package.Directory
    }
    Write-Output "PASS: $tag uses schema $expectedSchema, seven validated internal files and $expectedCount immutable public assets."
}
Write-Output "Compact release byte fixtures passed: $root"
