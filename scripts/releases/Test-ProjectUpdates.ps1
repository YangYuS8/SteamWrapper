[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProjectUpdates.ps1')
$root = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) ('target/project-update-fixtures/' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$key = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
try {
    $trust = [ordered]@{ schemaVersion = 1; keys = @(@{ keyId = 'fixture'; subjectPublicKeyInfo = [Convert]::ToBase64String($key.ExportSubjectPublicKeyInfo()) }); githubRepository = 'YangYuS8/SteamWrapper'; cnbRepository = 'Nesoriel/SteamWrapper' }
    $trustPath = Join-Path $root 'trust.json'
    $trust | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $trustPath
    $metadata = [pscustomobject]@{ schemaVersion = 2; tag = 'v0.2.5-preview.1'; version = '0.2.5'; commit = ('a' * 40); minimumWindowsVersion = '10.0.26100.0'; releaseChannel = 'preview'; installerAsset = [pscustomobject]@{ fileName = 'SteamWrapper-v0.2.5-preview.1-win-x64-setup.exe'; bytes = 128; sha256 = ('b' * 64) } }
    $now = [DateTimeOffset]::Parse('2026-10-05T00:00:00Z')
    $payload = New-ProjectUpdatePayload -ReleaseMetadata $metadata -Trust $trust -Now $now
    $path = Join-Path $root 'SteamWrapper-update.json'
    Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId 'fixture' -Path $path
    $verified = Read-ProjectUpdateEnvelope -Path $path -TrustPath $trustPath -Now $now
    if ($verified.schemaVersion -ne 2 -or $verified.release.artifact.trust -ne 'project-signature' -or $null -ne $verified.release.artifact.mirrorUrl) { throw 'Unsigned Windows installer/project signature contract differs.' }
    Write-Output 'PASS: project signatures authorize an installer without Authenticode; unconfigured mirrors stay absent.'
    $mirror = New-ProjectUpdatePayload -ReleaseMetadata $metadata -Trust $trust -Now $now -IncludeCnbMirror
    if ($mirror.release.artifact.mirrorUrl -cne 'https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/v0.2.5-preview.1/SteamWrapper-v0.2.5-preview.1-win-x64-setup.exe') { throw 'Mirror does not bind the same versioned installer.' }
    Write-Output 'PASS: the optional mirror names the same build and single signed hash/size.'
    $envelope = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $envelope.signature = [Convert]::ToBase64String([byte[]]::new(64))
    $envelope | ConvertTo-Json | Set-Content -LiteralPath $path
    $rejected = $false
    try { $null = Read-ProjectUpdateEnvelope -Path $path -TrustPath $trustPath -Now $now } catch { if ($_.Exception.Message -notlike '*signature*') { throw }; $rejected = $true }
    if (-not $rejected) { throw 'A tampered signature was accepted.' }
    Write-Output 'PASS: tampered metadata cannot be refreshed.'
    Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId 'fixture' -Path $path
    $rejected = $false
    try { $null = Read-ProjectUpdateEnvelope -Path $path -TrustPath $trustPath -Now $now.AddDays(31) } catch { if ($_.Exception.Message -notlike '*expired*') { throw }; $rejected = $true }
    if (-not $rejected) { throw 'Expired metadata was accepted as a current feed.' }
    $renew = Read-ProjectUpdateEnvelope -Path $path -TrustPath $trustPath -Now $now.AddDays(31) -AllowExpired
    $oldArtifact = $renew.release.artifact | ConvertTo-Json -Compress
    $renew = Update-ProjectUpdateFreshness -Payload $renew -Now $now.AddDays(31)
    if ($renew.sequence -le $payload.sequence -or ($renew.release.artifact | ConvertTo-Json -Compress) -cne $oldArtifact) { throw 'Refresh changed the authorized artifact or did not advance sequence.' }
    Write-Output 'PASS: low-frequency releases can renew signed freshness without authorizing new software.'

    . (Join-Path $PSScriptRoot '../windows/WinUIInstallableRelease.TestFixtures.ps1')
    $fixture = New-WinUIInstallableReleaseTestFixture -Root (Join-Path $root 'package')
    $package = New-WinUIInstallableReleaseTestPackage $fixture
    $packageMetadata = Get-Content -LiteralPath $package.Metadata -Raw | ConvertFrom-Json
    $mock = Join-Path $root 'gh-fixture.ps1'
    [IO.File]::WriteAllText($mock, @'
$global:LASTEXITCODE = 0
$state = Get-Content -LiteralPath $env:STEAMWRAPPER_UPDATE_FIXTURE -Raw | ConvertFrom-Json -AsHashtable
$a = @($args)
function Save { $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $env:STEAMWRAPPER_UPDATE_FIXTURE }
function Option([string]$name) { $a[[Array]::IndexOf($a, $name) + 1] }
if ($a[0] -eq 'api') { $state.commit; return }
switch ($a[1]) {
    'view' {
        if (-not $state.present) { $global:LASTEXITCODE = 1; 'release not found'; return }
        $assets = @()
        if (Test-Path -LiteralPath $state.manifest) { $assets += @{ name = 'SteamWrapper-update.json'; size = (Get-Item -LiteralPath $state.manifest).Length } }
        @{ tagName = 'update-preview'; isDraft = $state.draft; isPrerelease = $true; assets = $assets } | ConvertTo-Json -Depth 5 -Compress
    }
    'download' {
        $source = if ($a[2] -eq 'update-preview') { $state.manifest } else { $state.installer }
        Copy-Item -LiteralPath $source -Destination (Join-Path (Option '--dir') (Option '--pattern'))
    }
    'create' {
        if ($a[2] -cne 'update-preview' -or $a -notcontains '--draft' -or $a -notcontains '--latest=false' -or (Option '--target') -cne 'main') { throw 'Metadata release must target the default branch to avoid workflow write permissions.' }
        $state.present = $true; $state.draft = $true; $state.writes++; Save
    }
    'upload' {
        if ($a[2] -cne 'update-preview' -or [IO.Path]::GetFileName($a[3]) -cne 'SteamWrapper-update.json' -or $a -notcontains '--clobber') { throw 'Attempted overwrite outside the dedicated metadata feed.' }
        Copy-Item -LiteralPath $a[3] -Destination $state.manifest -Force
        $state.writes++; Save
    }
    'edit' {
        if (-not $state.draft) { throw 'An existing metadata feed should only replace its asset, not edit a historical workflow target.' }
        $state.draft = $false; $state.writes++; Save
    }
    default { throw 'Unexpected gh fixture command.' }
}
'@)
    $statePath = Join-Path $root 'github-state.json'
    $remoteManifest = Join-Path $root 'remote-update.json'
    @{ present = $false; draft = $false; writes = 0; commit = $packageMetadata.commit; manifest = $remoteManifest; installer = (Join-Path $package.Directory $packageMetadata.installerAsset.fileName) } | ConvertTo-Json | Set-Content -LiteralPath $statePath
    $previousFixture = $env:STEAMWRAPPER_UPDATE_FIXTURE
    $previousKey = $env:STEAMWRAPPER_UPDATE_PRIVATE_KEY
    try {
        $env:STEAMWRAPPER_UPDATE_FIXTURE = $statePath
        $env:STEAMWRAPPER_UPDATE_PRIVATE_KEY = $null
        $null = & (Join-Path $PSScriptRoot 'Publish-UpdateMetadata.ps1') -Refresh -SkipMissingFeed -Channel stable -TrustPath $trustPath -GhExecutable $mock
        if ((Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).writes -ne 0 -or $LASTEXITCODE -ne 0) { throw 'An unpublished channel was mutated or leaves the GitHub pwsh step failing.' }
        Write-Output 'PASS: scheduled refresh skips an unpublished channel without signing secrets or writes.'
        $env:STEAMWRAPPER_UPDATE_PRIVATE_KEY = [Convert]::ToBase64String($key.ExportPkcs8PrivateKey())
        $null = & (Join-Path $PSScriptRoot 'Publish-UpdateMetadata.ps1') -PackageDirectory $package.Directory -TrustPath $trustPath -GhExecutable $mock
        $published = Read-ProjectUpdateEnvelope -Path $remoteManifest -TrustPath $trustPath
        if ($published.release.tag -cne $packageMetadata.tag -or $published.release.artifact.sha256 -cne $packageMetadata.installerAsset.sha256) { throw 'The published feed selected different installer bytes.' }
        $null = & (Join-Path $PSScriptRoot 'Publish-UpdateMetadata.ps1') -Refresh -TrustPath $trustPath -GhExecutable $mock
        $refreshed = Read-ProjectUpdateEnvelope -Path $remoteManifest -TrustPath $trustPath
        if ($refreshed.sequence -le $published.sequence -or $refreshed.release.artifact.sha256 -cne $published.release.artifact.sha256) { throw 'Scheduled refresh did not preserve the authorized build.' }
        Write-Output 'PASS: a version publish creates the dedicated feed; scheduled refresh advances it without building or replacing version assets.'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $writes = $state.writes
        $tampered = Get-Content -LiteralPath $remoteManifest -Raw | ConvertFrom-Json
        $tampered.signature = [Convert]::ToBase64String([byte[]]::new(64))
        $tampered | ConvertTo-Json | Set-Content -LiteralPath $remoteManifest
        $rejected = $false
        try { $null = & (Join-Path $PSScriptRoot 'Publish-UpdateMetadata.ps1') -Refresh -TrustPath $trustPath -GhExecutable $mock }
        catch { if ($_.Exception.Message -notlike '*signature*') { throw }; $rejected = $true }
        if (-not $rejected -or (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).writes -ne $writes) { throw 'Invalid old metadata was reauthorized or mutated.' }
        Write-Output 'PASS: the scheduled publisher rejects tampered existing metadata before any network writes.'
    } finally { $env:STEAMWRAPPER_UPDATE_FIXTURE = $previousFixture; $env:STEAMWRAPPER_UPDATE_PRIVATE_KEY = $previousKey }

    . (Join-Path $PSScriptRoot 'UpdateFeedTransport.ps1')
    $rejected = $false
    try { $null = Invoke-CnbUpdateHttp -Method GET -Uri 'https://untrusted.example/path' -Authenticated }
    catch { if ($_.Exception.Message -notlike '*authentication is restricted*') { throw }; $rejected = $true }
    if (-not $rejected) { throw 'CNB credentials could be sent outside the selected API.' }
    Write-Output 'PASS: CNB authentication cannot be forwarded to a storage or unrelated host.'

    if (-not ('ProjectUpdateFixtureHandler' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class ProjectUpdateFixtureHandler : HttpMessageHandler {
    public readonly Queue<HttpResponseMessage> Replies = new();
    public readonly List<bool> Authenticated = new();
    public readonly List<string> Requests = new();
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        Authenticated.Add(request.Headers.Authorization != null);
        Requests.Add(request.Method + " " + request.RequestUri.Host + request.RequestUri.AbsolutePath);
        if (Replies.Count == 0) throw new Exception("Unexpected fixture request.");
        return Task.FromResult(Replies.Dequeue());
    }
    public void Reply(int status, string text, string redirect = null) {
        var reply = new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent(text) };
        if (redirect != null) reply.Headers.Location = new Uri(redirect);
        Replies.Enqueue(reply);
    }
}
'@
    }
    $cnbPayload = New-ProjectUpdatePayload -ReleaseMetadata $packageMetadata -Trust $trust -IncludeCnbMirror
    $cnbManifest = Join-Path $root 'cnb-update.json'
    Write-ProjectUpdateEnvelope -Payload $cnbPayload -Key $key -KeyId 'fixture' -Path $cnbManifest
    $cnbJson = [IO.File]::ReadAllText($cnbManifest)
    $previousCnbToken = $env:CNB_RELEASE_TOKEN
    try {
        $env:CNB_RELEASE_TOKEN = 'fixture-only-not-a-real-credential'
        foreach ($unsafe in @($false, $true)) {
            $handler = [ProjectUpdateFixtureHandler]::new()
            $client = [Net.Http.HttpClient]::new($handler)
            try {
                $handler.Reply(404, '{}')
                $handler.Reply(201, '{}')
                $handler.Reply(404, '{}')
                $handler.Reply(201, '{"id":"fixture-release","tag_name":"update-preview","prerelease":true,"draft":true,"assets":[]}')
                $confirmation = if ($unsafe) { 'https://untrusted.example/upload' } else { 'https://api.cnb.cool/Nesoriel/SteamWrapper/-/releases/fixture-release/asset-upload-confirmation/a/b' }
                $handler.Reply(200, (@{ upload_url = 'https://storage.example/fixture'; verify_url = $confirmation } | ConvertTo-Json -Compress))
                if ($unsafe) {
                    $rejected = $false
                    try { Publish-CnbUpdateFeed -ManifestPath $cnbManifest -Payload $cnbPayload -TrustPath $trustPath -Client $client }
                    catch { if ($_.Exception.Message -notlike '*Unsafe CNB update upload confirmation*') { throw }; $rejected = $true }
                    if (-not $rejected -or $handler.Requests.Count -ne 5) { throw 'An unsafe CNB confirmation allowed an upload.' }
                    Write-Output 'PASS: CNB rejects an unsafe upload confirmation before sending file bytes.'
                } else {
                    $handler.Reply(200, '')
                    $handler.Reply(200, '{}')
                    $handler.Reply(302, '', 'https://asset.cnb.cool/fixture')
                    $handler.Reply(200, $cnbJson)
                    $handler.Reply(200, '{}')
                    Publish-CnbUpdateFeed -ManifestPath $cnbManifest -Payload $cnbPayload -TrustPath $trustPath -Client $client
                    if ($handler.Requests.Count -ne 10 -or $handler.Authenticated[5] -or $handler.Authenticated[7] -or $handler.Authenticated[8] -or -not $handler.Authenticated[9]) { throw 'CNB upload/download authorization or publication sequence differs.' }
                    Write-Output 'PASS: the CNB feed publishes exactly the same signed bytes after download verification, with no storage credentials.'
                }
            } finally { $client.Dispose() }
        }
    } finally { $env:CNB_RELEASE_TOKEN = $previousCnbToken }
} finally { $key.Dispose() }
