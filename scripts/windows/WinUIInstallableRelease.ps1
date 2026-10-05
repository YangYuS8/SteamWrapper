# Explicit schema-2 installable releases. The historical five-asset schema-1
# contract is validated unchanged; these helpers never sign or publish files.
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')

function Assert-WinUIInstallableFields($Object, [string[]]$Names) {
    if ($Object -isnot [pscustomobject]) { throw 'Installable release metadata must contain JSON objects.' }
    foreach ($name in $Names) {
        if ($null -eq $Object.PSObject.Properties[$name]) { throw "Installable release metadata is missing $name." }
    }
    if (@($Object.PSObject.Properties).Count -ne $Names.Count) { throw 'Installable release metadata contains unsupported fields.' }
}

function Assert-WinUIInstallableJsonProperties([Text.Json.JsonElement]$Element) {
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'Installable release JSON contains duplicate property names.' }
            Assert-WinUIInstallableJsonProperties $property.Value
        }
    } elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-WinUIInstallableJsonProperties $item }
    }
}

function ConvertFrom-WinUIInstallableJson([string]$Text) {
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 32
    $document = [Text.Json.JsonDocument]::Parse($Text, $options)
    try { Assert-WinUIInstallableJsonProperties $document.RootElement }
    finally { $document.Dispose() }
    return $Text | ConvertFrom-Json -Depth 32
}

function Get-WinUIReleaseAssetNames($Metadata) {
    $names = @($Metadata.archive.fileName, "$($Metadata.tag).en.md", "$($Metadata.tag).zh-CN.md", 'release.json', 'SHA256SUMS')
    if ($Metadata.schemaVersion -eq 2) { $names += @('portable-release.json', $Metadata.installerAsset.fileName) }
    elseif ($Metadata.schemaVersion -ne 1) { throw 'Unsupported release package schema.' }
    return $names
}

function Assert-WinUIInstallableAsset($Record, [string]$ExpectedName, [string]$Directory, [long]$MaximumBytes = 1GB, [switch]$BuildRecord) {
    $fields = @('fileName', 'bytes', 'sha256')
    if ($BuildRecord) { $fields += @('signed', 'canonicalIconFrames') }
    Assert-WinUIInstallableFields $Record $fields
    $path = Join-Path $Directory $ExpectedName
    if ($Record.fileName -cne $ExpectedName -or ($Record.bytes -isnot [int] -and $Record.bytes -isnot [long]) -or
        $Record.bytes -le 0 -or $Record.bytes -gt $MaximumBytes -or $Record.bytes -ne (Get-Item -LiteralPath $path).Length -or
        $Record.sha256 -isnot [string] -or $Record.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $Record.sha256 -cne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) {
        throw "Installable release asset metadata does not match the actual bytes: $ExpectedName"
    }
}

function Assert-WinUIInstallableBuildIdentity($Build, [string]$Tag, [string]$Version) {
    Assert-WinUIInstallableFields $Build @('schemaVersion', 'tag', 'version', 'platform', 'installer', 'isolated', 'deploymentManifestSha256', 'payloadFiles')
    Assert-WinUIInstallableFields $Build.installer @('fileName', 'bytes', 'sha256', 'signed', 'canonicalIconFrames')
    if (($Build.schemaVersion -isnot [int] -and $Build.schemaVersion -isnot [long]) -or $Build.schemaVersion -ne 1 -or
        $Build.tag -cne $Tag -or $Build.version -cne $Version -or $Build.platform -cne 'win-x64' -or
        $Build.isolated -isnot [bool] -or $Build.isolated -or $Build.installer.signed -isnot [bool] -or $Build.installer.signed -or
        ($Build.installer.bytes -isnot [int] -and $Build.installer.bytes -isnot [long]) -or
        ($Build.installer.canonicalIconFrames -isnot [int] -and $Build.installer.canonicalIconFrames -isnot [long]) -or
        $Build.installer.canonicalIconFrames -lt 1 -or $Build.installer.canonicalIconFrames -gt 64) {
        throw 'Installable previews require matching unsigned, non-isolated Windows installer build metadata.'
    }
}

function Assert-WinUIInstallableBinding($Metadata, $Portable) {
    $build = $Metadata.installerBuild
    Assert-WinUIInstallableBuildIdentity $build $Metadata.tag $Metadata.version
    foreach ($key in @('fileName', 'bytes', 'sha256')) {
        if ($build.installer.$key -cne $Metadata.installerAsset.$key) { throw 'Installer build metadata differs from the release Setup asset.' }
    }
    $embedded = $Metadata.deploymentManifest
    Assert-WinUIInstallableFields $embedded @('bytes', 'sha256', 'json')
    if ($embedded.json -isnot [string]) { throw 'The deployment manifest must preserve the original bounded JSON text.' }
    $manifestBytes = [Text.Encoding]::UTF8.GetBytes($embedded.json)
    if (($embedded.bytes -isnot [int] -and $embedded.bytes -isnot [long]) -or $embedded.bytes -le 0 -or $embedded.bytes -gt 1MB -or
        $manifestBytes.Length -ne $embedded.bytes -or $embedded.sha256 -isnot [string] -or $embedded.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($manifestBytes)).ToLowerInvariant() -cne $embedded.sha256 -or
        $build.deploymentManifestSha256 -cne $embedded.sha256) { throw 'Installer deployment manifest bytes/hash differ from the recorded build.' }
    $manifest = ConvertFrom-WinUIInstallableJson $embedded.json
    Assert-WinUIInstallableFields $manifest @('schemaVersion', 'appId', 'tag', 'version', 'deploymentProtocol', 'profileContract', 'runnerContract', 'managerExecutable', 'files')
    foreach ($key in @('schemaVersion', 'deploymentProtocol', 'profileContract', 'runnerContract')) {
        if ($manifest.$key -isnot [int] -and $manifest.$key -isnot [long]) { throw 'Installer deployment contract versions must be integers.' }
    }
    if ($manifest.schemaVersion -ne 1 -or $manifest.deploymentProtocol -ne 1 -or $manifest.profileContract -ne 2 -or $manifest.runnerContract -ne 2 -or
        $manifest.appId -cne 'SteamWrapper' -or $manifest.tag -cne $Metadata.tag -or $manifest.version -cne $Metadata.version -or
        $manifest.managerExecutable -cne 'SteamWrapper.Manager.exe') { throw 'Installer deployment manifest identity or contracts do not match the release.' }
    $expected = @{}
    foreach ($record in $Portable.files) {
        Assert-WinUIInstallableFields $record @('path', 'bytes', 'sha256')
        if ($record.path -ceq "ReleaseNotes/$($Metadata.tag).en.md" -or $record.path -ceq "ReleaseNotes/$($Metadata.tag).zh-CN.md") { continue }
        $expected[$record.path] = $record
    }
    $records = @($manifest.files)
    if ($records.Count -eq 0 -or $records.Count -gt 4096 -or $records.Count -ne $expected.Count -or
        ($build.payloadFiles -isnot [int] -and $build.payloadFiles -isnot [long]) -or $build.payloadFiles -ne $records.Count) {
        throw 'Installer deployment inventory does not match the complete portable payload.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long]$total = 0
    foreach ($record in $records) {
        Assert-WinUIInstallableFields $record @('path', 'bytes', 'sha256')
        if ($record.path -isnot [string] -or -not $seen.Add($record.path) -or
            ($record.bytes -isnot [int] -and $record.bytes -isnot [long]) -or $record.bytes -le 0 -or $record.bytes -gt 512MB -or
            $record.sha256 -isnot [string] -or $record.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Installer deployment inventory contains an invalid path, size or hash.' }
        foreach ($segment in $record.path.Split('/')) {
            if ($segment -in @('', '.', '..') -or $segment -match '[:\\\x00-\x1f]' -or $segment -match '[. ]$' -or
                $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Installer deployment inventory contains an unsafe relative path.' }
        }
        $total += $record.bytes
        if ($total -gt 1GB -or -not $expected.ContainsKey($record.path)) { throw 'Installer deployment inventory does not match the portable payload.' }
        $portableFile = $expected[$record.path]
        if ($record.path -cne $portableFile.path -or $record.bytes -ne $portableFile.bytes -or $record.sha256 -cne $portableFile.sha256) {
            throw "Installer deployment payload differs from the portable bytes: $($record.path)"
        }
    }
    foreach ($required in @('SteamWrapper.Deployment.dll', 'Deployment/SteamWrapper.exe', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'LICENSES/index.json')) {
        if (-not $seen.Contains($required)) { throw "Installable preview is missing deployment content: $required" }
    }
}

function Test-WinUIInstallableReleasePackageDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageDirectory)
    $package = [IO.Path]::GetFullPath($PackageDirectory)
    $null = Assert-WinUIReleasePath $package $package
    $assets = @(Get-ChildItem -LiteralPath $package -Force)
    if ($assets.Count -ne 7) { throw 'Installable release package must contain exactly seven expected assets.' }
    foreach ($asset in $assets) {
        if ($asset.PSIsContainer -or $asset.Attributes -band [IO.FileAttributes]::ReparsePoint -or $asset.Length -le 0 -or $asset.Length -gt 1GB) {
            throw 'Installable release assets must be non-empty bounded regular files without reparse points.'
        }
    }
    $metadataText = Read-WinUIReleaseText (Join-Path $package 'release.json') $package 2MB
    $metadata = ConvertFrom-WinUIInstallableJson $metadataText
    Assert-WinUIInstallableFields $metadata @('schemaVersion', 'tag', 'version', 'commit', 'platform', 'minimumWindowsVersion', 'releaseChannel', 'tagPrerelease', 'githubPrerelease', 'signed', 'installer', 'portable', 'archive', 'portableMetadata', 'installerAsset', 'installerBuild', 'deploymentManifest')
    if ($metadata.tag -isnot [string]) { throw 'Installable release tag must be a string.' }
    $tagVersion = Get-WinUIReleaseTag $metadata.tag
    if (($metadata.schemaVersion -isnot [int] -and $metadata.schemaVersion -isnot [long]) -or $metadata.schemaVersion -ne 2 -or
        $metadata.version -cne $tagVersion.Version -or $metadata.commit -isnot [string] -or $metadata.commit -cnotmatch '^[0-9a-f]{40}$' -or
        $metadata.platform -cne 'win-x64' -or $metadata.minimumWindowsVersion -cne '10.0.26100.0' -or $metadata.releaseChannel -cne $tagVersion.Channel -or
        $metadata.tagPrerelease -isnot [bool] -or $metadata.tagPrerelease -ne $tagVersion.Prerelease -or
        $metadata.githubPrerelease -isnot [bool] -or $metadata.githubPrerelease -ne $tagVersion.Prerelease -or $metadata.signed -isnot [bool] -or $metadata.signed -or
        $metadata.installer -isnot [bool] -or -not $metadata.installer -or $metadata.portable -isnot [bool] -or -not $metadata.portable) {
        throw 'Release metadata is not an exact-version Windows x64 unsigned installable release.'
    }
    $expectedNames = @(Get-WinUIReleaseAssetNames $metadata)
    $expectedSetup = "SteamWrapper-$($metadata.tag)-win-x64-setup.exe"
    if ($metadata.archive.fileName -cne "SteamWrapper-$($metadata.tag)-win-x64.zip" -or $metadata.installerAsset.fileName -cne $expectedSetup -or
        $metadata.portableMetadata.fileName -cne 'portable-release.json') { throw 'Installable release contains unexpected asset filenames.' }
    foreach ($asset in $assets) { if ($asset.Name -cnotin $expectedNames) { throw 'Installable release contains an unexpected asset.' } }
    foreach ($language in @('en', 'zh-CN')) {
        if ((Get-Item -LiteralPath (Join-Path $package "$($metadata.tag).$language.md")).Length -gt 256KB) { throw 'Installable release notes exceed the bounded text limit.' }
    }
    $checksums = @{}
    $sums = Read-WinUIReleaseText (Join-Path $package 'SHA256SUMS') $package 16KB
    foreach ($line in @($sums -split '\r?\n' | Where-Object { $_ -ne '' })) {
        if ($line -cnotmatch '^(?<hash>[0-9a-f]{64})  (?<name>[A-Za-z0-9._-]+)$') { throw 'Installable release checksums contain an unsafe filename or invalid line.' }
        $name = $Matches['name']; $hash = $Matches['hash']
        if ($name -ceq 'SHA256SUMS' -or $name -cnotin $expectedNames -or $checksums.ContainsKey($name)) { throw 'Installable release checksums contain a duplicate, self-reference or unexpected asset.' }
        $checksums[$name] = $hash
        if ($hash -cne (Get-FileHash -LiteralPath (Join-Path $package $name) -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "Release asset checksum mismatch: $name" }
    }
    if ($checksums.Count -ne 6) { throw 'Installable release checksums must cover exactly six payload/metadata assets.' }
    foreach ($name in $expectedNames | Where-Object { $_ -cne 'SHA256SUMS' }) {
        if (-not $checksums.ContainsKey($name)) { throw "Installable release checksums are missing $name." }
    }
    Assert-WinUIInstallableAsset $metadata.archive "SteamWrapper-$($metadata.tag)-win-x64.zip" $package
    Assert-WinUIInstallableAsset $metadata.portableMetadata 'portable-release.json' $package 2MB
    Assert-WinUIInstallableAsset $metadata.installerAsset $expectedSetup $package 512MB
    $declaredPortable = ConvertFrom-WinUIInstallableJson (Read-WinUIReleaseText (Join-Path $package 'portable-release.json') $package 2MB)
    Assert-WinUIInstallableFields $declaredPortable @('schemaVersion', 'tag', 'version', 'commit', 'platform', 'minimumWindowsVersion', 'releaseChannel', 'tagPrerelease', 'githubPrerelease', 'signed', 'installer', 'portable', 'archive', 'runner', 'files')
    Assert-WinUIInstallableFields $declaredPortable.runner @('version', 'contractVersion', 'sha256')

    # Reconstruct only the five legacy assets in a fresh bounded scratch. There
    # is no ZIP extraction and the original schema-1 validator remains intact.
    $scratchParent = Join-Path ([IO.Path]::GetTempPath()) 'SteamWrapper-release-validation'
    $scratch = Join-Path $scratchParent ([Guid]::NewGuid().ToString('N'))
    $null = Assert-WinUIReleasePath $scratch $scratchParent
    if (Test-Path -LiteralPath $scratch) { throw 'Release validation scratch must be fresh.' }
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    $scratchNames = @($metadata.archive.fileName, "$($metadata.tag).en.md", "$($metadata.tag).zh-CN.md", 'release.json', 'SHA256SUMS')
    try {
        foreach ($name in $scratchNames | Where-Object { $_ -cne 'SHA256SUMS' }) {
            $sourceName = if ($name -ceq 'release.json') { 'portable-release.json' } else { $name }
            [IO.File]::Copy((Join-Path $package $sourceName), (Join-Path $scratch $name), $false)
        }
        @(Get-ChildItem -LiteralPath $scratch -File | Sort-Object Name | ForEach-Object {
            "$((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $($_.Name)"
        }) | Set-Content -LiteralPath (Join-Path $scratch 'SHA256SUMS') -Encoding utf8NoBOM
        $portable = Test-WinUIReleasePackageDirectory -PackageDirectory $scratch
        foreach ($key in @('tag', 'version', 'commit', 'platform', 'minimumWindowsVersion', 'releaseChannel', 'tagPrerelease', 'githubPrerelease', 'signed', 'portable')) {
            if ($portable.$key -cne $metadata.$key) { throw "Installable and portable descriptors disagree on $key." }
        }
        foreach ($key in @('fileName', 'bytes', 'sha256')) {
            if ($portable.archive.$key -cne $metadata.archive.$key) { throw 'Installable and portable archive metadata differ.' }
        }
        Assert-WinUIInstallableBinding $metadata $portable
    } finally {
        # Never recursively delete a computed tree or an unexpected file. If
        # something replaced a scratch entry, retain it for inspection.
        $null = Assert-WinUIReleasePath $scratch $scratchParent
        $scratchEntries = @(Get-ChildItem -LiteralPath $scratch -Force)
        foreach ($entry in $scratchEntries) {
            if ($entry.PSIsContainer -or $entry.Attributes -band [IO.FileAttributes]::ReparsePoint -or $entry.Name -cnotin $scratchNames) {
                throw "Unexpected validation scratch contents retained at $scratch"
            }
        }
        foreach ($entry in $scratchEntries) { Remove-Item -LiteralPath $entry.FullName }
        [IO.Directory]::Delete($scratch, $false)
    }
    return $metadata
}

function Test-WinUIReleaseArtifactDirectory {
    param([Parameter(Mandatory)][string]$PackageDirectory)
    $directory = [IO.Path]::GetFullPath($PackageDirectory)
    $metadata = Read-WinUIReleaseText (Join-Path $directory 'release.json') $directory 2MB | ConvertFrom-Json
    if ($metadata.schemaVersion -eq 1) { return Test-WinUIReleasePackageDirectory -PackageDirectory $directory }
    if ($metadata.schemaVersion -eq 2) { return Test-WinUIInstallableReleasePackageDirectory -PackageDirectory $directory }
    throw 'Unsupported release package schema.'
}

function New-WinUIInstallableReleasePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$PublishDirectory,
        [Parameter(Mandatory)][string]$InstallerDirectory,
        [Parameter(Mandatory)][string]$OutputDirectory
    )
    $plan = Get-WinUIReleasePlan -Tag $Tag -Commit $Commit -RepositoryRoot $RepositoryRoot
    $releaseRoot = Join-Path $plan.RepositoryRoot 'target/winui/releases'
    $output = Assert-WinUIReleasePath $OutputDirectory $releaseRoot
    if ($output -eq [IO.Path]::GetFullPath($releaseRoot) -or (Test-Path -LiteralPath $output)) { throw 'Installable release output must be a fresh child directory; existing output is never overwritten.' }
    $installer = Assert-WinUIReleasePath $InstallerDirectory (Join-Path $plan.RepositoryRoot 'target/winui')
    $build = ConvertFrom-WinUIInstallableJson (Read-WinUIReleaseText (Join-Path $installer 'installer-build.json') $installer)
    Assert-WinUIInstallableBuildIdentity $build $Tag $plan.Version
    $manifestPath = Join-Path $installer 'deployment-manifest.json'
    $manifestText = Read-WinUIReleaseText $manifestPath $installer 1MB
    $setupName = "SteamWrapper-$Tag-win-x64-setup.exe"
    $setupPath = Join-Path $installer $setupName
    $null = Assert-WinUIReleasePath $setupPath $installer
    Assert-WinUIInstallableAsset $build.installer $setupName $installer 512MB -BuildRecord
    $staging = Join-Path $releaseRoot ('.installable-staging-' + [Guid]::NewGuid().ToString('N'))
    $legacy = New-WinUIReleasePackage -Tag $Tag -Commit $Commit -RepositoryRoot $plan.RepositoryRoot -PublishDirectory $PublishDirectory -OutputDirectory $staging
    $portable = Test-WinUIReleasePackageDirectory -PackageDirectory $staging
    $portablePath = Join-Path $staging 'portable-release.json'
    [IO.File]::Move($legacy.Metadata, $portablePath)
    $metadata = [ordered]@{
        schemaVersion = 2; tag = $Tag; version = $plan.Version; commit = $Commit; platform = 'win-x64'
        minimumWindowsVersion = '10.0.26100.0'; releaseChannel = $plan.ReleaseChannel; tagPrerelease = $plan.TagPrerelease
        githubPrerelease = $plan.GitHubPrerelease; signed = $false; installer = $true; portable = $true; archive = $portable.archive
        portableMetadata = [ordered]@{ fileName = 'portable-release.json'; bytes = (Get-Item -LiteralPath $portablePath).Length; sha256 = (Get-FileHash -LiteralPath $portablePath).Hash.ToLowerInvariant() }
        installerAsset = [ordered]@{ fileName = $setupName; bytes = (Get-Item -LiteralPath $setupPath).Length; sha256 = (Get-FileHash -LiteralPath $setupPath).Hash.ToLowerInvariant() }
        installerBuild = $build
        deploymentManifest = [ordered]@{ bytes = (Get-Item -LiteralPath $manifestPath).Length; sha256 = (Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant(); json = $manifestText }
    }
    # Validate the original build manifest against the actual portable bytes
    # before accepting/copying Setup; fixture EXEs are not PE/signature proof.
    $parsed = ConvertFrom-WinUIInstallableJson ($metadata | ConvertTo-Json -Depth 12)
    Assert-WinUIInstallableBinding $parsed $portable
    [IO.File]::Copy($setupPath, (Join-Path $staging $setupName), $false)
    $metadata | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $legacy.Metadata -Encoding utf8NoBOM
    @(Get-ChildItem -LiteralPath $staging -File | Where-Object Name -ne 'SHA256SUMS' | Sort-Object Name | ForEach-Object {
        "$((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $($_.Name)"
    }) | Set-Content -LiteralPath $legacy.Checksums -Encoding utf8NoBOM
    $null = Test-WinUIInstallableReleasePackageDirectory -PackageDirectory $staging
    $null = Assert-WinUIReleasePath $staging $releaseRoot
    $null = Assert-WinUIReleasePath $output $releaseRoot
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
    [IO.Directory]::Move($staging, $output)
    return [pscustomobject]@{ Directory = $output; Archive = Join-Path $output $portable.archive.fileName; Setup = Join-Path $output $setupName; Metadata = Join-Path $output 'release.json'; Checksums = Join-Path $output 'SHA256SUMS' }
}
