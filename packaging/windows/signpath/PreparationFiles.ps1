# Bounded local preparation reads only. No network, process launch or file deletion.
. (Join-Path $PSScriptRoot '../../../scripts/windows/WindowsSigning.ps1')
function Get-PreparationFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$AllowedRoot, [long]$MaximumBytes = 4MB)
    $full = Resolve-WindowsSigningFile -Path $Path -AllowedRoot $AllowedRoot
    $file = Get-Item -LiteralPath $full -Force
    if ($file -isnot [IO.FileInfo] -or $file.Length -lt 0 -or $file.Length -gt $MaximumBytes) { throw 'Preparation input is not a bounded regular file.' }
    return $file
}
function Read-PreparationText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$AllowedRoot, [long]$MaximumBytes = 4MB)
    $file = Get-PreparationFile -Path $Path -AllowedRoot $AllowedRoot -MaximumBytes $MaximumBytes
    $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -gt $MaximumBytes) { throw 'Preparation text exceeds the configured byte limit.' }
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}
function Get-PreparationPublishFiles {
    param([Parameter(Mandatory)][string]$Root, [int]$MaximumEntries = 4096, [long]$MaximumTotalBytes = 2GB)
    $full = [IO.Path]::GetFullPath($Root)
    $null = Resolve-WindowsSigningFile -Path (Join-Path $full 'preparation-guard') -AllowedRoot $full -AllowMissing
    $pending = [Collections.Generic.Stack[object]]::new(); $pending.Push(@{ path = $full; depth = 0 })
    $files = [Collections.Generic.List[object]]::new(); $count = 0; $total = [long]0
    while ($pending.Count) {
        $current = $pending.Pop()
        foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($current.path)) {
            if (++$count -gt $MaximumEntries) { throw 'Preparation publication exceeds the entry-count limit.' }
            $entry = Get-Item -LiteralPath $path -Force
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Preparation publication cannot traverse reparse points.' }
            if ($entry.Name -match '(?i)^(\.env(?:\..*)?|credentials?|secrets?|tokens?)(?:\..*)?$' -or
                $entry.Extension -in @('.pfx', '.p12', '.pem', '.key')) { throw 'Preparation publication contains a private file name; no bytes were read.' }
            if ($entry -is [IO.DirectoryInfo]) {
                if ($current.depth -ge 16) { throw 'Preparation publication exceeds the directory-depth limit.' }
                $pending.Push(@{ path = $path; depth = $current.depth + 1 })
            } else {
                $file = Get-PreparationFile -Path $path -AllowedRoot $full -MaximumBytes 512MB
                $total += $file.Length
                if ($total -gt $MaximumTotalBytes) { throw 'Preparation publication exceeds the total-byte limit.' }
                $files.Add($file)
            }
        }
    }
    return $files.ToArray()
}
function Assert-PreparationDisjointRoots {
    param([Parameter(Mandatory)][string]$First, [Parameter(Mandatory)][string]$Second)
    $one = [IO.Path]::GetFullPath($First).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $two = [IO.Path]::GetFullPath($Second).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($one.Equals($two, [StringComparison]::OrdinalIgnoreCase) -or
        $one.StartsWith($two + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $two.StartsWith($one + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Preparation output and publication roots must be disjoint.' }
}
function Assert-ThirdPartyCatalog {
    param([Parameter(Mandatory)]$Catalog, [Parameter(Mandatory)][string]$LicenseRoot)
    if ($Catalog.schemaVersion -ne 1 -or @($Catalog.files).Count -eq 0 -or @($Catalog.files).Count -gt 512 -or @($Catalog.components).Count -gt 256) { throw 'Unsupported or oversized third-party catalog.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $total = [long]0
    foreach ($entry in $Catalog.files) {
        if ($entry.path -cnotmatch '^[A-Za-z0-9.+_/-]+\z' -or $entry.path.StartsWith('/') -or
            @($entry.path.Split('/') | Where-Object { $_ -in @('', '.', '..') -or $_ -match '(?i)^(\.env|credentials?|secrets?|tokens?)(?:[._-]|$)' }).Count -or
            [IO.Path]::GetExtension($entry.path) -cnotin @('.txt', '.TXT', '.md', '.rtf', '.0', '') -or -not $seen.Add($entry.path)) { throw 'Third-party catalog contains an unsafe, private or duplicate license path.' }
        if ($entry.sha256 -cnotmatch '^[a-f0-9]{64}\z' -or $entry.bytes -le 0 -or $entry.bytes -gt 2MB) { throw 'Third-party catalog contains an invalid or oversized legal file.' }
        $file = Get-PreparationFile -Path (Join-Path $LicenseRoot $entry.path) -AllowedRoot $LicenseRoot -MaximumBytes 2MB
        if ($file.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) { throw 'Canonical third-party legal file changed; review its version and hash before staging.' }
        $total += $file.Length
        if ($total -gt 16MB) { throw 'Third-party legal materials exceed the total-byte limit.' }
    }
    foreach ($component in $Catalog.components) {
        if (@($component.licenses).Count -eq 0 -or @($component.licenses | Where-Object { -not $seen.Contains($_) }).Count) { throw 'Third-party component has missing required license references.' }
    }
}
