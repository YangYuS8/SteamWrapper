[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$publisher = Join-Path $PSScriptRoot 'Publish-CnbRelease.ps1'
if (Test-Path -LiteralPath $publisher) { . $publisher }

# Fixture requests never reach the network. Record authorization presence only.
if (-not ('CnbReleaseFixtureHandler' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class CnbReleaseFixtureHandler : HttpMessageHandler {
    public readonly Queue<HttpResponseMessage> Replies = new();
    public readonly List<string> Requests = new();
    public readonly List<bool> Authenticated = new();
    public readonly List<string> Bodies = new();
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation) {
        Requests.Add(request.Method + " " + request.RequestUri.Host + request.RequestUri.AbsolutePath);
        Authenticated.Add(request.Headers.Authorization != null);
        Bodies.Add(request.Content == null ? "" : request.Content.ReadAsStringAsync(cancellation).GetAwaiter().GetResult());
        if (Replies.Count == 0) throw new Exception("Unexpected fixture HTTP request.");
        return Task.FromResult(Replies.Dequeue());
    }
    public void Reply(int status, string json) {
        Replies.Enqueue(new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent(json) });
    }
    public void Binary(byte[] bytes) {
        Replies.Enqueue(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) });
    }
    public void Redirect(string location) {
        var response = new HttpResponseMessage(HttpStatusCode.Found) { Content = new StringContent("") };
        response.Headers.Location = new Uri(location);
        Replies.Enqueue(response);
    }
}
'@
}
$root = Join-Path ((Resolve-Path (Join-Path $PSScriptRoot '../..')).Path) ('target/cnb-release-tests/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
. (Join-Path $PSScriptRoot '../windows/WinUIRelease.TestFixtures.ps1')
$fixture = New-WinUIReleaseTestFixture -Root (Join-Path $root 'package')
$package = New-WinUIReleasePackage -Tag $fixture.Tag -Commit $fixture.Commit -RepositoryRoot $fixture.RepositoryRoot -PublishDirectory $fixture.PublishDirectory -OutputDirectory $fixture.OutputDirectory
$root = $package.Directory
$metadata = Test-WinUIReleasePackageDirectory -PackageDirectory $root
$tag = $metadata.tag
$commit = $metadata.commit
$archive = $metadata.archive.fileName
$utf8 = [Text.UTF8Encoding]::new($false)
$names = @($archive, "$tag.en.md", "$tag.zh-CN.md", 'release.json')
$names += 'SHA256SUMS'
function New-FixtureClient {
    $handler = [CnbReleaseFixtureHandler]::new()
    @{ Handler = $handler; Client = [Net.Http.HttpClient]::new($handler) }
}
function Add-TagReply($Handler, [string]$Sha = $commit) { $Handler.Reply(200, (@{ name = $tag; commit = @{ sha = $Sha } } | ConvertTo-Json -Compress)) }
function Get-FixtureRelease([bool]$Draft, [string[]]$Names = @(), [bool]$Prerelease = $true, [string]$Sha = "refs/tags/$tag") {
    $records = foreach ($name in $Names) { @{ name = $name; size = (Get-Item -LiteralPath (Join-Path $root $name)).Length } }
    return @{ id = 'release-1'; tag_name = $tag; tag_commitish = $Sha; draft = $Draft; prerelease = $Prerelease; assets = @($records) } | ConvertTo-Json -Depth 5 -Compress
}
function Add-DownloadReply($Handler, [string]$Name) {
    $Handler.Redirect('https://downloads.example.test/' + $Name)
    $Handler.Binary([IO.File]::ReadAllBytes((Join-Path $root $Name)))
}
function Add-UploadReplies($Handler, [string[]]$Names = $names) {
    foreach ($name in $Names) {
        $Handler.Reply(201, (@{ upload_url = 'https://uploads.example.test/' + $name + '?signature=fixture'; verify_url = 'https://api.cnb.cool/Nesoriel/SteamWrapper/-/releases/release-1/asset-upload-confirmation/fixture/' + $name } | ConvertTo-Json -Compress))
        $Handler.Reply(200, '')
        $Handler.Reply(200, '{}')
        Add-DownloadReply $Handler $name
    }
}
function Assert-NoCnbWrites($Handler) {
    if (@($Handler.Requests | Where-Object { $_ -match '^(POST|PATCH|PUT) ' }).Count -ne 0) { throw 'A rejected CNB release was changed.' }
}
function Assert-Rejected([string]$Label, [scriptblock]$Run, [string]$Pattern) {
    $rejected = $false
    try { & $Run }
    catch { if ($_.Exception.Message -notlike $Pattern) { throw }; $rejected = $true }
    if (-not $rejected) { throw "$Label unexpectedly succeeded." }
    Write-Output "PASS: $Label"
}
$previousToken = $env:CNB_RELEASE_TOKEN
$env:CNB_RELEASE_TOKEN = 'fixture-token-never-a-real-credential'
try {
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(200, (Get-FixtureRelease $false $names $false))
        foreach ($name in $names) { Add-DownloadReply $fixture.Handler $name }
        Assert-Rejected 'an existing published stable release cannot be relabeled as preview' { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } '*preview*'
        if (@($fixture.Handler.Requests | Where-Object { $_ -match '^(POST|PATCH|PUT) ' }).Count -ne 0) { throw 'A stable release was changed.' }
    } finally { $fixture.Client.Dispose() }
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(404, '{}')
        $fixture.Handler.Reply(201, (Get-FixtureRelease $true))
        Add-UploadReplies $fixture.Handler
        $fixture.Handler.Reply(200, (Get-FixtureRelease $true $names))
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(200, '{}')
        $fixture.Handler.Reply(200, (Get-FixtureRelease $false $names))
        $null = Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client
        if ($fixture.Handler.Replies.Count -ne 0) { throw 'The release was not completely verified and published.' }
        $creation = $fixture.Handler.Bodies[2] | ConvertFrom-Json
        $publication = $fixture.Handler.Bodies[-2] | ConvertFrom-Json
        if (-not $creation.draft -or -not $creation.prerelease -or $creation.make_latest -ne 'false' -or $publication.draft -or -not $publication.prerelease) { throw 'Preview release flags were lost.' }
        for ($index = 0; $index -lt $fixture.Handler.Requests.Count; $index++) {
            if ($fixture.Handler.Requests[$index] -match '(uploads|downloads)\.example\.test' -and $fixture.Handler.Authenticated[$index]) { throw 'A CNB credential was forwarded to storage.' }
        }
        Write-Output 'PASS: verified draft publication keeps preview flags and does not forward credentials to storage.'
    } finally { $fixture.Client.Dispose() }
    foreach ($scenario in @('wrong-release-commit', 'unexpected', 'duplicate', 'incomplete-published')) {
        $fixture = New-FixtureClient
        try {
            Add-TagReply $fixture.Handler
            $state = Get-FixtureRelease $false $names | ConvertFrom-Json -AsHashtable
            $pattern = '*'
            switch ($scenario) {
                'wrong-release-commit' { $state.tag_commitish = 'f' * 40; $pattern = '*identity*' }
                'unexpected' { $state.assets += @{ name = 'unrelated.txt'; size = 1 }; $pattern = '*unexpected asset*' }
                'duplicate' { $state.assets += $state.assets[0]; $pattern = '*duplicate*' }
                'incomplete-published' { $state.assets = @($state.assets[0]); $pattern = '*incomplete*' }
            }
            $fixture.Handler.Reply(200, ($state | ConvertTo-Json -Depth 6 -Compress))
            Assert-Rejected "$scenario is rejected before release writes" { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } $pattern
            Assert-NoCnbWrites $fixture.Handler
        } finally { $fixture.Client.Dispose() }
    }
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(200, (Get-FixtureRelease $false @() $false))
        $fixture.Handler.Reply(200, '{}')
        Add-UploadReplies $fixture.Handler
        $fixture.Handler.Reply(200, (Get-FixtureRelease $true $names))
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(200, '{}')
        $fixture.Handler.Reply(200, (Get-FixtureRelease $false $names))
        $null = Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client
        $preparation = $fixture.Handler.Bodies[2] | ConvertFrom-Json
        if ($fixture.Handler.Requests[2] -notmatch '^PATCH ' -or -not $preparation.draft -or -not $preparation.prerelease) { throw 'Notes-only migration uploaded assets before making the release a preview draft.' }
        Write-Output 'PASS: a matching legacy notes-only release becomes a draft before attachments are uploaded.'
    } finally { $fixture.Client.Dispose() }
    foreach ($scenario in @('changed-draft-commit', 'missing-draft-asset', 'moved-tag', 'publication-not-confirmed')) {
        $fixture = New-FixtureClient
        try {
            Add-TagReply $fixture.Handler
            $fixture.Handler.Reply(200, (Get-FixtureRelease $true $names))
            foreach ($name in $names) { Add-DownloadReply $fixture.Handler $name }
            $state = Get-FixtureRelease $true $names | ConvertFrom-Json -AsHashtable
            switch ($scenario) {
                'changed-draft-commit' { $state.tag_commitish = 'f' * 40 }
                'missing-draft-asset' { $state.assets = @($state.assets | Select-Object -SkipLast 1) }
            }
            $fixture.Handler.Reply(200, ($state | ConvertTo-Json -Depth 6 -Compress))
            if ($scenario -eq 'moved-tag') { Add-TagReply $fixture.Handler ('f' * 40) }
            if ($scenario -eq 'publication-not-confirmed') {
                Add-TagReply $fixture.Handler
                $fixture.Handler.Reply(200, '{}')
                $fixture.Handler.Reply(200, (Get-FixtureRelease $true $names))
            }
            Assert-Rejected "$scenario cannot report successful publication" { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } '*'
            if ($scenario -ne 'publication-not-confirmed') { Assert-NoCnbWrites $fixture.Handler }
        } finally { $fixture.Client.Dispose() }
    }
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(200, (Get-FixtureRelease $false $names))
        foreach ($name in $names) { Add-DownloadReply $fixture.Handler $name }
        $null = Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client
        if (@($fixture.Handler.Requests | Where-Object { $_ -match '^(POST|PATCH|PUT) ' }).Count -ne 0) { throw 'An identical published release was mutated.' }
        Write-Output 'PASS: an identical published release is verified and reused without writes.'
    } finally { $fixture.Client.Dispose() }
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler ('0' * 40)
        Assert-Rejected 'a different tag commit is rejected before release writes' { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } '*tag commit*'
        if ($fixture.Handler.Requests.Count -ne 1) { throw 'A mismatched tag caused additional HTTP requests.' }
    } finally { $fixture.Client.Dispose() }
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(200, (Get-FixtureRelease $false $names))
        $fixture.Handler.Redirect('https://downloads.example.test/' + $archive)
        $fixture.Handler.Binary([Text.Encoding]::UTF8.GetBytes('different archive data'))
        Assert-Rejected 'different published bytes are rejected without overwrite' { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } '*bytes differ*'
        if (@($fixture.Handler.Requests | Where-Object { $_ -match '^(POST|PATCH|PUT) ' }).Count -ne 0) { throw 'A published release was overwritten.' }
    } finally { $fixture.Client.Dispose() }
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(200, (Get-FixtureRelease $true))
        $fixture.Handler.Reply(201, '{"upload_url":"https://uploads.example.test/archive","verify_url":"https://evil.example.test/confirmation"}')
        Assert-Rejected 'foreign confirmation URL is rejected before upload' { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } '*confirmation URL*'
        if ($fixture.Handler.Requests.Count -ne 3) { throw 'An unsafe confirmation URL caused another request.' }
    } finally { $fixture.Client.Dispose() }
    $fixture = New-FixtureClient
    try {
        Add-TagReply $fixture.Handler
        $fixture.Handler.Reply(302, '{}')
        Assert-Rejected 'authenticated API redirects are rejected' { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } '*HTTP 302*'
    } finally { $fixture.Client.Dispose() }
    [IO.File]::AppendAllText((Join-Path $root $archive), 'tampering', $utf8)
    $fixture = New-FixtureClient
    try {
        Assert-Rejected 'local checksum mismatch is rejected before HTTP' { Invoke-CnbRelease -PackageDirectory $root -Client $fixture.Client } '*checksum*'
        if ($fixture.Handler.Requests.Count -ne 0) { throw 'Unverified local data reached the network.' }
    } finally { $fixture.Client.Dispose() }
} finally { $env:CNB_RELEASE_TOKEN = $previousToken }
Write-Output "CNB release fixture tests passed: $root"
