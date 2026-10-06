[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProjectUpdateAcceptance.ps1') -HelpersOnly
$legacy=[pscustomobject]@{baseline=[pscustomobject]@{tag='v0.2.7'};target=[pscustomobject]@{tag='v0.2.8'}}
if ((Get-ProjectUpdateMetadataInputName $legacy baseline) -cne 'baseline-release.json') { throw 'Historical acceptance metadata filename changed.' }
$compact=[pscustomobject]@{
    baseline=[pscustomobject]@{tag='v0.2.8';commit=('a'*40);fileName='SteamWrapper-v0.2.8-win-x64-setup.exe';sha256=('b'*64);bytes=100}
    target=[pscustomobject]@{tag='v0.2.9';commit=('c'*40);fileName='SteamWrapper-v0.2.9-win-x64-setup.exe';sha256=('d'*64);bytes=101}
    baselinePublicAssetLayout=3;targetPublicAssetLayout=3
    baselineMetadataSha256=('e'*64);targetMetadataSha256=('f'*64)
    baselinePublicApiSha256=('a'*64);targetPublicApiSha256=('b'*64)
}
foreach ($role in @('baseline','target')) {
    if ((Get-ProjectUpdateMetadataInputName $compact $role) -cne "$role-public-installer.json") { throw 'Compact metadata must use an explicit public descriptor filename.' }
    $asset=$compact.$role
    $descriptor=[pscustomobject]@{schemaVersion=1;kind='PublicApiInstaller';publicAssetLayout=3;tag=$asset.tag;version=($asset.tag.Substring(1));commit=$asset.commit;releaseChannel='stable';verificationKind=$(if($role -ceq 'baseline'){'public-api-baseline'}else{'project-signature'});baselineScope=($role -ceq 'baseline');signatureVerified=($role -ceq 'target');installerAsset=[pscustomobject]@{fileName=$asset.fileName;sha256=$asset.sha256;bytes=$asset.bytes}}
    Assert-ProjectUpdateSealedMetadata $compact $role $descriptor
    $descriptor.signatureVerified=-not $descriptor.signatureVerified
    $rejected=$false
    try { Assert-ProjectUpdateSealedMetadata $compact $role $descriptor } catch { $rejected=$true }
    if(-not $rejected){throw 'Compact descriptor accepted a signature scope mismatch.'}
}
$seals=@(Get-ProjectUpdateMetadataInputSeals $compact)
if($seals.Count -ne 4 -or @($seals | Where-Object name -CEQ 'target-public-api.json').Count -ne 1 -or @($seals | Where-Object name -CEQ 'baseline-public-installer.json').Count -ne 1){throw 'Compact acceptance does not seal both explicit descriptors and API receipts.'}
$bundle=[pscustomobject]@{schemaVersion=1;contractVersion=2;version='0.2.9';sha256=('1'*64)}
$runner=[pscustomobject]@{path='Runner/SteamWrapperRunner.exe';bytes=101;sha256=('1'*64)}
Assert-ProjectUpdateBundledRunner $compact $bundle $runner 101 ('1'*64)
$runner.sha256=('2'*64);$rejected=$false
try { Assert-ProjectUpdateBundledRunner $compact $bundle $runner 101 ('1'*64) } catch { $rejected=$true }
if(-not $rejected){throw 'Activated signed-Setup Runner inventory differs without rejection.'}
$deployment=[pscustomobject]@{schemaVersion=1;appId='SteamWrapper';tag='v0.2.9';version='0.2.9';profileContract=2;runnerContract=2;deploymentProtocol=1}
$installation=[pscustomobject]@{current=[pscustomobject]@{tag='v0.2.9';manifestSha256=('3'*64)}}
Assert-ProjectUpdateActivatedDeployment $compact $deployment $installation ('3'*64)
$rejected=$false
try { Assert-ProjectUpdateActivatedDeployment $compact $deployment $installation ('4'*64) } catch { $rejected=$true }
if(-not $rejected){throw 'Changed activated inventory accepted a different installation journal hash.'}
Write-Output 'Compact public-update acceptance fixtures passed: explicit baseline API scope, signed current target, descriptor/API seals and activated Runner byte binding; no product or Sandbox execution.'
