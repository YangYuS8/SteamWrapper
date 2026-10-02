# Shared by tag preflight, real portable packaging and isolated regression tests.
# These functions do not create tags, publish releases, install software or sign files.
function Assert-WinUIReleasePath([string]$Path, [string]$AllowedRoot) {
    $full = [IO.Path]::GetFullPath($Path)
    $allowed = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($full -ne $allowed -and -not $full.StartsWith($allowed + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release path is outside the allowed directory: $full"
    }
    $ancestor = $full
    while ($ancestor) {
        $existing = Get-Item -LiteralPath $ancestor -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Release paths must not contain reparse points: $ancestor"
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}

function Read-WinUIReleaseText([string]$Path, [string]$RepositoryRoot, [long]$MaxBytes = 256KB) {
    $null = Assert-WinUIReleasePath $Path $RepositoryRoot
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Release input is missing: $Path" }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -eq 0 -or $item.Length -gt $MaxBytes) { throw "Release text must be non-empty and at most $MaxBytes bytes: $Path" }
    return [IO.File]::ReadAllText($Path)
}

function Get-WinUIReleaseRequiredFiles {
    return @(
        'SteamWrapper.Manager.exe', 'SteamWrapper.Manager.dll', 'SteamWrapper.Application.dll', 'SteamWrapper.Manager.pri',
        'SteamWrapper.Manager.runtimeconfig.json', 'SteamWrapper.Manager.deps.json',
        'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'System.Private.CoreLib.dll',
        'Microsoft.UI.Xaml.dll', 'Microsoft.WindowsAppRuntime.dll', 'Microsoft.Windows.Storage.Pickers.Projection.dll',
        'Runner/SteamWrapperRunner.exe', 'Runner/runner-manifest.json',
        'Assets/steamwrapper.svg', 'Assets/steamwrapper.ico', 'zh-CN/SteamWrapper.Application.resources.dll'
    )
}

function Get-WinUIReleaseTag([string]$Tag) {
    $number = '(?:0|[1-9][0-9]*)'
    $identifier = '(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    if ($Tag.Length -gt 80 -or $Tag -cnotmatch "^v(?<base>$number\.$number\.$number)(?:-(?<pre>$identifier(?:\.$identifier)*))?$" ) {
        throw 'Release tag must be strict vMAJOR.MINOR.PATCH[-prerelease] SemVer without build metadata or leading numeric zeroes.'
    }
    return [pscustomobject]@{ Version = $Matches['base']; Prerelease = $Matches.ContainsKey('pre') }
}

function Get-WinUIReleasePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    $tagVersion = Get-WinUIReleaseTag $Tag
    $baseVersion = $tagVersion.Version
    $tagPrerelease = $tagVersion.Prerelease
    if ($Commit -cnotmatch '^[0-9a-f]{40}$') { throw 'Release commit must be an exact lowercase 40-character Git SHA.' }
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $null = Assert-WinUIReleasePath $root $root
    $projectPath = Join-Path $root 'apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj'
    $projectText = Read-WinUIReleaseText $projectPath $root
    $xmlSettings = [Xml.XmlReaderSettings]::new()
    $xmlSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($projectText), $xmlSettings)
    try { $project = [Xml.XmlDocument]::new(); $project.Load($reader) }
    finally { $reader.Dispose() }
    $versions = @($project.SelectNodes('/Project/PropertyGroup/Version'))
    if ($versions.Count -ne 1 -or $versions[0].InnerText -cne $baseVersion) {
        throw "Release base version $baseVersion must match the single Manager project Version."
    }
    foreach ($crate in @('core', 'runner')) {
        $cargo = Read-WinUIReleaseText (Join-Path $root "crates/$crate/Cargo.toml") $root
        $cargoVersions = [regex]::Matches($cargo, '(?m)^version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*$')
        if ($cargoVersions.Count -ne 1 -or $cargoVersions[0].Groups[1].Value -cne $baseVersion) {
            throw "Release base version $baseVersion must match the single $crate Cargo package version."
        }
    }
    $notes = @()
    foreach ($language in @('en', 'zh-CN')) {
        $path = Join-Path $root "releases/$Tag.$language.md"
        $text = Read-WinUIReleaseText $path $root
        if ($text -notmatch ('(?m)^#{1,6}\s+.*' + [regex]::Escape($Tag) + '(?:\s|$)') -or
            @($text -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -lt 2) {
            throw "Release notes require a heading containing $Tag and a non-empty body: $path"
        }
        $notes += [pscustomobject]@{ Language = $language; Path = $path; FileName = [IO.Path]::GetFileName($path) }
    }
    $license = Join-Path $root 'LICENSE'
    $null = Read-WinUIReleaseText $license $root
    return [pscustomobject]@{
        Tag = $Tag; Version = $baseVersion; Commit = $Commit; TagPrerelease = $tagPrerelease
        RepositoryRoot = $root; Notes = $notes; LicensePath = $license
        # The current WinUI delivery gates do not justify a stable product claim.
        ReleaseChannel = 'preview'; GitHubPrerelease = $true; Signed = $false
    }
}

function Get-WinUIReleaseFiles([string]$PublishDirectory, [string]$RepositoryRoot) {
    $buildRoot = Join-Path $RepositoryRoot 'target/winui'
    $publish = Assert-WinUIReleasePath $PublishDirectory $buildRoot
    if (-not (Test-Path -LiteralPath $publish -PathType Container)) { throw 'Release publish directory is missing.' }
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($publish)
    $files = [Collections.Generic.List[object]]::new()
    [long]$bytes = 0
    [int]$visited = 0
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in [IO.DirectoryInfo]::new($directory).EnumerateFileSystemInfos()) {
            $visited++
            if ($visited -gt 10000) { throw 'Release publish tree exceeds the 10,000-entry limit.' }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Release contents must not contain reparse points: $($item.FullName)" }
            $relative = [IO.Path]::GetRelativePath($publish, $item.FullName).Replace('\', '/')
            if ($relative -match '[\r\n]' -or $relative -match '(?i)(^|/)(\.env(?:\..*)?|\.git|profiles\.toml|ui-settings\.json(?:\..*)?|logs|backups|cache)(/|$)') {
                throw "Release publish directory contains private or runtime data: $relative"
            }
            if ($item -is [IO.DirectoryInfo]) { $pending.Push($item.FullName); continue }
            $bytes += $item.Length
            if ($item.Length -gt 512MB -or $bytes -gt 1GB -or $files.Count -ge 5000) { throw 'Release publish files exceed the bounded package limits.' }
            $files.Add([pscustomobject]@{
                Path = $relative; FullName = $item.FullName; Bytes = $item.Length
                Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }
    return @($files | Sort-Object Path)
}

function New-WinUIReleasePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$PublishDirectory,
        [Parameter(Mandatory)][string]$OutputDirectory
    )
    $plan = Get-WinUIReleasePlan -Tag $Tag -Commit $Commit -RepositoryRoot $RepositoryRoot
    $releaseRoot = Join-Path $plan.RepositoryRoot 'target/winui/releases'
    $output = Assert-WinUIReleasePath $OutputDirectory $releaseRoot
    if ($output -eq [IO.Path]::GetFullPath($releaseRoot) -or (Test-Path -LiteralPath $output)) { throw 'Release output must be a fresh child directory; existing output is never overwritten.' }
    $files = @(Get-WinUIReleaseFiles -PublishDirectory $PublishDirectory -RepositoryRoot $plan.RepositoryRoot)
    $required = @(Get-WinUIReleaseRequiredFiles)
    foreach ($relative in $required) {
        $found = @($files | Where-Object { $_.Path -ieq $relative })
        if ($found.Count -ne 1 -or $found[0].Bytes -eq 0) { throw "Release is missing a non-empty required file: $relative" }
    }
    $manifestPath = Join-Path $PublishDirectory 'Runner/runner-manifest.json'
    $manifest = Read-WinUIReleaseText $manifestPath $plan.RepositoryRoot | ConvertFrom-Json
    foreach ($key in @('schemaVersion', 'contractVersion', 'version', 'sha256')) {
        if ($null -eq $manifest.PSObject.Properties[$key]) { throw "Runner manifest is missing $key." }
    }
    $runner = @($files | Where-Object { $_.Path -ieq 'Runner/SteamWrapperRunner.exe' })[0]
    if ($manifest.schemaVersion -ne 1 -or $manifest.contractVersion -ne 2 -or
        $manifest.version -cne $plan.Version -or $manifest.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $manifest.sha256 -cne $runner.Sha256) {
        throw 'Runner manifest schema, contract, version or SHA-256 does not match the release bytes.'
    }
    $runtime = Read-WinUIReleaseText (Join-Path $PublishDirectory 'SteamWrapper.Manager.runtimeconfig.json') $plan.RepositoryRoot | ConvertFrom-Json
    if ($null -eq $runtime.PSObject.Properties['runtimeOptions'] -or
        $null -eq $runtime.runtimeOptions.PSObject.Properties['includedFrameworks'] -or
        @($runtime.runtimeOptions.includedFrameworks | Where-Object { $_.name -eq 'Microsoft.NETCore.App' }).Count -ne 1) {
        throw 'Release Manager runtime configuration must declare its included self-contained .NET runtime.'
    }
    $staging = Join-Path $releaseRoot ('.staging-' + [Guid]::NewGuid().ToString('N'))
    $null = Assert-WinUIReleasePath $staging $releaseRoot
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    $stem = "SteamWrapper-$Tag-win-x64"
    $archivePath = Join-Path $staging "$stem.zip"
    $archiveFiles = [Collections.Generic.List[object]]::new()
    foreach ($file in $files) { $archiveFiles.Add($file) }
    $archiveFiles.Add([pscustomobject]@{ Path = 'LICENSE'; FullName = $plan.LicensePath; Bytes = (Get-Item -LiteralPath $plan.LicensePath).Length; Sha256 = (Get-FileHash -LiteralPath $plan.LicensePath).Hash.ToLowerInvariant() })
    foreach ($note in $plan.Notes) {
        $archiveFiles.Add([pscustomobject]@{ Path = "ReleaseNotes/$($note.FileName)"; FullName = $note.Path; Bytes = (Get-Item -LiteralPath $note.Path).Length; Sha256 = (Get-FileHash -LiteralPath $note.Path).Hash.ToLowerInvariant() })
    }
    $archiveStream = [IO.FileStream]::new($archivePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($file in $archiveFiles) {
            $entry = $archive.CreateEntry("$stem/$($file.Path)", [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $input = [IO.FileStream]::new($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $entryStream = $entry.Open()
            try { $input.CopyTo($entryStream) } finally { $entryStream.Dispose(); $input.Dispose() }
        }
    } finally { $archive.Dispose(); $archiveStream.Dispose() }
    # Check the actual compressed artifact, including every published dependency.
    $check = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        if ($check.Entries.Count -ne $archiveFiles.Count) { throw 'Release ZIP entry count does not match the inspected publish directory.' }
        foreach ($file in $archiveFiles) {
            $entry = $check.GetEntry("$stem/$($file.Path)")
            if ($null -eq $entry -or $entry.Length -ne $file.Bytes) { throw "Release ZIP lost or changed a file: $($file.Path)" }
            $entryStream = $entry.Open()
            try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($entryStream)).ToLowerInvariant() }
            finally { $entryStream.Dispose() }
            if ($hash -cne $file.Sha256) { throw "Release ZIP file hash differs from the inspected input: $($file.Path)" }
        }
    } finally { $check.Dispose() }
    foreach ($note in $plan.Notes) { Copy-Item -LiteralPath $note.Path -Destination (Join-Path $staging $note.FileName) }
    $metadata = [ordered]@{
        schemaVersion = 1; tag = $Tag; version = $plan.Version; commit = $Commit; platform = 'win-x64'
        minimumWindowsVersion = '10.0.26100.0'; releaseChannel = $plan.ReleaseChannel
        tagPrerelease = $plan.TagPrerelease; githubPrerelease = $plan.GitHubPrerelease
        signed = $false; installer = $false; portable = $true
        archive = [ordered]@{ fileName = "$stem.zip"; bytes = (Get-Item -LiteralPath $archivePath).Length; sha256 = (Get-FileHash -LiteralPath $archivePath).Hash.ToLowerInvariant() }
        runner = [ordered]@{ version = $manifest.version; contractVersion = $manifest.contractVersion; sha256 = $runner.Sha256 }
        files = @($archiveFiles | ForEach-Object { [ordered]@{ path = $_.Path; bytes = $_.Bytes; sha256 = $_.Sha256 } })
    }
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $staging 'release.json') -Encoding utf8NoBOM
    $sums = @(Get-ChildItem -LiteralPath $staging -File | Sort-Object Name | ForEach-Object { "$( (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $($_.Name)" })
    $sums | Set-Content -LiteralPath (Join-Path $staging 'SHA256SUMS') -Encoding utf8NoBOM
    $null = Assert-WinUIReleasePath $staging $releaseRoot
    $null = Assert-WinUIReleasePath $output $releaseRoot
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($output)) -Force | Out-Null
    [IO.Directory]::Move($staging, $output)
    return [pscustomobject]@{ Directory = $output; Archive = Join-Path $output "$stem.zip"; Metadata = Join-Path $output 'release.json'; Checksums = Join-Path $output 'SHA256SUMS' }
}

function Test-WinUIReleasePackageDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageDirectory)
    $package = [IO.Path]::GetFullPath($PackageDirectory)
    $null = Assert-WinUIReleasePath $package $package
    if (-not (Test-Path -LiteralPath $package -PathType Container)) { throw 'Release package directory is missing.' }
    $assets = @(Get-ChildItem -LiteralPath $package -Force)
    if ($assets.Count -ne 5) { throw 'Release package must contain exactly five expected assets.' }
    foreach ($asset in $assets) {
        if ($asset.PSIsContainer -or $asset.Attributes -band [IO.FileAttributes]::ReparsePoint -or $asset.Length -eq 0 -or $asset.Length -gt 1GB) {
            throw 'Release package assets must be non-empty bounded regular files, without reparse points.'
        }
    }
    $sumsPath = Join-Path $package 'SHA256SUMS'
    $sums = Read-WinUIReleaseText $sumsPath $package
    $checksumFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in @($sums -split '\r?\n' | Where-Object { $_ -ne '' })) {
        if ($line -cnotmatch '^(?<hash>[0-9a-f]{64})  (?<name>[A-Za-z0-9._-]+)$') { throw 'Release checksums contain an unsafe filename or invalid SHA-256 line.' }
        $expectedHash = $Matches['hash']; $name = $Matches['name']
        if ($name -eq 'SHA256SUMS' -or -not $checksumFiles.Add($name)) { throw 'Release checksums contain duplicate or self-referencing assets.' }
        $path = Join-Path $package $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $expectedHash) {
            throw "Release asset checksum mismatch or missing file: $name"
        }
    }
    if ($checksumFiles.Count -ne 4 -or -not $checksumFiles.Contains('release.json')) { throw 'Release checksums must cover exactly four assets including release.json.' }
    $metadata = Read-WinUIReleaseText (Join-Path $package 'release.json') $package 2MB | ConvertFrom-Json
    foreach ($key in @('schemaVersion', 'tag', 'version', 'commit', 'platform', 'minimumWindowsVersion', 'releaseChannel', 'tagPrerelease', 'githubPrerelease', 'signed', 'installer', 'portable', 'archive', 'runner', 'files')) {
        if ($null -eq $metadata.PSObject.Properties[$key]) { throw "Release metadata is missing $key." }
    }
    $tagVersion = Get-WinUIReleaseTag $metadata.tag
    if ($metadata.schemaVersion -ne 1 -or $metadata.version -cne $tagVersion.Version -or $metadata.commit -cnotmatch '^[0-9a-f]{40}$' -or
        $metadata.platform -cne 'win-x64' -or $metadata.minimumWindowsVersion -cne '10.0.26100.0' -or $metadata.releaseChannel -cne 'preview' -or
        $metadata.githubPrerelease -isnot [bool] -or -not $metadata.githubPrerelease -or
        $metadata.tagPrerelease -isnot [bool] -or $metadata.tagPrerelease -ne $tagVersion.Prerelease -or
        $metadata.signed -isnot [bool] -or $metadata.signed -or $metadata.installer -isnot [bool] -or $metadata.installer -or
        $metadata.portable -isnot [bool] -or -not $metadata.portable) { throw 'Release metadata is not an exact-version Windows x64 unsigned portable preview.' }
    $stem = "SteamWrapper-$($metadata.tag)-win-x64"
    $expectedAssets = @("$stem.zip", "$($metadata.tag).en.md", "$($metadata.tag).zh-CN.md", 'release.json')
    foreach ($name in $expectedAssets) { if (-not $checksumFiles.Contains($name)) { throw "Release package is missing the expected asset: $name" } }
    foreach ($key in @('fileName', 'bytes', 'sha256')) { if ($null -eq $metadata.archive.PSObject.Properties[$key]) { throw "Release archive metadata is missing $key." } }
    $archivePath = Join-Path $package "$stem.zip"
    if ($metadata.archive.fileName -cne "$stem.zip" -or $metadata.archive.bytes -ne (Get-Item -LiteralPath $archivePath).Length -or
        $metadata.archive.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $metadata.archive.sha256 -cne (Get-FileHash -LiteralPath $archivePath).Hash.ToLowerInvariant()) {
        throw 'Release archive metadata does not match the compressed asset.'
    }
    $records = @($metadata.files)
    if ($records.Count -eq 0 -or $records.Count -gt 5003) { throw 'Release file inventory is empty or exceeds the bounded entry limit.' }
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long]$totalBytes = 0
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        if ($archive.Entries.Count -ne $records.Count) { throw 'Release ZIP entries differ from the file inventory.' }
        foreach ($record in $records) {
            foreach ($key in @('path', 'bytes', 'sha256')) { if ($null -eq $record.PSObject.Properties[$key]) { throw "Release file inventory is missing $key." } }
            if ($record.path -isnot [string] -or $record.path -match '[\\:\x00-\x1f]' -or $record.path.StartsWith('/') -or
                @($record.path.Split('/') | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0 -or -not $paths.Add($record.path) -or
                $record.bytes -isnot [long] -and $record.bytes -isnot [int] -or $record.bytes -lt 0 -or $record.bytes -gt 512MB -or
                $record.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Release file inventory contains an unsafe path, duplicate, size or SHA-256.' }
            if ($record.path -match '(?i)(^|/)(\.env(?:\..*)?|\.git|profiles\.toml|ui-settings\.json(?:\..*)?|logs|backups|cache)(/|$)') {
                throw 'Release file inventory contains private or runtime data.'
            }
            $totalBytes += $record.bytes
            if ($totalBytes -gt 1GB + 768KB) { throw 'Release ZIP exceeds the bounded uncompressed size limit.' }
            $entry = $archive.GetEntry("$stem/$($record.path)")
            if ($null -eq $entry -or $entry.Length -ne $record.bytes) { throw "Release ZIP entry is missing or has the wrong length: $($record.path)" }
            $stream = $entry.Open()
            try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() }
            finally { $stream.Dispose() }
            if ($hash -cne $record.sha256) { throw "Release ZIP entry checksum mismatch: $($record.path)" }
        }
    } finally { $archive.Dispose() }
    foreach ($required in @((Get-WinUIReleaseRequiredFiles)) + @('LICENSE', "ReleaseNotes/$($metadata.tag).en.md", "ReleaseNotes/$($metadata.tag).zh-CN.md")) {
        $record = @($records | Where-Object { $_.path -ieq $required })
        if (-not $paths.Contains($required) -or $record[0].bytes -eq 0) { throw "Release file inventory is missing non-empty required content: $required" }
    }
    foreach ($key in @('version', 'contractVersion', 'sha256')) { if ($null -eq $metadata.runner.PSObject.Properties[$key]) { throw "Release Runner metadata is missing $key." } }
    $runner = @($records | Where-Object { $_.path -ieq 'Runner/SteamWrapperRunner.exe' })[0]
    if ($metadata.runner.version -cne $metadata.version -or $metadata.runner.contractVersion -ne 2 -or $metadata.runner.sha256 -cne $runner.sha256) { throw 'Release Runner metadata differs from the packaged Runner.' }
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $manifestRecord = @($records | Where-Object { $_.path -ieq 'Runner/runner-manifest.json' })[0]
        $runtimeRecord = @($records | Where-Object { $_.path -ieq 'SteamWrapper.Manager.runtimeconfig.json' })[0]
        if ($manifestRecord.bytes -gt 256KB -or $runtimeRecord.bytes -gt 256KB) { throw 'Packaged Runner/runtime JSON exceeds the bounded text limit.' }
        $manifestReader = [IO.StreamReader]::new($archive.GetEntry("$stem/$($manifestRecord.path)").Open())
        try { $manifest = $manifestReader.ReadToEnd() | ConvertFrom-Json } finally { $manifestReader.Dispose() }
        foreach ($key in @('schemaVersion', 'contractVersion', 'version', 'sha256')) { if ($null -eq $manifest.PSObject.Properties[$key]) { throw "Packaged Runner manifest is missing $key." } }
        if ($manifest.schemaVersion -ne 1 -or $manifest.contractVersion -ne 2 -or $manifest.version -cne $metadata.version -or $manifest.sha256 -cne $runner.sha256) {
            throw 'Packaged Runner manifest does not match the release Runner bytes/version/contract.'
        }
        $runtimeReader = [IO.StreamReader]::new($archive.GetEntry("$stem/$($runtimeRecord.path)").Open())
        try { $runtime = $runtimeReader.ReadToEnd() | ConvertFrom-Json } finally { $runtimeReader.Dispose() }
        if ($null -eq $runtime.PSObject.Properties['runtimeOptions'] -or $null -eq $runtime.runtimeOptions.PSObject.Properties['includedFrameworks'] -or
            @($runtime.runtimeOptions.includedFrameworks | Where-Object { $_.name -eq 'Microsoft.NETCore.App' }).Count -ne 1) {
            throw 'Packaged Manager runtime configuration is not self-contained.'
        }
    } finally { $archive.Dispose() }
    foreach ($language in @('en', 'zh-CN')) {
        $note = @($records | Where-Object { $_.path -ceq "ReleaseNotes/$($metadata.tag).$language.md" })[0]
        $attachedHash = (Get-FileHash -LiteralPath (Join-Path $package "$($metadata.tag).$language.md")).Hash.ToLowerInvariant()
        if ($note.sha256 -cne $attachedHash) { throw 'Attached release notes differ from the packaged notes.' }
    }
    return $metadata
}
