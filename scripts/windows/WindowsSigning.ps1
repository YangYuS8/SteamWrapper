# Release preparation only: this file never submits signing requests, exports
# keys, starts a game/Runner, or modifies installed application/user data.
function Resolve-WindowsSigningFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$AllowedRoot, [switch]$AllowMissing)
    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath($Path)
    if ($root.StartsWith('\\') -or $full.StartsWith('\\') -or
        -not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Signing inputs must be local child files of the explicitly selected staging root.'
    }
    $ancestor = $full
    while ($ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction SilentlyContinue
        if ($item -and $item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Signing paths must not traverse reparse points.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'Signing input file is missing.' }
    return $full
}

function Assert-WindowsSigningEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Evidence,
        [Parameter(Mandatory)][string[]]$AllowedCertificateSha256,
        [Parameter(Mandatory)][string]$ExpectedProductVersion
    )
    if ($AllowedCertificateSha256.Count -eq 0 -or @($AllowedCertificateSha256 | Where-Object { $_ -notmatch '^[0-9a-fA-F]{64}\z' }).Count) {
        throw 'Signing identity requires an explicit non-empty allowlist of certificate DER SHA-256 fingerprints.'
    }
    if ($ExpectedProductVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z' -or
        @($ExpectedProductVersion.Split('.') | Where-Object { [long]$_ -gt 65535 }).Count) { throw 'Signing requires a three-part numeric Windows product version.' }
    if ($Evidence.TrustStatus -ne 0) { throw ('Windows Authenticode trust verification failed: 0x{0:x8}.' -f [uint32]$Evidence.TrustStatus) }
    if ($Evidence.TimestampTrusted -isnot [bool] -or -not $Evidence.TimestampTrusted -or
        $Evidence.TimestampRfc3161 -isnot [bool] -or -not $Evidence.TimestampRfc3161) { throw 'Signing requires a trusted RFC3161 timestamp, not just a valid current certificate.' }
    if ($Evidence.DigestAlgorithmOid -cne '2.16.840.1.101.3.4.2.1') { throw 'Signing requires the SHA-256 file digest algorithm.' }
    if ($Evidence.SignerName -cne 'SignPath Foundation' -or $Evidence.CertificateSha256 -notmatch '^[0-9a-fA-F]{64}\z' -or
        $Evidence.CertificateSha256 -notin $AllowedCertificateSha256) { throw 'Signing certificate does not match the approved Foundation identity allowlist.' }
    if ($Evidence.ProductName -cne 'SteamWrapper' -or $Evidence.ProductVersion -cne $ExpectedProductVersion) { throw 'Signing PE product name/version does not match the coordinated SteamWrapper release.' }
    if ($Evidence.Sha256 -cnotmatch '^[0-9a-f]{64}\z' -or $Evidence.Bytes -le 0 -or $Evidence.Bytes -gt 512MB) { throw 'Signing input has invalid file size or final-byte SHA-256.' }
    return $Evidence
}

function Initialize-WindowsSigningTrust {
    if ('SteamWrapper.Signing.NativeTrust' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace SteamWrapper.Signing {
    public sealed class Evidence {
        public uint TrustStatus { get; set; }
        public bool TimestampTrusted { get; set; }
        public bool TimestampRfc3161 { get; set; }
        public string DigestAlgorithmOid { get; set; } = "";
        public string CertificateSha256 { get; set; } = "";
        public string SignerName { get; set; } = "";
        public string ProductName { get; set; } = "";
        public string ProductVersion { get; set; } = "";
        public string Sha256 { get; set; } = "";
        public long Bytes { get; set; }
        public bool CacheOnly { get; set; }
    }

    public static class NativeTrust {
        public static string NormalizeProductResource(string value) => (value ?? "").TrimEnd(' ', '\0');
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FileInfo {
            public uint cbStruct;
            [MarshalAs(UnmanagedType.LPWStr)] public string filePath;
            public IntPtr fileHandle;
            public IntPtr knownSubject;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct TrustData {
            public uint cbStruct;
            public IntPtr policyCallbackData, sipClientData;
            public uint uiChoice, revocationChecks, unionChoice;
            public IntPtr fileInfo;
            public uint stateAction;
            public IntPtr stateData, urlReference;
            public uint providerFlags, uiContext;
            public IntPtr signatureSettings;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime { public uint low, high; }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProviderSigner {
            public uint cbStruct;
            public FileTime verifyAsOf;
            public uint certChainCount;
            public IntPtr certChain;
            public uint signerType;
            public IntPtr signer;
            public uint error, counterSignerCount;
            public IntPtr counterSigners, chainContext;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProviderCertificate { public uint cbStruct; public IntPtr certificateContext; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Blob { public uint length; public IntPtr data; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Algorithm { public IntPtr oid; public Blob parameters; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Attributes { public uint count; public IntPtr attributes; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Attribute { public IntPtr oid; public uint valueCount; public IntPtr values; }
        [StructLayout(LayoutKind.Sequential)]
        private struct SignerInfo {
            public uint version;
            public Blob issuer, serial;
            public Algorithm hashAlgorithm, encryptionAlgorithm;
            public Blob encryptedHash;
            public Attributes authenticatedAttributes, unauthenticatedAttributes;
        }
        [DllImport("wintrust.dll", ExactSpelling = true)]
        private static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        private static extern IntPtr WTHelperProvDataFromStateData(IntPtr state);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        private static extern IntPtr WTHelperGetProvSignerFromChain(IntPtr provider, uint signer, [MarshalAs(UnmanagedType.Bool)] bool counter, uint counterSigner);

        public static Evidence Inspect(string path, bool onlineRevocation) {
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length == 0 || file.Length > 512L * 1024 * 1024) throw new IOException("Signing input exceeds the file-size limit.");
            var info = new FileInfo { cbStruct = (uint)Marshal.SizeOf<FileInfo>(), filePath = path, fileHandle = file.SafeFileHandle.DangerousGetHandle() };
            IntPtr nativeInfo = Marshal.AllocHGlobal(Marshal.SizeOf<FileInfo>());
            Marshal.StructureToPtr(info, nativeInfo, false);
            var data = new TrustData {
                cbStruct = (uint)Marshal.SizeOf<TrustData>(), uiChoice = 2, unionChoice = 1,
                fileInfo = nativeInfo, stateAction = 1,
                // Chain revocation excludes the root. Cache-only blocks all URL
                // retrieval, not merely OCSP/CRL checks. Online is opt-in.
                providerFlags = 0x80U | (onlineRevocation ? 0U : 0x1000U)
            };
            var action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
            var evidence = new Evidence { Bytes = file.Length, CacheOnly = !onlineRevocation };
            try {
                evidence.TrustStatus = unchecked((uint)WinVerifyTrust(new IntPtr(-1), ref action, ref data));
                if (evidence.TrustStatus == 0) {
                    IntPtr provider = WTHelperProvDataFromStateData(data.stateData);
                    IntPtr pointer = provider == IntPtr.Zero ? IntPtr.Zero : WTHelperGetProvSignerFromChain(provider, 0, false, 0);
                    if (pointer != IntPtr.Zero) {
                        var signer = Marshal.PtrToStructure<ProviderSigner>(pointer);
                        if (signer.certChainCount > 0 && signer.certChain != IntPtr.Zero) {
                            var cert = Marshal.PtrToStructure<ProviderCertificate>(signer.certChain);
#pragma warning disable SYSLIB0057
                            using var certificate = new X509Certificate2(cert.certificateContext);
#pragma warning restore SYSLIB0057
                            evidence.CertificateSha256 = Convert.ToHexString(SHA256.HashData(certificate.RawData)).ToLowerInvariant();
                            evidence.SignerName = certificate.GetNameInfo(X509NameType.SimpleName, false);
                        }
                        if (signer.signer != IntPtr.Zero) {
                            var signerInfo = Marshal.PtrToStructure<SignerInfo>(signer.signer);
                            evidence.DigestAlgorithmOid = Marshal.PtrToStringAnsi(signerInfo.hashAlgorithm.oid) ?? "";
                            if (signerInfo.unauthenticatedAttributes.count > 128) throw new IOException("Too many unsigned signature attributes.");
                            int size = Marshal.SizeOf<Attribute>();
                            for (int i = 0; i < signerInfo.unauthenticatedAttributes.count; i++) {
                                var attribute = Marshal.PtrToStructure<Attribute>(IntPtr.Add(signerInfo.unauthenticatedAttributes.attributes, i * size));
                                if (Marshal.PtrToStringAnsi(attribute.oid) == "1.3.6.1.4.1.311.3.3.1") evidence.TimestampRfc3161 = true;
                            }
                        }
                        IntPtr counter = signer.counterSignerCount == 0 ? IntPtr.Zero : WTHelperGetProvSignerFromChain(provider, 0, true, 0);
                        if (counter != IntPtr.Zero) {
                            var timestamp = Marshal.PtrToStructure<ProviderSigner>(counter);
                            evidence.TimestampTrusted = timestamp.error == 0 && timestamp.certChainCount > 0;
                        }
                    }
                }
                var version = FileVersionInfo.GetVersionInfo(path);
                evidence.ProductName = NormalizeProductResource(version.ProductName);
                evidence.ProductVersion = NormalizeProductResource(version.ProductVersion);
                evidence.Sha256 = Convert.ToHexString(SHA256.HashData(file)).ToLowerInvariant();
                return evidence;
            } finally {
                data.stateAction = 2;
                WinVerifyTrust(new IntPtr(-1), ref action, ref data);
                Marshal.DestroyStructure<FileInfo>(nativeInfo);
                Marshal.FreeHGlobal(nativeInfo);
            }
        }
    }
}
'@
}

function Get-WindowsSigningEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$AllowedRoot, [switch]$OnlineRevocation)
    if (-not $IsWindows) { throw 'Windows signing verification requires Windows.' }
    $full = Resolve-WindowsSigningFile -Path $Path -AllowedRoot $AllowedRoot
    Initialize-WindowsSigningTrust
    return [SteamWrapper.Signing.NativeTrust]::Inspect($full, [bool]$OnlineRevocation)
}

function Assert-WindowsSigning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [Parameter(Mandatory)][string[]]$AllowedCertificateSha256,
        [Parameter(Mandatory)][string]$ExpectedProductVersion,
        [switch]$OnlineRevocation
    )
    $evidence = Get-WindowsSigningEvidence -Path $Path -AllowedRoot $AllowedRoot -OnlineRevocation:$OnlineRevocation
    return Assert-WindowsSigningEvidence -Evidence $evidence -AllowedCertificateSha256 $AllowedCertificateSha256 -ExpectedProductVersion $ExpectedProductVersion
}

function Update-RunnerSigningManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunnerPath,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string[]]$AllowedCertificateSha256,
        [switch]$OnlineRevocation
    )
    $runner = Resolve-WindowsSigningFile -Path $RunnerPath -AllowedRoot $AllowedRoot
    $manifest = Resolve-WindowsSigningFile -Path $ManifestPath -AllowedRoot $AllowedRoot -AllowMissing
    if ([IO.Path]::GetFileName($runner) -cne 'SteamWrapperRunner.exe' -or [IO.Path]::GetFileName($manifest) -cne 'runner-manifest.json' -or
        [IO.Path]::GetDirectoryName($runner) -cne [IO.Path]::GetDirectoryName($manifest)) { throw 'Runner signing manifest must be adjacent to the distributed SteamWrapperRunner.exe.' }
    $evidence = Assert-WindowsSigning -Path $runner -AllowedRoot $AllowedRoot -AllowedCertificateSha256 $AllowedCertificateSha256 -ExpectedProductVersion $Version -OnlineRevocation:$OnlineRevocation
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($manifest)) ('.runner-manifest.json.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $null = Resolve-WindowsSigningFile -Path $temporary -AllowedRoot $AllowedRoot -AllowMissing
    # Keep the final verified Runner immutable through the sidecar commit.
    $source = [IO.FileStream]::new($runner, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($source)).ToLowerInvariant()
        if ($hash -cne $evidence.Sha256 -or $source.Length -ne $evidence.Bytes) { throw 'Runner bytes changed after signature verification.' }
        $json = [ordered]@{ schemaVersion = 1; version = $Version; contractVersion = 2; sha256 = $hash } | ConvertTo-Json
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
        $destination = [IO.FileStream]::new($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $destination.Write($bytes); $destination.Flush($true) } finally { $destination.Dispose() }
        if ([IO.File]::Exists($manifest)) { [IO.File]::Replace($temporary, $manifest, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $manifest) }
        return [pscustomobject]@{ schemaVersion = 1; version = $Version; contractVersion = 2; sha256 = $hash }
    } finally {
        $source.Dispose()
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
