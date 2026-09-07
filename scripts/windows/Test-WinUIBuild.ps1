# A real XAML build proves more than SDK version output. This is not the new Manager.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This task requires Windows.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$output = Join-Path $repoRoot ('target/toolchain-smoke/' + [Guid]::NewGuid().ToString('N'))

& dotnet new winui --name SteamWrapper.ToolchainSmoke --output $output --no-update-check `
    --dotnet-version net10.0 --target-platform-min-version 10.0.26100.0 `
    --UseLatestWindowsAppSDK false --windowsAppSdkVersion 2.4.0 `
    --windowsSdkBuildToolsVersion 10.0.26100.7705 --windowsSdkBuildToolsWinAppVersion 0.3.1
if ($LASTEXITCODE -ne 0) { throw 'WinUI template generation failed. Run mise run windows:templates first.' }
$project = Join-Path $output 'SteamWrapper.ToolchainSmoke.csproj'
if (-not (Test-Path -LiteralPath $project)) { throw "WinUI template did not create the expected project: $project" }

# Template 0.0.6-alpha unconditionally runs package-update post-actions, ignoring
# its version flags. Normalize the generated smoke project before the real build.
[xml]$projectXml = Get-Content -LiteralPath $project -Raw
$packageVersions = @{
    'Microsoft.WindowsAppSDK' = '2.4.0'
    'Microsoft.Windows.SDK.BuildTools' = '10.0.26100.7705'
    'Microsoft.Windows.SDK.BuildTools.WinApp' = '0.3.1'
}
foreach ($package in $packageVersions.Keys) {
    $reference = $projectXml.SelectSingleNode("//PackageReference[@Include='$package']")
    if (-not $reference) { throw "The pinned template is missing package reference $package." }
    $reference.SetAttribute('Version', $packageVersions[$package])
}
$projectXml.SelectSingleNode('//TargetPlatformMinVersion').InnerText = '10.0.26100.0'
$projectXml.Save($project)

& dotnet publish $project --configuration Release --runtime win-x64 --self-contained true `
    -p:Platform=x64 -p:WindowsPackageType=None -p:WindowsAppSDKSelfContained=true `
    -p:PublishTrimmed=false `
    -p:GenerateAppxPackageOnBuild=false -p:AppxPackageSigningEnabled=false `
    --output (Join-Path $output 'publish')
if ($LASTEXITCODE -ne 0) { throw "WinUI publish failed. Generated project retained at $output" }
$executable = Join-Path $output 'publish/SteamWrapper.ToolchainSmoke.exe'
if (-not (Test-Path -LiteralPath $executable) -or (Get-Item -LiteralPath $executable).Length -eq 0) {
    throw 'WinUI publish did not produce a non-empty executable.'
}
Write-Output "WinUI self-contained build passed: $executable"
