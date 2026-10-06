# Inbox PowerShell 5.1 compatible helpers. No executable or UI is started here.
function Assert-PortableAcceptance([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Assert-PortableAcceptancePath([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    $ancestor=$full
    while($ancestor) {
        $item=Get-Item -LiteralPath $ancestor -Force -ErrorAction SilentlyContinue
        Assert-PortableAcceptance (-not($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))) 'Portable acceptance paths must not contain reparse points.'
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}
function Assert-PortableAcceptanceRecord($Record) {
    foreach($key in @('path','bytes','sha256')) { Assert-PortableAcceptance ($null -ne $Record.PSObject.Properties[$key]) ('Portable file record lacks '+$key) }
    $path=$Record.path
    Assert-PortableAcceptance ($path -is [string] -and $path.Length -gt 0 -and $path.Length -le 240 -and
        $path -cnotmatch '[\\:<>"|?*\x00-\x1f]' -and -not $path.StartsWith('/') -and
        @($path.Split('/')|Where-Object {$_ -ceq '' -or $_ -ceq '.' -or $_ -ceq '..' -or $_ -match '[. ]$' -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'}).Count -eq 0 -and
        $path -notmatch '(?i)(^|/)(profiles\.toml|ui-settings\.json(?:\..*)?|installation\.json|\.git|\.env(?:\..*)?|logs|backups|cache)(/|$)') 'Unsafe or player-data portable inventory path.'
    Assert-PortableAcceptance (($Record.bytes -is [int] -or $Record.bytes -is [long]) -and $Record.bytes -ge 0 -and $Record.bytes -le 512MB -and
        $Record.sha256 -is [string] -and $Record.sha256 -cmatch '^[a-f0-9]{64}$') 'Unexpected portable file size or digest.'
}
function Assert-PortableAcceptanceMetadata($Metadata) {
    foreach($key in @('schemaVersion','tag','version','commit','platform','minimumWindowsVersion','releaseChannel','tagPrerelease','githubPrerelease','signed','installer','portable','archive','runner','files')) { Assert-PortableAcceptance ($null -ne $Metadata.PSObject.Properties[$key]) ('Portable descriptor lacks '+$key) }
    $number='(?:0|[1-9][0-9]*)';$identifier='(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    Assert-PortableAcceptance ($Metadata.tag -is [string] -and $Metadata.tag.Length -le 80 -and $Metadata.tag -cmatch ('^v(?<base>'+ $number+'\.'+$number+'\.'+$number+')(?:-(?<pre>'+$identifier+'(?:\.'+$identifier+')*))?$')) 'Expected a strict portable release tag.'
    $base=$Matches['base'];$preview=$Matches.ContainsKey('pre');$channel=if($preview){'preview'}else{'stable'}
    Assert-PortableAcceptance ($Metadata.schemaVersion -eq 1 -and $Metadata.version -ceq $base -and $Metadata.commit -cmatch '^[a-f0-9]{40}$' -and
        $Metadata.platform -ceq 'win-x64' -and $Metadata.minimumWindowsVersion -ceq '10.0.26100.0' -and $Metadata.releaseChannel -ceq $channel -and
        $Metadata.tagPrerelease -is [bool] -and $Metadata.tagPrerelease -eq $preview -and $Metadata.githubPrerelease -is [bool] -and $Metadata.githubPrerelease -eq $preview -and
        $Metadata.signed -is [bool] -and -not $Metadata.signed -and $Metadata.installer -is [bool] -and -not $Metadata.installer -and $Metadata.portable -is [bool] -and $Metadata.portable) 'Expected exact Windows unsigned portable schema-1 metadata.'
    foreach($key in @('fileName','bytes','sha256')) { Assert-PortableAcceptance ($null -ne $Metadata.archive.PSObject.Properties[$key]) ('Portable archive lacks '+$key) }
    Assert-PortableAcceptance ($Metadata.archive.fileName -ceq ('SteamWrapper-'+$Metadata.tag+'-win-x64.zip') -and
        ($Metadata.archive.bytes -is [int] -or $Metadata.archive.bytes -is [long]) -and $Metadata.archive.bytes -gt 0 -and $Metadata.archive.bytes -le 1GB -and $Metadata.archive.sha256 -cmatch '^[a-f0-9]{64}$') 'Unexpected portable archive identity.'
    Assert-PortableAcceptance ($Metadata.runner.version -ceq $base -and $Metadata.runner.contractVersion -eq 2 -and $Metadata.runner.sha256 -cmatch '^[a-f0-9]{64}$') 'Unexpected portable Runner contract.'
    $records=@($Metadata.files);Assert-PortableAcceptance ($records.Count -gt 0 -and $records.Count -le 5003) 'Portable inventory exceeds the bounded file count.'
    $paths=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [long]$total=0
    foreach($record in $records) { Assert-PortableAcceptanceRecord $record;Assert-PortableAcceptance ($paths.Add($record.path)) 'Duplicate portable inventory path.';$total+=$record.bytes }
    Assert-PortableAcceptance ($total -le 1GB) 'Portable inventory exceeds the total byte limit.'
}
function Get-PortableAcceptanceStreamHash($Stream) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return (-join($sha.ComputeHash($Stream)|ForEach-Object{$_.ToString('x2')})) } finally { $sha.Dispose() }
}
function Expand-PortableAcceptanceArchive([string]$Path,$Metadata,[string]$Destination) {
    Assert-PortableAcceptanceMetadata $Metadata
    $path=Assert-PortableAcceptancePath $Path;$destination=Assert-PortableAcceptancePath $Destination
    Assert-PortableAcceptance (-not(Test-Path -LiteralPath $destination)) 'Portable extraction requires a fresh directory; existing files are never overwritten.'
    Assert-PortableAcceptance ((Get-Item -LiteralPath $path).Length -eq $Metadata.archive.bytes) 'Portable archive length changed.'
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        Assert-PortableAcceptance ((Get-PortableAcceptanceStreamHash $stream) -ceq $Metadata.archive.sha256) 'Portable archive digest changed.'
        $stream.Position=0
        Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
        $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
        try {
            $records=@($Metadata.files);$stem='SteamWrapper-'+$Metadata.tag+'-win-x64/'
            Assert-PortableAcceptance ($archive.Entries.Count -eq $records.Count) 'Portable ZIP differs from its inventory.'
            $entries=New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
            foreach($entry in $archive.Entries) { Assert-PortableAcceptance (-not $entries.ContainsKey($entry.FullName)) 'Duplicate portable ZIP entry.';$entries.Add($entry.FullName,$entry) }
            foreach($record in $records) {
                $name=$stem+$record.path
                Assert-PortableAcceptance ($entries.ContainsKey($name) -and $entries[$name].Length -eq $record.bytes) 'Portable ZIP entry name or length differs.'
                # Unix symlinks and non-regular Unix entry types are not portable payload files.
                $type=([long]$entries[$name].ExternalAttributes -shr 16) -band 0xF000
                Assert-PortableAcceptance ($type -eq 0 -or $type -eq 0x8000) 'Portable ZIP entry is not a regular file.'
                $input=$entries[$name].Open();try { Assert-PortableAcceptance ((Get-PortableAcceptanceStreamHash $input) -ceq $record.sha256) 'Portable ZIP file digest differs.' }finally{$input.Dispose()}
            }
            # Only after every exact entry is verified do we create any output.
            [IO.Directory]::CreateDirectory($destination)|Out-Null
            foreach($record in $records) {
                $target=Assert-PortableAcceptancePath (Join-Path $destination $record.path.Replace('/','\'))
                Assert-PortableAcceptance ($target.StartsWith($destination.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) 'Portable extraction escaped its destination.'
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
                $output=New-Object IO.FileStream($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                $input=$entries[$stem+$record.path].Open();try{$input.CopyTo($output)}finally{$input.Dispose();$output.Dispose()}
            }
        } finally {$archive.Dispose()}
    } finally {$stream.Dispose()}
}
function Get-PortableCleanHelperDefinitions([string]$Path) {
    $path=Assert-PortableAcceptancePath $Path
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    Assert-PortableAcceptance (@($errors).Count -eq 0) 'The pinned clean guest script cannot be parsed.'
    $names=@('Assert-Acceptance','Quote-AcceptanceArgument','Wait-Acceptance','Test-AcceptanceInboxRuntimePackage','Get-AcceptancePayloadRuntimeModules','Assert-AcceptanceManualAppIdAction','Retain-AcceptanceProcessHandle','Get-AcceptanceExitDiagnostic','Read-AcceptanceBoundedDiagnosticFile','Write-AcceptanceEvidence','Record-Acceptance','Get-AcceptanceProcessSecurity','Get-AcceptanceDataHashes','Assert-AcceptanceDataHashes','Find-AcceptanceElement','Wait-AcceptanceElement','Invoke-AcceptanceElement','Set-AcceptanceValue','Capture-AcceptanceWindow','Close-AcceptanceManager','Invoke-AcceptanceRunner')
    $definitions=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -cin $names})
    Assert-PortableAcceptance ($definitions.Count -eq $names.Count -and @($definitions.Name|Sort-Object -Unique).Count -eq $names.Count) 'Expected exactly the named clean guest helpers.'
    # Only known function definitions are returned. The clean script's main
    # installer entry, ValidateHelpers branch and top-level statements never run.
    return [scriptblock]::Create(($definitions|ForEach-Object {$_.Extent.Text}) -join "`r`n")
}
