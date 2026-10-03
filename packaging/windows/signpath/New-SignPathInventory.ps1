[CmdletBinding()]
param([string]$PublishDirectory, [string]$OutputDirectory, [string]$SchemaPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Actual Windows publish inventory requires Windows.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$allowedRoot = Join-Path $repoRoot 'target/winui'
. (Join-Path $PSScriptRoot 'PreparationFiles.ps1')
. (Join-Path $PSScriptRoot 'SignPathConfiguration.ps1')
$policy = (Read-PreparationText -Path (Join-Path $PSScriptRoot 'inventory-policy.v1.json') -AllowedRoot $PSScriptRoot -MaximumBytes 256KB) | ConvertFrom-Json
if (-not $PublishDirectory) { $PublishDirectory = Join-Path $allowedRoot 'publish' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $allowedRoot ('signpath-dossier/' + [guid]::NewGuid().ToString('N')) }
$publish = [IO.Path]::GetFullPath($PublishDirectory)
$output = [IO.Path]::GetFullPath($OutputDirectory)
Assert-PreparationDisjointRoots -First $publish -Second $output
$null = Resolve-WindowsSigningFile -Path (Join-Path $publish 'inventory-guard') -AllowedRoot $allowedRoot -AllowMissing
$null = Resolve-WindowsSigningFile -Path (Join-Path $output 'inventory.json') -AllowedRoot $allowedRoot -AllowMissing
if (-not (Test-Path -LiteralPath $publish -PathType Container)) { throw 'The selected actual publish directory is missing.' }
if (Test-Path -LiteralPath $output) { throw 'Preserve previous dossiers; choose a new output directory.' }
$entries = @(Get-PreparationPublishFiles -Root $publish)
[IO.Directory]::CreateDirectory($output) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $output 'licenses')) | Out-Null
function Write-NewJson([string]$Name, $Value) {
    $path = Resolve-WindowsSigningFile -Path (Join-Path $output $Name) -AllowedRoot $output -AllowMissing
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 12))
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes) } finally { $stream.Dispose() }
}
function Read-SafeXml([string]$Path) {
    $file = Get-PreparationFile -Path $Path -AllowedRoot ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) -MaximumBytes 512KB
    $settings = [Xml.XmlReaderSettings]::new(); $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
    $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    if ($stream.Length -gt 512KB) { $stream.Dispose(); throw 'Preparation XML exceeds the byte limit.' }
    $reader = [Xml.XmlReader]::Create($stream, $settings)
    $document = [Xml.XmlDocument]::new(); $document.XmlResolver = $null
    try { $document.Load($reader) } finally { $reader.Dispose(); $stream.Dispose() }
    return $document
}
function Hash([string]$Path, [string]$AllowedRoot, [long]$MaximumBytes = 512MB) {
    if (-not $AllowedRoot) { $AllowedRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)) }
    $file = Get-PreparationFile -Path $Path -AllowedRoot $AllowedRoot -MaximumBytes $MaximumBytes
    return (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$fileInventory = @($entries | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($publish, $_.FullName).Replace('\', '/')
    $pe = $_.Extension -in @('.exe', '.dll')
    $owned = $relative -cin $policy.ownedPePaths
    $metadata = if ($pe) { [Diagnostics.FileVersionInfo]::GetVersionInfo($_.FullName) } else { $null }
    [ordered]@{ path = $relative; bytes = $_.Length; sha256 = Hash $_.FullName; classification = $(if ($owned) { 'own-pe-signing-target' } elseif ($pe) { 'upstream-pe-preserve-signatures' } else { 'non-pe-preserve-bytes' }); product = $(if ($metadata) { $metadata.ProductName } else { $null }); version = $(if ($metadata) { $metadata.ProductVersion } else { $null }) }
})
foreach ($path in $policy.ownedPePaths) { if ($path -cnotin $fileInventory.path) { throw "Own published PE is missing: $path" } }
$owned = @($fileInventory | Where-Object { $_.classification -ceq 'own-pe-signing-target' })
$source = Read-SafeXml (Join-Path $repoRoot 'apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj')
$sourceVersion = @($source.Project.PropertyGroup.Version | Where-Object { $_ })[0]
$coordinated = @($owned | Where-Object { $_.product -cne 'SteamWrapper' -or $_.version -cne $sourceVersion }).Count -eq 0

# Inventory resolved NuGet lock entries and original package licenses, not guessed
# SPDX labels from a similarly named source repository. No package restore occurs.
$packages = @{}; $folders = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$lockEvidence = [Collections.Generic.List[object]]::new()
foreach ($project in $policy.nugetProjects) {
    $lockPath = Join-Path $repoRoot "$project/packages.lock.json"
    $lock = (Read-PreparationText -Path $lockPath -AllowedRoot $repoRoot -MaximumBytes 2MB) | ConvertFrom-Json
    $lockEvidence.Add([ordered]@{ path = "$project/packages.lock.json"; sha256 = Hash $lockPath })
    foreach ($target in $lock.dependencies.PSObject.Properties) {
        foreach ($package in $target.Value.PSObject.Properties) {
            if ($package.Value.type -ceq 'Project') { continue }
            $id = $package.Name; $version = $package.Value.resolved
            if ($id -cnotmatch '^[A-Za-z0-9._-]+\z' -or $version -cnotmatch '^[A-Za-z0-9.+_-]+\z') { throw 'Unsafe or unresolved NuGet package identity.' }
            $key = "$id/$version"
            if (-not $packages.ContainsKey($key)) { $packages[$key] = [ordered]@{ id = $id; version = $version; owners = [Collections.Generic.List[string]]::new(); contentHash = $package.Value.contentHash } }
            if ($packages.Count -gt 128) { throw 'NuGet inventory exceeds the package-count limit.' }
            if ($project -notin $packages[$key].owners) { $packages[$key].owners.Add($project) }
        }
    }
    $assetsPath = Join-Path $repoRoot "$project/obj/project.assets.json"
    if (Test-Path -LiteralPath $assetsPath -PathType Leaf) {
        $assets = (Read-PreparationText -Path $assetsPath -AllowedRoot $repoRoot -MaximumBytes 8MB) | ConvertFrom-Json
        foreach ($folder in $assets.packageFolders.PSObject.Properties.Name) { $null = $folders.Add($folder) }
        if ($folders.Count -gt 8) { throw 'NuGet inventory exceeds the cache-root limit.' }
    }
}
$nuget = @($packages.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $package = $_.Value; $packageRoot = $null
    foreach ($folder in $folders) {
        $candidate = Join-Path $folder ($package.id.ToLowerInvariant() + '/' + $package.version.ToLowerInvariant())
        if (Test-Path -LiteralPath $candidate -PathType Container) { $packageRoot = $candidate; break }
    }
    $licenseKind = $null; $licenseValue = $null; $licenseUrl = $null; $licenseHash = $null; $copiedLicense = $null
    if ($packageRoot) {
        $null = Resolve-WindowsSigningFile -Path (Join-Path $packageRoot 'cache-guard') -AllowedRoot $packageRoot -AllowMissing
        $spec = [Collections.Generic.List[object]]::new()
        foreach ($specPath in [IO.Directory]::EnumerateFiles($packageRoot, '*.nuspec')) {
            if ($spec.Count -ge 2) { throw 'NuGet cache contains an ambiguous package specification.' }
            $spec.Add((Get-PreparationFile -Path $specPath -AllowedRoot $packageRoot -MaximumBytes 512KB))
        }
        if ($spec.Count -ne 1) { throw 'NuGet cache contains an ambiguous package specification.' }
        $xml = Read-SafeXml $spec[0].FullName
        $metadata = $xml.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]')
        $license = $metadata.SelectSingleNode('*[local-name()="license"]')
        $url = $metadata.SelectSingleNode('*[local-name()="licenseUrl"]')
        if ($url) { $licenseUrl = $url.InnerText }
        if ($license) {
            $licenseKind = $license.GetAttribute('type'); $licenseValue = $license.InnerText
            if ($licenseKind -ceq 'file') {
                $path = Resolve-WindowsSigningFile -Path (Join-Path $packageRoot $licenseValue) -AllowedRoot $packageRoot
                $license = Get-PreparationFile -Path $path -AllowedRoot $packageRoot -MaximumBytes 2MB
                $licenseHash = Hash $path $packageRoot 2MB
                $copiedLicense = "licenses/$($package.id)-$($package.version).txt"
                $input = [IO.File]::Open($license.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    if ($input.Length -gt 2MB) { throw 'NuGet legal file exceeds the preparation byte limit.' }
                    $target = [IO.File]::Open((Join-Path $output $copiedLicense), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    try { $input.CopyTo($target) } finally { $target.Dispose() }
                } finally { $input.Dispose() }
                if ((Hash (Join-Path $output $copiedLicense) $output 2MB) -cne $licenseHash) { throw 'NuGet license bytes changed after verification; preserve the partial dossier.' }
            }
        }
    }
    [ordered]@{ id = $package.id; version = $package.version; projects = @($package.owners); contentHash = $package.contentHash; classification = $(if ($package.id -cin $policy.toolsExcludedFromInstalledPayload) { 'build-tool' } else { 'upstream-package-never-re-sign' }); licenseKind = $licenseKind; licenseValue = $licenseValue; licenseUrl = $licenseUrl; licenseFileSha256 = $licenseHash; copiedLicense = $copiedLicense; reviewRequired = (-not $licenseKind -or $licenseKind -ceq 'file'); cacheAvailable = [bool]$packageRoot }
})

# Follow the actual Windows Runner non-dev dependency graph, including build
# dependencies. cargo metadata reads licenses from the resolved manifests.
Push-Location $repoRoot
try {
    $metadataJson = & cargo metadata --offline --locked --format-version 1 --filter-platform $policy.cargoTarget
    if ($LASTEXITCODE -ne 0) { throw 'cargo metadata failed; run with the pinned Rust toolchain on PATH.' }
} finally { Pop-Location }
$metadataJson = $metadataJson -join [Environment]::NewLine
if ($metadataJson.Length -gt 8MB) { throw 'Cargo metadata exceeds the preparation text limit.' }
$cargo = $metadataJson | ConvertFrom-Json
if ($cargo.packages.Count -gt 4096 -or $cargo.resolve.nodes.Count -gt 4096) { throw 'Cargo dependency graph exceeds the package-count limit.' }
$rootPackage = @($cargo.packages | Where-Object { $_.name -ceq $policy.cargoRoot -and $_.id -in $cargo.workspace_members })
if ($rootPackage.Count -ne 1) { throw 'Cannot identify the actual owned Windows Runner package.' }
$nodes = @{}; foreach ($node in $cargo.resolve.nodes) { $nodes[$node.id] = $node }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$pending = [Collections.Generic.Stack[string]]::new(); $pending.Push($rootPackage[0].id)
while ($pending.Count) {
    $id = $pending.Pop(); if (-not $seen.Add($id)) { continue }
    foreach ($dependency in $nodes[$id].deps) {
        if (@($dependency.dep_kinds | Where-Object { $_.kind -cne 'dev' }).Count) { $pending.Push($dependency.pkg) }
    }
}
$rust = @($cargo.packages | Where-Object { $seen.Contains($_.id) } | Sort-Object name, version | ForEach-Object {
    [ordered]@{ name = $_.name; version = $_.version; licenseExpression = $_.license; licenseFile = $(if ($_.license_file) { [IO.Path]::GetFileName($_.license_file) } else { $null }); licenseFileSha256 = $(if ($_.license_file) { Hash $_.license_file ([IO.Path]::GetDirectoryName($_.manifest_path)) 2MB } else { $null }); source = $_.source; classification = $(if ($_.id -in $cargo.workspace_members) { 'own-source' } else { 'upstream-source-compiled-into-runner' }); reviewRequired = [string]::IsNullOrWhiteSpace($_.license) }
})
$runtimeLibraries = @($entries | Where-Object { -not $_.PSIsContainer -and $_.Name.EndsWith('.deps.json', [StringComparison]::Ordinal) } | ForEach-Object {
    $deps = (Read-PreparationText -Path $_.FullName -AllowedRoot $publish -MaximumBytes 4MB) | ConvertFrom-Json
    foreach ($library in $deps.libraries.PSObject.Properties) {
        if ($library.Value.type -cne 'project') {
            $id = $library.Name.Substring(0, $library.Name.LastIndexOf('/'))
            $knownSource = $policy.runtimeLicenseSources.PSObject.Properties[$id]
            [ordered]@{ idVersion = $library.Name; depsFile = [IO.Path]::GetRelativePath($publish, $_.FullName).Replace('\', '/'); classification = 'upstream-runtime-preserve'; licenseReference = $(if ($knownSource) { $knownSource.Value } else { $null }); licenseInLockInventory = $packages.ContainsKey($library.Name); systemLibraryExceptionAccepted = $false }
        }
    }
})
$templates = @('payload', 'uninstaller', 'setup') | ForEach-Object { Assert-SignPathArtifactConfiguration -Path (Join-Path $PSScriptRoot "$_-v1.xml") -Stage $_ -SchemaPath $SchemaPath }
$inventory = [ordered]@{
    schemaVersion = 1; status = 'preparation-not-provider-approval'; createdUtc = [DateTime]::UtcNow.ToString('O')
    sourceVersion = $sourceVersion; actualPublishedOwnedVersions = @($owned.version | Sort-Object -Unique); sourceAndPublishCoordinated = $coordinated
    cargoTarget = $policy.cargoTarget; cargoLockSha256 = Hash (Join-Path $repoRoot 'Cargo.lock'); nugetLocks = @($lockEvidence)
    ownPe = $owned; actualPublishFiles = $fileInventory; nugetPackages = $nuget; rustPackages = $rust; runtimeLibraries = $runtimeLibraries
    templates = @($templates); limitations = @($policy.limitations) + 'Files were inspected but not executed, submitted, signed or installed. No player or Steam data was read.'
}
Write-NewJson 'inventory.json' $inventory
Write-Output "SignPath preparation inventory: $(Join-Path $output 'inventory.json')"
Write-Output "Owned PE=$($owned.Count); NuGet=$($nuget.Count); Windows Rust=$($rust.Count); source/publish coordinated=$coordinated; provider approval=false."
return (Join-Path $output 'inventory.json')
