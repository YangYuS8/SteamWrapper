[CmdletBinding()]
param([switch]$HelpersOnly,[ValidateSet('Prepare','ReadEvidence')][string]$Action='Prepare',
    [string]$BaselineTag='v0.2.5-preview.1',[string]$Tag,[ValidateSet('github','cnb')][string]$Source='github',
    [string]$BaselineInstallerPath,[string]$PreparedRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function Assert-ProjectUpdateAcceptance([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Test-ProjectUpdateElementEnabled($Element){
    return $null -ne $Element -and $Element.Current.IsEnabled
}
function Test-ProjectUpdateDownloadReady($State,[string[]]$ReadyNames,[string[]]$DownloadNames,$Observation){
    if(-not $State.enabled){$Observation.busyObserved=$true;return $false}
    if($State.status -cin $ReadyNames){return $true}
    if($Observation.busyObserved -and $State.action -cin $DownloadNames){
        throw ('The actual Manager download ended without a verified installer: '+$State.status)
    }
    return $false
}
function Get-ProjectUpdateNumericVersion([string]$Tag){
    $number='(?:0|[1-9][0-9]*)';$identifier='(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    Assert-ProjectUpdateAcceptance ($Tag.Length -le 80 -and $Tag -cmatch ('^v(?<base>'+$number+'\.'+$number+'\.'+$number+')(?:-'+$identifier+'(?:\.'+$identifier+')*)?$')) 'Expected a strict public update tag.'
    return [Version]$Matches['base']
}
function Assert-ProjectUpdateAcceptanceManifest($Manifest){
    Assert-ProjectUpdateAcceptance ($Manifest.schemaVersion -eq 1 -and $Manifest.scenario -ceq 'PublicProjectUpdate' -and
        $Manifest.runId -cmatch '^[a-f0-9]{32}$' -and $Manifest.sandboxOnly -is [bool] -and $Manifest.sandboxOnly -and
        $Manifest.networkingEnabled -is [bool] -and $Manifest.networkingEnabled -and $Manifest.localCandidate -is [bool] -and -not $Manifest.localCandidate -and
        $Manifest.source -cin @('github','cnb')) 'Expected a public-network Sandbox update manifest, never a local candidate.'
    $baseline=Get-ProjectUpdateNumericVersion $Manifest.baseline.tag;$target=Get-ProjectUpdateNumericVersion $Manifest.target.tag
    Assert-ProjectUpdateAcceptance ($target -gt $baseline) 'Public update acceptance requires a genuinely newer numeric version.'
    $channel=if($Manifest.baseline.tag.Contains('-')){'preview'}else{'stable'}
    Assert-ProjectUpdateAcceptance ($Manifest.channel -ceq $channel -and ($channel -cne 'stable' -or -not $Manifest.target.tag.Contains('-'))) 'The installed release must select its real automatic feed channel.'
    foreach($asset in @($Manifest.baseline,$Manifest.target)){
        Assert-ProjectUpdateAcceptance ($asset.fileName -ceq ('SteamWrapper-'+$asset.tag+'-win-x64-setup.exe') -and
            $asset.sha256 -cmatch '^[a-f0-9]{64}$' -and ($asset.bytes -is [int] -or $asset.bytes -is [long]) -and $asset.bytes -gt 0 -and $asset.bytes -le 512MB -and $asset.commit -cmatch '^[a-f0-9]{40}$') 'Unexpected public installer identity.'
    }
    Assert-ProjectUpdateAcceptance (($Manifest.feed.sequence -is [int] -or $Manifest.feed.sequence -is [long]) -and $Manifest.feed.sequence -gt 0 -and
        $Manifest.feed.payloadSha256 -cmatch '^[a-f0-9]{64}$' -and $Manifest.feed.envelopeSha256 -cmatch '^[a-f0-9]{64}$' -and
        $Manifest.feed.mirrorVerified -is [bool] -and ($Manifest.source -cne 'cnb' -or $Manifest.feed.mirrorVerified)) 'Public CNB acceptance requires a verified signed mirror, and every run requires pinned signed feed identity.'
}
function Assert-ProjectUpdateUiAction($State,[string[]]$Names,[int]$RootProcessId,[int]$ManagerProcessId){
    Assert-ProjectUpdateAcceptance ($ManagerProcessId -gt 0 -and $RootProcessId -eq $ManagerProcessId -and ($State.processId -eq 0 -or $State.processId -eq $ManagerProcessId) -and
        $State.automationId -ceq 'PrimaryButton' -and $State.name -cin $Names -and $State.enabled -is [bool] -and $State.enabled -and $State.controlType -ceq 'Button') 'The requested public-update primary action is not the expected owned Manager dialog.'
}
function Assert-ProjectUpdateAcceptedFeed($Manifest,$TrustState){
    $accepted=$TrustState.channels.($Manifest.channel)
    Assert-ProjectUpdateAcceptance ($TrustState.schemaVersion -eq 1 -and $accepted.sequence -eq $Manifest.feed.sequence -and $accepted.digest -ceq $Manifest.feed.payloadSha256) 'The actual client did not accept the pinned signed public payload. A feed renewal race requires a fresh preparation; do not weaken this check.'
}
function Assert-ProjectUpdatePreservedTrust([string]$Path,[string]$ExpectedSha256,$Manifest){
    $file=Get-Item -LiteralPath $Path -Force
    Assert-ProjectUpdateAcceptance ($ExpectedSha256 -cmatch '^[a-f0-9]{64}$' -and $file -is [IO.FileInfo] -and
        -not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $file.Length -gt 0 -and $file.Length -le 2MB -and
        (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() -ceq $ExpectedSha256) 'Installation or uninstall changed the exact previously accepted update trust state.'
    Assert-ProjectUpdateAcceptedFeed $Manifest (Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json)
}
function New-ProjectUpdateSandboxConfiguration([string]$InputPath,[string]$OutputPath){
    $inputXml=[Security.SecurityElement]::Escape($InputPath);$outputXml=[Security.SecurityElement]::Escape($OutputPath)
    return @"
<Configuration><vGPU>Disable</vGPU><Networking>Enable</Networking><ClipboardRedirection>Disable</ClipboardRedirection><AudioInput>Disable</AudioInput><VideoInput>Disable</VideoInput><PrinterRedirection>Disable</PrinterRedirection><MemoryInMB>8192</MemoryInMB><MappedFolders><MappedFolder><HostFolder>$inputXml</HostFolder><SandboxFolder>C:\AcceptanceInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder><MappedFolder><HostFolder>$outputXml</HostFolder><SandboxFolder>C:\AcceptanceOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder></MappedFolders></Configuration>
"@
}
function Get-ProjectUpdateCleanHelperDefinitions([string]$Path){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    Assert-ProjectUpdateAcceptance (@($errors).Count -eq 0) 'Pinned clean guest helpers cannot be parsed.'
    $names=@('Assert-Acceptance','Quote-AcceptanceArgument','Wait-Acceptance','Test-AcceptanceInboxRuntimePackage','Get-AcceptancePayloadRuntimeModules','Assert-AcceptanceManualAppIdAction','Retain-AcceptanceProcessHandle','Get-AcceptanceExitDiagnostic','Read-AcceptanceBoundedDiagnosticFile','Write-AcceptanceEvidence','Record-Acceptance','Get-AcceptanceProcessSecurity','Read-AcceptanceAsset','Invoke-AcceptanceInstaller','Read-AcceptanceInstallation','Get-AcceptanceDataHashes','Assert-AcceptanceDataHashes','Get-AcceptanceShortcuts','Assert-AcceptanceShortcuts','Find-AcceptanceElement','Wait-AcceptanceElement','Invoke-AcceptanceElement','Set-AcceptanceValue','Capture-AcceptanceWindow','Start-AcceptanceManager','Close-AcceptanceManager','Invoke-AcceptanceRunner')
    $definitions=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -cin $names})
    Assert-ProjectUpdateAcceptance ($definitions.Count -eq $names.Count -and @($definitions.Name|Sort-Object -Unique).Count -eq $names.Count) 'Missing transitive installed-client acceptance helper.'
    return [scriptblock]::Create(($definitions|ForEach-Object {$_.Extent.Text}) -join "`r`n")
}
function Read-ProjectUpdatePublicBytes([Uri]$Uri,[int]$Limit=524288){
    $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false;$handler.UseCookies=$false;$handler.UseDefaultCredentials=$false;$handler.Credentials=$null;$handler.AutomaticDecompression=[Net.DecompressionMethods]::None
    $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(30)
    try{
        for($hop=0;$hop -le 5;$hop++){
            Assert-ProjectUpdateAcceptance ($Uri.Scheme -ceq 'https' -and $Uri.Port -eq 443 -and $Uri.UserInfo -ceq '' -and $Uri.Fragment -ceq '' -and $Uri.Host -cin @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com','cnb.cool','api.cnb.cool','asset.cnb.cool')) 'Public update preparation refused an unchecked HTTPS host.'
            $response=$client.GetAsync($Uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try{
                if([int]$response.StatusCode -in @(301,302,303,307,308)){
                    Assert-ProjectUpdateAcceptance ($hop -lt 5 -and $null -ne $response.Headers.Location) 'Public update redirect exceeds its bound.'
                    $Uri=if($response.Headers.Location.IsAbsoluteUri){$response.Headers.Location}else{[Uri]::new($Uri,$response.Headers.Location)};continue
                }
                $null=$response.EnsureSuccessStatusCode();Assert-ProjectUpdateAcceptance ($response.Content.Headers.ContentEncoding.Count -eq 0 -and ($null -eq $response.Content.Headers.ContentLength -or $response.Content.Headers.ContentLength -le $Limit)) 'Public update response length or encoding is outside policy.'
                $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult();$output=[IO.MemoryStream]::new()
                try{$buffer=[byte[]]::new(16384);while(($count=$input.Read($buffer,0,$buffer.Length)) -gt 0){Assert-ProjectUpdateAcceptance ($output.Length+$count -le $Limit) 'Public update stream exceeded its limit.';$output.Write($buffer,0,$count)};return ,$output.ToArray()}finally{$input.Dispose();$output.Dispose()}
            }finally{$response.Dispose()}
        }
    }catch{throw 'Anonymous public update preparation failed; no credentials or redirected storage URL is logged.'}finally{$client.Dispose()}
}
if($HelpersOnly){return}
if(-not $IsWindows){throw 'Public update client acceptance requires a Windows host.'}
. (Join-Path $PSScriptRoot 'CleanWindowsAcceptance.ps1')
. (Join-Path $PSScriptRoot '../releases/ProjectUpdates.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$prefix=Join-Path $repo 'target/winui/public-update-'
if($Action -ceq 'ReadEvidence'){
    $root=Assert-WinUIReleasePath $PreparedRoot (Join-Path $repo 'target/winui')
    Assert-ProjectUpdateAcceptance ($root.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and $root.Substring($prefix.Length) -cmatch '^[a-f0-9]{32}$') 'Expected the dedicated public-update run directory.'
    $manifest=Get-Content -LiteralPath (Join-Path $root 'input/update-input.json') -Raw|ConvertFrom-Json;Assert-ProjectUpdateAcceptanceManifest $manifest
    $evidence=Get-Content -LiteralPath (Join-Path $root 'evidence/evidence.json') -Raw|ConvertFrom-Json
    Assert-ProjectUpdateAcceptance ($evidence.runId -ceq $manifest.runId -and $evidence.result -ceq 'passed' -and $evidence.signedPublicNetwork -and $evidence.actualUiInstallation -and $evidence.numericUpgradeTested -and $evidence.updateTrustStatePreserved -eq $true) 'No matching complete public signed UI-to-Setup upgrade acceptance pass with preserved update trust history.'
    $evidence|Select-Object result,runId,source,baselineTag,targetTag,steps;return
}
if($PreparedRoot -or -not $Tag){throw 'Prepare requires an explicit published target Tag and creates a new run directory.'}
$null=Get-ProjectUpdateNumericVersion $Tag;$null=Get-ProjectUpdateNumericVersion $BaselineTag
Assert-ProjectUpdateAcceptance ((Get-ProjectUpdateNumericVersion $Tag) -gt (Get-ProjectUpdateNumericVersion $BaselineTag)) 'A same-numeric public release cannot exercise genuine application upgrade.'
function Invoke-ProjectUpdateGh([string[]]$Arguments){$raw=& gh @Arguments 2>&1|Out-String;if($LASTEXITCODE -ne 0){throw ('Read-only public GitHub preparation failed: '+$Arguments[0])};return $raw.Trim()}
function Get-ProjectUpdatePublicRelease([string]$ReleaseTag,[string]$Directory,[switch]$WithInstaller){
    $state=Invoke-ProjectUpdateGh @('release','view',$ReleaseTag,'--repo','YangYuS8/SteamWrapper','--json','tagName,isDraft,isPrerelease,assets')|ConvertFrom-Json
    Assert-CleanWindowsPublicRelease $state $ReleaseTag;[IO.Directory]::CreateDirectory($Directory)|Out-Null
    $apiPath=Join-Path $Directory 'public-api.json';$state|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $apiPath -Encoding utf8NoBOM
    $assets=@($state.assets|Where-Object {$_.name -ceq 'release.json' -or ($WithInstaller -and $_.name -ceq ('SteamWrapper-'+$ReleaseTag+'-win-x64-setup.exe'))})
    foreach($asset in $assets){
        Assert-ProjectUpdateAcceptance ($asset.digest -cmatch '^sha256:[a-f0-9]{64}$' -and $asset.size -gt 0 -and $asset.size -le $(if($asset.name -ceq 'release.json'){2MB}else{512MB})) 'Public API lacks a bounded exact SHA-256 asset identity.'
        $path=Join-Path $Directory $asset.name
        if($WithInstaller -and $BaselineInstallerPath -and $asset.name -cne 'release.json'){$cached=Assert-WinUIReleasePath $BaselineInstallerPath ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($BaselineInstallerPath)));Copy-Item -LiteralPath $cached -Destination $path}else{$null=Invoke-ProjectUpdateGh @('release','download',$ReleaseTag,'--repo','YangYuS8/SteamWrapper','--pattern',$asset.name,'--dir',$Directory)}
        Assert-ProjectUpdateAcceptance ((Get-Item -LiteralPath $path).Length -eq $asset.size -and ('sha256:'+(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()) -ceq $asset.digest) 'Downloaded public asset differs from API identity.'
    }
    $metadata=Get-Content -LiteralPath (Join-Path $Directory 'release.json') -Raw|ConvertFrom-Json
    $commit=Invoke-ProjectUpdateGh @('api',('repos/YangYuS8/SteamWrapper/commits/'+$ReleaseTag),'--jq','.sha')
    $setup=@($state.assets|Where-Object name -CEQ ('SteamWrapper-'+$ReleaseTag+'-win-x64-setup.exe'))[0]
    Assert-CleanWindowsPublicInstaller $metadata $setup $ReleaseTag $commit
    return $metadata
}
$runId=[guid]::NewGuid().ToString('N');$root=$prefix+$runId;$inputRoot=Join-Path $root 'input';$outputRoot=Join-Path $root 'evidence'
[IO.Directory]::CreateDirectory($inputRoot)|Out-Null;[IO.Directory]::CreateDirectory($outputRoot)|Out-Null
$baseline=Get-ProjectUpdatePublicRelease $BaselineTag (Join-Path $root 'packages/baseline') -WithInstaller
$target=Get-ProjectUpdatePublicRelease $Tag (Join-Path $root 'packages/target')
$channel=if($BaselineTag.Contains('-')){'preview'}else{'stable'}
$base=if($Source -ceq 'github'){'https://github.com/YangYuS8/SteamWrapper/releases/download/'}else{'https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/'}
$envelopePath=Join-Path $inputRoot 'signed-public-feed.json';[IO.File]::WriteAllBytes($envelopePath,(Read-ProjectUpdatePublicBytes ([Uri]($base+'update-'+$channel+'/SteamWrapper-update.json'))))
$payload=Read-ProjectUpdateEnvelope -Path $envelopePath -TrustPath (Join-Path $repo 'packaging/windows/update-trust.json')
Assert-ProjectUpdateAcceptance ($payload.channel -ceq $channel -and $payload.release.tag -ceq $Tag -and $payload.release.commit -ceq $target.commit -and $payload.release.artifact.sha256 -ceq $target.installerAsset.sha256 -and $payload.release.artifact.bytes -eq $target.installerAsset.bytes) 'The real project-signed feed does not authorize the exact public target installer.'
$mirror=$false
if($Source -ceq 'cnb'){
    Assert-ProjectUpdateAcceptance ($null -ne $payload.release.artifact.mirrorUrl) 'The signed feed does not advertise CNB.'
    $mirrorBytes=Read-ProjectUpdatePublicBytes ([Uri]$payload.release.artifact.mirrorUrl) ([int]$payload.release.artifact.bytes)
    Assert-ProjectUpdateAcceptance ($mirrorBytes.Length -eq $payload.release.artifact.bytes -and [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($mirrorBytes)).ToLowerInvariant() -ceq $payload.release.artifact.sha256) 'Anonymous CNB mirror bytes do not match the actual project-signed target.'
    $mirrorBytes=$null;$mirror=$true
}
$wrapper=Get-Content -LiteralPath $envelopePath -Raw|ConvertFrom-Json;$payloadBytes=[Convert]::FromBase64String($wrapper.payload)
$manifest=[ordered]@{schemaVersion=1;scenario='PublicProjectUpdate';runId=$runId;sandboxOnly=$true;networkingEnabled=$true;localCandidate=$false;source=$Source;channel=$channel;hostComputerName=$env:COMPUTERNAME;hostBuild=(Get-CimInstance Win32_OperatingSystem).BuildNumber
    baseline=@{tag=$BaselineTag;fileName=$baseline.installerAsset.fileName;sha256=$baseline.installerAsset.sha256;bytes=$baseline.installerAsset.bytes;commit=$baseline.commit}
    target=@{tag=$Tag;fileName=$target.installerAsset.fileName;sha256=$target.installerAsset.sha256;bytes=$target.installerAsset.bytes;commit=$target.commit}
    feed=@{sequence=$payload.sequence;payloadSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payloadBytes)).ToLowerInvariant();envelopeSha256=(Get-FileHash -LiteralPath $envelopePath).Hash.ToLowerInvariant();mirrorVerified=$mirror}}
foreach($file in @('ProjectUpdateAcceptance.ps1','Invoke-ProjectUpdateGuestAcceptance.ps1','Invoke-CleanWindowsGuestAcceptance.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $inputRoot;$manifest[$file.Replace('.ps1','')+'Sha256']=(Get-FileHash -LiteralPath (Join-Path $inputRoot $file)).Hash.ToLowerInvariant()}
Copy-Item -LiteralPath (Join-Path (Join-Path $root 'packages/baseline') $baseline.installerAsset.fileName) -Destination $inputRoot
foreach($pair in @(@('baseline',$baseline),@('target',$target))){Copy-Item -LiteralPath (Join-Path (Join-Path $root ('packages/'+$pair[0])) 'release.json') -Destination (Join-Path $inputRoot ($pair[0]+'-release.json'));$manifest[$pair[0]+'MetadataSha256']=(Get-FileHash -LiteralPath (Join-Path $inputRoot ($pair[0]+'-release.json'))).Hash.ToLowerInvariant()}
$texts=[ordered]@{}
foreach($key in @('UpdateDownload','UpdateReady','UpdateInstall','UpdateInstallTitle','RunnerUpdate')){$values=@();foreach($language in @('Strings.resx','Strings.zh-CN.resx')){$xml=[xml][IO.File]::ReadAllText((Join-Path $repo ('apps/manager-winui/SteamWrapper.Application/Localization/'+$language)));$values+=[string]$xml.SelectSingleNode('/root/data[@name="'+$key+'"]/value').InnerText};$texts[$key]=$values}
$manifest.uiTexts=$texts
$manifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $inputRoot 'update-input.json') -Encoding utf8NoBOM
Assert-ProjectUpdateAcceptanceManifest ([pscustomobject]$manifest)
New-ProjectUpdateSandboxConfiguration $inputRoot $outputRoot|Set-Content -LiteralPath (Join-Path $root 'acceptance.wsb') -Encoding utf8NoBOM
Write-Output "Prepared signed public-network UI update acceptance: $root"
Write-Output 'Start/connect this sealed AfterLogin .wsb via official wsb CLI, then exec inbox PowerShell -MTA -File C:\AcceptanceInput\Invoke-ProjectUpdateGuestAcceptance.ps1 under ExistingLogin. Never execute this product gate on the host.'
