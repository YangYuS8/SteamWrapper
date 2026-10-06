using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Manager;

namespace SteamWrapper.Windows.Tests;

[TestClass]
public sealed class InitialWindowPlacementTests
{
    [TestMethod]
    [DataRow(1.0, 1160, 900)]
    [DataRow(1.25, 1450, 1125)]
    [DataRow(1.5, 1740, 1344)]
    [DataRow(2.0, 2320, 1344)]
    public void InitialSizeUsesActualScaleAndAvailableWorkArea(double scale, int width, int height)
    {
        var bounds = InitialWindowPlacement.Calculate(scale, 0, 0, 2560, 1344, 288, 288);
        Assert.AreEqual(width, bounds.Width);
        Assert.AreEqual(height, bounds.Height);
        AssertInside(bounds, 0, 0, 2560, 1344);
    }

    [TestMethod]
    public void TwoHundredPercentColdStartPreservesEffectiveWidthAndKeepsAllEdgesOnScreen()
    {
        var bounds = InitialWindowPlacement.Calculate(2, 0, 0, 2560, 1344, 288, 288);
        Assert.AreEqual(new InitialWindowBounds(240, 0, 2320, 1344), bounds);
        Assert.AreEqual(1160, bounds.Width / 2);
        AssertInside(bounds, 0, 0, 2560, 1344);
    }

    [TestMethod]
    [DataRow(-1920, 40, 1920, 1040, 600, 600, -1160, 180)]
    [DataRow(2560, -1440, 2560, 1344, -100, -2000, 2560, -1440)]
    [DataRow(0, 0, 2560, 1344, 3000, 3000, 1400, 444)]
    public void PositionUsesTheActualWorkAreaOrigin(int x, int y, int width, int height,
        int currentX, int currentY, int expectedX, int expectedY)
    {
        var bounds = InitialWindowPlacement.Calculate(1, x, y, width, height, currentX, currentY);
        Assert.AreEqual(expectedX, bounds.X);
        Assert.AreEqual(expectedY, bounds.Y);
        AssertInside(bounds, x, y, width, height);
    }

    [TestMethod]
    public void SmallWorkAreaLimitsBothDimensionsWithoutLeavingAnyEdgeOutside()
    {
        var bounds = InitialWindowPlacement.Calculate(2, 40, 80, 640, 360, 200, 300);
        Assert.AreEqual(new InitialWindowBounds(40, 80, 640, 360), bounds);
    }

    [TestMethod]
    [DataRow(0.0)]
    [DataRow(-1.0)]
    [DataRow(double.NaN)]
    [DataRow(double.PositiveInfinity)]
    [DataRow(double.NegativeInfinity)]
    public void UnavailableScaleFallsBackToOneHundredPercent(double scale)
    {
        var bounds = InitialWindowPlacement.Calculate(scale, 0, 0, 2560, 1344, 288, 288);
        Assert.AreEqual(new InitialWindowBounds(288, 288, 1160, 900), bounds);
    }

    [TestMethod]
    [DataRow(0, 1344)]
    [DataRow(-1, 1344)]
    [DataRow(2560, 0)]
    [DataRow(2560, -1)]
    public void InvalidWorkAreaIsRejectedBeforeNativePlacement(int width, int height)
    {
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() =>
            InitialWindowPlacement.Calculate(1, 0, 0, width, height, 0, 0));
    }

    [TestMethod]
    public void AFiniteScaleCannotOverflowIntoNegativeNativeDimensions()
    {
        var bounds = InitialWindowPlacement.Calculate(double.MaxValue, 0, 0, 2560, 1344, 288, 288);
        Assert.AreEqual(new InitialWindowBounds(0, 0, 2560, 1344), bounds);
    }

    [TestMethod]
    public void PositionClampingDoesNotOverflowAtTheCoordinateBoundary()
    {
        var bounds = InitialWindowPlacement.Calculate(1, int.MaxValue - 1000, int.MinValue, 1000, 1000,
            int.MinValue, int.MaxValue);
        Assert.AreEqual(new InitialWindowBounds(int.MaxValue - 1000, int.MinValue + 100, 1000, 900), bounds);
        AssertInside(bounds, int.MaxValue - 1000, int.MinValue, 1000, 1000);
    }

    [TestMethod]
    public void DisplayRelativeLeftTaskbarKeepsTheWindowOnANegativeMonitor()
    {
        var bounds = InitialWindowPlacement.CalculateForDisplay(1,
            -1920, 0, 48, 0, 1872, 1040, -1600, 100);
        Assert.AreEqual(new InitialWindowBounds(-1600, 100, 1160, 900), bounds);
        AssertInside(bounds, -1872, 0, 1872, 1040);
    }

    [TestMethod]
    public void DisplayRelativeTopTaskbarCombinesBothNegativeMonitorAxes()
    {
        var bounds = InitialWindowPlacement.CalculateForDisplay(1,
            -1920, -1080, 0, 40, 1920, 1040, -100, -900);
        Assert.AreEqual(new InitialWindowBounds(-1160, -900, 1160, 900), bounds);
        AssertInside(bounds, -1920, -1040, 1920, 1040);
    }

    [TestMethod]
    public void DisplayRelativeTopTaskbarClampsHighDpiPlacementOnAPositiveMonitor()
    {
        var bounds = InitialWindowPlacement.CalculateForDisplay(2,
            2560, 0, 0, 48, 2560, 1392, 2700, 120);
        Assert.AreEqual(new InitialWindowBounds(2700, 48, 2320, 1392), bounds);
        AssertInside(bounds, 2560, 48, 2560, 1392);
    }

    [TestMethod]
    public void DisplayRelativePrimaryOriginRetainsTheExistingPlacement()
    {
        var bounds = InitialWindowPlacement.CalculateForDisplay(2,
            0, 0, 0, 0, 2560, 1344, 288, 288);
        Assert.AreEqual(new InitialWindowBounds(240, 0, 2320, 1344), bounds);
    }

    [TestMethod]
    [DataRow(int.MaxValue, 0, 1, 0)]
    [DataRow(int.MinValue, 0, -1, 0)]
    [DataRow(0, int.MaxValue, 0, 1)]
    [DataRow(0, int.MinValue, 0, -1)]
    public void DisplayRelativeOriginOverflowIsRejectedBeforeNativePlacement(int displayX, int displayY, int workX, int workY)
    {
        Assert.ThrowsExactly<OverflowException>(() => InitialWindowPlacement.CalculateForDisplay(1,
            displayX, displayY, workX, workY, 2560, 1344, 0, 0));
    }

    private static void AssertInside(InitialWindowBounds bounds, int x, int y, int width, int height)
    {
        Assert.IsGreaterThan(0, bounds.Width);
        Assert.IsGreaterThan(0, bounds.Height);
        Assert.IsTrue(bounds.X >= x && bounds.Y >= y);
        Assert.IsTrue((long)bounds.X + bounds.Width <= (long)x + width);
        Assert.IsTrue((long)bounds.Y + bounds.Height <= (long)y + height);
    }
}
