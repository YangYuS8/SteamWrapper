[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PortableAcceptance.ps1')
$cases=0
function Assert-PortableTest([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message}; $script:cases++ }
function Reject-PortableTest([scriptblock]$Operation,[string]$Message) { $rejected=$false;try{$null=& $Operation}catch{$rejected=$true};Assert-PortableTest $rejected $Message }
$metadata=[pscustomobject]@{
    schemaVersion=1;tag='v0.2.6';version='0.2.6';commit=('b'*40);platform='win-x64';minimumWindowsVersion='10.0.26100.0'
    releaseChannel='stable';tagPrerelease=$false;githubPrerelease=$false;signed=$false;installer=$false;portable=$true
    archive=[pscustomobject]@{fileName='SteamWrapper-v0.2.6-win-x64.zip';bytes=1;sha256=('a'*64)}
    runner=[pscustomobject]@{version='0.2.6';contractVersion=2;sha256=('a'*64)}
    files=@([pscustomobject]@{path='SteamWrapper.Manager.exe';bytes=1;sha256=('a'*64)})
}
Assert-PortableAcceptanceMetadata $metadata
$cases++
foreach($path in @('../escape.dll','Assets/../../escape.dll','/absolute.dll','C:/file.dll','x\\file.dll','x//file.dll','x/./file.dll','file.dll:stream','profiles.toml','logs/log.txt','cache/a','installation.json','x/CON.txt','x/file.','x/a?.dll','x/a*.dll','x/a|.dll','x/a".dll','x/a>.dll','x/a<.dll')) {
    Reject-PortableTest { Assert-PortableAcceptanceRecord ([pscustomobject]@{path=$path;bytes=1;sha256=('a'*64)}) } ('Unsafe portable record accepted: '+$path)
}
$metadata.files=@($metadata.files[0],$metadata.files[0])
Reject-PortableTest { Assert-PortableAcceptanceMetadata $metadata } 'Duplicate portable inventory accepted.'
$metadata.files=@($metadata.files[0]);$metadata.installer=$true
Reject-PortableTest { Assert-PortableAcceptanceMetadata $metadata } 'Installer descriptor accepted as portable.'
$metadata.installer=$false;$metadata.version='0.2.5'
Reject-PortableTest { Assert-PortableAcceptanceMetadata $metadata } 'Wrong numeric portable version accepted.'
$metadata.version='0.2.6';$metadata.releaseChannel='preview'
Reject-PortableTest { Assert-PortableAcceptanceMetadata $metadata } 'Portable tag/channel mismatch accepted.'
$metadata.releaseChannel='stable'
$root=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../target/winui'))) ('portable-guards-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$archivePath=Join-Path $root $metadata.archive.fileName
$archive=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
try {
    $entry=$archive.CreateEntry('SteamWrapper-v0.2.6-win-x64/SteamWrapper.Manager.exe')
    $stream=$entry.Open();try{$stream.WriteByte(65)}finally{$stream.Dispose()}
} finally {$archive.Dispose()}
$metadata.archive.bytes=(Get-Item -LiteralPath $archivePath).Length
$metadata.archive.sha256=(Get-FileHash -LiteralPath $archivePath).Hash.ToLowerInvariant()
$sha=[Security.Cryptography.SHA256]::Create();try{$metadata.files[0].sha256=(-join($sha.ComputeHash([byte[]]@(65))|ForEach-Object{$_.ToString('x2')}))}finally{$sha.Dispose()}
$destination=Join-Path $root 'extract'
Expand-PortableAcceptanceArchive $archivePath $metadata $destination
Assert-PortableTest ([IO.File]::ReadAllText((Join-Path $destination 'SteamWrapper.Manager.exe')) -ceq 'A') 'Verified portable bytes were not extracted.'
Reject-PortableTest { Expand-PortableAcceptanceArchive $archivePath $metadata $destination } 'Portable extraction overwrote an existing directory.'
$metadata.files[0].sha256=('c'*64)
Reject-PortableTest { Expand-PortableAcceptanceArchive $archivePath $metadata (Join-Path $root 'bad-hash') } 'Changed portable entry digest accepted.'
Assert-PortableTest (-not(Test-Path -LiteralPath (Join-Path $root 'bad-hash'))) 'Invalid portable inventory created output before validation.'
$metadata.files[0].sha256=('a'*64)
$helperText=Get-PortableCleanHelperDefinitions (Join-Path $PSScriptRoot 'Invoke-CleanWindowsGuestAcceptance.ps1')
Assert-PortableTest ($helperText -is [scriptblock]) 'Portable helper import did not produce definitions.'
. $helperText
Assert-PortableTest ((Quote-AcceptanceArgument 'C:\fixture path') -ceq '"C:\fixture path"') 'Existing clean quoting helper was not reusable.'
Assert-PortableTest (-not(Test-Path 'variable:evidencePath')) 'Helper import executed the clean main entry.'
# Exercise the current shared Runner helper with a harmless inbox Framework
# child. This catches missing transitive helper imports under StrictMode; a
# source-text assertion would miss the real closure used by the guest.
$dataRoot=Join-Path $root 'helper-data';[IO.Directory]::CreateDirectory((Join-Path $dataRoot 'bin'))|Out-Null
$compileFile=Join-Path $root 'CompileHarmless.ps1'
[IO.File]::WriteAllText($compileFile,@'
param([string]$Output)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
public static class PortableHelperFixture {
    public static int Main() {
        System.Threading.Thread.Sleep(300);
        System.IO.File.WriteAllText(System.Environment.GetEnvironmentVariable("STEAMWRAPPER_PORTABLE_HELPER_MARKER"),System.Environment.CurrentDirectory);
        return 0;
    }
}
"@ -OutputAssembly $Output -OutputType ConsoleApplication
'@,[Text.UTF8Encoding]::new($false))
& (Join-Path $env:windir 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -File $compileFile -Output (Join-Path $dataRoot 'bin/SteamWrapperRunner.exe')
if($LASTEXITCODE -ne 0){throw 'Harmless Framework fixture compilation failed.'}
$OutputDirectory=$root;$evidencePath=Join-Path $root 'helper-evidence.json';$utf8=New-Object Text.UTF8Encoding($false)
$events=New-Object 'Collections.Generic.List[object]';$runnerDiagnostics=New-Object 'Collections.Generic.List[object]';$evidence=[ordered]@{steps=$events;runnerDiagnostics=$runnerDiagnostics}
Reject-PortableTest { Get-AcceptanceProcessSecurity ([Diagnostics.Process]::GetCurrentProcess()) } 'An unspecified account mode silently bypassed the shared StrictMode security helper.'
$standardAccount=$false
Assert-PortableTest ($null -eq (Get-AcceptanceProcessSecurity ([Diagnostics.Process]::GetCurrentProcess()))) 'Explicit WDAG portable mode did not bypass standard-account-only token acquisition.'
$marker=Join-Path $root 'helper-runner-marker.txt';$previousMarker=$env:STEAMWRAPPER_PORTABLE_HELPER_MARKER;$env:STEAMWRAPPER_PORTABLE_HELPER_MARKER=$marker
try {
    Invoke-AcceptanceRunner 'shared portable helper regression' $marker ([Environment]::CurrentDirectory)
    Assert-PortableTest ($runnerDiagnostics.Count -eq 1 -and $runnerDiagnostics[0].exit.exitCode -eq 0 -and $events.Count -eq 1) 'Shared portable Runner helper did not complete with a retained actual exit status.'
} finally {$env:STEAMWRAPPER_PORTABLE_HELPER_MARKER=$previousMarker}
Write-Output "Portable acceptance helper regression passed: $cases cases; no production executable, SDK installation, UI or Sandbox run."
