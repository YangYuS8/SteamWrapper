namespace SteamWrapper.Manager;

internal readonly record struct InitialWindowBounds(int X, int Y, int Width, int Height);

// Pure initial-placement calculation, separate from native window operations.
internal static class InitialWindowPlacement
{
    internal static InitialWindowBounds CalculateForDisplay(double rasterizationScale,
        int displayX, int displayY, int workX, int workY, int workWidth, int workHeight, int currentX, int currentY)
    {
        // DisplayArea.WorkArea offsets are relative to OuterBounds; AppWindow uses screen coordinates.
        var absoluteX = checked(displayX + workX);
        var absoluteY = checked(displayY + workY);
        return Calculate(rasterizationScale, absoluteX, absoluteY, workWidth, workHeight, currentX, currentY);
    }

    internal static InitialWindowBounds Calculate(double rasterizationScale,
        int workX, int workY, int workWidth, int workHeight, int currentX, int currentY)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(workWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(workHeight);
        var scale = double.IsFinite(rasterizationScale) && rasterizationScale > 0 ? rasterizationScale : 1;
        // XAML uses effective pixels; AppWindow placement uses physical screen pixels.
        var width = (int)Math.Max(1, Math.Round(Math.Min(workWidth, 1160 * scale), MidpointRounding.AwayFromZero));
        var height = (int)Math.Max(1, Math.Round(Math.Min(workHeight, 900 * scale), MidpointRounding.AwayFromZero));
        var x = (int)Math.Clamp((long)currentX, workX, (long)workX + workWidth - width);
        var y = (int)Math.Clamp((long)currentY, workY, (long)workY + workHeight - height);
        return new(x, y, width, height);
    }
}
