# Developer-only, sealed empty WinUI control. Never an installer or release asset.
[CmdletBinding()]
param([switch]$HelpersOnly,[ValidateSet('WDAG','StandardUser')][string]$Role='WDAG',
    [string]$InputDirectory='C:\AcceptanceInput',[string]$OutputDirectory='C:\AcceptanceOutput')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Assert-StandardWinUiControl([bool]$Condition,[string]$Message) {if(-not $Condition){throw $Message}}
function Assert-StandardWinUiControlEntry([string]$Name,[long]$Bytes) {
    Assert-StandardWinUiControl ($Name.Length -gt 0 -and $Name.Length -le 240 -and $Name -cmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$' -and
        @($Name.Split('/') | Where-Object {$_ -in @('.','..')}).Count -eq 0 -and $Bytes -gt 0 -and $Bytes -le 128MB) 'Unsafe or oversized control payload entry.'
}
function Assert-StandardWinUiControlInventory($Inventory) {
    Assert-StandardWinUiControl ($Inventory.schemaVersion -eq 1 -and $Inventory.kind -ceq 'EmptyWinUiControl' -and
        $Inventory.developerOnly -is [bool] -and $Inventory.developerOnly -and $Inventory.fileName -ceq 'standard-winui-control.zip' -and
        $Inventory.sha256 -cmatch '^[a-f0-9]{64}$' -and $Inventory.bytes -gt 0 -and $Inventory.bytes -le 256MB -and
        $Inventory.executable -ceq 'SteamWrapper.WinUiControl.exe' -and $Inventory.resources -ceq 'empty') 'Unexpected control fixture identity or release-like payload.'
    $names=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $total=0L;$files=@($Inventory.files)
    Assert-StandardWinUiControl ($files.Count -gt 0 -and $files.Count -le 2000) 'Control inventory count exceeds its bound.'
    foreach($file in $files) {
        Assert-StandardWinUiControlEntry $file.path $file.bytes
        Assert-StandardWinUiControl ($file.sha256 -cmatch '^[a-f0-9]{64}$' -and $names.Add([string]$file.path)) 'Duplicate or unsealed control file.'
        $total+=$file.bytes
        Assert-StandardWinUiControl ($total -le 512MB) 'Control payload exceeds its extraction bound.'
    }
    foreach($required in @($Inventory.executable,'SteamWrapper.WinUiControl.dll','SteamWrapper.WinUiControl.pri','Microsoft.UI.Xaml.dll','coreclr.dll')) {
        Assert-StandardWinUiControl $names.Contains($required) ('Missing self-contained control dependency: '+$required)
    }
}
function Assert-StandardWinUiControlObservation($Observation,$Context,$Manifest,[string]$Role,[string]$Executable) {
    Assert-StandardWinUiControl ($Role -cin @('WDAG','StandardUser') -and $Observation.path -ieq $Executable -and
        $Observation.processId -gt 0 -and $Observation.parentProcessId -eq [Diagnostics.Process]::GetCurrentProcess().Id -and
        $Observation.token.userSid -ceq $Context.token.userSid -and $Observation.token.sessionId -eq $Context.sessionId -and
        $Observation.token.logonSid -ceq $Context.token.logonSid) 'The control process changed image, parent, account, logon or session.'
    if($Role -ceq 'StandardUser') {Assert-StandardAcceptanceProcessToken $Observation.token $Manifest.expectedStandardUserSid}
    else {Assert-StandardWinUiControl ($Observation.token.administratorEnabled -eq $true -and $Context.userName -ieq 'WDAGUtilityAccount') 'The WDAG control did not retain its actual controller token.'}
}
function Assert-StandardWinUiControlStages($Stages,$Manifest,[string]$Role,[int]$ProcessId) {
    $expected=@('main-entry','before-com-wrappers','after-com-wrappers','before-Start','callback-entry','before-dispatcher-context','after-dispatcher-context','before-new-App','app-body-entry','InitializeComponent-entered','InitializeComponent-complete','app-body-complete','after-new-App','OnLaunched','window-created','window-activated','normal-close-request','window-closed','Start-returned','normal-exit')
    $all=@($Stages)
    Assert-StandardWinUiControl ($all.Count -eq $expected.Count) 'The control did not complete the exact minimal startup and normal close sequence.'
    for($i=0;$i -lt $expected.Count;$i++) {
        Assert-StandardWinUiControl ($all[$i].stage -ceq $expected[$i] -and $all[$i].runId -ceq $Manifest.runId -and
            $all[$i].role -ceq $Role -and $all[$i].processId -eq $ProcessId -and $null -eq $all[$i].exception) 'Unexpected control stage order, identity or failure.'
    }
}
if($HelpersOnly){return}
# Refuse the host before native observation, extraction, files or GUI.
Assert-StandardWinUiControl (($Role -ceq 'WDAG' -and [Environment]::UserName -ieq 'WDAGUtilityAccount' -and $PSScriptRoot -ieq 'C:\AcceptanceInput' -and
    $InputDirectory -ceq 'C:\AcceptanceInput' -and $OutputDirectory -ceq 'C:\AcceptanceOutput') -or
    ($Role -ceq 'StandardUser' -and [Environment]::UserName -cmatch '^SwAcc-[a-f0-9]{14}$' -and
    $PSScriptRoot -cmatch '^C:\\Users\\Public\\SteamWrapperAcceptance-[a-f0-9]{32}\\input$' -and $InputDirectory -ceq $PSScriptRoot)) 'The control can run only from its sealed disposable guest handoff.'
. (Join-Path $PSScriptRoot 'StandardUserAcceptance.ps1') -HelpersOnly
$manifest=Read-StandardAcceptanceManifest $InputDirectory
$context=Get-StandardAcceptanceContext
if($Role -ceq 'WDAG'){Assert-StandardAcceptanceControllerContext $context $manifest $InputDirectory $OutputDirectory}
else {
    $context | Add-Member -NotePropertyName accountAdministratorMember -NotePropertyValue ([SteamWrapperStandardAcceptance.Native]::AccountIsAdministrator([Environment]::UserName))
    Assert-StandardAcceptanceChildContext $context $manifest $InputDirectory $OutputDirectory
}
Assert-StandardWinUiControl ($manifest.standardWinUiControl -is [bool] -and $manifest.standardWinUiControl) 'The control requires the explicit dedicated diagnostic route.'
foreach($file in @(@{name='Invoke-StandardWinUiControlProbe.ps1';hash=$manifest.winUiControl.driverSha256},@{name='standard-winui-control.json';hash=$manifest.winUiControl.inventorySha256},@{name='standard-winui-control.zip';hash=$manifest.winUiControl.sha256})) {
    Assert-StandardAcceptanceSealedFile (Join-Path $InputDirectory $file.name) $file.hash
}
$inventoryPath=Join-Path $InputDirectory 'standard-winui-control.json'
Assert-StandardWinUiControl ((Get-Item -LiteralPath $inventoryPath).Length -le 2MB) 'Control inventory exceeds its read bound.'
$inventory=Read-StandardAcceptanceJson $inventoryPath
Assert-StandardWinUiControlInventory $inventory
Assert-StandardWinUiControl ($inventory.sha256 -ceq $manifest.winUiControl.sha256 -and $inventory.bytes -eq $manifest.winUiControl.bytes) 'Control bytes disagree with the prepared pin.'
$root=Join-Path $context.nativeLocalAppData ('Temp\SteamWrapperWinUiControl-'+$manifest.runId+'-'+$Role)
Assert-StandardAcceptanceRegularPath $OutputDirectory $true
Assert-StandardWinUiControl (-not (Test-Path -LiteralPath $root)) 'This control output is not fresh.'
Assert-StandardAcceptanceRegularPath $context.nativeLocalAppData $true
[IO.Directory]::CreateDirectory($root) | Out-Null
$payload=Join-Path $root 'payload';[IO.Directory]::CreateDirectory($payload) | Out-Null
$report=[ordered]@{schemaVersion=1;runId=$manifest.runId;role=$Role;kind='EmptyWinUiControl';result='running';resources='empty';context=$context;payload=$payload;process=$null;processExited=$false;exitCode=$null;stages=@();applicationEvents=@();productionInstallerExecuted=$false;ordinaryExplorerTested=$false;failure=$null}
$reportPath=Join-Path $OutputDirectory ('control-'+$Role.ToLowerInvariant()+'.log')
$process=$null;$startedAt=Get-Date
try {
    Write-StandardAcceptanceJson $reportPath $report
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead((Join-Path $InputDirectory $inventory.fileName))
    try {
        Assert-StandardWinUiControl ($archive.Entries.Count -eq @($inventory.files).Count) 'ZIP inventory count changed.'
        $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach($entry in $archive.Entries) {
            Assert-StandardWinUiControlEntry $entry.FullName $entry.Length
            Assert-StandardWinUiControl $seen.Add($entry.FullName) 'ZIP contains ambiguous duplicate names.'
            $pin=@($inventory.files | Where-Object path -CEQ $entry.FullName)
            Assert-StandardWinUiControl ($pin.Count -eq 1 -and $pin[0].bytes -eq $entry.Length) 'ZIP entry is absent from the exact sealed inventory.'
            $destination=Join-Path $payload ($entry.FullName.Replace('/','\'))
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$destination,$false)
            Assert-StandardAcceptanceSealedFile $destination $pin[0].sha256 $pin[0].bytes
        }
    } finally {$archive.Dispose()}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $payload $inventory.executable;$start.WorkingDirectory=$payload;$start.UseShellExecute=$false
    $start.Arguments=$Role+' '+$manifest.runId+' '+(Quote-StandardAcceptanceArgument $manifest.hostComputerName)
    $process=[Diagnostics.Process]::Start($start)
    $report['actualProcessId']=$process.Id
    try {$report.process=[SteamWrapperStandardAcceptance.Native]::ObserveProcess($process.Id);Assert-StandardWinUiControlObservation $report.process $context $manifest $Role $start.FileName}
    finally {Write-StandardAcceptanceJson $reportPath $report}
    $report.processExited=$process.WaitForExit(45000)
    Assert-StandardWinUiControl $report.processExited 'The control did not close normally within its bounded diagnostic; no process was killed.'
    $report.exitCode=$process.ExitCode
    Assert-StandardWinUiControl ($report.exitCode -eq 0) ('The control exited with code '+$report.exitCode+'.')
    $stagePath=Join-Path $root 'stages.jsonl'
    Assert-StandardAcceptanceRegularPath $stagePath $false
    Assert-StandardWinUiControl ((Get-Item -LiteralPath $stagePath).Length -le 128KB) 'Control stage log exceeds its read limit.'
    $report.stages=@([IO.File]::ReadAllLines($stagePath,[Text.Encoding]::UTF8) | ForEach-Object {$_ | ConvertFrom-Json})
    Assert-StandardWinUiControlStages $report.stages $manifest $Role $process.Id
    $report.result='passed'
} catch {
    $report.result='failed';$report.failure=[ordered]@{message=$_.Exception.GetBaseException().Message;exception=$_.Exception.ToString();script=$_.InvocationInfo.ScriptName;line=$_.InvocationInfo.ScriptLineNumber;stack=$_.ScriptStackTrace}
    throw
} finally {
    try {
        if($null -ne $process -and $process.HasExited){$report.processExited=$true;$report.exitCode=$process.ExitCode}
        $stagePath=Join-Path $root 'stages.jsonl'
        if(Test-Path -LiteralPath $stagePath){Assert-StandardAcceptanceRegularPath $stagePath $false;Assert-StandardWinUiControl ((Get-Item -LiteralPath $stagePath).Length -le 128KB) 'Control stage evidence exceeded its bound.';$report.stages=@([IO.File]::ReadAllLines($stagePath,[Text.Encoding]::UTF8) | ForEach-Object {$_ | ConvertFrom-Json})}
        $report.applicationEvents=@(Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$startedAt} -MaxEvents 80 -ErrorAction SilentlyContinue | Where-Object {$_.Message -like '*SteamWrapper.WinUiControl*'} | Select-Object -First 8 | ForEach-Object {[ordered]@{time=$_.TimeCreated.ToString('O');id=$_.Id;provider=$_.ProviderName;message=$_.Message.Substring(0,[Math]::Min($_.Message.Length,32768))}})
        Write-StandardAcceptanceJson $reportPath $report
    } finally {if($null -ne $process){$process.Dispose()}}
}
Write-Output ($Role+' empty self-contained WinUI control passed with actual startup stages and normal exit.')
