using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;
using SteamWrapper.Application.Services.Updates;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class UpdatesSecurityTests
{
    [TestMethod]
    public void SignedDuplicatePayloadPropertiesAreRejected()
    {
        using var fixture = new UpdateFixture();
        var bytes = Encoding.UTF8.GetBytes(fixture.Payload().ToJsonString().Replace("\"appId\":\"SteamWrapper\"", "\"appId\":\"SteamWrapper\",\"appId\":\"SteamWrapper\"", StringComparison.Ordinal));
        var error = Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(fixture.Envelope(bytes)));
        Assert.AreEqual(UpdateFailure.InvalidMetadata, error.Failure);
    }

    [TestMethod]
    public void SignatureBindsExactBytesAndPrecedesPayloadParsing()
    {
        using var fixture = new UpdateFixture();
        var payload = Encoding.UTF8.GetBytes(fixture.Payload().ToJsonString());
        var verified = fixture.Verify(fixture.Envelope(payload));
        Assert.IsTrue(verified.IsUpgrade);
        Assert.AreEqual(Convert.ToHexStringLower(SHA256.HashData(payload)), verified.PayloadSha256);
        var changed = JsonNode.Parse(fixture.Envelope(payload))!.AsObject();
        changed["payload"] = Convert.ToBase64String(Encoding.UTF8.GetBytes("not JSON"));
        var invalid = Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(Encoding.UTF8.GetBytes(changed.ToJsonString())));
        Assert.AreEqual(UpdateFailure.InvalidSignature, invalid.Failure);
        var whitespace = JsonNode.Parse(fixture.Envelope(payload))!.AsObject();
        whitespace["payload"] = Convert.ToBase64String(payload.Concat(new byte[] { (byte)' ' }).ToArray());
        Assert.AreEqual(UpdateFailure.InvalidSignature, Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(Encoding.UTF8.GetBytes(whitespace.ToJsonString()))).Failure);
    }

    [TestMethod]
    public void UnknownKeysNonCanonicalEnvelopeAndOversizeInputFailClosed()
    {
        using var fixture = new UpdateFixture();
        var payload = Encoding.UTF8.GetBytes(fixture.Payload().ToJsonString());
        var envelope = JsonNode.Parse(fixture.Envelope(payload))!.AsObject();
        envelope["keyId"] = "not-approved";
        Assert.AreEqual(UpdateFailure.UnknownKey, Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(Encoding.UTF8.GetBytes(envelope.ToJsonString()))).Failure);
        envelope["keyId"] = "fixture";
        envelope["payload"] = Convert.ToBase64String(payload) + " ";
        Assert.AreEqual(UpdateFailure.InvalidEnvelope, Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(Encoding.UTF8.GetBytes(envelope.ToJsonString()))).Failure);
        Assert.AreEqual(UpdateFailure.InvalidEnvelope, Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(new byte[UpdateTrustPolicy.MaximumMetadataBytes + 1])).Failure);
        Assert.ThrowsExactly<ArgumentException>(() => new UpdateTrustPolicy(new Uri("https://updates.example.invalid/preview.json"), "preview", new Dictionary<string, byte[]>(), ["downloads.example.invalid"]));
    }

    [TestMethod]
    public void WrongProductContractsVersionsAndUnsignedInstallerCannotProduceAPlan()
    {
        using var fixture = new UpdateFixture();
        foreach (var change in new Action<JsonObject>[]
        {
            root => root["appId"] = "Unrelated app",
            root => root["platform"] = "win-arm64",
            root => root["channel"] = "stable",
            root => root["release"]!["profileContract"] = 3,
            root => root["release"]!["runnerContract"] = 3,
            root => root["release"]!["deploymentProtocol"] = 2,
            root => root["release"]!["minimumWindowsVersion"] = "10.0.99999.0",
            root => root["release"]!["version"] = "0.3.1",
            root => root["release"]!["tag"] = "v00.3.0-preview.1",
            root => root["release"]!["commit"] = "main",
            root => root["release"]!["artifact"]!["type"] = "portable",
            root => root["release"]!["artifact"]!["authenticodeRequired"] = false,
            root => root["release"]!["artifact"]!["bytes"] = UpdateTrustPolicy.MaximumArtifactBytes + 1,
            root => root["release"]!["artifact"]!["sha256"] = "not-a-hash"
        })
        {
            var payload = fixture.Payload(); change(payload);
            Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(fixture.Envelope(Encoding.UTF8.GetBytes(payload.ToJsonString()))));
        }
        var sameBase = fixture.Payload();
        sameBase["release"]!["tag"] = "v0.2.1-preview.2"; sameBase["release"]!["version"] = "0.2.1";
        Assert.AreEqual(UpdateFailure.IncompatibleProduct, Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(fixture.Envelope(Encoding.UTF8.GetBytes(sameBase.ToJsonString())))).Failure);
    }

    [TestMethod]
    public void ExpiredFutureAndUnboundedIndexesAreRejected()
    {
        using var fixture = new UpdateFixture();
        foreach (var change in new Action<JsonObject>[]
        {
            root => root["expiresAt"] = UpdateFixture.Stamp(fixture.Now),
            root => root["issuedAt"] = UpdateFixture.Stamp(fixture.Now.AddSeconds(1)),
            root => root["expiresAt"] = UpdateFixture.Stamp(fixture.Now.AddDays(8)),
            root => root["issuedAt"] = "2026-10-03T12:00:00+00:00"
        })
        {
            var payload = fixture.Payload(); change(payload);
            Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(fixture.Envelope(Encoding.UTF8.GetBytes(payload.ToJsonString()))));
        }
    }

    [TestMethod]
    public void ArtifactUrlsRequireExplicitHttpsDnsHostsWithoutCredentialsOrFragments()
    {
        using var fixture = new UpdateFixture();
        foreach (var url in new[] { "http://downloads.example.invalid/setup.exe", "https://elsewhere.example.invalid/setup.exe", "https://127.0.0.1/setup.exe", "https://user:secret@downloads.example.invalid/setup.exe", "https://downloads.example.invalid:8443/setup.exe", "https://downloads.example.invalid/setup.exe#fragment", "file:///C:/setup.exe" })
        {
            var payload = fixture.Payload(); payload["release"]!["artifact"]!["url"] = url;
            Assert.AreEqual(UpdateFailure.UnsafeUrl, Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(fixture.Envelope(Encoding.UTF8.GetBytes(payload.ToJsonString())))).Failure);
        }
    }

    [TestMethod]
    public void KeyRingsAcceptOnlyExplicitP256KeysAndRejectRemovedOrWrongCurveKeys()
    {
        using var first = new UpdateFixture();
        using var rotated = new UpdateFixture();
        var overlap = new UpdateTrustPolicy(first.Policy.MetadataUri, "preview", new Dictionary<string, byte[]>
        {
            ["previous"] = first.PublicKey(), ["replacement"] = rotated.PublicKey()
        }, ["downloads.example.invalid"]);
        var verifier = new UpdateMetadataVerifier(overlap);
        var bytes = Encoding.UTF8.GetBytes(first.Payload().ToJsonString());
        Assert.IsTrue(verifier.Verify(first.Envelope(bytes, "previous"), first.Installed, first.Now).IsUpgrade);
        Assert.IsTrue(verifier.Verify(rotated.Envelope(bytes, "replacement"), first.Installed, first.Now).IsUpgrade);
        var removed = new UpdateMetadataVerifier(new UpdateTrustPolicy(first.Policy.MetadataUri, "preview",
            new Dictionary<string, byte[]> { ["replacement"] = rotated.PublicKey() }, ["downloads.example.invalid"]));
        Assert.AreEqual(UpdateFailure.UnknownKey, Assert.ThrowsExactly<UpdateValidationException>(() => removed.Verify(first.Envelope(bytes, "previous"), first.Installed, first.Now)).Failure);
        Assert.AreEqual(UpdateFailure.InvalidSignature, Assert.ThrowsExactly<UpdateValidationException>(() => verifier.Verify(first.Envelope(bytes, "replacement"), first.Installed, first.Now)).Failure);
        using var otherCurve = ECDsa.Create(ECCurve.NamedCurves.nistP384);
        Assert.ThrowsExactly<ArgumentException>(() => new UpdateTrustPolicy(first.Policy.MetadataUri, "preview",
            new Dictionary<string, byte[]> { ["unsupported"] = otherCurve.ExportSubjectPublicKeyInfo() }, ["downloads.example.invalid"]));
        Assert.ThrowsExactly<ArgumentException>(() => new UpdateTrustPolicy(first.Policy.MetadataUri, "preview",
            new Dictionary<string, byte[]> { ["trailing"] = first.PublicKey().Concat(new byte[] { 0 }).ToArray() }, ["downloads.example.invalid"]));
    }

    [TestMethod]
    public void StrictJsonAndSemVerRejectAmbiguityWithoutSuggestingADowngrade()
    {
        using var fixture = new UpdateFixture();
        var encoded = fixture.Envelope();
        var outer = Encoding.UTF8.GetString(encoded);
        Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(Encoding.UTF8.GetBytes(outer.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1", StringComparison.Ordinal))));
        foreach (var json in new[] { "[]", "{}", "{\"schemaVersion\":1,}", "/* comment */" + outer, outer.Insert(1, "\"algorithm\":\"none\",") })
            Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(Encoding.UTF8.GetBytes(json)));
        Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify([0xc3, 0x28]));
        foreach (var tag in new[] { "0.3.0", "v0.3.0+build", "v0.3.0-preview.01", "v65536.0.0", "v0.3.0-" })
        {
            var payload = fixture.Payload(); payload["release"]!["tag"] = tag;
            Assert.ThrowsExactly<UpdateValidationException>(() => fixture.Verify(fixture.Envelope(Encoding.UTF8.GetBytes(payload.ToJsonString()))));
        }
        var verified = new UpdateMetadataVerifier(fixture.Policy).Verify(encoded, fixture.Installed with { ReleaseTag = "v0.4.0-preview.1" }, fixture.Now);
        Assert.IsFalse(verified.IsUpgrade);
        Assert.IsTrue(UpdateVersion.Parse("v0.3.0-preview.10").CompareTo(UpdateVersion.Parse("v0.3.0-preview.9")) > 0);
        Assert.IsTrue(UpdateVersion.Parse("v0.3.0").CompareTo(UpdateVersion.Parse("v0.3.0-preview.10")) > 0);
    }
}

internal sealed class UpdateFixture : IDisposable
{
    private readonly ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    internal DateTimeOffset Now { get; } = new(2026, 10, 3, 12, 0, 0, TimeSpan.Zero);
    internal UpdateTrustPolicy Policy { get; }
    internal UpdateInstallationContext Installed { get; } = new("v0.2.1-preview.1", "win-x64", new Version(10, 0, 26100, 0));
    internal UpdateFixture() => Policy = new(new Uri("https://updates.example.invalid/preview.json"), "preview", new Dictionary<string, byte[]> { ["fixture"] = key.ExportSubjectPublicKeyInfo() }, ["downloads.example.invalid"]);
    internal static string Stamp(DateTimeOffset value) => value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
    internal JsonObject Payload(long sequence = 1) => new()
    {
        ["schemaVersion"] = 1, ["appId"] = "SteamWrapper", ["platform"] = "win-x64", ["channel"] = "preview",
        ["sequence"] = sequence, ["issuedAt"] = Stamp(Now.AddMinutes(-1)), ["expiresAt"] = Stamp(Now.AddHours(1)),
        ["release"] = new JsonObject
        {
            ["tag"] = "v0.3.0-preview.1", ["version"] = "0.3.0", ["commit"] = new string('a', 40), ["minimumWindowsVersion"] = "10.0.26100.0",
            ["profileContract"] = 2, ["runnerContract"] = 2, ["deploymentProtocol"] = 1,
            ["artifact"] = new JsonObject { ["type"] = "installer", ["url"] = "https://downloads.example.invalid/SteamWrapper.exe", ["sha256"] = new string('b', 64), ["bytes"] = 12345, ["authenticodeRequired"] = true }
        }
    };
    internal byte[] PublicKey() => key.ExportSubjectPublicKeyInfo();
    internal byte[] Envelope(byte[] payload, string keyId = "fixture") => JsonSerializer.SerializeToUtf8Bytes(new
    {
        schemaVersion = 1, keyId, payload = Convert.ToBase64String(payload),
        signature = Convert.ToBase64String(key.SignData(payload, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
    });
    internal byte[] Envelope(long sequence = 1) => Envelope(Encoding.UTF8.GetBytes(Payload(sequence).ToJsonString()));
    internal VerifiedUpdateMetadata Verify(byte[] bytes) => new UpdateMetadataVerifier(Policy).Verify(bytes, Installed, Now);
    public void Dispose() => key.Dispose();
}
