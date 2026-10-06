[CmdletBinding()]
param([string]$PackageDirectory, [switch]$Installable, [switch]$Preview, [switch]$Compact)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root = Join-Path $repoRoot ('target/github-publisher-tests/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
if (-not $PackageDirectory) {
    $version = if ($Compact) { '0.2.8' } else { '0.2.0' }
    $tag = if ($Preview) { "v$version-rc.1" } else { "v$version" }
    if ($Installable -or $Compact) {
        . (Join-Path $repoRoot 'scripts/windows/WinUIInstallableRelease.TestFixtures.ps1')
        . (Join-Path $repoRoot 'scripts/windows/WinUIInstallableRelease.ps1')
        $fixture = New-WinUIInstallableReleaseTestFixture -Root (Join-Path $root 'package') -Tag $tag
        $package = if ($Compact) { New-WinUIInstallableReleasePackage -Tag $tag -Commit $fixture.Commit -RepositoryRoot $fixture.RepositoryRoot -PublishDirectory $fixture.PublishDirectory -InstallerDirectory $fixture.InstallerDirectory -OutputDirectory $fixture.OutputDirectory } else { New-WinUIInstallableReleaseTestPackage $fixture }
    } else {
        . (Join-Path $repoRoot 'scripts/windows/WinUIRelease.TestFixtures.ps1')
        $fixture = New-WinUIReleaseTestFixture -Root (Join-Path $root 'package') -Tag $tag
        $package = New-WinUIReleasePackage -Tag $fixture.Tag -Commit $fixture.Commit -RepositoryRoot $fixture.RepositoryRoot -PublishDirectory $fixture.PublishDirectory -OutputDirectory $fixture.OutputDirectory
    }
    $PackageDirectory = $package.Directory
}
$metadata = & (Join-Path $repoRoot 'scripts/windows/Test-WinUIReleasePackage.ps1') -PackageDirectory $PackageDirectory
. (Join-Path $repoRoot 'scripts/windows/WinUIInstallableRelease.ps1')
$names = @(Get-WinUIPublicReleaseAssetNames $metadata)
if ($Compact -and ($metadata.schemaVersion -ne 3 -or $names.Count -ne 3)) { throw 'Compact publisher fixtures must select exactly three public assets.' }
$mock = Join-Path $root 'gh-fixture.ps1'
[IO.File]::WriteAllText($mock, @'
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$path = $env:STEAMWRAPPER_GH_FIXTURE
$state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
$arguments = @($args)
$state.requests += ,$arguments
function Save-State { [IO.File]::WriteAllText($path, ($state | ConvertTo-Json -Depth 12)) }
function Fail-Fixture([string]$Message) { Save-State; $global:LASTEXITCODE = 1; Write-Output $Message }
function Option-Value([string]$Name) {
    $index = [Array]::IndexOf($arguments, $Name)
    if ($index -lt 0) { throw "Missing fixture option $Name." }
    return $arguments[$index + 1]
}
if ($arguments[0] -eq 'api') {
    $state.apiCalls++
    Save-State
    if ($state.scenario -eq 'moved-tag' -and $state.apiCalls -gt 1) { Write-Output ('f' * 40) }
    else { Write-Output $state.remoteCommit }
    return
}
switch ($arguments[1]) {
    'view' {
        Save-State
        if (-not $state.present) { Fail-Fixture 'release not found'; return }
        $visible = @($state.assets | ForEach-Object { @{ name = $_.name; size = $_.size } })
        if ($state.scenario -eq 'missing-upload' -and $state.uploads -gt 0) { $visible = @($visible | Select-Object -SkipLast 1) }
        $target = $state.commit
        if ($state.scenario -eq 'changed-draft' -and $state.uploads -gt 0) { $target = 'f' * 40 }
        @{ tagName = $state.tag; targetCommitish = $target; isDraft = $state.draft; isPrerelease = $state.prerelease; assets = $visible } | ConvertTo-Json -Depth 8 -Compress
    }
    'create' {
        if ($arguments -notcontains '--draft' -or $arguments -notcontains ('--prerelease=' + $state.prerelease.ToString().ToLowerInvariant()) -or $arguments -notcontains '--latest=false' -or $arguments -notcontains '--verify-tag') { throw 'Unsafe fixture release creation flags.' }
        $state.title = Option-Value '--title'
        $state.notes = [IO.File]::ReadAllText((Option-Value '--notes-file'))
        $state.present = $true
        $state.draft = $true
        Save-State
    }
    'upload' {
        $state.uploads++
        if ($state.scenario -eq 'upload-failure' -and $state.uploads -eq 3) { Fail-Fixture 'fixture upload failure'; return }
        if ($arguments -contains '--clobber') { throw 'The publisher tried to clobber an asset.' }
        $source = $arguments[3]
        $name = [IO.Path]::GetFileName($source)
        $remote = Join-Path $state.remoteDirectory $name
        Copy-Item -LiteralPath $source -Destination $remote
        $state.assets += @{ name = $name; size = (Get-Item -LiteralPath $source).Length; file = $remote }
        Save-State
    }
    'download' {
        $name = Option-Value '--pattern'
        $destination = Join-Path (Option-Value '--dir') $name
        $asset = @($state.assets | Where-Object { $_.name -ceq $name })[0]
        Copy-Item -LiteralPath $asset.file -Destination $destination
        if ($state.scenario -eq 'corrupt-download') { [IO.File]::AppendAllText($destination, 'corrupted') }
        Save-State
    }
    'edit' {
        if ($arguments -notcontains '--draft=false' -or $arguments -notcontains ('--prerelease=' + $state.prerelease.ToString().ToLowerInvariant()) -or $arguments -notcontains ('--latest=' + (-not $state.prerelease).ToString().ToLowerInvariant())) { throw 'Unsafe fixture publication flags.' }
        $state.draft = $false
        Save-State
    }
    default { throw 'Unexpected fixture gh command.' }
}
'@, [Text.UTF8Encoding]::new($false))

function New-GhScenario([string]$Scenario, [bool]$Present = $false, [bool]$Draft = $true, [string[]]$Assets = @()) {
    $caseRoot = Join-Path $root ([Guid]::NewGuid().ToString('N'))
    $remote = Join-Path $caseRoot 'remote'
    New-Item -ItemType Directory -Path $remote -Force | Out-Null
    $records = foreach ($name in $Assets) {
        $target = Join-Path $remote $name
        Copy-Item -LiteralPath (Join-Path $PackageDirectory $name) -Destination $target -Force
        @{ name = $name; size = (Get-Item -LiteralPath $target).Length; file = $target }
    }
    $state = @{ scenario = $Scenario; present = $Present; draft = $Draft; prerelease = $metadata.githubPrerelease; tag = $metadata.tag; commit = $metadata.commit; remoteCommit = $metadata.commit; uploads = 0; apiCalls = 0; assets = @($records); requests = @(); remoteDirectory = $remote }
    if ($Scenario -eq 'wrong-tag') { $state.remoteCommit = 'f' * 40 }
    if ($Scenario -eq 'wrong-channel') { $state.prerelease = -not $metadata.githubPrerelease }
    $path = Join-Path $caseRoot 'state.json'
    [IO.File]::WriteAllText($path, ($state | ConvertTo-Json -Depth 10))
    $env:STEAMWRAPPER_GH_FIXTURE = $path
    return $path
}
function Invoke-FixturePublication {
    & (Join-Path $PSScriptRoot 'Publish-GitHubRelease.ps1') -PackageDirectory $PackageDirectory -GhExecutable $mock
}
function Read-FixtureState([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
function Assert-GhRejected([string]$Label, [string]$Pattern) {
    $rejected = $false
    try { $null = Invoke-FixturePublication }
    catch { if ($_.Exception.Message -notlike $Pattern) { throw }; $rejected = $true }
    if (-not $rejected) { throw "$Label unexpectedly succeeded." }
    Write-Output "PASS: $Label"
}
function Assert-NoGhWrites($State) {
    if (@($State.requests | Where-Object { $_[0] -eq 'release' -and $_[1] -in @('create', 'upload', 'edit') }).Count -ne 0) { throw 'A rejected or unchanged release was mutated.' }
}
$previousFixture = $env:STEAMWRAPPER_GH_FIXTURE
try {
    $path = New-GhScenario 'success'
    $null = Invoke-FixturePublication
    $state = Read-FixtureState $path
    if ($state.draft -or $state.uploads -ne $names.Count -or @($state.requests | Where-Object { $_[1] -eq 'download' }).Count -ne $names.Count) { throw 'The complete draft/upload/download/publish sequence did not occur.' }
    $presentationErrors = @()
    if ($state.title -cne $metadata.tag) { $presentationErrors += 'GitHub release title must be exactly the version tag.' }
    if ($state.notes -cne [IO.File]::ReadAllText((Join-Path $PackageDirectory "$($metadata.tag).en.md"))) { $presentationErrors += 'GitHub release body must contain only the English release notes.' }
    if ($presentationErrors.Count) { throw ($presentationErrors -join ' ') }
    Write-Output 'PASS: GitHub uses the tag as its title and only English notes as its body, retaining both internal localized notes.'
    Write-Output "PASS: a new $($metadata.releaseChannel) release verifies all $($names.Count) uploaded assets before publishing with the matching latest flag."
    $writes = @($state.requests | Where-Object { $_[1] -in @('create', 'upload', 'edit') }).Count
    $null = Invoke-FixturePublication
    $state = Read-FixtureState $path
    if (@($state.requests | Where-Object { $_[1] -in @('create', 'upload', 'edit') }).Count -ne $writes) { throw 'Retry modified an already-published identical release.' }
    Write-Output 'PASS: an identical published release is verified and reused without writes.'
    $path = New-GhScenario 'wrong-channel' $true $false $names
    Assert-GhRejected 'a release in the opposite channel is rejected without relabeling it' '*release channel*'
    Assert-NoGhWrites (Read-FixtureState $path)
    $path = New-GhScenario 'retry' $true $true @($names[0])
    $null = Invoke-FixturePublication
    $state = Read-FixtureState $path
    if ($state.draft -or $state.uploads -ne $names.Count - 1) { throw 'A partial draft was not resumed using only missing assets.' }
    Write-Output 'PASS: a partial draft resumes without replacing its existing asset.'
    $path = New-GhScenario 'duplicate' $true $false (@($names[0]) + $names)
    Assert-GhRejected 'duplicate published asset names are rejected' '*duplicate*'
    Assert-NoGhWrites (Read-FixtureState $path)
    $path = New-GhScenario 'corrupt-download' $true $false $names
    Assert-GhRejected 'different published bytes are rejected without mutation' '*Downloaded GitHub asset*'
    Assert-NoGhWrites (Read-FixtureState $path)
    $path = New-GhScenario 'wrong-tag'
    Assert-GhRejected 'a remote tag mismatch is rejected before release writes' '*remote GitHub tag*'
    Assert-NoGhWrites (Read-FixtureState $path)
    foreach ($scenario in @('missing-upload', 'corrupt-download', 'upload-failure', 'changed-draft', 'moved-tag')) {
        $path = New-GhScenario $scenario
        Assert-GhRejected "$scenario leaves the new release as a draft" '*'
        $state = Read-FixtureState $path
        if (-not $state.draft -or @($state.requests | Where-Object { $_[1] -eq 'edit' }).Count -ne 0) { throw 'A failed release was made public.' }
    }
} finally { $env:STEAMWRAPPER_GH_FIXTURE = $previousFixture }
Write-Output "GitHub publisher fixture tests passed: $root"
