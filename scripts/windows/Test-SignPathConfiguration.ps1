[CmdletBinding()]
param([string]$SchemaPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../packaging/windows/signpath/SignPathConfiguration.ps1')
. (Join-Path $PSScriptRoot '../../packaging/windows/signpath/PreparationFiles.ps1')

function New-FixtureConfiguration {
    # These values test validation only; they are never provider identities or credentials.
    return [ordered]@{
        schemaVersion = 1; providerApproved = $true
        organizationId = 'd1a26ca5-44f7-4e0e-9c22-cf757c995c52'
        projectSlug = 'fixture-project'; signingPolicySlug = 'fixture-release'
        artifactConfigurationSlugs = [ordered]@{ payload = 'fixture-payload'; uninstaller = 'fixture-uninstaller'; setup = 'fixture-setup' }
        certificateSha256 = @('a' * 64)
        approvalReference = 'https://app.signpath.io/fixture-provider-review'
        humanApprover = 'fixture-human'; requireManualApproval = $true
        trustedBuildSystem = 'GitHub.com'; repository = 'https://github.com/YangYuS8/SteamWrapper'
    }
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    try { $null = & $Action }
    catch {
        if ($_.Exception.Message -notlike $Pattern) { throw "Unexpected rejection instead of $Pattern : $($_.Exception.Message)" }
        return
    }
    throw "Expected SignPath prerequisite rejection: $Pattern"
}

$unapproved = New-FixtureConfiguration
$unapproved.providerApproved = $false
Assert-Rejected { Assert-SignPathProductionConfiguration $unapproved -SubmissionTokenAvailable $true } '*actual Foundation approval*'
$valid = New-FixtureConfiguration
$null = Assert-SignPathProductionConfiguration $valid -SubmissionTokenAvailable $true
foreach ($entry in @(
    @{ key = 'organizationId'; value = ''; pattern = '*organization ID*' },
    @{ key = 'organizationId'; value = '00000000-0000-0000-0000-000000000000'; pattern = '*organization ID*' },
    @{ key = 'projectSlug'; value = ''; pattern = '*project or signing-policy*' },
    @{ key = 'signingPolicySlug'; value = "release`n"; pattern = '*project or signing-policy*' },
    @{ key = 'artifactConfigurationSlugs'; value = @{ payload = 'fixture-payload'; uninstaller = ''; setup = 'fixture-setup' }; pattern = '*all three provider-approved*' },
    @{ key = 'certificateSha256'; value = @(); pattern = '*explicit approved certificate*' },
    @{ key = 'certificateSha256'; value = @('0' * 64); pattern = '*explicit approved certificate*' },
    @{ key = 'certificateSha256'; value = @(('a' * 64), ('a' * 64)); pattern = '*explicit approved certificate*' },
    @{ key = 'approvalReference'; value = 'https://app.signpath.io.evil.example/review'; pattern = '*provider approval reference*' },
    @{ key = 'humanApprover'; value = ''; pattern = '*confirmed human approver*' },
    @{ key = 'requireManualApproval'; value = $false; pattern = '*manual approval*' },
    @{ key = 'trustedBuildSystem'; value = 'local'; pattern = '*GitHub-hosted*' },
    @{ key = 'repository'; value = 'https://github.com/somebody/SteamWrapper'; pattern = '*GitHub-hosted*' },
    @{ key = 'schemaVersion'; value = 2; pattern = '*schema version*' },
    @{ key = 'schemaVersion'; value = $true; pattern = '*schema version*' }
)) {
    $config = New-FixtureConfiguration
    $config[$entry.key] = $entry.value
    Assert-Rejected { Assert-SignPathProductionConfiguration $config -SubmissionTokenAvailable $true } $entry.pattern
}
Assert-Rejected { Assert-SignPathProductionConfiguration (New-FixtureConfiguration) } '*dedicated submitter token*'
$draft = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../packaging/windows/signpath/production-config.draft.json') -Raw | ConvertFrom-Json
Assert-Rejected { Assert-SignPathProductionConfiguration $draft -SubmissionTokenAvailable $true } '*actual Foundation approval*'
foreach ($stage in @('payload', 'uninstaller', 'setup')) {
    $path = Join-Path $PSScriptRoot "../../packaging/windows/signpath/$stage-v1.xml"
    $null = Assert-SignPathArtifactConfiguration -Path $path -Stage $stage -SchemaPath $SchemaPath
}
$fixtureRoot = Join-Path $PSScriptRoot ('../../target/winui/signpath-tests/' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../packaging/windows/signpath/payload-v1.xml'))
foreach ($mutation in @(
    @{ name = 'upstream'; content = $template.Replace('path="SteamWrapper.Manager.exe"', 'path="Microsoft.WindowsAppRuntime.dll"'); pattern = '*precise owned file set*' },
    @{ name = 'wildcard'; content = $template.Replace('path="SteamWrapper.Manager.dll"', 'path="*.dll"'); pattern = '*precise owned file set*' },
    @{ name = 'version'; content = $template.Replace('product-version="${version}"', 'product-version="*"'); pattern = '*coordinated SteamWrapper*' },
    @{ name = 'sha1'; content = $template.Replace('hash-algorithm="sha256"', 'hash-algorithm="sha1"'); pattern = '*SHA-256 Authenticode*' },
    @{ name = 'default'; content = $template.Replace('name="version" required="true"', 'name="version" required="true" default-value="1.0.0"'); pattern = '*without guessed default*' },
    @{ name = 'optional'; content = $template.Replace('path="SteamWrapper.Manager.exe"', 'path="SteamWrapper.Manager.exe" min-matches="0"'); pattern = '*one required file*' }
    @{ name = 'oversized'; content = $template + '<!--' + ('x' * 70000) + '-->'; pattern = '*bounded regular file*' }
)) {
    $path = Join-Path $fixtureRoot "$($mutation.name).xml"
    [IO.File]::WriteAllText($path, $mutation.content, [Text.UTF8Encoding]::new($false))
    Assert-Rejected { Assert-SignPathArtifactConfiguration -Path $path -Stage payload } $mutation.pattern
}
$null = Assert-SignPathRequestParameters -Stage payload -Version '0.2.3'
$null = Assert-SignPathRequestParameters -Stage setup -Version '0.2.3' -Tag 'v0.2.3-preview.1'
$null = Assert-SignPathRequestParameters -Stage uninstaller -Version '0.2.3' -UninstallerFile 'generated-uninstaller.exe'
Assert-Rejected { Assert-SignPathRequestParameters -Stage payload -Version '0.2.3*' } '*numeric Windows product version*'
Assert-Rejected { Assert-SignPathRequestParameters -Stage payload -Version '65536.0.0' } '*numeric Windows product version*'
Assert-Rejected { Assert-SignPathRequestParameters -Stage setup -Version '0.2.3' -Tag 'v0.2.2-preview.1' } '*safe reviewed tag*'
Assert-Rejected { Assert-SignPathRequestParameters -Stage uninstaller -Version '0.2.3' -UninstallerFile '../SteamWrapperRunner.exe' } '*exact generated EXE basename*'
Assert-Rejected { Assert-SignPathRequestParameters -Stage uninstaller -Version '0.2.3' -UninstallerFile '*.exe' } '*exact generated EXE basename*'
$inventory = Join-Path $PSScriptRoot '../../packaging/windows/signpath/New-SignPathInventory.ps1'
Assert-Rejected { & $inventory -PublishDirectory $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'nested-output') } '*must be disjoint*'
if (Test-Path -LiteralPath (Join-Path $fixtureRoot 'nested-output')) { throw 'Rejected inventory input/output overlap created files.' }
$oversized = Join-Path $fixtureRoot 'oversized-json.txt'
[IO.File]::WriteAllText($oversized, 'bounded read fixture')
Assert-Rejected { Read-PreparationText -Path $oversized -AllowedRoot $fixtureRoot -MaximumBytes 1 } '*bounded regular file*'
Assert-Rejected { Get-PreparationPublishFiles -Root $fixtureRoot -MaximumEntries 1 } '*entry-count limit*'
$private = Join-Path $fixtureRoot '.env'
[IO.File]::WriteAllText($private, 'disposable fixture, contains no credentials')
Assert-Rejected { Get-PreparationPublishFiles -Root $fixtureRoot } '*private file name*'
Write-Output 'PASS: SignPath prerequisites reject unapproved, missing, malformed and broadened inputs; no request was submitted.'
Write-Output "PASS: all three exact signing templates validated; official schema validation=$([bool]$SchemaPath). Evidence: $fixtureRoot"
