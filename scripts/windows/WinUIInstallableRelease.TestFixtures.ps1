# Byte-contract fixtures only. Their EXE/DLL files are text and never prove
# Windows installer resources, installation behavior or signing.
. (Join-Path $PSScriptRoot 'WinUIRelease.TestFixtures.ps1')
function New-WinUIInstallableReleaseTestFixture {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Tag = 'v0.2.0',
        [ValidateSet('THIRD_PARTY_NOTICES.md', 'LICENSES/index.json')][string]$OmitThirdPartyFile,
        [ValidateSet('THIRD_PARTY_NOTICES.md', 'LICENSES/index.json')][string]$EmptyThirdPartyFile
    )
    $fixture = New-WinUIReleaseTestFixture -Root $Root -Tag $Tag
    $version = (Get-WinUIReleaseTag $Tag).Version
    foreach ($relative in @('SteamWrapper.Deployment.dll', 'Deployment/SteamWrapper.exe', 'THIRD_PARTY_NOTICES.md', 'LICENSES/index.json')) {
        if ($relative -ceq $OmitThirdPartyFile) { continue }
        $path = Join-Path $fixture.PublishDirectory $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        $content = if ($relative -ceq $EmptyThirdPartyFile) { '' }
        elseif ($relative -ceq 'LICENSES/index.json') { '{"schemaVersion":1,"files":[],"fixtureOnly":true}' }
        else { "Non-executable installer fixture: $relative" }
        [IO.File]::WriteAllText($path, $content)
    }
    $installer = Join-Path $fixture.RepositoryRoot 'target/winui/installers/fixture'
    [IO.Directory]::CreateDirectory($installer) | Out-Null
    $files = @(Get-WinUIReleaseFiles $fixture.PublishDirectory $fixture.RepositoryRoot | ForEach-Object {
        [ordered]@{ path = $_.Path; bytes = $_.Bytes; sha256 = $_.Sha256 }
    })
    $license = Join-Path $fixture.RepositoryRoot 'LICENSE'
    $files += [ordered]@{ path = 'LICENSE'; bytes = (Get-Item -LiteralPath $license).Length; sha256 = (Get-FileHash -LiteralPath $license).Hash.ToLowerInvariant() }
    $manifest = [ordered]@{ schemaVersion = 1; appId = 'SteamWrapper'; tag = $fixture.Tag; version = $version; deploymentProtocol = 1; profileContract = 2; runnerContract = 2; managerExecutable = 'SteamWrapper.Manager.exe'; files = $files }
    $manifestPath = Join-Path $installer 'deployment-manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $name = "SteamWrapper-$($fixture.Tag)-win-x64-setup.exe"
    $setup = Join-Path $installer $name
    [IO.File]::WriteAllText($setup, 'Non-executable Setup byte-contract fixture; not a PE or acceptance result.')
    $setupRecord = [ordered]@{ fileName = $name; bytes = (Get-Item -LiteralPath $setup).Length; sha256 = (Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant(); signed = $false; canonicalIconFrames = 1 }
    $build = [ordered]@{ schemaVersion = 1; tag = $fixture.Tag; version = $version; platform = 'win-x64'; installer = $setupRecord; isolated = $false; deploymentManifestSha256 = (Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant(); payloadFiles = $files.Count }
    [IO.File]::WriteAllText((Join-Path $installer 'installer-build.json'), ($build | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $fixture | Add-Member -NotePropertyName InstallerDirectory -NotePropertyValue $installer
    return $fixture
}

function Update-WinUIInstallableFixtureChecksums([string]$Directory) {
    @(Get-ChildItem -LiteralPath $Directory -File | Where-Object Name -ne 'SHA256SUMS' | Sort-Object Name |
        ForEach-Object { "$((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $($_.Name)" }) |
        Set-Content -LiteralPath (Join-Path $Directory 'SHA256SUMS') -Encoding utf8NoBOM
}

# Independently assemble a descriptor so the positive validator test does not
# just echo the implementation's package-generation code.
function New-WinUIInstallableReleaseTestPackage($Fixture) {
    $package = New-WinUIReleasePackage -Tag $Fixture.Tag -Commit $Fixture.Commit -RepositoryRoot $Fixture.RepositoryRoot -PublishDirectory $Fixture.PublishDirectory -OutputDirectory $Fixture.OutputDirectory
    $portablePath = Join-Path $package.Directory 'portable-release.json'
    [IO.File]::Move($package.Metadata, $portablePath)
    $portable = [IO.File]::ReadAllText($portablePath) | ConvertFrom-Json
    $build = [IO.File]::ReadAllText((Join-Path $Fixture.InstallerDirectory 'installer-build.json')) | ConvertFrom-Json
    $manifestPath = Join-Path $Fixture.InstallerDirectory 'deployment-manifest.json'
    $installer = [ordered]@{ fileName = $build.installer.fileName; bytes = $build.installer.bytes; sha256 = $build.installer.sha256 }
    $metadata = [ordered]@{
        schemaVersion = 2; tag = $portable.tag; version = $portable.version; commit = $portable.commit; platform = $portable.platform
        minimumWindowsVersion = $portable.minimumWindowsVersion; releaseChannel = $portable.releaseChannel; tagPrerelease = $portable.tagPrerelease
        githubPrerelease = $portable.githubPrerelease; signed = $false; installer = $true; portable = $true; archive = $portable.archive
        portableMetadata = [ordered]@{ fileName = 'portable-release.json'; bytes = (Get-Item -LiteralPath $portablePath).Length; sha256 = (Get-FileHash -LiteralPath $portablePath).Hash.ToLowerInvariant() }
        installerAsset = $installer; installerBuild = $build
        deploymentManifest = [ordered]@{ bytes = (Get-Item -LiteralPath $manifestPath).Length; sha256 = (Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant(); json = [IO.File]::ReadAllText($manifestPath) }
    }
    Copy-Item -LiteralPath (Join-Path $Fixture.InstallerDirectory $installer.fileName) -Destination (Join-Path $package.Directory $installer.fileName)
    $metadata | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $package.Metadata -Encoding utf8NoBOM
    Update-WinUIInstallableFixtureChecksums $package.Directory
    return $package
}
