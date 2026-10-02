using System.Buffers.Binary;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Windows.Graphics.Imaging;

namespace SteamWrapper.Manager;

/// <summary>Validate encoded files with Windows' decoder before caching or displaying them.</summary>
internal static class CoverImageValidator
{
    private static readonly uint[] CrcTable = CreateCrcTable();

    public static async Task<bool> ValidateAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.Asynchronous);
            if (input.Length is <= 0 or > 4 * 1024 * 1024) return false;
            var encoded = new byte[(int)input.Length];
            await input.ReadExactlyAsync(encoded, cancellationToken);
            // WIC can fill missing pixels and accept truncated images. Check the complete
            // encoded container as well as decoding it; never cache those partial images.
            if (!await Task.Run(() => IsCompleteImage(encoded, cancellationToken), cancellationToken)) return false;
            input.Position = 0;
            using var stream = input.AsRandomAccessStream();
            var decoder = await BitmapDecoder.CreateAsync(stream).AsTask(cancellationToken);
            if (decoder.FrameCount != 1 || decoder.PixelWidth is 0 or > 4096 || decoder.PixelHeight is 0 or > 4096 ||
                (ulong)decoder.PixelWidth * decoder.PixelHeight > 8_000_000) return false;
            // Header recognition alone does not prove that the image payload can be decoded.
            var pixels = await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied,
                new BitmapTransform(), ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.DoNotColorManage).AsTask(cancellationToken);
            var bytes = pixels.DetachPixelData();
            cancellationToken.ThrowIfCancellationRequested();
            return (ulong)bytes.Length == (ulong)decoder.PixelWidth * decoder.PixelHeight * 4;
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or COMException or ArgumentException or NotSupportedException)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return false;
        }
    }

    private static bool IsCompleteImage(byte[] bytes, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var data = bytes.AsSpan();
        if (data.StartsWith(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })) return CompletePng(data, cancellationToken);
        if (data.StartsWith(new byte[] { 0xFF, 0xD8 })) return CompleteJpeg(data, cancellationToken);
        return data.Length >= 20 && data[..4].SequenceEqual("RIFF"u8) && data[8..12].SequenceEqual("WEBP"u8)
            && (ulong)BinaryPrimitives.ReadUInt32LittleEndian(data[4..8]) + 8 == (ulong)data.Length;
    }

    private static bool CompletePng(ReadOnlySpan<byte> data, CancellationToken cancellationToken)
    {
        var offset = 8;
        uint width = 0, height = 0;
        byte depth = 0, color = 0, interlace = 0;
        using var compressed = new MemoryStream();
        while (offset <= data.Length - 12)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var length = BinaryPrimitives.ReadUInt32BigEndian(data[offset..]);
            if (length > (uint)(data.Length - offset - 12)) return false;
            var type = data.Slice(offset + 4, 4);
            var payload = data.Slice(offset + 8, (int)length);
            var crc = uint.MaxValue;
            foreach (var value in data.Slice(offset + 4, checked((int)length + 4)))
                crc = CrcTable[(crc ^ value) & 255] ^ (crc >> 8);
            if (~crc != BinaryPrimitives.ReadUInt32BigEndian(data.Slice(offset + 8 + (int)length, 4))) return false;
            if (offset == 8)
            {
                if (!type.SequenceEqual("IHDR"u8) || length != 13) return false;
                width = BinaryPrimitives.ReadUInt32BigEndian(payload);
                height = BinaryPrimitives.ReadUInt32BigEndian(payload[4..]);
                depth = payload[8]; color = payload[9]; interlace = payload[12];
                if (width is 0 or > 4096 || height is 0 or > 4096 || (ulong)width * height > 8_000_000 ||
                    payload[10] != 0 || payload[11] != 0 || interlace > 1) return false;
            }
            else if (type.SequenceEqual("IHDR"u8)) return false;
            if (type.SequenceEqual("IDAT"u8)) compressed.Write(payload);
            offset += (int)length + 12;
            if (type.SequenceEqual("IEND"u8))
            {
                if (length != 0 || offset != data.Length || compressed.Length == 0) return false;
                return ValidPngPixels(compressed, width, height, depth, color, interlace, cancellationToken);
            }
        }
        return false;
    }

    private static bool ValidPngPixels(MemoryStream compressed, uint width, uint height, byte depth, byte color, byte interlace, CancellationToken cancellationToken)
    {
        var channels = color switch { 0 or 3 => 1, 2 => 3, 4 => 2, 6 => 4, _ => 0 };
        if (channels == 0 || (color is 2 or 4 or 6 ? depth is not (8 or 16) : color == 3 ? depth is not (1 or 2 or 4 or 8) : depth is not (1 or 2 or 4 or 8 or 16))) return false;
        compressed.Position = 0;
        using var pixels = new ZLibStream(compressed, CompressionMode.Decompress, true);
        var row = new byte[checked((int)(((ulong)width * (uint)channels * depth + 7) / 8))];
        // Adam7 interlaced PNGs contain seven smaller sets of scanlines.
        (uint X, uint Y, uint StepX, uint StepY)[] passes = interlace == 0
            ? [(0, 0, 1, 1)] : [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)];
        foreach (var pass in passes)
        {
            var columns = width <= pass.X ? 0 : (width - pass.X + pass.StepX - 1) / pass.StepX;
            var rows = height <= pass.Y ? 0 : (height - pass.Y + pass.StepY - 1) / pass.StepY;
            if (columns == 0 || rows == 0) continue;
            var count = checked((int)(((ulong)columns * (uint)channels * depth + 7) / 8));
            for (var y = 0; y < rows; y++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (pixels.ReadByte() is < 0 or > 4) return false;
                pixels.ReadExactly(row.AsSpan(0, count));
            }
        }
        return pixels.ReadByte() == -1;
    }

    private static bool CompleteJpeg(ReadOnlySpan<byte> data, CancellationToken cancellationToken)
    {
        var offset = 2;
        var scan = false;
        while (offset < data.Length)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (data[offset++] != 255) return false;
            while (offset < data.Length && data[offset] == 255) offset++;
            if (offset >= data.Length) return false;
            var marker = data[offset++];
            if (marker == 0xD9) return scan && offset == data.Length;
            if (marker is 0 or 0xD8 or >= 0xD0 and <= 0xD7) return false;
            if (marker == 1) continue;
            if (offset > data.Length - 2) return false;
            var length = BinaryPrimitives.ReadUInt16BigEndian(data[offset..]);
            if (length < 2 || length > data.Length - offset) return false;
            offset += length;
            if (marker != 0xDA) continue;
            scan = true;
            while (offset < data.Length)
            {
                if ((offset & 0x3FFF) == 0) cancellationToken.ThrowIfCancellationRequested();
                if (data[offset] != 255) { offset++; continue; }
                if (offset + 1 >= data.Length) return false;
                var next = data[offset + 1];
                if (next is 0 or >= 0xD0 and <= 0xD7) { offset += 2; continue; }
                break;
            }
        }
        return false;
    }

    private static uint[] CreateCrcTable()
    {
        var table = new uint[256];
        for (uint index = 0; index < table.Length; index++)
        {
            var crc = index;
            for (var bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320);
            table[index] = crc;
        }
        return table;
    }
}
