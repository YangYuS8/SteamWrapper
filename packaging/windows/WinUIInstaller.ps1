Set-StrictMode -Version Latest

function Assert-WinUIInstallerPath {
    param([Parameter(Mandatory)][string]$Path, [switch]$Output)
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $full = [IO.Path]::GetFullPath($Path)
    $allowed = Join-Path $repoRoot 'target/winui'
    if ($Output -and -not $full.StartsWith($allowed + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Installer build/test outputs must stay inside target/winui.' }
    $ancestor = $full
    while ($ancestor) {
        if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Installer paths must not contain reparse points.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (Test-Path -LiteralPath $full -PathType Container) {
        foreach ($entry in Get-ChildItem -LiteralPath $full -Recurse -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Installer contents must not contain reparse points.' }
        }
    }
    return $full
}

function Get-WinUIInstallerRequiredFiles {
    return @('SteamWrapper.Manager.exe', 'SteamWrapper.Manager.dll', 'SteamWrapper.Application.dll', 'SteamWrapper.Deployment.dll', 'SteamWrapper.Manager.pri',
        'SteamWrapper.Manager.runtimeconfig.json', 'SteamWrapper.Manager.deps.json', 'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'System.Private.CoreLib.dll',
        'Microsoft.UI.Xaml.dll', 'Microsoft.WindowsAppRuntime.dll', 'Microsoft.Windows.Storage.Pickers.Projection.dll',
        'Runner/SteamWrapperRunner.exe', 'Runner/runner-manifest.json', 'Assets/steamwrapper.svg', 'Assets/steamwrapper.ico',
        'zh-CN/SteamWrapper.Application.resources.dll', 'Deployment/SteamWrapper.exe', 'LICENSE')
}

function Assert-WinUIInstallerPayloadPrivacy {
    param([Parameter(Mandatory)][string]$Directory)
    $tree = Assert-WinUIInstallerPath $Directory
    $entries = 0
    foreach ($entry in Get-ChildItem -LiteralPath $tree -Recurse -Force) {
        $entries++
        if ($entries -gt 10000) { throw 'Installer input exceeds its bounded tree-entry limit.' }
        $relative = [IO.Path]::GetRelativePath($tree, $entry.FullName).Replace('\', '/')
        # Check metadata only; never open a possible credential or player-data file.
        if ($relative -match '[\r\n]' -or $relative -match '(?i)(^|/)(\.env(?:\..*)?|\.git|profiles\.toml|ui-settings\.json(?:\..*)?|logs|backups|cache)(/|$)') { throw 'Installer input contains private or runtime data.' }
    }
}

function Assert-WinUIInstallerTag {
    param([Parameter(Mandatory)][string]$Tag)
    # Keep the three-part numeric component version used by the existing Runner contract.
    if ($Tag -notmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$') { throw 'Installer tag must be a valid three-part version tag.' }
    if ($Matches[4]) { foreach ($identifier in $Matches[4].Split('.')) { if ($identifier -match '^0[0-9]+$') { throw 'Numeric prerelease identifiers must not have leading zeroes.' } } }
    return $Tag.Substring(1).Split('-')[0]
}

function New-WinUIInstallerManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PayloadDirectory, [Parameter(Mandatory)][string]$Tag)
    $version = Assert-WinUIInstallerTag $Tag
    $payload = Assert-WinUIInstallerPath $PayloadDirectory -Output
    Assert-WinUIInstallerPayloadPrivacy $payload
    foreach ($relative in Get-WinUIInstallerRequiredFiles) {
        $required = Join-Path $payload $relative
        if (-not (Test-Path -LiteralPath $required -PathType Leaf) -or (Get-Item -LiteralPath $required).Length -eq 0) { throw "Installer payload is missing a non-empty required file: $relative." }
    }
    $runtimePath = Join-Path $payload 'SteamWrapper.Manager.runtimeconfig.json'
    if ((Get-Item -LiteralPath $runtimePath).Length -gt 256KB) { throw 'Manager runtime configuration exceeds its bounded JSON limit.' }
    $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json -AsHashtable
    if ($runtime -isnot [Collections.IDictionary] -or -not $runtime.Contains('runtimeOptions') -or $runtime['runtimeOptions'] -isnot [Collections.IDictionary]) { throw 'Manager runtime configuration must declare its self-contained runtime.' }
    $runtimeOptions = $runtime['runtimeOptions']
    if ($runtimeOptions.Contains('framework') -or $runtimeOptions.Contains('frameworks') -or -not $runtimeOptions.Contains('includedFrameworks')) { throw 'Manager must include its .NET runtime and must not depend on a machine-installed framework.' }
    $includedRuntime = @($runtimeOptions['includedFrameworks'] | Where-Object { $_ -is [Collections.IDictionary] -and $_['name'] -ceq 'Microsoft.NETCore.App' })
    $runtimeVersion = $null
    if ($includedRuntime.Count -ne 1 -or -not [Version]::TryParse([string]$includedRuntime[0]['version'], [ref]$runtimeVersion) -or $runtimeVersion.Major -lt 1) { throw 'Manager runtime configuration has no valid included .NET runtime version.' }
    $runner = Get-Content -LiteralPath (Join-Path $payload 'Runner/runner-manifest.json') -Raw | ConvertFrom-Json
    if ($runner.schemaVersion -ne 1 -or $runner.contractVersion -ne 2 -or $runner.version -ne $version -or
        $runner.sha256 -ne (Get-FileHash -LiteralPath (Join-Path $payload 'Runner/SteamWrapperRunner.exe') -Algorithm SHA256).Hash.ToLowerInvariant()) { throw 'The Runner manifest does not match the final packaged Runner and version.' }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = @(Get-ChildItem -LiteralPath $payload -File -Recurse -Force | Sort-Object FullName | Where-Object FullName -ne (Join-Path $payload 'deployment-manifest.json') | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($payload, $_.FullName).Replace('\', '/')
        foreach ($segment in $relative.Split('/')) {
            if ($segment -in @('', '.', '..') -or $segment -match '[:\\\x00-\x1f]' -or $segment -match '[. ]$' -or $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Installer payload contains an unsafe relative path.' }
        }
        if (-not $names.Add($relative)) { throw 'Installer payload contains duplicate case-insensitive paths.' }
        if ($_.Length -eq 0 -or $_.Length -gt 512L * 1024 * 1024) { throw 'Installer payload contains an empty or oversized file.' }
        [ordered]@{ path = $relative; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $totalBytes = [long]0
    foreach ($entry in $files) { $totalBytes += $entry.bytes }
    if ($files.Count -gt 4096 -or $totalBytes -gt 1024 * 1024 * 1024) { throw 'Installer payload exceeds its bounded file-count or uncompressed-size limit.' }
    $manifest = [ordered]@{ schemaVersion = 1; appId = 'SteamWrapper'; tag = $Tag; version = $version; deploymentProtocol = 1; profileContract = 2; runnerContract = 2; managerExecutable = 'SteamWrapper.Manager.exe'; files = $files }
    $manifestPath = Join-Path $payload 'deployment-manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    return $manifestPath
}
