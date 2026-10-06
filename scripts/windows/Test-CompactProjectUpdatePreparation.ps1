[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProjectUpdateAcceptance.ps1') -HelpersOnly
. (Join-Path $PSScriptRoot '../releases/PublicReleaseDownload.ps1')
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'ProjectUpdateAcceptance.ps1'),[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'Project update preparation parser failed.'}
$function=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq 'Get-ProjectUpdatePublicRelease'})
if($function.Count -ne 1){throw 'Missing public preparation helper.'}
. ([scriptblock]::Create($function[0].Extent.Text))
$root=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../target/winui'))) ('compact-public-update-preparation-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$tag='v0.2.8';$commit='a'*40;$setupName="SteamWrapper-$tag-win-x64-setup.exe"
$setup=Join-Path $root $setupName;[IO.File]::WriteAllText($setup,'Non-executable public acceptance Setup byte fixture.')
$setupHash=(Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant();$setupBytes=(Get-Item -LiteralPath $setup).Length
$state=[pscustomobject]@{tag_name=$tag;target_commitish=$commit;draft=$false;prerelease=$false;assets=@(
    [pscustomobject]@{name=$setupName;size=$setupBytes;digest='sha256:'+$setupHash;state='uploaded'},
    [pscustomobject]@{name="SteamWrapper-$tag-win-x64.zip";size=100;digest='sha256:'+('b'*64);state='uploaded'},
    [pscustomobject]@{name='SHA256SUMS';size=100;digest='sha256:'+('c'*64);state='uploaded'})}
$requests=New-Object 'Collections.Generic.List[object]'
function Invoke-ProjectUpdateGh([string[]]$Arguments){
    $requests.Add($Arguments)
    if($Arguments[0] -ceq 'api' -and $Arguments[1] -like '*/commits/*'){return $commit}
    if($Arguments[0] -ceq 'api' -and $Arguments[1] -like '*/releases/tags/*'){return $state|ConvertTo-Json -Depth 8 -Compress}
    if($Arguments[0] -ceq 'release' -and $Arguments[1] -ceq 'download'){
        if($Arguments[[Array]::IndexOf($Arguments,'--pattern')+1] -cne $setupName){throw 'Compact acceptance tried to download internal metadata.'}
        Copy-Item -LiteralPath $setup -Destination (Join-Path $Arguments[[Array]::IndexOf($Arguments,'--dir')+1] $setupName);return ''
    }
    throw 'Unexpected fixture preparation command.'
}
$BaselineInstallerPath=$null
$baseline=Get-ProjectUpdatePublicRelease $tag (Join-Path $root 'baseline') -WithInstaller -BaselineOnly -TrustPath (Join-Path $PSScriptRoot '../../packaging/windows/update-trust.json')
if($baseline.verificationKind -cne 'public-api-baseline' -or $baseline.signatureVerified -or -not(Test-Path -LiteralPath (Join-Path $root 'baseline/public-installer.json')) -or (Test-Path -LiteralPath (Join-Path $root 'baseline/release.json'))){throw 'Baseline preparation fabricated internal metadata or signed evidence.'}
$key=[Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
try{
    $trust=[pscustomobject]@{schemaVersion=1;keys=@([pscustomobject]@{keyId='fixture';subjectPublicKeyInfo=[Convert]::ToBase64String($key.ExportSubjectPublicKeyInfo())});githubRepository='YangYuS8/SteamWrapper';cnbRepository='Nesoriel/SteamWrapper'}
    $trustPath=Join-Path $root 'trust.json';$trust|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $trustPath -Encoding utf8NoBOM
    $metadata=[pscustomobject]@{schemaVersion=3;tag=$tag;version='0.2.8';commit=$commit;minimumWindowsVersion='10.0.26100.0';releaseChannel='stable';installerAsset=[pscustomobject]@{fileName=$setupName;bytes=$setupBytes;sha256=$setupHash}}
    $payload=New-ProjectUpdatePayload -ReleaseMetadata $metadata -Trust $trust
    $envelope=Join-Path $root 'signed-feed.json';Write-ProjectUpdateEnvelope -Payload $payload -Key $key -KeyId fixture -Path $envelope
    $target=Get-ProjectUpdatePublicRelease $tag (Join-Path $root 'target') -EnvelopePath $envelope -TrustPath $trustPath
    if($target.verificationKind -cne 'project-signature' -or -not $target.signatureVerified -or $target.baselineScope -or (Test-Path -LiteralPath (Join-Path $root ('target/'+$setupName)))){throw 'Target preparation lost current signature or staged the target installer instead of requiring the real UI download.'}
    $writesBefore=@($requests|Where-Object {$_[0] -ceq 'release'}).Count
    $rejected=$false
    try{$null=Get-ProjectUpdatePublicRelease $tag (Join-Path $root 'missing-signature') -EnvelopePath (Join-Path $root 'missing.json') -TrustPath $trustPath}catch{$rejected=$true}
    if(-not $rejected -or (Test-Path -LiteralPath (Join-Path $root 'missing-signature'))){throw 'Missing current signature fell back to baseline API preparation.'}
    if(@($requests|Where-Object {$_[0] -ceq 'release'}).Count -ne $writesBefore){throw 'Rejected target signature caused a target installer download.'}
}finally{$key.Dispose()}
Write-Output 'Compact public-update host preparation passed: explicit API baseline, signed current target, separate descriptor/API files and no staged target; isolated bytes and mocked reads only.'
