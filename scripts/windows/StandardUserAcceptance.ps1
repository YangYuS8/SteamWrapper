# A bounded, guest-only standard-account test controller. Passwords stay in
# memory. No host account, mapped-folder ACL or machine policy is changed.
[CmdletBinding()]
param(
    [switch]$HelpersOnly,
    [switch]$DiagnosticOnly,
    [switch]$StandardChild,
    [string]$StandardInputDirectory = 'C:\AcceptanceInput',
    [string]$StandardOutputDirectory = 'C:\AcceptanceOutput'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-StandardAcceptance([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Get-StandardAcceptancePaths([string]$RunId) {
    Assert-StandardAcceptance ($RunId -cmatch '^[a-f0-9]{32}$') 'Expected the exact prepared acceptance run ID.'
    $root = 'C:\Users\Public\SteamWrapperAcceptance-' + $RunId
    return [pscustomobject]@{ root=$root; input=$root + '\input'; output=$root + '\evidence'; userName='SwAcc-' + $RunId.Substring(0,14) }
}
function Quote-StandardAcceptanceArgument([string]$Value) {
    Assert-StandardAcceptance (-not [string]::IsNullOrWhiteSpace($Value) -and
        -not $Value.Contains('"') -and -not $Value.Contains([string][char]13) -and -not $Value.Contains([string][char]10)) 'Unsafe standard-user child command argument.'
    return '"' + $Value.TrimEnd('\') + '"'
}
function Assert-StandardAcceptanceCommonContext($Context, $Manifest) {
    Assert-StandardAcceptance ($Manifest.schemaVersion -eq 1 -and $Manifest.sandboxOnly -is [bool] -and $Manifest.sandboxOnly -and
        $Manifest.networkingDisabled -is [bool] -and $Manifest.networkingDisabled -and
        -not [string]::IsNullOrWhiteSpace([string]$Manifest.hostComputerName) -and
        $Context.computerName -ine $Manifest.hostComputerName) 'Refusing an unexpected manifest or its development host.'
    Assert-StandardAcceptance ($Context.interactive -eq $true -and $Context.sessionId -gt 0 -and
        $Context.manufacturer -ceq 'Microsoft Corporation' -and $Context.model -ceq 'Virtual Machine' -and
        $Context.productType -eq 1 -and $Context.build -ge 26100 -and $Context.x64 -eq $true) 'A connected native x64 Windows 11 Sandbox client is required.'
    Assert-StandardAcceptance ($Context.profile -ieq $Context.nativeProfile -and $Context.localAppData -ieq $Context.nativeLocalAppData -and
        -not $Context.machineDotnetExists -and -not $Context.dotnetOnPath -and @($Context.overrides).Count -eq 0) 'Refusing redirected AppData, an SDK/runtime or test overrides.'
}
function Assert-StandardAcceptanceControllerContext($Context, $Manifest, [string]$InputPath, [string]$OutputPath) {
    Assert-StandardAcceptanceCommonContext $Context $Manifest
    $null=Get-StandardAcceptancePaths $Manifest.runId
    Assert-StandardAcceptance ($InputPath -ceq 'C:\AcceptanceInput' -and $OutputPath -ceq 'C:\AcceptanceOutput' -and
        $Context.userName -ieq 'WDAGUtilityAccount' -and $Context.profile -ieq 'C:\Users\WDAGUtilityAccount' -and
        $Context.token.administratorEnabled -eq $true) 'Account creation is allowed only in the dedicated WDAG Sandbox controller.'
}
function Assert-StandardAcceptanceChildContext($Context, $Manifest, [string]$InputPath, [string]$OutputPath) {
    Assert-StandardAcceptanceCommonContext $Context $Manifest
    $paths=Get-StandardAcceptancePaths $Manifest.runId
    Assert-StandardAcceptance ($Manifest.accountMode -ceq 'StandardUser' -and $Manifest.expectedStandardUserName -ceq $paths.userName -and
        $Manifest.expectedStandardUserSid -cmatch '^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-[0-9]+$' -and
        $Manifest.standardInputDirectory -ceq $paths.input -and $Manifest.standardOutputDirectory -ceq $paths.output -and
        $InputPath -ceq $paths.input -and $OutputPath -ceq $paths.output -and
        $Context.userName -ceq $paths.userName -and $Context.profile -ieq ('C:\Users\' + $paths.userName) -and
        $Context.sessionId -eq $Manifest.standardSessionId -and $Context.accountAdministratorMember -is [bool] -and -not $Context.accountAdministratorMember) 'The child is not the exact fresh standard account and native profile.'
    Assert-StandardAcceptanceProcessToken $Context.token $Manifest.expectedStandardUserSid
}
function Assert-StandardAcceptanceProcessToken($Token, [string]$ExpectedSid) {
    Assert-StandardAcceptance ($Token.userSid -ceq $ExpectedSid -and $Token.elevated -is [bool] -and -not $Token.elevated -and
        $Token.elevationType -eq 1 -and $Token.integritySid -ceq 'S-1-16-8192' -and
        $Token.administratorPresent -is [bool] -and -not $Token.administratorPresent -and
        $Token.administratorEnabled -is [bool] -and -not $Token.administratorEnabled -and
        $Token.administratorDenyOnly -is [bool] -and -not $Token.administratorDenyOnly -and
        $Token.uiAccess -is [bool] -and -not $Token.uiAccess -and $Token.appContainer -is [bool] -and -not $Token.appContainer -and $Token.type -eq 1) 'A real standard-account Medium, non-elevated primary token is required; a filtered administrator is not accepted.'
}
function Assert-StandardAcceptanceRegularPath([string]$Path, [bool]$Directory) {
    $item=Get-Item -LiteralPath $Path -Force
    Assert-StandardAcceptance (($Directory -and $item -is [IO.DirectoryInfo]) -or (-not $Directory -and $item -is [IO.FileInfo])) 'Unexpected standard-user input/output file type.'
    $ancestor=$item
    while ($null -ne $ancestor) {
        Assert-StandardAcceptance (-not ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Standard-account acceptance paths must not contain links.'
        $ancestor=if ($ancestor -is [IO.DirectoryInfo]) {$ancestor.Parent} else {$ancestor.Directory}
    }
}
function Read-StandardAcceptanceManifest([string]$Directory) {
    $path=Join-Path $Directory 'acceptance-input.json'
    Assert-StandardAcceptanceRegularPath $path $false
    Assert-StandardAcceptance ((Get-Item -LiteralPath $path).Length -le 2MB) 'The acceptance manifest exceeds its read limit.'
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}
function Assert-StandardAcceptanceSealedFile([string]$Path, [string]$Hash, [long]$Bytes=-1) {
    Assert-StandardAcceptanceRegularPath $Path $false
    $file=Get-Item -LiteralPath $Path
    Assert-StandardAcceptance ($Hash -cmatch '^[a-f0-9]{64}$' -and $file.Length -gt 0 -and $file.Length -le 512MB -and
        ($Bytes -lt 0 -or $file.Length -eq $Bytes) -and
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Hash) 'A sealed standard-account acceptance input changed.'
}
function New-StandardAcceptanceGuestAcl([string]$UserSid, [string]$ControllerSid, [bool]$Writable) {
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier($ControllerSid)))
    foreach($grant in @(
        @{sid='S-1-5-18';rights=[Security.AccessControl.FileSystemRights]::FullControl},
        @{sid='S-1-5-32-544';rights=[Security.AccessControl.FileSystemRights]::FullControl},
        @{sid=$UserSid;rights=$(if($Writable){[Security.AccessControl.FileSystemRights]::Modify}else{[Security.AccessControl.FileSystemRights]::ReadAndExecute})}
    )) {
        $rule=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($grant.sid)), $grant.rights,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    return $acl
}
function Initialize-StandardAcceptanceNative {
    if ('SteamWrapperStandardAcceptance.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
namespace SteamWrapperStandardAcceptance {
public sealed class TokenSnapshot {
    public string userSid, integritySid;
    public bool elevated, administratorPresent, administratorEnabled, administratorDenyOnly, uiAccess, appContainer;
    public int elevationType, type, sessionId;
}
public sealed class ChildHandle : IDisposable {
    internal IntPtr handle;
    public int ProcessId;
    public int Wait(int milliseconds) {
        uint result=Native.WaitForSingleObject(handle,(uint)milliseconds);
        if(result==258) throw new TimeoutException("The standard-user child did not finish; no process was killed.");
        if(result!=0) throw new Win32Exception(Marshal.GetLastWin32Error(),"WaitForSingleObject failed.");
        uint code; if(!Native.GetExitCodeProcess(handle,out code)) throw new Win32Exception(Marshal.GetLastWin32Error(),"GetExitCodeProcess failed.");
        return unchecked((int)code);
    }
    public void Dispose() { if(handle!=IntPtr.Zero) { Native.CloseHandle(handle); handle=IntPtr.Zero; } }
}
public static class Native {
    [StructLayout(LayoutKind.Sequential)] struct SidAttributes { public IntPtr sid; public uint attributes; }
    [StructLayout(LayoutKind.Sequential)] struct GroupsFirst { public uint count; public SidAttributes first; }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct UserInfo {
        [MarshalAs(UnmanagedType.LPWStr)] public string name, password;
        public uint passwordAge, privilege;
        [MarshalAs(UnmanagedType.LPWStr)] public string home, comment;
        public uint flags;
        [MarshalAs(UnmanagedType.LPWStr)] public string script;
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Startup {
        public int cb;
        public string reserved, desktop, title;
        public uint x,y,xSize,ySize,xCount,yCount,fill,flags;
        public ushort show,reservedSize;
        public IntPtr reservedBytes,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process,thread; public uint pid,tid; }
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr buffer,uint length,out uint needed);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int processId);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    [DllImport("kernel32.dll",SetLastError=true)] internal static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
    [DllImport("netapi32.dll",CharSet=CharSet.Unicode)] static extern uint NetUserAdd(string server,uint level,ref UserInfo info,out uint parameter);
    [DllImport("netapi32.dll",CharSet=CharSet.Unicode)] static extern uint NetUserGetLocalGroups(string server,string user,uint level,uint flags,out IntPtr buffer,uint maximum,out uint count,out uint total);
    [DllImport("netapi32.dll")] static extern uint NetApiBufferFree(IntPtr buffer);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessWithLogonW(
        string user,string domain,string password,uint logonFlags,string application,StringBuilder command,uint creationFlags,
        IntPtr environment,string directory,ref Startup startup,out ProcessInfo process);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr GetProcessWindowStation();
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr GetThreadDesktop(uint threadId);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool GetUserObjectInformationW(IntPtr handle,int index,StringBuilder value,uint bytes,out uint needed);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr handle);
    static IntPtr Information(IntPtr token,int kind) {
        uint length; GetTokenInformation(token,kind,IntPtr.Zero,0,out length);
        if(length==0 || length>131072) throw new Win32Exception(Marshal.GetLastWin32Error(),"Unexpected token information size.");
        IntPtr buffer=Marshal.AllocHGlobal((int)length);
        if(!GetTokenInformation(token,kind,buffer,length,out length)) { int error=Marshal.GetLastWin32Error(); Marshal.FreeHGlobal(buffer); throw new Win32Exception(error,"GetTokenInformation failed."); }
        return buffer;
    }
    static int Scalar(IntPtr token,int kind) { IntPtr b=Information(token,kind); try { return Marshal.ReadInt32(b); } finally { Marshal.FreeHGlobal(b); } }
    static string SidInformation(IntPtr token,int kind) { IntPtr b=Information(token,kind); try { return new SecurityIdentifier(Marshal.ReadIntPtr(b)).Value; } finally { Marshal.FreeHGlobal(b); } }
    public static TokenSnapshot GetToken(int processId) {
        IntPtr process=processId==0 ? GetCurrentProcess() : OpenProcess(0x1000,false,processId);
        if(process==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess failed.");
        IntPtr token=IntPtr.Zero;
        try {
            if(!OpenProcessToken(process,8,out token)) throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcessToken failed.");
            TokenSnapshot value=new TokenSnapshot();
            value.userSid=SidInformation(token,1); value.integritySid=SidInformation(token,25);
            value.elevated=Scalar(token,20)!=0; value.elevationType=Scalar(token,18); value.type=Scalar(token,8);
            value.sessionId=Scalar(token,12); value.uiAccess=Scalar(token,26)!=0; value.appContainer=Scalar(token,29)!=0;
            IntPtr groups=Information(token,2);
            try {
                int count=Marshal.ReadInt32(groups); if(count<0 || count>4096) throw new InvalidOperationException("Unexpected token group count.");
                int offset=(int)Marshal.OffsetOf(typeof(GroupsFirst),"first"), size=Marshal.SizeOf(typeof(SidAttributes));
                for(int i=0;i<count;i++) {
                    SidAttributes group=(SidAttributes)Marshal.PtrToStructure(IntPtr.Add(groups,offset+i*size),typeof(SidAttributes));
                    if(new SecurityIdentifier(group.sid).Value=="S-1-5-32-544") {
                        value.administratorPresent=true; value.administratorEnabled=(group.attributes&4)!=0; value.administratorDenyOnly=(group.attributes&16)!=0;
                    }
                }
            } finally { Marshal.FreeHGlobal(groups); }
            return value;
        } finally { if(token!=IntPtr.Zero) CloseHandle(token); if(processId!=0) CloseHandle(process); }
    }
    public static bool AccountIsAdministrator(string name) {
        IntPtr buffer=IntPtr.Zero; uint count,total;
        uint status=NetUserGetLocalGroups(null,name,0,1,out buffer,0xffffffff,out count,out total);
        try {
            if(status!=0 || count!=total || count>1024) throw new Win32Exception((int)status,"A complete local-account group query failed.");
            for(int i=0;i<count;i++) {
                string group=Marshal.PtrToStringUni(Marshal.ReadIntPtr(buffer,i*IntPtr.Size));
                SecurityIdentifier sid=(SecurityIdentifier)new NTAccount(Environment.MachineName,group).Translate(typeof(SecurityIdentifier));
                if(sid.Value=="S-1-5-32-544") return true;
            }
            return false;
        } finally { if(buffer!=IntPtr.Zero) NetApiBufferFree(buffer); }
    }
    public static string AddNormalUser(string name,string password) {
        UserInfo info=new UserInfo(); info.name=name; info.password=password; info.privilege=1;
        info.comment="Disposable SteamWrapper Sandbox acceptance"; info.flags=0x10201;
        uint parameter; uint status;
        try { status=NetUserAdd(null,1,ref info,out parameter); } finally { info.password=null; }
        if(status!=0) throw new Win32Exception((int)status,"NetUserAdd failed; no policy was changed.");
        return ((SecurityIdentifier)new NTAccount(Environment.MachineName,name).Translate(typeof(SecurityIdentifier))).Value;
    }
    public static ChildHandle StartChild(string name,string password,string application,string command,string directory) {
        Startup startup=new Startup(); startup.cb=Marshal.SizeOf(typeof(Startup)); startup.desktop=@"WinSta0\Default";
        ProcessInfo process;
        if(!CreateProcessWithLogonW(name,".",password,1,application,new StringBuilder(command),0x08000000,IntPtr.Zero,directory,ref startup,out process))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"CreateProcessWithLogonW failed; desktop or logon rights were not widened.");
        CloseHandle(process.thread);
        ChildHandle child=new ChildHandle(); child.handle=process.process; child.ProcessId=(int)process.pid; return child;
    }
    static string ObjectName(IntPtr handle) {
        if(handle==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"Desktop/window-station handle is unavailable.");
        StringBuilder value=new StringBuilder(256); uint needed;
        if(!GetUserObjectInformationW(handle,2,value,512,out needed)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Desktop/window-station name query failed.");
        return value.ToString();
    }
    public static string WindowStationName() { return ObjectName(GetProcessWindowStation()); }
    public static string DesktopName() { return ObjectName(GetThreadDesktop(GetCurrentThreadId())); }
    public static void AssertInputDesktopReadable() {
        IntPtr desktop=OpenInputDesktop(0,false,0x41);
        if(desktop==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"The standard account cannot read/enumerate the input desktop; its ACL was not changed.");
        CloseDesktop(desktop);
    }
}
}
'@
}
function Get-StandardAcceptanceContext {
    Initialize-StandardAcceptanceNative
    $computer=Get-CimInstance Win32_ComputerSystem
    $os=Get-CimInstance Win32_OperatingSystem
    $overrides=@(Get-ChildItem Env: | Where-Object { $_.Name -cin @('STEAMWRAPPER_E2E_ROOT','STEAMWRAPPER_DEPLOYMENT_TEST','STEAM_DIR') -or $_.Name -like 'STEAMWRAPPER_DEPLOYMENT_*' } | Where-Object { -not [string]::IsNullOrEmpty($_.Value) } | Select-Object -ExpandProperty Name)
    $dotnetDirectories=@('C:\Program Files\dotnet','C:\Program Files (x86)\dotnet',(Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet')) | Where-Object {Test-Path -LiteralPath $_}
    return [pscustomobject]@{
        computerName=$env:COMPUTERNAME; userName=$env:USERNAME; profile=$env:USERPROFILE; nativeProfile=[Environment]::GetFolderPath('UserProfile')
        localAppData=$env:LOCALAPPDATA; nativeLocalAppData=[Environment]::GetFolderPath('LocalApplicationData')
        interactive=[Environment]::UserInteractive; sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
        manufacturer=$computer.Manufacturer; model=$computer.Model; build=[int]$os.BuildNumber; productType=[int]$os.ProductType; x64=[Environment]::Is64BitProcess
        machineDotnetExists=@($dotnetDirectories).Count -ne 0; dotnetOnPath=$null -ne (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue)
        overrides=$overrides; token=[SteamWrapperStandardAcceptance.Native]::GetToken(0)
    }
}
if ($HelpersOnly) { return }

# Refuse a development host before reading input, making a file or calling
# NetUserAdd. Full context validation follows this inexpensive first guard.
if (-not $StandardChild) {
    Assert-StandardAcceptance ($env:USERNAME -ieq 'WDAGUtilityAccount' -and $env:USERPROFILE -ieq 'C:\Users\WDAGUtilityAccount' -and
        $PSScriptRoot -ieq 'C:\AcceptanceInput' -and $StandardInputDirectory -ceq 'C:\AcceptanceInput' -and
        $StandardOutputDirectory -ceq 'C:\AcceptanceOutput') 'The standard-account controller may run only from the dedicated WDAG Sandbox input.'
}
$manifest=Read-StandardAcceptanceManifest $StandardInputDirectory
$paths=Get-StandardAcceptancePaths $manifest.runId
$context=Get-StandardAcceptanceContext
$controllerHash=[string]$manifest.standardControllerSha256
Assert-StandardAcceptanceSealedFile $PSCommandPath $controllerHash
$utf8=New-Object Text.UTF8Encoding($false)
function Write-StandardAcceptanceJson([string]$Path,$Value) {
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 15),$utf8)
}
if ($StandardChild) {
    $context | Add-Member -NotePropertyName accountAdministratorMember -NotePropertyValue ([SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator($env:USERNAME))
    Assert-StandardAcceptanceChildContext $context $manifest $StandardInputDirectory $StandardOutputDirectory
    Assert-StandardAcceptanceRegularPath $StandardOutputDirectory $true
    Assert-StandardAcceptance (@(Get-ChildItem -LiteralPath $StandardOutputDirectory -Force).Count -eq 0) 'Standard-account diagnostic output is not fresh.'
    $diagnostic=[ordered]@{schemaVersion=1;runId=$manifest.runId;result='running';standardAccount=$true;context=$context;desktop=$null;productionInstallerExecuted=$false}
    $diagnosticPath=Join-Path $StandardOutputDirectory 'standard-user-diagnostic.json'
    try {
        $station=[SteamWrapperStandardAcceptance.Native]::WindowStationName()
        $desktop=[SteamWrapperStandardAcceptance.Native]::DesktopName()
        [SteamWrapperStandardAcceptance.Native]::AssertInputDesktopReadable()
        Assert-StandardAcceptance ($station -ceq 'WinSta0' -and $desktop -ceq 'Default') 'The standard account did not reach the exact connected acceptance desktop.'
        $diagnostic.desktop=[ordered]@{windowStation=$station;name=$desktop;inputDesktopReadable=$true}
        $diagnostic.result='passed'; Write-StandardAcceptanceJson $diagnosticPath $diagnostic
        if (-not $DiagnosticOnly) {
            Assert-StandardAcceptanceSealedFile (Join-Path $StandardInputDirectory 'Invoke-CleanWindowsGuestAcceptance.ps1') $manifest.guestScriptSha256
            & (Join-Path $StandardInputDirectory 'Invoke-CleanWindowsGuestAcceptance.ps1') -InputDirectory $StandardInputDirectory -OutputDirectory $StandardOutputDirectory *> (Join-Path $StandardOutputDirectory 'guest-launch.log')
        }
    } catch {
        $diagnostic.result='failed'; $diagnostic.failureType=$_.Exception.GetBaseException().GetType().FullName
        $diagnostic.failureMessage=$_.Exception.GetBaseException().Message
        Write-StandardAcceptanceJson $diagnosticPath $diagnostic
        throw
    }
    return
}

Assert-StandardAcceptanceControllerContext $context $manifest $StandardInputDirectory $StandardOutputDirectory
Assert-StandardAcceptanceRegularPath $StandardInputDirectory $true
Assert-StandardAcceptanceRegularPath $StandardOutputDirectory $true
Assert-StandardAcceptance (-not (Test-Path -LiteralPath $paths.root) -and -not (Test-Path -LiteralPath ('C:\Users\' + $paths.userName))) 'This run already has a guest handoff root or account profile; start a fresh Sandbox.'
Assert-StandardAcceptanceRegularPath 'C:\Users\Public' $true
$existingOutput=@(Get-ChildItem -LiteralPath $StandardOutputDirectory -Force)
Assert-StandardAcceptance (@($existingOutput | Where-Object { $_.PSIsContainer -or $_.Name -cne 'guest-launch.log' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $_.Length -gt 16384 }).Count -eq 0) 'The standard-account controller requires fresh mapped output.'
$sealedFiles=@(
    [pscustomobject]@{name='Invoke-CleanWindowsGuestAcceptance.ps1';hash=$manifest.guestScriptSha256;bytes=-1},
    [pscustomobject]@{name='Start-CleanWindowsAcceptance.ps1';hash=$manifest.launchScriptSha256;bytes=-1},
    [pscustomobject]@{name='StandardUserAcceptance.ps1';hash=$controllerHash;bytes=-1}
)
foreach($asset in @($manifest.baseline,$manifest.target)) {
    Assert-StandardAcceptance ($asset.fileName -cmatch '^SteamWrapper-v[0-9A-Za-z.-]+-win-x64-setup\.exe$' -and $asset.bytes -gt 0 -and $asset.bytes -le 512MB) 'Unexpected standard-account installer input.'
    $sealedFiles += [pscustomobject]@{name=$asset.fileName;hash=$asset.sha256;bytes=$asset.bytes}
}
if ($null -ne $manifest.PSObject.Properties['candidateBuildSha256']) {
    $sealedFiles += [pscustomobject]@{name='installer-build.json';hash=$manifest.candidateBuildSha256;bytes=-1}
    $sealedFiles += [pscustomobject]@{name='deployment-manifest.json';hash=$manifest.candidateDeploymentManifestSha256;bytes=-1}
}
$sealedFiles=@($sealedFiles | Sort-Object -Property name -Unique)
foreach($file in $sealedFiles) { Assert-StandardAcceptanceSealedFile (Join-Path $StandardInputDirectory $file.name) $file.hash $file.bytes }
$report=[ordered]@{schemaVersion=1;runId=$manifest.runId;result='running';mode=$(if($DiagnosticOnly){'DiagnosticOnly'}else{'Lifecycle'});environment='Windows Sandbox';controller=$context;accountCreated=$false;standardUserName=$paths.userName;standardUserSid=$null;childProcessId=$null;childExitCode=$null;childHexExitCode=$null;desktopAclChanged=$false;mappedFolderAclChanged=$false;machinePolicyChanged=$false;productionInstallerExecuted=$(if($DiagnosticOnly){$false}else{$null});failure=$null}
$reportPath=Join-Path $StandardOutputDirectory 'standard-controller.json'
$password=$null; $child=$null
try {
    Write-StandardAcceptanceJson $reportPath $report
    $random=New-Object byte[] 48; $rng=New-Object Security.Cryptography.RNGCryptoServiceProvider
    try {$rng.GetBytes($random); $password=[Convert]::ToBase64String($random) + 'aA1!'} finally {$rng.Dispose(); [Array]::Clear($random,0,$random.Length)}
    $sid=[SteamWrapperStandardAcceptance.Native]::AddNormalUser($paths.userName,$password)
    $report.accountCreated=$true; $report.standardUserSid=$sid
    Assert-StandardAcceptance (-not [SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator($paths.userName)) 'The new Sandbox account unexpectedly belongs to Administrators.'
    [IO.Directory]::CreateDirectory($paths.input) | Out-Null
    [IO.Directory]::CreateDirectory($paths.output) | Out-Null
    # Only this guest-local handoff tree receives the new SID. The host-mapped
    # folders and existing desktop/window-station ACLs are untouched.
    foreach($record in @(@{path=$paths.root;writable=$false},@{path=$paths.output;writable=$true})) {
        Set-Acl -LiteralPath $record.path -AclObject (New-StandardAcceptanceGuestAcl $sid $context.token.userSid $record.writable)
    }
    foreach($file in $sealedFiles) {
        Copy-Item -LiteralPath (Join-Path $StandardInputDirectory $file.name) -Destination (Join-Path $paths.input $file.name)
        Assert-StandardAcceptanceSealedFile (Join-Path $paths.input $file.name) $file.hash $file.bytes
    }
    $manifest | Add-Member -NotePropertyName accountMode -NotePropertyValue 'StandardUser' -Force
    $manifest | Add-Member -NotePropertyName expectedStandardUserName -NotePropertyValue $paths.userName -Force
    $manifest | Add-Member -NotePropertyName expectedStandardUserSid -NotePropertyValue $sid -Force
    $manifest | Add-Member -NotePropertyName standardInputDirectory -NotePropertyValue $paths.input -Force
    $manifest | Add-Member -NotePropertyName standardOutputDirectory -NotePropertyValue $paths.output -Force
    $manifest | Add-Member -NotePropertyName standardSessionId -NotePropertyValue $context.sessionId -Force
    Write-StandardAcceptanceJson (Join-Path $paths.input 'acceptance-input.json') $manifest
    foreach($file in Get-ChildItem -LiteralPath $paths.input -Force) { $file.Attributes=$file.Attributes -bor [IO.FileAttributes]::ReadOnly }
    $inboxPowerShell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $command=(Quote-StandardAcceptanceArgument $inboxPowerShell) + ' -NoLogo -NoProfile -MTA -ExecutionPolicy Bypass -File ' +
        (Quote-StandardAcceptanceArgument (Join-Path $paths.input 'StandardUserAcceptance.ps1')) + ' -StandardChild -StandardInputDirectory ' +
        (Quote-StandardAcceptanceArgument $paths.input) + ' -StandardOutputDirectory ' + (Quote-StandardAcceptanceArgument $paths.output)
    if($DiagnosticOnly) {$command += ' -DiagnosticOnly'}
    Assert-StandardAcceptance ($command.Length -le 1023) 'The standard-user child command exceeds the native API limit.'
    $child=[SteamWrapperStandardAcceptance.Native]::StartChild($paths.userName,$password,$inboxPowerShell,$command,$paths.input)
    $report.childProcessId=$child.ProcessId; Write-StandardAcceptanceJson $reportPath $report
    $report.childExitCode=$child.Wait($(if($DiagnosticOnly){180000}else{900000}))
    $unsigned=if($report.childExitCode -lt 0){[long]$report.childExitCode + 4294967296L}else{[long]$report.childExitCode}
    $report.childHexExitCode='0x{0:X8}' -f $unsigned
    $exports=@(Get-ChildItem -LiteralPath $paths.output -Force)
    Assert-StandardAcceptance ($exports.Count -le 64 -and ($exports | Measure-Object -Property Length -Sum).Sum -le 64MB) 'The standard-account evidence exceeds its export limits.'
    foreach($file in $exports) {
        Assert-StandardAcceptanceRegularPath $file.FullName $false
        Assert-StandardAcceptance ($file.Name -cmatch '^(?:evidence\.json|standard-user-diagnostic\.json|guest-launch\.log|[A-Za-z0-9][A-Za-z0-9._-]{0,100}\.(?:log|png))$' -and $file.Length -le 16MB) 'Unexpected standard-account evidence file.'
        $name=if($file.Name -ceq 'guest-launch.log'){'standard-user-launch.log'}else{$file.Name}
        $destination=Join-Path $StandardOutputDirectory $name
        Assert-StandardAcceptance (-not (Test-Path -LiteralPath $destination)) 'Refusing to overwrite mapped evidence.'
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
    Assert-StandardAcceptance ($report.childExitCode -eq 0) 'The real standard-account child failed; inspect its retained diagnostics. No account rights or policy were changed.'
    $diagnostic=Get-Content -LiteralPath (Join-Path $paths.output 'standard-user-diagnostic.json') -Raw | ConvertFrom-Json
    Assert-StandardAcceptance ($diagnostic.runId -ceq $manifest.runId -and $diagnostic.result -ceq 'passed' -and $diagnostic.standardAccount -eq $true) 'The standard-account token/desktop diagnostic did not pass.'
    if(-not $DiagnosticOnly) {
        $finished=Get-Content -LiteralPath (Join-Path $paths.output 'evidence.json') -Raw | ConvertFrom-Json
        Assert-StandardAcceptance ($finished.runId -ceq $manifest.runId -and $finished.result -ceq 'passed') 'The real standard-account lifecycle did not finish.'
        $report.productionInstallerExecuted=$true
    }
    $report.result='passed'; Write-StandardAcceptanceJson $reportPath $report
    Write-Output ('Standard-account ' + $report.mode + ' passed; inspect the retained Sandbox evidence. The disposable account/profile disappear when this Sandbox stops.')
} catch {
    $base=$_.Exception.GetBaseException()
    $report.result='failed'; $report.failure=[ordered]@{type=$base.GetType().FullName;message=$base.Message;win32Error=$(if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null})}
    Write-StandardAcceptanceJson $reportPath $report
    throw
} finally {
    $password=$null
    if($null -ne $child) {$child.Dispose()}
}
