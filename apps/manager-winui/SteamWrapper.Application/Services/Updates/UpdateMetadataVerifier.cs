using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SteamWrapper.Application.Services.Updates;

internal enum UpdateFailure
{
    InvalidEnvelope, UnknownKey, InvalidSignature, InvalidMetadata, IncompatibleProduct,
    UnsafeUrl, StaleMetadata, ClockRollback, Replay, StateCorrupt, UnsafeStatePath
}

/// <summary>Internal reasons; a future UI must map them to localized messages.</summary>
internal sealed class UpdateValidationException(UpdateFailure failure, string message, Exception? inner = null)
    : Exception(message, inner)
{
    internal UpdateFailure Failure { get; } = failure;
}

/// <summary>Explicit configuration only. No production feed or trust key is fabricated.</summary>
internal sealed class UpdateTrustPolicy
{
    internal const int MaximumMetadataBytes = 512 * 1024;
    internal const long MaximumArtifactBytes = 512L * 1024 * 1024;
    private readonly Dictionary<string, byte[]> keys = new(StringComparer.Ordinal);
    private readonly HashSet<string> artifactHosts;
    internal Uri MetadataUri { get; }
    internal string Channel { get; }
    internal TimeSpan MaximumLifetime { get; }

    internal UpdateTrustPolicy(Uri metadataUri, string channel, IReadOnlyDictionary<string, byte[]> publicKeys,
        IEnumerable<string> allowedArtifactHosts, TimeSpan? maximumLifetime = null)
    {
        if (!metadataUri.IsAbsoluteUri)
            throw new UpdateValidationException(UpdateFailure.UnsafeUrl, "Update metadata requires an explicit absolute HTTPS URL.");
        MetadataUri = metadataUri;
        Channel = channel is "preview" or "stable" ? channel : throw new ArgumentException("Unknown update channel.", nameof(channel));
        MaximumLifetime = maximumLifetime ?? TimeSpan.FromDays(7);
        if (MaximumLifetime <= TimeSpan.Zero || MaximumLifetime > TimeSpan.FromDays(31)) throw new ArgumentOutOfRangeException(nameof(maximumLifetime));
        if (publicKeys.Count is < 1 or > 16) throw new ArgumentException("Supply one to sixteen approved update keys.", nameof(publicKeys));
        foreach (var (id, bytes) in publicKeys)
        {
            if (!Regex.IsMatch(id, "^[A-Za-z0-9_-]{1,64}$", RegexOptions.CultureInvariant) || bytes.Length is < 1 or > 1024)
                throw new ArgumentException("Update key identity/size is invalid.", nameof(publicKeys));
            using var key = ECDsa.Create();
            key.ImportSubjectPublicKeyInfo(bytes, out var consumed);
            if (consumed != bytes.Length || key.KeySize != 256 || key.ExportParameters(false).Curve.Oid.Value != "1.2.840.10045.3.1.7")
                throw new ArgumentException("Update keys must be exact ECDSA P-256 SubjectPublicKeyInfo.", nameof(publicKeys));
            keys.Add(id, bytes.ToArray());
        }
        artifactHosts = new HashSet<string>(allowedArtifactHosts, StringComparer.OrdinalIgnoreCase);
        if (artifactHosts.Count is < 1 or > 16 || artifactHosts.Any(host => Uri.CheckHostName(host) != UriHostNameType.Dns || host.Any(c => c > 127)))
            throw new ArgumentException("Artifact hosts must be explicit ASCII DNS names.", nameof(allowedArtifactHosts));
        RequireUrl(metadataUri, new HashSet<string>([metadataUri.IdnHost], StringComparer.OrdinalIgnoreCase));
    }

    internal void RequireMetadataUrl(Uri uri) => RequireUrl(uri, new HashSet<string>([MetadataUri.IdnHost], StringComparer.OrdinalIgnoreCase));
    internal void RequireArtifactUrl(Uri uri) => RequireUrl(uri, artifactHosts);

    private static void RequireUrl(Uri uri, HashSet<string> hosts)
    {
        if (!uri.IsAbsoluteUri || uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 || uri.IsLoopback ||
            uri.HostNameType != UriHostNameType.Dns || uri.Host.Any(c => c > 127) || !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.IsNullOrEmpty(uri.Fragment) || uri.AbsoluteUri.Length > 4096 || !hosts.Contains(uri.IdnHost))
            throw new UpdateValidationException(UpdateFailure.UnsafeUrl, "Update URL is not an explicitly allowed HTTPS destination.");
    }

    internal bool Verify(string keyId, ReadOnlySpan<byte> payload, ReadOnlySpan<byte> signature)
    {
        if (!keys.TryGetValue(keyId, out var bytes)) throw new UpdateValidationException(UpdateFailure.UnknownKey, "Update signing key is not approved.");
        using var key = ECDsa.Create();
        key.ImportSubjectPublicKeyInfo(bytes, out _);
        return signature.Length == 64 && key.VerifyData(payload, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }
}

internal sealed record UpdateInstallationContext(string ReleaseTag, string Platform, Version WindowsVersion,
    int ProfileContract = 2, int RunnerContract = 2, int DeploymentProtocol = 1);

internal sealed record VerifiedUpdateMetadata(string Channel, long Sequence, string PayloadSha256,
    DateTimeOffset IssuedAt, DateTimeOffset ExpiresAt, string ReleaseTag, string Version, string SourceCommit,
    Uri ArtifactUri, string ArtifactSha256, long ArtifactBytes, bool IsUpgrade);

internal sealed class UpdateMetadataVerifier(UpdateTrustPolicy policy)
{
    internal VerifiedUpdateMetadata Verify(ReadOnlyMemory<byte> envelope, UpdateInstallationContext installed, DateTimeOffset now)
    {
        if (envelope.Length is < 1 or > UpdateTrustPolicy.MaximumMetadataBytes)
            throw Invalid(UpdateFailure.InvalidEnvelope, "Update metadata exceeds its byte limit.");
        using var outer = UpdateJson.Parse(envelope, UpdateFailure.InvalidEnvelope);
        var wrapper = outer.RootElement;
        UpdateJson.RequireProperties(wrapper, "schemaVersion", "keyId", "payload", "signature");
        if (UpdateJson.Number(wrapper, "schemaVersion") != 1) throw Invalid(UpdateFailure.InvalidEnvelope, "Unsupported update envelope schema.");
        var keyId = UpdateJson.Text(wrapper, "keyId", 64);
        var payload = Base64(UpdateJson.Text(wrapper, "payload", UpdateTrustPolicy.MaximumMetadataBytes), UpdateTrustPolicy.MaximumMetadataBytes);
        var signature = Base64(UpdateJson.Text(wrapper, "signature", 128), 64);
        if (!policy.Verify(keyId, payload, signature)) throw Invalid(UpdateFailure.InvalidSignature, "Update payload signature is invalid.");

        // Parse product/URLs only after verifying the signature of the exact bytes.
        using var document = UpdateJson.Parse(payload, UpdateFailure.InvalidMetadata);
        var root = document.RootElement;
        UpdateJson.RequireProperties(root, "schemaVersion", "appId", "platform", "channel", "sequence", "issuedAt", "expiresAt", "release");
        if (UpdateJson.Number(root, "schemaVersion") != 1) throw Invalid(UpdateFailure.InvalidMetadata, "Unsupported signed update schema.");
        if (UpdateJson.Text(root, "appId", 64) != "SteamWrapper" || UpdateJson.Text(root, "platform", 32) != "win-x64" || installed.Platform != "win-x64" ||
            UpdateJson.Text(root, "channel", 16) != policy.Channel) throw Invalid(UpdateFailure.IncompatibleProduct, "Update application/platform/channel differs from the selected installation.");
        var sequence = UpdateJson.Number(root, "sequence");
        if (sequence < 1) throw Invalid(UpdateFailure.InvalidMetadata, "Update sequence must be positive.");
        var issued = Timestamp(root, "issuedAt");
        var expires = Timestamp(root, "expiresAt");
        RequireFreshness(issued, expires, now, policy.MaximumLifetime);

        var release = root.GetProperty("release");
        UpdateJson.RequireProperties(release, "tag", "version", "commit", "minimumWindowsVersion", "profileContract", "runnerContract", "deploymentProtocol", "artifact");
        var tag = UpdateJson.Text(release, "tag", 80);
        var version = UpdateJson.Text(release, "version", 24);
        var selected = UpdateVersion.Parse(tag);
        var current = UpdateVersion.Parse(installed.ReleaseTag);
        if (selected.NumericText != version || (policy.Channel == "stable" && selected.Prerelease.Length != 0))
            throw Invalid(UpdateFailure.InvalidMetadata, "Tag and coordinated version/channel do not agree.");
        var minimum = UpdateJson.Text(release, "minimumWindowsVersion", 40);
        if (!Regex.IsMatch(minimum, "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", RegexOptions.CultureInvariant) ||
            !System.Version.TryParse(minimum, out var minimumVersion)) throw Invalid(UpdateFailure.InvalidMetadata, "Minimum Windows version is invalid.");
        if (minimumVersion > installed.WindowsVersion || UpdateJson.Number(release, "profileContract") != installed.ProfileContract ||
            UpdateJson.Number(release, "runnerContract") != installed.RunnerContract || UpdateJson.Number(release, "deploymentProtocol") != installed.DeploymentProtocol)
            throw Invalid(UpdateFailure.IncompatibleProduct, "Update OS or data/Runner/deployment contract is incompatible.");
        var commit = UpdateJson.Text(release, "commit", 40);
        if (!Regex.IsMatch(commit, "^[0-9a-f]{40}$", RegexOptions.CultureInvariant)) throw Invalid(UpdateFailure.InvalidMetadata, "Source commit is not an exact Git SHA.");
        var comparison = selected.CompareTo(current);
        if (comparison > 0 && selected.Numeric == current.Numeric) throw Invalid(UpdateFailure.IncompatibleProduct, "An upgrade cannot replace Runner bytes under the same coordinated numeric version.");

        var artifact = release.GetProperty("artifact");
        UpdateJson.RequireProperties(artifact, "type", "url", "sha256", "bytes", "authenticodeRequired");
        if (UpdateJson.Text(artifact, "type", 16) != "installer" || artifact.GetProperty("authenticodeRequired").ValueKind != JsonValueKind.True)
            throw Invalid(UpdateFailure.InvalidMetadata, "An update plan requires a separately verified signed installer.");
        if (!Uri.TryCreate(UpdateJson.Text(artifact, "url", 4096), UriKind.Absolute, out var uri)) throw Invalid(UpdateFailure.UnsafeUrl, "Artifact URL is invalid.");
        policy.RequireArtifactUrl(uri);
        var bytes = UpdateJson.Number(artifact, "bytes");
        var hash = UpdateJson.Text(artifact, "sha256", 64);
        if (bytes is < 1 or > UpdateTrustPolicy.MaximumArtifactBytes || !Regex.IsMatch(hash, "^[0-9a-f]{64}$", RegexOptions.CultureInvariant))
            throw Invalid(UpdateFailure.InvalidMetadata, "Artifact length or SHA-256 exceeds the signed-package policy.");
        return new(policy.Channel, sequence, Convert.ToHexStringLower(SHA256.HashData(payload)), issued, expires,
            tag, version, commit, uri, hash, bytes, comparison > 0);
    }

    internal static void RequireFreshness(DateTimeOffset issued, DateTimeOffset expires, DateTimeOffset now, TimeSpan maximumLifetime)
    {
        if (issued > now || expires <= now || expires <= issued || expires - issued > maximumLifetime)
            throw Invalid(UpdateFailure.StaleMetadata, "Update metadata is expired, future-dated or has an excessive validity interval.");
    }

    private static DateTimeOffset Timestamp(JsonElement source, string name)
    {
        var text = UpdateJson.Text(source, name, 40);
        if (!DateTimeOffset.TryParseExact(text, ["yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'"], CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var value)) throw Invalid(UpdateFailure.InvalidMetadata, "Update timestamps must be strict UTC RFC3339.");
        return value;
    }

    private static byte[] Base64(string text, int maximum)
    {
        try
        {
            var bytes = Convert.FromBase64String(text);
            if (bytes.Length is < 1 || bytes.Length > maximum || Convert.ToBase64String(bytes) != text)
                throw Invalid(UpdateFailure.InvalidEnvelope, "Update envelope uses invalid/non-canonical base64.");
            return bytes;
        }
        catch (FormatException error) { throw new UpdateValidationException(UpdateFailure.InvalidEnvelope, "Update envelope base64 is invalid.", error); }
    }
    private static UpdateValidationException Invalid(UpdateFailure failure, string text) => new(failure, text);
}

internal static class UpdateJson
{
    internal static JsonDocument Parse(ReadOnlyMemory<byte> bytes, UpdateFailure failure)
    {
        try
        {
            _ = new UTF8Encoding(false, true).GetString(bytes.Span);
            var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 16, AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow });
            try { RejectDuplicates(document.RootElement, failure); return document; }
            catch { document.Dispose(); throw; }
        }
        catch (Exception error) when (error is JsonException or DecoderFallbackException) { throw new UpdateValidationException(failure, "Update JSON is invalid.", error); }
    }
    private static void RejectDuplicates(JsonElement element, UpdateFailure failure)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw new UpdateValidationException(failure, "Update JSON contains a duplicate property.");
                RejectDuplicates(property.Value, failure);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var item in element.EnumerateArray()) RejectDuplicates(item, failure);
    }
    internal static void RequireProperties(JsonElement element, params string[] expected)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.EnumerateObject().Select(p => p.Name).ToHashSet(StringComparer.Ordinal).SetEquals(expected))
            throw new UpdateValidationException(UpdateFailure.InvalidMetadata, "Update JSON fields do not match the supported schema.");
    }
    internal static string Text(JsonElement parent, string key, int maximum)
    {
        var value = parent.GetProperty(key);
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { } text || text.Length is < 1 || text.Length > maximum || text.Any(char.IsControl))
            throw new UpdateValidationException(UpdateFailure.InvalidMetadata, "Update string field is invalid or too large.");
        return text;
    }
    internal static long Number(JsonElement parent, string key)
    {
        var value = parent.GetProperty(key);
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt64(out var number)) throw new UpdateValidationException(UpdateFailure.InvalidMetadata, "Update integer field is invalid.");
        return number;
    }
}

internal sealed record UpdateVersion(Version Numeric, string NumericText, string[] Prerelease) : IComparable<UpdateVersion>
{
    internal static UpdateVersion Parse(string tag)
    {
        var number = "(?:0|[1-9][0-9]*)";
        var identifier = "(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)";
        var match = Regex.Match(tag, $"^v(?<base>{number}\\.{number}\\.{number})(?:-(?<pre>{identifier}(?:\\.{identifier})*))?$", RegexOptions.CultureInvariant);
        if (tag.Length > 80 || !match.Success || !Version.TryParse(match.Groups["base"].Value, out var numeric) || numeric.Major > 65535 || numeric.Minor > 65535 || numeric.Build > 65535)
            throw new UpdateValidationException(UpdateFailure.InvalidMetadata, "Update tag must be strict coordinated Windows SemVer.");
        return new(numeric, match.Groups["base"].Value, match.Groups["pre"].Success ? match.Groups["pre"].Value.Split('.') : []);
    }
    public int CompareTo(UpdateVersion? other)
    {
        if (other is null) return 1;
        var numeric = Numeric.CompareTo(other.Numeric);
        if (numeric != 0) return numeric;
        if (Prerelease.Length == 0 || other.Prerelease.Length == 0) return other.Prerelease.Length.CompareTo(Prerelease.Length);
        for (var index = 0; index < Math.Min(Prerelease.Length, other.Prerelease.Length); index++)
        {
            var left = Prerelease[index];
            var right = other.Prerelease[index];
            var leftNumeric = left.All(char.IsAsciiDigit); var rightNumeric = right.All(char.IsAsciiDigit);
            var comparison = leftNumeric && rightNumeric ? left.Length != right.Length ? left.Length.CompareTo(right.Length) : string.CompareOrdinal(left, right)
                : leftNumeric != rightNumeric ? leftNumeric ? -1 : 1 : string.CompareOrdinal(left, right);
            if (comparison != 0) return comparison;
        }
        return Prerelease.Length.CompareTo(other.Prerelease.Length);
    }
}
