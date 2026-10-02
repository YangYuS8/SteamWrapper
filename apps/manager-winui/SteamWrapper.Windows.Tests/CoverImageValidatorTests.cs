using System.Buffers.Binary;
using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Manager;
using SteamWrapper.Application.Services;
using Windows.Graphics.Imaging;

namespace SteamWrapper.Windows.Tests;

[TestClass]
public sealed class CoverImageValidatorTests
{
    [TestMethod]
    public async Task ValidPngAndJpegAreFullyDecodedWithWindows()
    {
        using var fixture = new DecoderFixture();
        Assert.IsTrue(await CoverImageValidator.ValidateAsync(fixture.Png("valid.png", 40, 56), default));
        Assert.IsTrue(await CoverImageValidator.ValidateAsync(fixture.Png("wide-boundary.png", 4096, 1), default));
        Assert.IsTrue(await CoverImageValidator.ValidateAsync(await fixture.JpegAsync("portrait.jpg", 40, 56), default));
    }

    [TestMethod]
    public async Task TruncatedPngAndCorruptPayloadsReturnFalse()
    {
        using var fixture = new DecoderFixture();
        var complete = await File.ReadAllBytesAsync(fixture.Png("complete.png", 40, 56));
        // WIC alone accepted this header and incomplete image data, even after pixel extraction.
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("truncated.png", complete[..48]), default));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("missing-end.png", complete[..^12]), default));
        complete[^1] ^= 255;
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("wrong-crc.png", complete), default));
        // All chunk lengths/CRCs are valid; the compressed pixel data has a bad checksum.
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Png("bad-zlib.png", 1, 1, corruptZlib: true), default));
    }

    [TestMethod]
    public async Task TruncatedJpegKeepsThePlaceholder()
    {
        using var fixture = new DecoderFixture();
        var complete = await File.ReadAllBytesAsync(await fixture.JpegAsync("complete.jpg", 40, 56));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("missing-eoi.jpg", complete[..^2]), default));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("incomplete.jpg", complete[..(complete.Length / 2)]), default));
    }

    [TestMethod]
    public async Task CompleteImagesExceedingDimensionOrPixelLimitsAreRejected()
    {
        using var fixture = new DecoderFixture();
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Png("too-wide.png", 4097, 1), default));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Png("too-high.png", 1, 4097), default));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Png("too-many-pixels.png", 3000, 3000), default));
    }

    [TestMethod]
    public async Task MissingUnsupportedEmptyAndOverLimitFilesAreRejected()
    {
        using var fixture = new DecoderFixture();
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(Path.Combine(fixture.Root, "missing.png"), default));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("empty.png", []), default));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("html.png", "<html>unavailable</html>"u8.ToArray()), default));
        var huge = fixture.Write("too-large.png", []);
        using (var input = File.OpenWrite(huge)) input.SetLength(4 * 1024 * 1024 + 1);
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(huge, default));
    }

    [TestMethod]
    public async Task LocalWebpUsesTheAvailableWindowsCodecAndRejectsIncompleteRiff()
    {
        using var fixture = new DecoderFixture();
        // A complete 1x1 VP8 WebP. Optional WIC codecs vary across Windows installations.
        var bytes = Convert.FromBase64String("UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA");
        var path = fixture.Write("local.webp", bytes);
        var supported = false;
        try
        {
            using var input = File.OpenRead(path);
            using var stream = input.AsRandomAccessStream();
            var decoder = await BitmapDecoder.CreateAsync(stream);
            _ = await decoder.GetPixelDataAsync();
            supported = decoder.PixelWidth == 1 && decoder.PixelHeight == 1;
        }
        catch (Exception error) when (error is COMException or NotSupportedException) { }
        Assert.AreEqual(supported, await CoverImageValidator.ValidateAsync(path, default));
        Assert.IsFalse(await CoverImageValidator.ValidateAsync(fixture.Write("truncated.webp", bytes[..^2]), default));
    }

    [TestMethod]
    public async Task PreCancelledValidationPropagatesCancellation()
    {
        using var fixture = new DecoderFixture();
        var path = fixture.Png("valid.png", 40, 56);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAsync<OperationCanceledException>(() => CoverImageValidator.ValidateAsync(path, cancellation.Token));
    }

    [TestMethod]
    public async Task OfficialDownloadUsesProductionDecoderAndCacheRemainsAvailableOffline()
    {
        using var fixture = new DecoderFixture();
        var jpeg = await File.ReadAllBytesAsync(await fixture.JpegAsync("official.jpg", 40, 56));
        var handler = new ImageResponseHandler(jpeg, "image/jpeg");
        using var covers = new CoverService(new DataPaths(Path.Combine(fixture.Root, "data")), CoverImageValidator.ValidateAsync, handler);
        var game = new SteamGame("480", "Isolated game", fixture.Root, null);
        var downloaded = await covers.ResolveAsync(game, true);
        Assert.IsNotNull(downloaded);
        StringAssert.EndsWith(downloaded, ".cover");
        CollectionAssert.AreEqual(jpeg, await File.ReadAllBytesAsync(downloaded));
        Assert.AreEqual(downloaded, await covers.ResolveAsync(game, false));
        Assert.AreEqual(1, handler.Requests);
    }

    [TestMethod]
    public async Task CorruptOfficialImageNeverEntersTheCache()
    {
        using var fixture = new DecoderFixture();
        var corrupt = await File.ReadAllBytesAsync(fixture.Png("corrupt.png", 1, 1, corruptZlib: true));
        var handler = new ImageResponseHandler(corrupt, "image/png");
        var paths = new DataPaths(Path.Combine(fixture.Root, "data"));
        using var covers = new CoverService(paths, CoverImageValidator.ValidateAsync, handler);
        var game = new SteamGame("480", "Isolated game", fixture.Root, null);
        Assert.IsNull(await covers.ResolveAsync(game, true));
        Assert.IsNull(await covers.ResolveAsync(game, true));
        Assert.AreEqual(1, handler.Requests);
        Assert.IsEmpty(Directory.GetFiles(paths.CacheDirectory, "*.cover*", SearchOption.AllDirectories));
    }
}

internal sealed class ImageResponseHandler(byte[] bytes, string mediaType) : HttpMessageHandler
{
    public int Requests { get; private set; }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Requests++;
        Assert.AreEqual("https", request.RequestUri!.Scheme);
        Assert.AreEqual("shared.steamstatic.com", request.RequestUri.Host);
        var content = new ByteArrayContent(bytes);
        content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content, RequestMessage = request });
    }
}

internal sealed class DecoderFixture : IDisposable
{
    private static readonly string Base = Path.Combine(Path.GetTempPath(), "SteamWrapper-native-cover-tests");
    public string Root { get; } = Path.Combine(Base, Guid.NewGuid().ToString("N"));
    public DecoderFixture() => Directory.CreateDirectory(Root);

    public string Write(string name, byte[] bytes)
    {
        var path = Path.Combine(Root, name);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    public string Png(string name, uint width, uint height, bool corruptZlib = false)
    {
        var path = Path.Combine(Root, name);
        using var output = File.Create(path);
        output.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        byte[] header = new byte[13];
        BinaryPrimitives.WriteUInt32BigEndian(header, width);
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(4), height);
        header[8] = 8; header[9] = 6;
        Chunk(output, "IHDR", header);
        using var compressed = new MemoryStream();
        using (var encoder = new ZLibStream(compressed, CompressionLevel.SmallestSize, true))
        {
            var row = new byte[checked((int)width * 4 + 1)];
            for (var y = 0; y < height; y++) encoder.Write(row);
        }
        var encoded = compressed.ToArray();
        if (corruptZlib) encoded[^1] ^= 255;
        Chunk(output, "IDAT", encoded);
        Chunk(output, "IEND", []);
        return path;
    }

    public async Task<string> JpegAsync(string name, uint width, uint height)
    {
        var path = Path.Combine(Root, name);
        using var output = File.Create(path);
        using var stream = output.AsRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, width, height, 96, 96, new byte[checked((int)(width * height * 4))]);
        await encoder.FlushAsync();
        return path;
    }

    private static void Chunk(Stream output, string type, byte[] payload)
    {
        Span<byte> value = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(value, (uint)payload.Length);
        output.Write(value);
        var body = Encoding.ASCII.GetBytes(type).Concat(payload).ToArray();
        output.Write(body);
        uint crc = uint.MaxValue;
        foreach (var item in body)
        {
            crc ^= item;
            for (var bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320);
        }
        BinaryPrimitives.WriteUInt32BigEndian(value, ~crc);
        output.Write(value);
    }

    public void Dispose()
    {
        if (!Path.GetFullPath(Root).StartsWith(Path.GetFullPath(Base) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Native image fixture cleanup escaped its root.");
        Directory.Delete(Root, recursive: true);
    }
}
