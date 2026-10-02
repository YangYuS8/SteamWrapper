# Disposable byte fixtures exercise package integrity and publisher behavior.
# Their .exe/.dll files are text, never executable acceptance evidence.
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')
function New-WinUIReleaseTestFixture {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Tag = 'v0.2.0',
        [string]$Commit = '0123456789abcdef0123456789abcdef01234567'
    )
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $null = Assert-WinUIReleasePath $Root (Join-Path $repoRoot 'target')
    $source = Join-Path $Root 'source'
    if (Test-Path -LiteralPath $source) { throw 'Release test fixture source must be fresh.' }
    $publish = Join-Path $source 'target/winui/publish'
    New-Item -ItemType Directory -Path (Join-Path $source 'apps/manager-winui/SteamWrapper.Manager'), (Join-Path $source 'crates/core'), (Join-Path $source 'crates/runner'), (Join-Path $source 'releases'), $publish -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'apps/manager-winui/SteamWrapper.Manager/SteamWrapper.Manager.csproj'), '<Project><PropertyGroup><Version>0.2.0</Version></PropertyGroup></Project>')
    foreach ($crate in @('core', 'runner')) { [IO.File]::WriteAllText((Join-Path $source "crates/$crate/Cargo.toml"), "[package]`nversion = `"0.2.0`"`n") }
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'), 'Fixture license text.')
    foreach ($language in @('en', 'zh-CN')) { [IO.File]::WriteAllText((Join-Path $source "releases/$Tag.$language.md"), "# $Tag`n`nUnsigned Windows preview / 未签名 Windows 预览。`n") }
    foreach ($relative in @(Get-WinUIReleaseRequiredFiles) + @('extra-runtime-dependency.dll')) {
        $path = Join-Path $publish $relative
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($path)) -Force | Out-Null
        [IO.File]::WriteAllText($path, "Fixture bytes for $relative")
    }
    $runnerHash = (Get-FileHash -LiteralPath (Join-Path $publish 'Runner/SteamWrapperRunner.exe')).Hash.ToLowerInvariant()
    @{ schemaVersion = 1; contractVersion = 2; version = '0.2.0'; sha256 = $runnerHash } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $publish 'Runner/runner-manifest.json') -Encoding utf8NoBOM
    [IO.File]::WriteAllText((Join-Path $publish 'SteamWrapper.Manager.runtimeconfig.json'), '{"runtimeOptions":{"includedFrameworks":[{"name":"Microsoft.NETCore.App","version":"10.0.0"}]}}')
    return [pscustomobject]@{
        RepositoryRoot = $source; PublishDirectory = $publish
        OutputDirectory = Join-Path $source "target/winui/releases/$Tag"
        Tag = $Tag; Commit = $Commit
    }
}
