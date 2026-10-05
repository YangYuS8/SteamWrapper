[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WinUIInstallableRelease.TestFixtures.ps1')
. (Join-Path $PSScriptRoot 'WinUIInstallableRelease.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root = Join-Path $repoRoot ('target/winui/installable-release-tests/' + [Guid]::NewGuid().ToString('N'))
$fixture = New-WinUIInstallableReleaseTestFixture -Root $root
$package = New-WinUIInstallableReleaseTestPackage $fixture
$metadata = & (Join-Path $PSScriptRoot 'Test-WinUIReleasePackage.ps1') -PackageDirectory $package.Directory
if ($metadata.schemaVersion -ne 2 -or -not $metadata.installer -or $metadata.signed -or $metadata.releaseChannel -cne 'stable' -or $metadata.githubPrerelease -or @(Get-ChildItem -LiteralPath $package.Directory).Count -ne 7) { throw 'An installable unsigned stable release did not retain its exact seven-asset contract.' }
Write-Output 'PASS: independent schema-2 fixture validates all seven assets and its portable/deployment inventories.'
$previewFixture = New-WinUIInstallableReleaseTestFixture -Root (Join-Path $root 'preview') -Tag 'v0.2.0-rc.1'
$previewPackage = New-WinUIInstallableReleaseTestPackage $previewFixture
$previewMetadata = Test-WinUIReleaseArtifactDirectory $previewPackage.Directory
if ($previewMetadata.releaseChannel -cne 'preview' -or -not $previewMetadata.githubPrerelease -or -not $previewMetadata.tagPrerelease -or @(Get-ChildItem -LiteralPath $previewPackage.Directory).Count -ne 7) { throw 'Prerelease schema-2 fixtures must retain preview identity and all seven assets.' }
Write-Output 'PASS: preview and stable installable packages share the unchanged seven-asset contract.'

function Assert-InstallableRejected([string]$Label, [scriptblock]$Action, [string]$Pattern) {
    $rejected = $false
    try { $null = & $Action }
    catch { if ($_.Exception.Message -notlike $Pattern) { throw }; $rejected = $true }
    if (-not $rejected) { throw "$Label unexpectedly succeeded." }
    Write-Output "PASS: $Label"
}

Assert-InstallableRejected 'schema-1 validator still rejects installable seven-asset packages' {
    Test-WinUIReleasePackageDirectory $package.Directory
} '*exactly five*'

function New-InstallableMutation([string]$Name) {
    $directory = Join-Path $fixture.RepositoryRoot "target/winui/releases/$Name"
    $null = Assert-WinUIReleasePath $directory (Join-Path $fixture.RepositoryRoot 'target/winui/releases')
    if (Test-Path -LiteralPath $directory) { throw 'Mutation fixtures must be fresh.' }
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    foreach ($asset in Get-ChildItem -LiteralPath $package.Directory -File) {
        [IO.File]::Copy($asset.FullName, (Join-Path $directory $asset.Name), $false)
    }
    return $directory
}

function Write-InstallableMetadata([string]$Directory, $Metadata) {
    $Metadata | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Directory 'release.json') -Encoding utf8NoBOM
    Update-WinUIInstallableFixtureChecksums $Directory
}

foreach ($scenario in @('signed', 'isolated', 'wrong-commit', 'wrong-version', 'wrong-channel', 'wrong-prerelease', 'duplicate-json', 'unknown-field')) {
    $directory = New-InstallableMutation $scenario
    $metadata = Get-Content -LiteralPath (Join-Path $directory 'release.json') -Raw | ConvertFrom-Json
    $pattern = '*unsigned installable release*'
    switch ($scenario) {
        'signed' { $metadata.signed = $true }
        'isolated' { $metadata.installerBuild.isolated = $true; $pattern = '*non-isolated*' }
        'wrong-commit' { $metadata.commit = 'main' }
        'wrong-version' { $metadata.version = '0.3.0' }
        'wrong-channel' { $metadata.releaseChannel = 'preview' }
        'wrong-prerelease' { $metadata.githubPrerelease = $true }
        'unknown-field' { $metadata.installerBuild | Add-Member -NotePropertyName unsupported -NotePropertyValue 'fixture only'; $pattern = '*unsupported fields*' }
    }
    Write-InstallableMetadata $directory $metadata
    if ($scenario -eq 'duplicate-json') {
        $path = Join-Path $directory 'release.json'
        $text = [IO.File]::ReadAllText($path).Replace('"schemaVersion": 2,', '"schemaVersion": 2, "schemaVersion": 2,')
        [IO.File]::WriteAllText($path, $text)
        Update-WinUIInstallableFixtureChecksums $directory
        $pattern = '*duplicate property*'
    }
    Assert-InstallableRejected "$scenario metadata is rejected after outer checksums are recalculated" {
        Test-WinUIReleaseArtifactDirectory $directory
    } $pattern
}

$directory = New-InstallableMutation 'different-manifest'
$metadata = Get-Content -LiteralPath (Join-Path $directory 'release.json') -Raw | ConvertFrom-Json
$manifest = $metadata.deploymentManifest.json | ConvertFrom-Json
$manifest.files[0].sha256 = 'f' * 64
$metadata.deploymentManifest.json = $manifest | ConvertTo-Json -Depth 6
$bytes = [Text.Encoding]::UTF8.GetBytes($metadata.deploymentManifest.json)
$metadata.deploymentManifest.bytes = $bytes.Length
$metadata.deploymentManifest.sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
$metadata.installerBuild.deploymentManifestSha256 = $metadata.deploymentManifest.sha256
Write-InstallableMetadata $directory $metadata
Assert-InstallableRejected 'a rehashed deployment manifest must still match every portable payload byte' {
    Test-WinUIReleaseArtifactDirectory $directory
} '*payload differs from the portable bytes*'

$directory = New-InstallableMutation 'different-inner-zip'
$metadata = Get-Content -LiteralPath (Join-Path $directory 'release.json') -Raw | ConvertFrom-Json
$zipPath = Join-Path $directory $metadata.archive.fileName
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Update)
try {
    $name = "SteamWrapper-$($fixture.Tag)-win-x64/extra-runtime-dependency.dll"
    $zip.GetEntry($name).Delete()
    $writer = [IO.StreamWriter]::new($zip.CreateEntry($name).Open())
    try { $writer.Write('Tampered inner dependency bytes.') } finally { $writer.Dispose() }
} finally { $zip.Dispose() }
$metadata.archive.bytes = (Get-Item -LiteralPath $zipPath).Length
$metadata.archive.sha256 = (Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant()
$portablePath = Join-Path $directory 'portable-release.json'
$portable = Get-Content -LiteralPath $portablePath -Raw | ConvertFrom-Json
$portable.archive = $metadata.archive
$portable | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $portablePath -Encoding utf8NoBOM
$metadata.portableMetadata.bytes = (Get-Item -LiteralPath $portablePath).Length
$metadata.portableMetadata.sha256 = (Get-FileHash -LiteralPath $portablePath).Hash.ToLowerInvariant()
Write-InstallableMetadata $directory $metadata
Assert-InstallableRejected 'rehashed ZIP and both outer descriptors cannot hide changed internal inventory bytes' {
    Test-WinUIReleaseArtifactDirectory $directory
} '*Release ZIP entry*'

$directory = New-InstallableMutation 'unknown-asset'
[IO.File]::Move((Join-Path $directory $metadata.installerAsset.fileName), (Join-Path $directory 'unexpected.exe'))
Update-WinUIInstallableFixtureChecksums $directory
Assert-InstallableRejected 'an unexpected seventh asset cannot replace Setup' { Test-WinUIReleaseArtifactDirectory $directory } '*unexpected asset*'

function Invoke-InstallableCreation([string]$Output) {
    New-WinUIInstallableReleasePackage -Tag $fixture.Tag -Commit $fixture.Commit -RepositoryRoot $fixture.RepositoryRoot -PublishDirectory $fixture.PublishDirectory -InstallerDirectory $fixture.InstallerDirectory -OutputDirectory $Output
}
$createdPath = Join-Path $fixture.RepositoryRoot 'target/winui/releases/created'
$created = Invoke-InstallableCreation $createdPath
$checked = Test-WinUIReleaseArtifactDirectory $created.Directory
if ($checked.schemaVersion -ne 2 -or $checked.installerBuild.isolated -or $created.Setup -cne (Join-Path $created.Directory $checked.installerAsset.fileName)) { throw 'Explicit package creation did not preserve validated Setup and release metadata.' }
Write-Output 'PASS: explicit creation uses the complete same-source portable and installer inventories.'
$before = (Get-FileHash -LiteralPath $created.Metadata).Hash
Assert-InstallableRejected 'existing installable output is never overwritten' { Invoke-InstallableCreation $createdPath } '*fresh child directory*'
if ((Get-FileHash -LiteralPath $created.Metadata).Hash -cne $before) { throw 'An existing installable descriptor was modified.' }

$buildPath = Join-Path $fixture.InstallerDirectory 'installer-build.json'
$buildText = [IO.File]::ReadAllText($buildPath)
$build = $buildText | ConvertFrom-Json
try {
    $build.isolated = $true
    $build | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $buildPath -Encoding utf8NoBOM
    Assert-InstallableRejected 'creation refuses isolated test installation identities' {
        Invoke-InstallableCreation (Join-Path $fixture.RepositoryRoot 'target/winui/releases/isolated-creation')
    } '*non-isolated*'
} finally { [IO.File]::WriteAllText($buildPath, $buildText) }

$setupPath = Join-Path $fixture.InstallerDirectory $build.installer.fileName
$setupBytes = [IO.File]::ReadAllBytes($setupPath)
try {
    [IO.File]::WriteAllText($setupPath, 'Different Setup from another build, despite a matching filename.')
    Assert-InstallableRejected 'creation rejects Setup bytes from a different build before packaging' {
        Invoke-InstallableCreation (Join-Path $fixture.RepositoryRoot 'target/winui/releases/foreign-setup')
    } '*asset metadata does not match the actual bytes*'
} finally { [IO.File]::WriteAllBytes($setupPath, $setupBytes) }

$dependencyPath = Join-Path $fixture.PublishDirectory 'extra-runtime-dependency.dll'
$dependencyBytes = [IO.File]::ReadAllBytes($dependencyPath)
try {
    [IO.File]::WriteAllText($dependencyPath, 'Same version, different build payload.')
    Assert-InstallableRejected 'creation rejects same-version portable bytes from a different installer payload' {
        Invoke-InstallableCreation (Join-Path $fixture.RepositoryRoot 'target/winui/releases/mixed-payload')
    } '*payload differs from the portable bytes*'
} finally { [IO.File]::WriteAllBytes($dependencyPath, $dependencyBytes) }

if ($IsWindows) {
    $protected = Join-Path $root 'protected'
    [IO.Directory]::CreateDirectory($protected) | Out-Null
    $sentinel = Join-Path $protected 'sentinel.txt'
    [IO.File]::WriteAllText($sentinel, 'Keep untouched.')
    $link = Join-Path $fixture.RepositoryRoot 'target/winui/releases/redirect'
    New-Item -ItemType Junction -Path $link -Target $protected | Out-Null
    try {
        Assert-InstallableRejected 'creation rejects output junctions without changing their target' {
            Invoke-InstallableCreation (Join-Path $link 'new')
        } '*reparse points*'
        if ([IO.File]::ReadAllText($sentinel) -cne 'Keep untouched.' -or @(Get-ChildItem -LiteralPath $protected).Count -ne 1) { throw 'A release output junction target was changed.' }
    } finally { Remove-Item -LiteralPath $link }
}

# Build each omission/empty-file fixture before producing its ZIP and manifests.
# All recorded inventories and checksums therefore agree with the actual bytes;
# rejecting it requires the schema-2 mandatory-content contract, not stale hashes.
$acceptedIncomplete = [Collections.Generic.List[string]]::new()
foreach ($required in @('THIRD_PARTY_NOTICES.md', 'LICENSES/index.json')) {
    foreach ($scenario in @('missing', 'empty')) {
        $caseRoot = Join-Path $root ($scenario + '-' + $required.Replace('/', '-').Replace('.', '-'))
        $fixtureParameters = @{ Root = $caseRoot }
        if ($scenario -eq 'missing') { $fixtureParameters.OmitThirdPartyFile = $required }
        else { $fixtureParameters.EmptyThirdPartyFile = $required }
        $incompleteFixture = New-WinUIInstallableReleaseTestFixture @fixtureParameters
        $incompletePackage = New-WinUIInstallableReleaseTestPackage $incompleteFixture
        $label = "$scenario $required is rejected with consistent ZIP, inventories and checksums"
        $pattern = if ($scenario -eq 'missing') { "*missing deployment content: $required" } else { '*invalid path, size or hash*' }
        try {
            Assert-InstallableRejected $label { Test-WinUIReleaseArtifactDirectory $incompletePackage.Directory } $pattern
        } catch {
            if ($_.Exception.Message -cne "$label unexpectedly succeeded.") { throw }
            $acceptedIncomplete.Add($label)
            Write-Output "RED: $($_.Exception.Message)"
        }
    }
}
if ($acceptedIncomplete.Count -gt 0) { throw ($acceptedIncomplete -join '; ') }
Write-Output "Installable release byte fixtures: $root"
