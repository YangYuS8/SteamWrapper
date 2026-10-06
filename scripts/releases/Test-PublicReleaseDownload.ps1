[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PublicReleaseDownload.ps1')
. (Join-Path $PSScriptRoot '../windows/WinUIInstallableRelease.TestFixtures.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root = Join-Path $repoRoot ('target/public-release-download-tests/' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$key = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
$priorFixture = $env:STEAMWRAPPER_PUBLIC_DOWNLOAD_FIXTURE
try {
    $trust = [pscustomobject]@{ schemaVersion = 1; keys = @([pscustomobject]@{ keyId = 'fixture'; subjectPublicKeyInfo = [Convert]::ToBase64String($key.ExportSubjectPublicKeyInfo()) }); githubRepository = 'YangYuS8/SteamWrapper'; cnbRepository = 'Nesoriel/SteamWrapper' }
    $trustPath = Join-Path $root 'trust.json'
    [IO.File]::WriteAllText($trustPath, ($trust | ConvertTo-Json -Depth 5))
    $tag = 'v0.2.8'
    $source = Join-Path $root 'source'
    [IO.Directory]::CreateDirectory((Join-Path $source 'releases')) | Out-Null
    $sourceNotes = "# $tag`n`nExact committed Chinese release note fixture. 精确提交的发布说明。`n"
    [IO.File]::WriteAllText((Join-Path $source "releases/$tag.zh-CN.md"), $sourceNotes, [Text.UTF8Encoding]::new($false))
    & git -C $source init --quiet
    & git -C $source -c core.autocrlf=false add -- "releases/$tag.zh-CN.md"
    & git -C $source -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgSign=false commit --quiet -m 'Disposable exact source fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Could not create disposable source fixture.' }
    $commit = (& git -C $source rev-parse HEAD).Trim()
    $public = Join-Path $root 'public'
    [IO.Directory]::CreateDirectory($public) | Out-Null
    $zipName = "SteamWrapper-$tag-win-x64.zip"
    $setupName = "SteamWrapper-$tag-win-x64-setup.exe"
    [IO.File]::WriteAllText((Join-Path $public $zipName), 'Non-executable opaque public ZIP byte fixture; no package/installation acceptance claim.')
    [IO.File]::WriteAllText((Join-Path $public $setupName), 'Non-executable project-authorized Setup byte fixture.')
    $lines = foreach ($name in @($zipName, $setupName)) { "$((Get-FileHash -LiteralPath (Join-Path $public $name)).Hash.ToLowerInvariant())  $name" }
    [IO.File]::WriteAllText((Join-Path $public 'SHA256SUMS'), ($lines -join "`n") + "`n")
    $assets = foreach ($name in @($zipName, $setupName, 'SHA256SUMS')) { [pscustomobject]@{ name = $name; size = (Get-Item -LiteralPath (Join-Path $public $name)).Length; digest = 'sha256:' + (Get-FileHash -LiteralPath (Join-Path $public $name)).Hash.ToLowerInvariant(); state = 'uploaded' } }
    $release = [pscustomobject]@{ tag_name = $tag; target_commitish = $commit; draft = $false; prerelease = $false; assets = @($assets) }
    $publicInstaller = New-WinUIPublicInstallerDescriptor -ReleaseState $release -Tag $tag -Commit $commit -BaselineOnly
    if ($publicInstaller.schemaVersion -ne 1 -or $publicInstaller.kind -cne 'PublicApiInstaller' -or $publicInstaller.publicAssetLayout -ne 3 -or $null -ne $publicInstaller.PSObject.Properties['installerBuild'] -or $publicInstaller.installerAsset.sha256 -cne $assets[1].digest.Substring(7)) { throw 'Public API receipt fabricated private build metadata or omitted exact installer bytes.' }
    $metadata = [pscustomobject]@{ schemaVersion = 2; tag = $tag; version = '0.2.8'; commit = $commit; minimumWindowsVersion = '10.0.26100.0'; releaseChannel = 'stable'; installerAsset = [pscustomobject]@{ fileName = $setupName; bytes = $assets[1].size; sha256 = $assets[1].digest.Substring(7) } }
    $envelope = Join-Path $root 'signed-update.json'
    $payload = New-ProjectUpdatePayload -ReleaseMetadata $metadata -Trust $trust
    Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId fixture -Path $envelope
    $signedInstaller = New-WinUIPublicInstallerDescriptor -ReleaseState $release -Tag $tag -Commit $commit -EnvelopePath $envelope -TrustPath $trustPath
    if ($signedInstaller.verificationKind -cne 'project-signature' -or $signedInstaller.baselineScope -or -not $signedInstaller.signatureVerified -or $publicInstaller.verificationKind -cne 'public-api-baseline' -or -not $publicInstaller.baselineScope -or $publicInstaller.signatureVerified) { throw 'Public installer descriptors did not distinguish explicit historical baselines from signature-verified current targets.' }
    $parameters = @{ PackageDirectory = $public; EnvelopePath = $envelope; TrustPath = $trustPath; Tag = $tag; Commit = $commit; ReleaseState = $release; RepositoryRoot = $source; NotesPath = (Join-Path $root 'notes.zh-CN.md') }
    $descriptor = Test-WinUIPublicReleaseDirectory @parameters
    if ($descriptor.schemaVersion -ne 3 -or $descriptor.commit -cne $commit -or $descriptor.installerAsset.sha256 -cne $metadata.installerAsset.sha256 -or [IO.File]::ReadAllText($descriptor.notesPath) -cne $sourceNotes -or @(Get-ChildItem -LiteralPath $public -Force).Count -ne 3) { throw 'Compact public verification did not retain the exact signed installer and committed notes outside its three public assets.' }
    [IO.File]::WriteAllText((Join-Path $source "releases/$tag.zh-CN.md"), 'Uncommitted notes must never become release body.')
    $descriptor = Test-WinUIPublicReleaseDirectory @parameters
    if ([IO.File]::ReadAllText($descriptor.notesPath) -cne $sourceNotes) { throw 'Public mirror notes were read from the working tree instead of the exact release commit.' }
    Write-Output 'PASS: exactly three public assets bind signed Setup bytes and source-commit Chinese notes without fabricating internal release metadata.'

    function Assert-Rejected([scriptblock]$Action, [string]$Reason) {
        $failed = $false
        try { $null = & $Action } catch { $failed = $true }
        if (-not $failed) { throw "Unsafe public release input was accepted: $Reason" }
    }
    function Copy-State { ConvertFrom-WinUIInstallableJson ($release | ConvertTo-Json -Depth 8 -Compress) }
    Assert-Rejected { New-WinUIPublicInstallerDescriptor -ReleaseState $release -Tag $tag -Commit $commit } 'missing current target envelope has no implicit API-only fallback'
    foreach ($scenario in @('missing', 'extra', 'duplicate', 'wrong-tag', 'wrong-commit', 'draft', 'wrong-channel', 'missing-digest', 'invalid-digest', 'wrong-size', 'oversize', 'not-uploaded')) {
        $bad = Copy-State
        switch ($scenario) {
            'missing' { $bad.assets = @($bad.assets | Select-Object -SkipLast 1) }
            'extra' { $bad.assets += [pscustomobject]@{ name = 'release.json'; size = 1; digest = 'sha256:' + ('a' * 64); state = 'uploaded' } }
            'duplicate' { $bad.assets[2].name = $zipName }
            'wrong-tag' { $bad.tag_name = 'v0.2.9' }
            'wrong-commit' { $bad.target_commitish = 'f' * 40 }
            'draft' { $bad.draft = $true }
            'wrong-channel' { $bad.prerelease = $true }
            'missing-digest' { $bad.assets[0].PSObject.Properties.Remove('digest') }
            'invalid-digest' { $bad.assets[0].digest = 'sha512:' + ('a' * 64) }
            'wrong-size' { $bad.assets[0].size++ }
            'oversize' { $bad.assets[1].size = 512MB + 1 }
            'not-uploaded' { $bad.assets[1].state = 'new' }
        }
        $badParameters = $parameters.Clone(); $badParameters.ReleaseState = $bad
        Assert-Rejected { Test-WinUIPublicReleaseDirectory @badParameters } $scenario
    }
    $originalChecksums = [IO.File]::ReadAllText((Join-Path $public 'SHA256SUMS'))
    [IO.File]::AppendAllText((Join-Path $public 'SHA256SUMS'), ('a' * 64) + "  release.json`n")
    $bad = Copy-State; $bad.assets[2].size = (Get-Item -LiteralPath (Join-Path $public 'SHA256SUMS')).Length; $bad.assets[2].digest = 'sha256:' + (Get-FileHash -LiteralPath (Join-Path $public 'SHA256SUMS')).Hash.ToLowerInvariant()
    $badParameters = $parameters.Clone(); $badParameters.ReleaseState = $bad
    Assert-Rejected { Test-WinUIPublicReleaseDirectory @badParameters } 'checksums include internal metadata'
    [IO.File]::WriteAllText((Join-Path $public 'SHA256SUMS'), $originalChecksums)
    $badPayload = ConvertFrom-ProjectUpdateJson ($payload | ConvertTo-Json -Depth 10 -Compress); $badPayload.release.artifact.sha256 = 'f' * 64
    Write-ProjectUpdateEnvelope -Payload $badPayload -Key $key -KeyId fixture -Path $envelope
    Assert-Rejected { Test-WinUIPublicReleaseDirectory @parameters } 'signed installer descriptor differs'
    Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId fixture -Path $envelope
    $wrapper = ConvertFrom-WinUIInstallableJson ([IO.File]::ReadAllText($envelope)); $wrapper.signature = [Convert]::ToBase64String([byte[]]::new(64))
    [IO.File]::WriteAllText($envelope, ($wrapper | ConvertTo-Json -Compress))
    Assert-Rejected { Test-WinUIPublicReleaseDirectory @parameters } 'tampered envelope signature'
    Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId fixture -Path $envelope
    Write-Output 'PASS: malformed/incomplete/duplicate API inventories, channel/commit mismatches, limits, internal checksums and unauthorized/tampered Setup descriptors fail closed.'

    $expired = New-ProjectUpdatePayload -ReleaseMetadata $metadata -Trust $trust -Now ([DateTimeOffset]::UtcNow.AddDays(-40))
    Write-ProjectUpdateEnvelope -Payload $expired -Key $key -KeyId fixture -Path $envelope
    Assert-Rejected { New-WinUIPublicInstallerDescriptor -ReleaseState $release -Tag $tag -Commit $commit -EnvelopePath $envelope -TrustPath $trustPath } 'expired current target signature has no API-only fallback'
    $historical = Test-WinUIPublicReleaseDirectory @parameters
    if ($historical.installerAsset.sha256 -cne $metadata.installerAsset.sha256) { throw 'Expired historical authorization changed its installer identity.' }
    Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId fixture -Path $envelope
    Write-Output 'PASS: historical mirrors may reuse expired signed authorization while preserving its signature, identity, installer and validity-shape checks.'

    $mock = Join-Path $root 'gh-fixture.ps1'
    [IO.File]::WriteAllText($mock, @'
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$fixturePath = $env:STEAMWRAPPER_PUBLIC_DOWNLOAD_FIXTURE
$fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json -AsHashtable
$a = @($args)
$fixture.requests += ,$a
function Save { [IO.File]::WriteAllText($fixturePath, ($fixture | ConvertTo-Json -Depth 12)) }
function Option([string]$Name) { $a[[Array]::IndexOf($a, $Name) + 1] }
if ($a[0] -eq 'api') {
    if ($a[1] -like '*/commits/*') {
        $fixture.commitCalls++
        Save
        if ($fixture.scenario -eq 'moved-tag' -and $fixture.commitCalls -gt 1) { 'f' * 40 } else { $fixture.commit }
    } elseif ($a[1] -like '*/releases/tags/*') {
        Save
        $state = $fixture.release
        if ($fixture.scenario -eq 'missing') { $state.assets = @($state.assets | Select-Object -SkipLast 1) }
        $state | ConvertTo-Json -Depth 12 -Compress
    } else { throw 'Unexpected public API fixture request.' }
    return
}
if ($a[0] -cne 'release' -or $a[1] -cne 'download' -or $a -contains '--clobber') { throw 'Public downloader made a write or unexpected gh request.' }
$name = Option '--pattern'
Copy-Item -LiteralPath (Join-Path $fixture.directory $name) -Destination (Join-Path (Option '--dir') $name)
if ($fixture.scenario -eq 'corrupt') { [IO.File]::AppendAllText((Join-Path (Option '--dir') $name), 'corrupt fixture bytes') }
Save
'@, [Text.UTF8Encoding]::new($false))
    function New-DownloadCase([string]$Scenario, $State = $release, [string]$Directory = $public, [string]$SourceCommit = $commit) {
        $case = Join-Path $root ([Guid]::NewGuid().ToString('N')); [IO.Directory]::CreateDirectory($case) | Out-Null
        $statePath = Join-Path $case 'fixture.json'
        [IO.File]::WriteAllText($statePath, (@{ scenario = $Scenario; release = $State; directory = $Directory; commit = $SourceCommit; commitCalls = 0; requests = @() } | ConvertTo-Json -Depth 12))
        $env:STEAMWRAPPER_PUBLIC_DOWNLOAD_FIXTURE = $statePath
        return [pscustomobject]@{ PackageDirectory = (Join-Path $case 'download'); FixturePath = $statePath }
    }
    foreach ($scenario in @('missing', 'corrupt', 'moved-tag')) {
        $case = New-DownloadCase $scenario
        Assert-Rejected { & (Join-Path $PSScriptRoot 'Download-PublishedRelease.ps1') -Tag $tag -Commit $commit -PackageDirectory $case.PackageDirectory -EnvelopePath $envelope -TrustPath $trustPath -RepositoryRoot $source -GhExecutable $mock } $scenario
        if (Test-Path -LiteralPath ($case.PackageDirectory + '-verification/receipt.json')) { throw 'Failed public download retained a successful verification receipt.' }
    }
    $case = New-DownloadCase 'valid'
    $downloaded = & (Join-Path $PSScriptRoot 'Download-PublishedRelease.ps1') -Tag $tag -Commit $commit -PackageDirectory $case.PackageDirectory -EnvelopePath $envelope -TrustPath $trustPath -RepositoryRoot $source -GhExecutable $mock
    if (@($downloaded).Count -ne 1 -or $downloaded.schemaVersion -ne 3 -or @(Get-ChildItem -LiteralPath $case.PackageDirectory -Force).Count -ne 3 -or -not (Test-Path -LiteralPath $downloaded.verificationPath)) { throw 'Compact download did not return one validated descriptor and an external receipt.' }
    $read = Read-WinUIPublicReleaseVerification -PackageDirectory $case.PackageDirectory -VerificationPath $downloaded.verificationPath -TrustPath $trustPath -RepositoryRoot $source
    if ($read.installerAsset.sha256 -cne $metadata.installerAsset.sha256 -or [IO.File]::ReadAllText($read.notesPath) -cne $sourceNotes) { throw 'Stored compact verification did not recheck the exact signed Setup and source notes.' }
    $verificationDirectory = [IO.Path]::GetDirectoryName($downloaded.verificationPath)
    $storedReceipt = [IO.File]::ReadAllText($downloaded.verificationPath)
    $storedNotes = [IO.File]::ReadAllText($read.notesPath)
    $storedEnvelopePath = Join-Path $verificationDirectory 'signed-update.json'
    $storedEnvelope = [IO.File]::ReadAllText($storedEnvelopePath)
    $storedStatePath = Join-Path $verificationDirectory 'release-state.json'
    $storedState = [IO.File]::ReadAllText($storedStatePath)
    foreach ($scenario in @('wrong-receipt', 'unknown-receipt-field', 'duplicate-receipt-field', 'tampered-notes', 'tampered-signature', 'incomplete-api-receipt')) {
        switch ($scenario) {
            'wrong-receipt' { $bad = ConvertFrom-WinUIInstallableJson $storedReceipt; $bad.commit = 'f' * 40; [IO.File]::WriteAllText($downloaded.verificationPath, ($bad | ConvertTo-Json -Compress)) }
            'unknown-receipt-field' { $bad = ConvertFrom-WinUIInstallableJson $storedReceipt; $bad | Add-Member arbitraryPath 'outside'; [IO.File]::WriteAllText($downloaded.verificationPath, ($bad | ConvertTo-Json -Compress)) }
            'duplicate-receipt-field' { [IO.File]::WriteAllText($downloaded.verificationPath, $storedReceipt.TrimEnd().TrimEnd('}') + ',"tag":"v0.2.9"}') }
            'tampered-notes' { [IO.File]::WriteAllText($read.notesPath, '# v0.2.8' + "`n`nUncommitted or replaced release body.") }
            'tampered-signature' { $bad = ConvertFrom-WinUIInstallableJson $storedEnvelope; $bad.signature = [Convert]::ToBase64String([byte[]]::new(64)); [IO.File]::WriteAllText($storedEnvelopePath, ($bad | ConvertTo-Json -Compress)) }
            'incomplete-api-receipt' { $bad = ConvertFrom-WinUIInstallableJson $storedState; $bad.assets = @($bad.assets | Select-Object -SkipLast 1); [IO.File]::WriteAllText($storedStatePath, ($bad | ConvertTo-Json -Depth 8 -Compress)) }
        }
        Assert-Rejected { Read-WinUIPublicReleaseVerification -PackageDirectory $case.PackageDirectory -VerificationPath $downloaded.verificationPath -TrustPath $trustPath -RepositoryRoot $source } $scenario
        [IO.File]::WriteAllText($downloaded.verificationPath, $storedReceipt)
        [IO.File]::WriteAllText($read.notesPath, $storedNotes)
        [IO.File]::WriteAllText($storedEnvelopePath, $storedEnvelope)
        [IO.File]::WriteAllText($storedStatePath, $storedState)
    }
    Write-Output 'PASS: stored receipts reject replaced identity, unsupported/duplicate fields, notes/signature tampering and incomplete API inventories.'

    # Exercise the publisher's public-download mode with an entirely local HTTP
    # handler. No fixture Setup is executed and no CNB request reaches a network.
    . (Join-Path $PSScriptRoot 'Publish-CnbRelease.ps1') -TrustPath $trustPath -SourceRepositoryRoot $source
    if (-not ('PublicReleaseMirrorFixtureHandler' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class PublicReleaseMirrorFixtureHandler : HttpMessageHandler {
    public readonly Queue<HttpResponseMessage> Replies = new();
    public readonly List<string> Methods = new();
    public readonly List<string> Bodies = new();
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation) {
        Methods.Add(request.Method.Method);
        Bodies.Add(request.Content == null ? "" : request.Content.ReadAsStringAsync(cancellation).GetAwaiter().GetResult());
        if (Replies.Count == 0) throw new Exception("Unexpected public mirror fixture request.");
        return Task.FromResult(Replies.Dequeue());
    }
    public void Json(int status, string json) { Replies.Enqueue(new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent(json) }); }
    public void Bytes(byte[] bytes) { Replies.Enqueue(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) }); }
}
'@
    }
    $cnbParameters = @{ PackageDirectory = $case.PackageDirectory; PublicReleaseVerificationPath = $downloaded.verificationPath; TrustPath = $trustPath; SourceRepositoryRoot = $source }
    function Get-PublicCnbState([bool]$Draft, [bool]$Complete = $false) {
        $records = if ($Complete) { @($release.assets | ForEach-Object { @{ name = $_.name; size = $_.size } }) } else { @() }
        return @{ id = 'release-1'; tag_name = $tag; tag_commitish = "refs/tags/$tag"; draft = $Draft; prerelease = $false; assets = @($records) } | ConvertTo-Json -Depth 5 -Compress
    }
    $previousCnbToken = $env:CNB_RELEASE_TOKEN
    $env:CNB_RELEASE_TOKEN = 'fixture-only-never-a-real-credential'
    try {
        $handler = [PublicReleaseMirrorFixtureHandler]::new(); $client = [Net.Http.HttpClient]::new($handler)
        try {
            $handler.Json(200, (@{ name = $tag; commit = @{ sha = $commit } } | ConvertTo-Json -Compress))
            $handler.Json(404, '{}'); $handler.Json(201, (Get-PublicCnbState $true))
            foreach ($asset in $release.assets) {
                $handler.Json(201, (@{ upload_url = ('https://uploads.example.test/' + $asset.name); verify_url = ('https://api.cnb.cool/Nesoriel/SteamWrapper/-/releases/release-1/asset-upload-confirmation/fixture/' + $asset.name) } | ConvertTo-Json -Compress))
                $handler.Json(200, ''); $handler.Json(200, '{}')
                $handler.Bytes([IO.File]::ReadAllBytes((Join-Path $case.PackageDirectory $asset.name)))
            }
            $handler.Json(200, (Get-PublicCnbState $true $true))
            $handler.Json(200, (@{ name = $tag; commit = @{ sha = $commit } } | ConvertTo-Json -Compress))
            $handler.Json(200, '{}'); $handler.Json(200, (Get-PublicCnbState $false $true))
            $null = Invoke-CnbRelease @cnbParameters -Client $client
            $creation = $handler.Bodies[2] | ConvertFrom-Json
            if ($handler.Replies.Count -ne 0 -or $creation.body -cne $sourceNotes -or $creation.name -cne $tag -or @($handler.Methods | Where-Object { $_ -ceq 'PUT' }).Count -ne 3) { throw 'Public mirror mode did not publish exactly three checked assets with source-commit Chinese notes.' }
        } finally { $client.Dispose() }
        $handler = [PublicReleaseMirrorFixtureHandler]::new(); $client = [Net.Http.HttpClient]::new($handler)
        try {
            $handler.Json(200, (@{ name = $tag; commit = @{ sha = $commit } } | ConvertTo-Json -Compress))
            $handler.Json(200, (Get-PublicCnbState $false $true))
            foreach ($asset in $release.assets) { $handler.Bytes([IO.File]::ReadAllBytes((Join-Path $case.PackageDirectory $asset.name))) }
            $null = Invoke-CnbRelease @cnbParameters -Client $client
            if ($handler.Replies.Count -ne 0 -or @($handler.Methods | Where-Object { $_ -cne 'GET' }).Count -ne 0) { throw 'Public mirror retry changed an already identical published release.' }
        } finally { $client.Dispose() }
        [IO.File]::WriteAllText($read.notesPath, 'Tampered source notes.')
        $handler = [PublicReleaseMirrorFixtureHandler]::new(); $client = [Net.Http.HttpClient]::new($handler)
        try {
            Assert-Rejected { Invoke-CnbRelease @cnbParameters -Client $client } 'invalid public receipt before CNB HTTP'
            if ($handler.Methods.Count -ne 0) { throw 'An invalid public receipt reached CNB before local verification.' }
        } finally { $client.Dispose(); [IO.File]::WriteAllText($read.notesPath, $storedNotes) }
    } finally { $env:CNB_RELEASE_TOKEN = $previousCnbToken }
    Write-Output 'PASS: isolated public CNB publication uses exactly three verified assets, committed notes, safe reuse and rejects a bad receipt before HTTP.'

    [IO.File]::AppendAllText((Join-Path $case.PackageDirectory $zipName), 'tampered after download')
    Assert-Rejected { Read-WinUIPublicReleaseVerification -PackageDirectory $case.PackageDirectory -VerificationPath $downloaded.verificationPath -TrustPath $trustPath -RepositoryRoot $source } 'tampered downloaded ZIP'
    $requests = (Get-Content -LiteralPath $case.FixturePath -Raw | ConvertFrom-Json).requests
    if (@($requests | Where-Object { $_[0] -cne 'api' -and ($_[0] -cne 'release' -or $_[1] -cne 'download') }).Count -ne 0) { throw 'Public downloader mutated the external release.' }
    Write-Output 'PASS: the read-only downloader rejects preflight incompleteness, corrupt bytes and moved tags, and stored receipts reverify every asset before mirror use.'

    $legacyFixture = New-WinUIInstallableReleaseTestFixture -Root (Join-Path $root 'legacy') -Tag 'v0.2.7'
    $legacyPackage = New-WinUIInstallableReleaseTestPackage $legacyFixture
    $legacyMetadata = ConvertFrom-WinUIInstallableJson ([IO.File]::ReadAllText($legacyPackage.Metadata))
    $legacyAssets = foreach ($file in Get-ChildItem -LiteralPath $legacyPackage.Directory -File) { [pscustomobject]@{ name = $file.Name; size = $file.Length; digest = 'sha256:' + (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant(); state = 'uploaded' } }
    $legacyState = [pscustomobject]@{ tag_name = 'v0.2.7'; target_commitish = 'main'; draft = $false; prerelease = $false; assets = @($legacyAssets) }
    $legacyCase = New-DownloadCase 'valid' $legacyState $legacyPackage.Directory $legacyFixture.Commit
    $downloadedLegacy = & (Join-Path $PSScriptRoot 'Download-PublishedRelease.ps1') -Tag v0.2.7 -Commit $legacyFixture.Commit -PackageDirectory $legacyCase.PackageDirectory -RepositoryRoot $legacyFixture.RepositoryRoot -GhExecutable $mock -TrustPath $trustPath
    if ($downloadedLegacy.schemaVersion -ne 2 -or @(Get-ChildItem -LiteralPath $legacyCase.PackageDirectory -Force).Count -ne 7 -or $downloadedLegacy.installerAsset.sha256 -cne $legacyMetadata.installerAsset.sha256) { throw 'Historical v0.2.7 did not retain its seven-assets full package validator.' }
    Write-Output 'PASS: historical v0.2.7 downloads retain all seven assets and the existing full package validator unchanged.'
} finally { $env:STEAMWRAPPER_PUBLIC_DOWNLOAD_FIXTURE = $priorFixture; $key.Dispose() }
