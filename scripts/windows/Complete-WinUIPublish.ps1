# Shared by the real publish command and focused filesystem regression checks.
function Assert-WinUIBuildPath([string]$Path) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'target/winui'))
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -ne $allowedRoot -and -not $full.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Publish path is outside the repository's target/winui directory: $full"
    }
    # Check ancestors as well as children so a junction cannot redirect a move/delete.
    $ancestor = $full
    while ($ancestor -and $ancestor -ne $repoRoot) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Publish paths must not contain reparse points: $ancestor"
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (Test-Path -LiteralPath $full -PathType Container) {
        $reparse = Get-ChildItem -LiteralPath $full -Recurse -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Select-Object -First 1
        if ($reparse) { throw "Publish contents must not contain reparse points: $($reparse.FullName)" }
    }
}

function Complete-WinUIPublish {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string[]]$RequiredFiles
    )
    $rootPath = [IO.Path]::GetFullPath($Root)
    $candidatePath = [IO.Path]::GetFullPath($Candidate)
    $destination = Join-Path $rootPath 'publish'
    $previous = Join-Path $rootPath ('publish-previous-' + [Guid]::NewGuid().ToString('N'))
    foreach ($path in @($rootPath, $candidatePath, $destination, $previous)) { Assert-WinUIBuildPath $path }
    if ([IO.Path]::GetDirectoryName($candidatePath) -ne $rootPath -or
        [IO.Path]::GetFileName($candidatePath) -notmatch '^publish-staging-[a-f0-9]{32}$') {
        throw 'The publish candidate must be a fresh publish-staging directory directly under the output root.'
    }
    foreach ($relative in $RequiredFiles) {
        $file = [IO.Path]::GetFullPath((Join-Path $candidatePath $relative))
        if (-not $file.StartsWith($candidatePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
            throw "Publish is missing a non-empty required file: $relative. The previous release is unchanged."
        }
    }

    # Serialize this tool's publishers; directory renames are not a power-loss transaction.
    $publishLock = [IO.FileStream]::new((Join-Path $rootPath '.publish.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        try {
            if (Test-Path -LiteralPath $destination) {
                Assert-WinUIBuildPath $destination
                Assert-WinUIBuildPath $previous
                [IO.Directory]::Move($destination, $previous)
            }
            Assert-WinUIBuildPath $candidatePath
            Assert-WinUIBuildPath $destination
            # Directory.Move performs a same-parent rename. Move-Item can instead
            # create an empty destination before failing on a locked child file.
            [IO.Directory]::Move($candidatePath, $destination)
        } catch {
            $failure = $_
            if ((Test-Path -LiteralPath $previous) -and -not (Test-Path -LiteralPath $destination)) {
                try {
                    Assert-WinUIBuildPath $previous
                    Assert-WinUIBuildPath $destination
                    [IO.Directory]::Move($previous, $destination)
                } catch {
                    throw "Publish replacement failed. The previous release is retained at $previous; automatic restoration failed: $_"
                }
            }
            throw $failure
        }
        if (Test-Path -LiteralPath $previous) {
            try {
                Assert-WinUIBuildPath $previous
                Remove-Item -LiteralPath $previous -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Warning "The new release is ready. The previous directory could not be removed and is retained at ${previous}: $_"
            }
        }
    } finally { $publishLock.Dispose() }
    return $destination
}
