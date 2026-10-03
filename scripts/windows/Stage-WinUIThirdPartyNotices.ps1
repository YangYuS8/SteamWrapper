[CmdletBinding()]
param([Parameter(Mandatory)][string]$PublishDirectory, [switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repoRoot 'packaging/windows/signpath/PreparationFiles.ps1')
$publish = [IO.Path]::GetFullPath($PublishDirectory)
$allowedRoot = Join-Path $repoRoot 'target/winui'
$null = Resolve-WindowsSigningFile -Path (Join-Path $publish 'THIRD_PARTY_NOTICES.md') -AllowedRoot $allowedRoot -AllowMissing
if (-not (Test-Path -LiteralPath $publish -PathType Container)) { throw 'The selected publication candidate is missing.' }
$noticePath = Join-Path $publish 'THIRD_PARTY_NOTICES.md'
$indexPath = Join-Path $publish 'LICENSES/index.json'
if ($VerifyOnly -and (-not (Test-Path -LiteralPath $noticePath -PathType Leaf) -or -not (Test-Path -LiteralPath $indexPath -PathType Leaf))) { throw 'Publication is missing third-party notices or the license index.' }
$catalogRoot = Join-Path $repoRoot 'packaging/windows/third-party-notices'
$licenseRoot = Join-Path $repoRoot 'packaging/windows/third-party-licenses'
$manifestPath = Join-Path $catalogRoot 'manifest.v1.json'
$catalog = (Read-PreparationText -Path $manifestPath -AllowedRoot $catalogRoot) | ConvertFrom-Json
Assert-ThirdPartyCatalog -Catalog $catalog -LicenseRoot $licenseRoot
$noticeSource = Get-PreparationFile -Path (Join-Path $catalogRoot 'NOTICE.md') -AllowedRoot $catalogRoot -MaximumBytes 2MB

# Check actual external runtime dependencies, including runtimepack and reference
# projections. A changed package or newly added runtime cannot silently omit notices.
$deps = (Read-PreparationText -Path (Join-Path $publish 'SteamWrapper.Manager.deps.json') -AllowedRoot $publish -MaximumBytes 4MB) | ConvertFrom-Json
$runtime = @($deps.libraries.PSObject.Properties | Where-Object { $_.Value.type -cne 'project' } | ForEach-Object Name | Sort-Object)
if (@(Compare-Object -ReferenceObject @($catalog.runtimeLibraries | Sort-Object) -DifferenceObject $runtime).Count) { throw 'Actual runtime dependency versions differ from the reviewed third-party catalog.' }
$managerLock = (Read-PreparationText -Path (Join-Path $repoRoot 'apps/manager-winui/SteamWrapper.Manager/packages.lock.json') -AllowedRoot $repoRoot) | ConvertFrom-Json
$knownNuget = @($catalog.components | Where-Object ecosystem -ceq 'nuget')
foreach ($target in $managerLock.dependencies.PSObject.Properties) {
    foreach ($package in $target.Value.PSObject.Properties) {
        if ($package.Value.type -ceq 'Project' -or $package.Name -in @('Microsoft.Windows.SDK.BuildTools', 'Microsoft.Windows.SDK.BuildTools.MSIX')) { continue }
        if (@($knownNuget | Where-Object { $_.id -ceq $package.Name -and $_.version -ceq $package.Value.resolved }).Count -ne 1) { throw 'Actual NuGet lock contains a component/version missing from the notice catalog.' }
    }
}
Push-Location $repoRoot
try {
    $metadataText = & cargo metadata --offline --locked --format-version 1 --filter-platform $catalog.cargoTarget
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect locked Windows Rust dependencies; ensure the pinned cargo is on PATH.' }
} finally { Pop-Location }
$metadataText = $metadataText -join [Environment]::NewLine
if ($metadataText.Length -gt 8MB) { throw 'Cargo metadata exceeds the preparation text limit.' }
$cargo = $metadataText | ConvertFrom-Json
$nodes = @{}; foreach ($node in $cargo.resolve.nodes) { $nodes[$node.id] = $node }
$runner = @($cargo.packages | Where-Object { $_.name -ceq 'steamwrapper-runner' -and $_.id -in $cargo.workspace_members })
if ($runner.Count -ne 1) { throw 'Cannot identify the owned Runner dependency root.' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$pending = [Collections.Generic.Stack[string]]::new(); $pending.Push($runner[0].id)
while ($pending.Count) {
    $id = $pending.Pop(); if (-not $seen.Add($id)) { continue }
    foreach ($dependency in $nodes[$id].deps) { if (@($dependency.dep_kinds | Where-Object { $_.kind -cne 'dev' }).Count) { $pending.Push($dependency.pkg) } }
}
$actualCargo = @($cargo.packages | Where-Object { $seen.Contains($_.id) -and $_.id -notin $cargo.workspace_members } | ForEach-Object { "$($_.name)/$($_.version)" } | Sort-Object)
$knownCargo = @($catalog.components | Where-Object ecosystem -ceq 'cargo' | ForEach-Object { "$($_.id)/$($_.version)" } | Sort-Object)
if (@(Compare-Object -ReferenceObject $knownCargo -DifferenceObject $actualCargo).Count) { throw 'Locked Windows Rust dependency versions differ from the reviewed third-party catalog.' }
$innoPin = (Read-PreparationText -Path (Join-Path $repoRoot 'packaging/windows/inno-toolchain.json') -AllowedRoot $repoRoot) | ConvertFrom-Json
if (@($catalog.components | Where-Object { $_.ecosystem -ceq 'installer' -and $_.id -ceq 'InnoSetup' -and $_.version -ceq $innoPin.version }).Count -ne 1) { throw 'Pinned installer version lacks reviewed notices.' }

$expected = @([pscustomobject]@{ source = $noticeSource.FullName; path = 'THIRD_PARTY_NOTICES.md'; bytes = $noticeSource.Length; sha256 = (Get-FileHash -LiteralPath $noticeSource.FullName -Algorithm SHA256).Hash.ToLowerInvariant() })
foreach ($entry in $catalog.files) { $expected += [pscustomobject]@{ source = Join-Path $licenseRoot $entry.path; path = 'LICENSES/' + $entry.path; bytes = $entry.bytes; sha256 = $entry.sha256 } }
$index = [ordered]@{ schemaVersion = 1; catalogSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant(); files = @($expected | Select-Object path, bytes, sha256) }
$indexText = ($index | ConvertTo-Json -Depth 5) + "`n"
$expected += [pscustomobject]@{ source = $null; path = 'LICENSES/index.json'; bytes = [Text.UTF8Encoding]::new($false).GetByteCount($indexText); sha256 = [Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($indexText))) }
# Validate every existing destination before creating anything; preserve unknown files.
foreach ($entry in $expected) {
    $destination = Resolve-WindowsSigningFile -Path (Join-Path $publish $entry.path) -AllowedRoot $publish -AllowMissing
    if (Test-Path -LiteralPath $destination) {
        $file = Get-PreparationFile -Path $destination -AllowedRoot $publish -MaximumBytes 2MB
        if ($file.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) { throw 'Existing notice bytes differ; preserve them and use a fresh publication candidate.' }
    } elseif ($VerifyOnly) { throw 'Publication is missing required third-party license material.' }
}
if (-not $VerifyOnly) {
    foreach ($entry in $expected) {
        $destination = Join-Path $publish $entry.path
        if (Test-Path -LiteralPath $destination) { continue }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            if ($entry.source) {
                $input = [IO.File]::Open($entry.source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try { if ($input.Length -ne $entry.bytes) { throw 'Canonical legal input changed after preflight.' }; $input.CopyTo($stream) } finally { $input.Dispose() }
            } else { $stream.Write([Text.UTF8Encoding]::new($false).GetBytes($indexText)) }
        } finally { $stream.Dispose() }
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) { throw 'Staged legal bytes changed; quarantine the candidate for inspection.' }
    }
}
Write-Output "PASS: $($catalog.components.Count) upstream components and $($catalog.files.Count) original legal files verified; notices=$noticePath"
