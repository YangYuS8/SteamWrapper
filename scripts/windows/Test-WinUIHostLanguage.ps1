[CmdletBinding()]
param(
    [string]$HostPath = (Join-Path $PSScriptRoot '../../target/winui/publish/Deployment/SteamWrapper.exe')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Actual NativeAOT Host language acceptance requires Windows.' }
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$allowedRoot = Join-Path $repository 'target/winui'

function Assert-HostAcceptancePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\') -or
        -not $full.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $full.Substring([IO.Path]::GetPathRoot($full).Length).Contains(':')) {
        throw 'Host language inputs and outputs must be local descendants of target/winui.'
    }
    for ($ancestor = $full; $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
        try { $attributes = [IO.File]::GetAttributes($ancestor) }
        catch [IO.FileNotFoundException] { continue }
        catch [IO.DirectoryNotFoundException] { continue }
        if ($attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Host language paths must not traverse reparse points.' }
    }
    return $full
}

$hostFile = Get-Item -LiteralPath (Assert-HostAcceptancePath $HostPath) -Force
if ($hostFile -isnot [IO.FileInfo] -or $hostFile.Name -cne 'SteamWrapper.exe' -or $hostFile.Length -lt 512 -or $hostFile.Length -gt 64MB) {
    throw 'Host language acceptance requires a bounded regular SteamWrapper.exe.'
}
# Inspect the existing final PE before executing it. A framework-dependent DLL
# or apphost is not evidence for the NativeAOT production Host.
$hostBytes = [IO.File]::ReadAllBytes($hostFile.FullName)
$peOffset = [BitConverter]::ToInt32($hostBytes, 60)
if ($hostBytes[0] -ne 0x4d -or $hostBytes[1] -ne 0x5a -or $peOffset -lt 64 -or $peOffset + 264 -gt $hostBytes.Length -or
    [BitConverter]::ToUInt32($hostBytes, $peOffset) -ne 0x4550 -or
    [BitConverter]::ToUInt16($hostBytes, $peOffset + 4) -ne 0x8664 -or
    [BitConverter]::ToUInt16($hostBytes, $peOffset + 24) -ne 0x20b -or
    [BitConverter]::ToUInt16($hostBytes, $peOffset + 24 + 68) -ne 2 -or
    [BitConverter]::ToUInt32($hostBytes, $peOffset + 24 + 112 + 14 * 8) -ne 0) {
    throw 'Host language acceptance requires the published x64 GUI NativeAOT PE without a CLR header.'
}
$product = [Diagnostics.FileVersionInfo]::GetVersionInfo($hostFile.FullName)
if ($product.ProductName -cne 'SteamWrapper' -or $product.ProductVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z') {
    throw 'Host language acceptance requires the coordinated SteamWrapper product metadata.'
}
$hostHash = (Get-FileHash -LiteralPath $hostFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$fixture = Assert-HostAcceptancePath (Join-Path $allowedRoot ('host-language-acceptance/' + [guid]::NewGuid().ToString('N')))
if ([IO.Directory]::Exists($fixture) -or [IO.File]::Exists($fixture)) { throw 'Host language acceptance requires a fresh fixture.' }
$program = Join-Path $fixture 'program'
$localData = Join-Path $fixture 'data'
$data = Join-Path $localData 'SteamWrapper'
$settings = Join-Path $data 'ui-settings.json'
foreach ($directory in @($program, (Join-Path $data 'bin'))) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
[IO.File]::WriteAllText((Join-Path $data 'profiles.toml'), 'preserve fixture profile 中文', [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $data 'bin/SteamWrapperRunner.exe'), 'nonexecuted stable Runner fixture', [Text.UTF8Encoding]::new($false))

function Get-HostDataSnapshot {
    $snapshot = [ordered]@{}
    $entries = @(Get-ChildItem -LiteralPath $data -Recurse -Force)
    if ($entries.Count -gt 64) { throw 'Host language fixture exceeds its bounded entry limit.' }
    foreach ($entry in $entries | Sort-Object FullName) {
        $null = Assert-HostAcceptancePath $entry.FullName
        $relative = [IO.Path]::GetRelativePath($data, $entry.FullName).Replace('\', '/')
        if ($entry -is [IO.DirectoryInfo]) { $snapshot[$relative + '/'] = 'directory'; continue }
        if ($entry -isnot [IO.FileInfo] -or $entry.Length -gt 64KB) { throw 'Host language fixture contains an oversized or non-regular file.' }
        $snapshot[$relative] = [ordered]@{ bytes = $entry.Length; sha256 = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return $snapshot
}

# This is the actual Windows process UI culture, never an injected test culture.
$systemCulture = [Globalization.CultureInfo]::CurrentUICulture
$systemLanguage = 'en'
for ($culture = $systemCulture; $culture.Name; $culture = $culture.Parent) {
    if ($culture.Name -in @('zh-CN', 'zh-SG', 'zh-Hans')) { $systemLanguage = 'zh-CN'; break }
}
$messages = @{
    'en' = 'No complete Manager installation is available. Run the matching verified installer to install or repair it.'
    'zh-CN' = '没有可用的完整管理器安装。请运行匹配且经过验证的安装包进行安装或修复。'
}
$cases = @(
    @{ name = 'missing preference follows actual system UI culture'; content = $null; language = $systemLanguage },
    @{ name = 'language-less preference follows actual system UI culture'; content = '{"steamCdnCovers":false,"future":{"text":"保留 中文"}}'; language = $systemLanguage },
    @{ name = 'explicit English overrides actual system UI culture'; content = '{"language":"en","future":"保留 中文"}'; language = 'en' },
    @{ name = 'explicit Chinese overrides actual system UI culture'; content = '{"language":"zh-CN","future":"保留 中文"}'; language = 'zh-CN' },
    @{ name = 'malformed preference retains read-only English fallback'; content = '{bad 中文'; language = 'en' }
)
$results = [Collections.Generic.List[object]]::new()
$evidencePath = Join-Path $fixture 'evidence.json'
try {
    foreach ($case in $cases) {
        if ($null -ne $case.content) { [IO.File]::WriteAllText($settings, $case.content, [Text.UTF8Encoding]::new($false)) }
        $before = Get-HostDataSnapshot
        $record = [ordered]@{ name = $case.name; expectedLanguage = $case.language; passed = $false; before = $before }
        $start = [Diagnostics.ProcessStartInfo]::new($hostFile.FullName)
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.WorkingDirectory = $fixture
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        foreach ($argument in @('--repair', '--test-root', '--root', $program)) { $start.ArgumentList.Add($argument) }
        $start.Environment['STEAMWRAPPER_DEPLOYMENT_TEST'] = '1'
        $start.Environment['STEAMWRAPPER_E2E_ROOT'] = $fixture
        $start.Environment['LOCALAPPDATA'] = $localData
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            if (-not $process.Start()) { throw 'The existing NativeAOT Host did not start.' }
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(30000)) {
                throw 'The fixture Host did not exit in 30 seconds. It was not killed; no further cases will run.'
            }
            $record['exitCode'] = $process.ExitCode
            $record['stdout'] = $stdout.GetAwaiter().GetResult()
            $record['stderr'] = $stderr.GetAwaiter().GetResult()
            $record['after'] = Get-HostDataSnapshot
            $programEntries = @(Get-ChildItem -LiteralPath $program -Force -Recurse)
            $unchanged = ($before | ConvertTo-Json -Depth 6 -Compress) -ceq ($record.after | ConvertTo-Json -Depth 6 -Compress)
            $programIsEmpty = $programEntries.Count -eq 1 -and $programEntries[0] -is [IO.FileInfo] -and $programEntries[0].Name -ceq '.installation.lock' -and $programEntries[0].Length -eq 0
            $record['passed'] = $process.ExitCode -eq 11 -and $record.stdout -ceq '' -and
                $record.stderr.Trim() -ceq $messages[$case.language] -and $unchanged -and $programIsEmpty
            if (-not $record.passed) { $record['error'] = 'Missing-installation message, exit code, read-only data or empty program-root assertion failed.' }
            Write-Output ("{0}: {1}" -f $(if ($record.passed) { 'PASS' } else { 'FAIL' }), $case.name)
        }
        catch { $record['error'] = $_.Exception.Message; throw }
        finally { $results.Add($record); $process.Dispose() }
    }
    if ((Get-FileHash -LiteralPath $hostFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hostHash) {
        throw 'The published Host changed during acceptance; the evidence is not for one immutable artifact.'
    }
}
finally {
    $evidence = [ordered]@{
        schemaVersion = 1; nativeAotHost = $true; cleanVm = $false; hostPath = $hostFile.FullName; hostSha256 = $hostHash
        productVersion = $product.ProductVersion; systemUiCulture = $systemCulture.Name; expectedSystemLanguage = $systemLanguage
        fixtureRoot = $fixture; cases = $results.ToArray()
        limits = @('Only the actual local Windows UI culture was tested.', 'No installed application, user settings, Steam or game files were changed.', 'No process was forcibly terminated.')
    }
    [IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Write-Output "NativeAOT Host language evidence: $evidencePath"
}
if (@($results | Where-Object { -not $_.passed }).Count) { throw 'Actual NativeAOT Host language acceptance failed; inspect the retained evidence.' }
Write-Output 'PASS: all five actual NativeAOT Host language cases; fixture data and published Host bytes preserved.'
