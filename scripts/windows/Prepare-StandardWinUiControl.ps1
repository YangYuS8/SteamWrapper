# Generate a developer-only minimal WinUI control; never execute it on the host.
[CmdletBinding()]
param([switch]$HelpersOnly,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Get-StandardWinUiControlProject([xml]$Manager) {
    $properties=@('TargetFramework','TargetPlatformMinVersion','Platforms','PlatformTarget','RuntimeIdentifier','UseWinUI','WinUISDKReferences','EnableMsixTooling','WindowsPackageType','GenerateAppxPackageOnBuild','AppxPackageSigningEnabled','WindowsAppSDKSelfContained','SelfContained','PublishTrimmed','ImplicitUsings','Nullable','RestorePackagesWithLockFile','IncludeSourceRevisionInInformationalVersion')
    $result='<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>WinExe</OutputType><AssemblyName>SteamWrapper.WinUiControl</AssemblyName><ApplicationManifest>app.manifest</ApplicationManifest><DefineConstants>$(DefineConstants);DISABLE_XAML_GENERATED_MAIN</DefineConstants>'
    foreach($name in $properties) {
        $values=@($Manager.SelectNodes('/Project/PropertyGroup/'+$name) | ForEach-Object {$_.InnerText})
        if($values.Count -ne 1 -or $values[0] -match '[<>]'){throw ('Missing or ambiguous Manager control property: '+$name)}
        $result+='<'+$name+'>'+[Security.SecurityElement]::Escape([string]$values[0])+'</'+$name+'>'
    }
    $result+='</PropertyGroup><ItemGroup>'
    foreach($name in @('Microsoft.WindowsAppSDK.WinUI','Microsoft.WindowsAppSDK.InteractiveExperiences','Microsoft.Windows.SDK.BuildTools')) {
        $refs=@($Manager.SelectNodes('/Project/ItemGroup/PackageReference') | Where-Object Include -CEQ $name)
        if($refs.Count -ne 1 -or $refs[0].Version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?$'){throw ('Missing exact SDK package pin: '+$name)}
        $result+='<PackageReference Include="'+$name+'" Version="'+$refs[0].Version+'" />'
    }
    return $result+'<Manifest Include="$(ApplicationManifest)" /></ItemGroup></Project>'
}
if($HelpersOnly){return}
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$base=Join-Path $repoRoot 'target\winui'
if(-not $OutputDirectory){$OutputDirectory=Join-Path $base ('standard-winui-control-'+[Guid]::NewGuid().ToString('N'))}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $OutputDirectory.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $OutputDirectory)){throw 'Control output must be a fresh directory inside target/winui.'}
. (Join-Path $PSScriptRoot 'StandardUserAcceptance.ps1') -HelpersOnly
Assert-StandardAcceptanceRegularPath $base $true
$source=Join-Path $OutputDirectory 'source';$payload=Join-Path $OutputDirectory 'payload'
[IO.Directory]::CreateDirectory($source) | Out-Null
$encoding=New-Object Text.UTF8Encoding($false)
$managerPath=Join-Path $repoRoot 'apps\manager-winui\SteamWrapper.Manager\SteamWrapper.Manager.csproj'
$project=Join-Path $source 'SteamWrapper.WinUiControl.csproj'
[IO.File]::WriteAllText($project,(Get-StandardWinUiControlProject ([xml](Get-Content -LiteralPath $managerPath -Raw))),$encoding)
Copy-Item -LiteralPath (Join-Path $repoRoot 'global.json') -Destination (Join-Path $source 'global.json')
Copy-Item -LiteralPath (Join-Path $repoRoot 'apps\manager-winui\SteamWrapper.Manager\app.manifest') -Destination (Join-Path $source 'app.manifest')
[IO.File]::WriteAllText((Join-Path $source 'App.xaml'),@'
<Application x:Class="SteamWrapper.WinUiControl.App"
 xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" />
'@,$encoding)
[IO.File]::WriteAllText((Join-Path $source 'App.xaml.cs'),@'
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;
namespace SteamWrapper.WinUiControl;
internal static class Witness {
 internal static string Role="", RunId="", Path="";
 internal static void Stage(string name,Exception? error=null) {
  File.AppendAllText(Path,JsonSerializer.Serialize(new {stage=name,runId=RunId,role=Role,processId=Environment.ProcessId,time=DateTimeOffset.UtcNow.ToString("O"),user=Environment.UserName,sid=WindowsIdentity.GetCurrent().User!.Value,exception=error?.ToString(),hresult=error?.HResult})+"\n");
 }
}
internal static class Program {
 [STAThread] static int Main(string[] args) {
  // Independent cheap host refusal before any WinUI call or file creation.
  if(args.Length!=3 || (args[0]!="WDAG" && args[0]!="StandardUser") || !System.Text.RegularExpressions.Regex.IsMatch(args[1],"^[a-f0-9]{32}$") || Environment.MachineName.Equals(args[2],StringComparison.OrdinalIgnoreCase)) return 90;
  string expected=args[0]=="WDAG" ? "WDAGUtilityAccount" : "SwAcc-"+args[1][..14];
  string native=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
  if(!Environment.UserName.Equals(expected,StringComparison.Ordinal) || !native.Equals(@"C:\Users\"+expected+@"\AppData\Local",StringComparison.OrdinalIgnoreCase)) return 91;
  string root=System.IO.Path.Combine(native,"Temp","SteamWrapperWinUiControl-"+args[1]+"-"+args[0]);
  if(!Directory.Exists(root) || File.Exists(System.IO.Path.Combine(root,"stages.jsonl"))) return 92;
  Witness.Role=args[0];Witness.RunId=args[1];Witness.Path=System.IO.Path.Combine(root,"stages.jsonl");
  try {
   Witness.Stage("main-entry");Witness.Stage("before-com-wrappers");
   WinRT.ComWrappersSupport.InitializeComWrappers();Witness.Stage("after-com-wrappers");
   Witness.Stage("before-Start");
   Microsoft.UI.Xaml.Application.Start(initialization=>{
    Witness.Stage("callback-entry");Witness.Stage("before-dispatcher-context");
    var context=new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
    SynchronizationContext.SetSynchronizationContext(context);Witness.Stage("after-dispatcher-context");
    Witness.Stage("before-new-App");_ = new App();Witness.Stage("after-new-App");
   });
   Witness.Stage("Start-returned");Witness.Stage("normal-exit");return Environment.ExitCode;
  } catch(Exception error){Witness.Stage("main-failed",error);return 11;}
 }
}
public partial class App : Microsoft.UI.Xaml.Application {
 private Window? window; private DispatcherTimer? closeTimer;
 public App() {
  Witness.Stage("app-body-entry");
  UnhandledException+=(_,e)=>Witness.Stage("unhandled",e.Exception);
  Witness.Stage("InitializeComponent-entered");InitializeComponent();Witness.Stage("InitializeComponent-complete");
  Witness.Stage("app-body-complete");
 }
 protected override void OnLaunched(LaunchActivatedEventArgs args) {
  Witness.Stage("OnLaunched");
  window=new Window {Title="SteamWrapper empty WinUI control",Content=new TextBlock {Text="Developer-only control. This window closes normally.",Margin=new Thickness(24)}};
  Witness.Stage("window-created");window.Closed+=(_,_)=>{Witness.Stage("window-closed");Exit();};
  window.Activate();Witness.Stage("window-activated");
  closeTimer=new DispatcherTimer {Interval=TimeSpan.FromSeconds(2)};
  closeTimer.Tick+=(_,_)=>{closeTimer.Stop();Witness.Stage("normal-close-request");window.Close();};closeTimer.Start();
 }
}
'@,$encoding)
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$components=(Get-Content -LiteralPath (Join-Path $repoRoot '.vsconfig') -Raw | ConvertFrom-Json).components
$installation=& $vswhere -latest -products '*' -requires $components -property installationPath
if($LASTEXITCODE -ne 0 -or -not $installation){throw 'Required official MSVC/SDK components are missing.'}
& (Join-Path $installation 'Common7\Tools\Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
& dotnet restore $project -r win-x64 -p:Platform=x64
if($LASTEXITCODE -ne 0){throw 'Control restore failed; its generated source is retained.'}
& dotnet publish $project --no-restore --configuration Release --runtime win-x64 --self-contained true -p:Platform=x64 --output $payload
if($LASTEXITCODE -ne 0){throw 'Control publish failed; its generated source is retained.'}
$files=@(Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName | ForEach-Object {
    Assert-StandardAcceptanceRegularPath $_.FullName $false
    [ordered]@{path=$_.FullName.Substring($payload.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
})
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath=Join-Path $OutputDirectory 'standard-winui-control.zip'
$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
try {foreach($file in $files){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $payload $file.path),$file.path,[IO.Compression.CompressionLevel]::Optimal) | Out-Null}} finally {$zip.Dispose()}
$inventory=[ordered]@{schemaVersion=1;kind='EmptyWinUiControl';developerOnly=$true;resources='empty';fileName='standard-winui-control.zip';executable='SteamWrapper.WinUiControl.exe';bytes=(Get-Item -LiteralPath $zipPath).Length;sha256=(Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant();managerProjectSha256=(Get-FileHash -LiteralPath $managerPath).Hash.ToLowerInvariant();sdk=(Get-Content -LiteralPath (Join-Path $repoRoot 'global.json') -Raw | ConvertFrom-Json).sdk.version;sourceHead=(& git -C $repoRoot rev-parse HEAD);sourceDirty=[bool](& git -C $repoRoot status --porcelain);files=$files}
& {param($ControlInventory,$Driver) . $Driver -HelpersOnly; Assert-StandardWinUiControlInventory $ControlInventory} ([pscustomobject]$inventory) (Join-Path $PSScriptRoot 'Invoke-StandardWinUiControlProbe.ps1')
Write-StandardAcceptanceJson (Join-Path $OutputDirectory 'standard-winui-control.json') $inventory
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Invoke-StandardWinUiControlProbe.ps1') -Destination $OutputDirectory
Write-Output ('Built and sealed developer-only control without executing it: '+$OutputDirectory)
