[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root = Join-Path $repoRoot ('target/winui/notices-tests/' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$stage = Join-Path $PSScriptRoot 'Stage-WinUIThirdPartyNotices.ps1'
. (Join-Path $repoRoot 'packaging/windows/signpath/PreparationFiles.ps1')
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    try { $null = & $Action } catch { if ($_.Exception.Message -notlike $Pattern) { throw }; return }
    throw "Expected third-party notice rejection: $Pattern"
}
Assert-Rejected { & $stage -PublishDirectory $root -VerifyOnly } '*missing third-party notices*'
$catalogRoot = Join-Path $repoRoot 'packaging/windows/third-party-notices'
$licenseRoot = Join-Path $repoRoot 'packaging/windows/third-party-licenses'
$catalog = (Read-PreparationText -Path (Join-Path $catalogRoot 'manifest.v1.json') -AllowedRoot $catalogRoot) | ConvertFrom-Json
$libraries = [ordered]@{}
foreach ($id in $catalog.runtimeLibraries) { $libraries[$id] = @{ type = 'package' } }
$depsPath = Join-Path $root 'SteamWrapper.Manager.deps.json'
[IO.File]::WriteAllText($depsPath, (@{ libraries = $libraries } | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
& $stage -PublishDirectory $root
$index = Join-Path $root 'LICENSES/index.json'
$before = (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash
& $stage -PublishDirectory $root
& $stage -PublishDirectory $root -VerifyOnly
if ((Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash -cne $before) { throw 'Repeated staging changed the sealed legal index.' }
$bad = ($catalog | ConvertTo-Json -Depth 8) | ConvertFrom-Json
$bad.files[0].path = '../../.env'
Assert-Rejected { Assert-ThirdPartyCatalog -Catalog $bad -LicenseRoot $licenseRoot } '*unsafe, private or duplicate*'
$bad = ($catalog | ConvertTo-Json -Depth 8) | ConvertFrom-Json
$bad.files[0].sha256 = 'b' * 64
Assert-Rejected { Assert-ThirdPartyCatalog -Catalog $bad -LicenseRoot $licenseRoot } '*Canonical third-party legal file changed*'
$bad = ($catalog | ConvertTo-Json -Depth 8) | ConvertFrom-Json
$bad.files[0].bytes = 2MB + 1
Assert-Rejected { Assert-ThirdPartyCatalog -Catalog $bad -LicenseRoot $licenseRoot } '*oversized legal file*'
$bad = ($catalog | ConvertTo-Json -Depth 8) | ConvertFrom-Json
$bad.components[0].licenses = @()
Assert-Rejected { Assert-ThirdPartyCatalog -Catalog $bad -LicenseRoot $licenseRoot } '*missing required license*'
$first = Join-Path $root ('LICENSES/' + $catalog.files[0].path)
[IO.File]::AppendAllText($first, 'fixture mutation')
$mutated = (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash
Assert-Rejected { & $stage -PublishDirectory $root } '*Existing notice bytes differ*'
if ((Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash -cne $mutated) { throw 'Staging overwrote unknown existing legal bytes.' }
$libraries['unexpected-upstream/1.0.0'] = @{ type = 'package' }
[IO.File]::WriteAllText($depsPath, (@{ libraries = $libraries } | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Assert-Rejected { & $stage -PublishDirectory $root } '*Actual runtime dependency versions differ*'
Assert-Rejected { & $stage -PublishDirectory $repoRoot } '*Signing inputs must be local child files*'
$oversized = Join-Path $root 'oversized.txt'
[IO.File]::WriteAllText($oversized, 'bounded fixture')
Assert-Rejected { Read-PreparationText -Path $oversized -AllowedRoot $root -MaximumBytes 1 } '*bounded regular file*'
Assert-Rejected { Get-PreparationPublishFiles -Root $root -MaximumEntries 1 } '*entry-count limit*'
Assert-Rejected { Assert-PreparationDisjointRoots -First $root -Second (Join-Path $root 'nested') } '*must be disjoint*'
Write-Output "PASS: missing notices, version/hash drift, missing legal files, unsafe/private paths and oversized inputs rejected; repeat staging is unchanged. Evidence: $root"
