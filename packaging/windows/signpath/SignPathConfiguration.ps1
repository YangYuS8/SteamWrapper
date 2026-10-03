# Local preparation only. This module never submits or approves a signing request.
. (Join-Path $PSScriptRoot 'PreparationFiles.ps1')
function Assert-SignPathProductionConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration, [bool]$SubmissionTokenAvailable = $false)
    function Read-Setting([string]$Name) {
        if ($Configuration -is [Collections.IDictionary]) {
            if ($Configuration.Contains($Name)) { return ,$Configuration[$Name] }
        } else {
            $property = $Configuration.PSObject.Properties[$Name]
            if ($property) { return ,$property.Value }
        }
        return $null
    }
    $schemaVersion = Read-Setting 'schemaVersion'
    if (($schemaVersion -isnot [int] -and $schemaVersion -isnot [long]) -or $schemaVersion -ne 1) { throw 'Unsupported SignPath production configuration schema version.' }
    $approved = Read-Setting 'providerApproved'
    if ($approved -isnot [bool] -or -not $approved) { throw 'Production signing requires actual Foundation approval; draft configuration cannot submit.' }
    $organization = [guid]::Empty
    if (-not [guid]::TryParse((Read-Setting 'organizationId'), [ref]$organization) -or $organization -eq [guid]::Empty) { throw 'Production signing requires the actual non-empty provider organization ID.' }
    foreach ($key in @('projectSlug', 'signingPolicySlug')) {
        if ((Read-Setting $key) -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\z') { throw 'Production signing requires an approved project or signing-policy slug.' }
    }
    $slugs = Read-Setting 'artifactConfigurationSlugs'
    foreach ($stage in @('payload', 'uninstaller', 'setup')) {
        $value = if ($slugs -is [Collections.IDictionary]) { $slugs[$stage] } elseif ($slugs -and $slugs.PSObject.Properties[$stage]) { $slugs.PSObject.Properties[$stage].Value } else { $null }
        if ($value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\z') { throw 'Production signing requires all three provider-approved artifact configuration slugs.' }
    }
    $pins = Read-Setting 'certificateSha256'
    if ($pins -isnot [Array] -or $pins.Count -eq 0 -or
        @($pins | Where-Object { $_ -isnot [string] -or $_ -cnotmatch '^[a-fA-F0-9]{64}\z' -or $_ -match '^0{64}\z' }).Count -gt 0 -or
        @($pins | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique).Count -ne $pins.Count) { throw 'Production signing requires explicit approved certificate DER SHA-256 pins.' }
    $reference = $null
    if (-not [uri]::TryCreate((Read-Setting 'approvalReference'), [UriKind]::Absolute, [ref]$reference) -or
        $reference.Scheme -cne 'https' -or $reference.Host -cne 'app.signpath.io' -or $reference.UserInfo -or -not $reference.IsDefaultPort -or $reference.AbsolutePath -eq '/') { throw 'Production signing requires a recorded provider approval reference on app.signpath.io.' }
    $approver = Read-Setting 'humanApprover'
    if ($approver -isnot [string] -or [string]::IsNullOrWhiteSpace($approver) -or $approver -match '[\r\n\x00-\x1f]') { throw 'Production signing requires a confirmed human approver.' }
    $manual = Read-Setting 'requireManualApproval'
    if ($manual -isnot [bool] -or -not $manual) { throw 'Foundation releases require manual approval; the CI submitter cannot approve.' }
    if ((Read-Setting 'trustedBuildSystem') -cne 'GitHub.com' -or
        (Read-Setting 'repository') -cne 'https://github.com/YangYuS8/SteamWrapper') { throw 'Production signing requires the approved repository and GitHub-hosted origin verification.' }
    if (-not $SubmissionTokenAvailable) { throw 'Production signing requires a dedicated submitter token; never pass a token to this preparation validator.' }
    # Only validates declared local prerequisites. Provider admission, policies,
    # roles, MFA and the certificate's actual trust still require external evidence.
    return $Configuration
}

function Assert-SignPathArtifactConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][ValidateSet('payload', 'uninstaller', 'setup')][string]$Stage, [string]$SchemaPath)
    $ns = 'http://signpath.io/artifact-configuration/v1'
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 512KB
    if ($SchemaPath) {
        $pin = (Read-PreparationText -Path (Join-Path $PSScriptRoot 'schema-v1.pin.json') -AllowedRoot $PSScriptRoot -MaximumBytes 16KB) | ConvertFrom-Json
        $schemaFile = Get-PreparationFile -Path $SchemaPath -AllowedRoot ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($SchemaPath))) -MaximumBytes 512KB
        $schemaStream = [IO.File]::Open($schemaFile.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $set = [Xml.Schema.XmlSchemaSet]::new()
        $set.XmlResolver = $null
        try {
            if ($schemaStream.Length -gt 512KB) { throw 'Provider XML schema exceeds the configured byte limit.' }
            $hash = [Security.Cryptography.SHA256]::Create()
            try { $actualHash = [Convert]::ToHexString($hash.ComputeHash($schemaStream)).ToLowerInvariant() } finally { $hash.Dispose() }
            if ($actualHash -cne $pin.sha256) { throw 'Provider XML schema differs from the reviewed schema pin; review before updating it.' }
            $schemaStream.Position = 0
            $schemaReader = [Xml.XmlReader]::Create($schemaStream, $settings)
            try { $null = $set.Add($ns, $schemaReader) } finally { $schemaReader.Dispose() }
        } finally { $schemaStream.Dispose() }
        $set.Compile()
        $settings.Schemas = $set
        $settings.ValidationType = [Xml.ValidationType]::Schema
    }
    $template = Read-PreparationText -Path $Path -AllowedRoot ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) -MaximumBytes 64KB
    $templateReader = [IO.StringReader]::new($template)
    $reader = [Xml.XmlReader]::Create($templateReader, $settings)
    $xml = [Xml.XmlDocument]::new()
    $xml.XmlResolver = $null
    try { $xml.Load($reader) } finally { $reader.Dispose(); $templateReader.Dispose() }
    if ($xml.DocumentElement.LocalName -cne 'artifact-configuration' -or $xml.DocumentElement.NamespaceURI -cne $ns) { throw 'Unexpected SignPath artifact configuration namespace or root.' }
    $manager = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $manager.AddNamespace('ac', $ns)
    $root = $xml.DocumentElement
    $parameters = @($root.SelectNodes('ac:parameters/ac:parameter', $manager))
    $expectedParameters = @(switch ($Stage) { 'payload' { 'version' } 'uninstaller' { 'version'; 'uninstallerFile' } 'setup' { 'version'; 'tag' } })
    if ($parameters.Count -ne $expectedParameters.Count -or @($parameters | ForEach-Object { $_.GetAttribute('name') } | Sort-Object -Unique).Count -ne $parameters.Count -or
        @($parameters | Where-Object { $_.GetAttribute('name') -cnotin $expectedParameters -or $_.GetAttribute('required') -cne 'true' -or $_.HasAttribute('default-value') }).Count) { throw 'Artifact parameters must be explicit and required, without guessed default values.' }
    if (@($root.SelectNodes('ac:zip-file', $manager)).Count -ne 1 -or @($root.ChildNodes | Where-Object { $_ -is [Xml.XmlElement] -and $_.LocalName -cnotin @('parameters', 'zip-file') }).Count) { throw 'Signing submissions require exactly one artifact ZIP root.' }
    $policy = (Read-PreparationText -Path (Join-Path $PSScriptRoot 'inventory-policy.v1.json') -AllowedRoot $PSScriptRoot -MaximumBytes 256KB) | ConvertFrom-Json
    $expectedPaths = @(switch ($Stage) { 'payload' { $policy.ownedPePaths } 'uninstaller' { '${uninstallerFile}' } 'setup' { 'SteamWrapper-${tag}-win-x64-setup.exe' } })
    $files = @($root.SelectNodes('ac:zip-file/ac:pe-file', $manager))
    $paths = @($files | ForEach-Object { $_.GetAttribute('path') })
    if ($files.Count -ne $expectedPaths.Count -or @($paths | Sort-Object -Unique).Count -ne $paths.Count -or
        @($paths | Where-Object { $_ -cnotin $expectedPaths }).Count -or
        @($root.SelectNodes('ac:zip-file/*', $manager) | Where-Object { $_.LocalName -cne 'pe-file' }).Count) { throw 'Signing targets must match the precise owned file set; broad or additional targets are forbidden.' }
    foreach ($file in $files) {
        foreach ($limit in @('min-matches', 'max-matches')) {
            if ($file.HasAttribute($limit) -and $file.GetAttribute($limit) -cne '1') { throw 'Every signing target must match exactly one required file.' }
        }
        if ($file.GetAttribute('product-name') -cne 'SteamWrapper' -or $file.GetAttribute('product-version') -cne '${version}') { throw 'Signing targets require the coordinated SteamWrapper product and version restrictions.' }
        $sign = @($file.SelectNodes('ac:authenticode-sign', $manager))
        if ($sign.Count -ne 1 -or $sign[0].GetAttribute('hash-algorithm') -cne 'sha256' -or
            @($file.ChildNodes | Where-Object { $_ -is [Xml.XmlElement] -and $_.LocalName -cne 'authenticode-sign' }).Count -or
            @($sign[0].Attributes | Where-Object { $_.Name -cne 'hash-algorithm' -and $_.Specified }).Count) { throw 'Owned files require one SHA-256 Authenticode directive; upstream re-signing and signature appending are forbidden.' }
    }
    return [pscustomobject]@{ stage = $Stage; ownedTargets = $paths; officialSchemaValidated = [bool]$SchemaPath; providerApproved = $false }
}

function Assert-SignPathRequestParameters {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('payload', 'uninstaller', 'setup')][string]$Stage,
        [Parameter(Mandatory)][string]$Version, [string]$Tag, [string]$UninstallerFile)
    if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z' -or
        @($Version.Split('.') | Where-Object { [long]$_ -gt 65535 }).Count) { throw 'Signing parameters require a coordinated numeric Windows product version.' }
    $parameters = [ordered]@{ version = $Version }
    if ($Stage -ceq 'setup') {
        $prefix = 'v' + $Version
        if ($Tag -cnotmatch ('^' + [regex]::Escape($prefix) + '(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?\z')) { throw 'Setup parameters require the exact safe reviewed tag for this product version.' }
        $parameters.tag = $Tag
    }
    if ($Stage -ceq 'uninstaller') {
        if ($UninstallerFile -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.exe\z' -or $UninstallerFile.Contains('..')) { throw 'Uninstaller parameters require an exact generated EXE basename, without wildcard or path traversal.' }
        $parameters.uninstallerFile = $UninstallerFile
    }
    return $parameters
}
