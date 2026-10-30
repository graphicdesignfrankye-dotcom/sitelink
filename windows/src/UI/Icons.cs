using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace SiteLink.UI;

/// <summary>Icone della tray disegnate al volo: casa e arco, colorati secondo lo stato.</summary>
public static class Icons
{
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr handle);

    private static readonly Dictionary<LinkState, Icon> Cache = new();

    public static Color ColorFor(LinkState s) => s switch
    {
        LinkState.On => Color.FromArgb(46, 160, 67),
        LinkState.Partial => Color.FromArgb(230, 140, 20),
        LinkState.Off => Color.FromArgb(130, 130, 130),
        _ => Color.FromArgb(170, 170, 170),
    };

    public static Icon For(LinkState s)
    {
        if (Cache.TryGetValue(s, out var ic)) return ic;
        var size = Math.Max(SystemInformation.SmallIconSize.Width, 16) * 2;
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var u = size / 32f;
            using var pen = new Pen(ColorFor(s), 2.6f * u) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
            // arco sopra
            g.DrawArc(pen, 3 * u, 3 * u, 26 * u, 26 * u, 200, 140);
            // casa
            g.DrawPolygon(pen, new[]
            {
                new PointF(9 * u, 16 * u), new PointF(16 * u, 10 * u), new PointF(23 * u, 16 * u),
                new PointF(23 * u, 25 * u), new PointF(9 * u, 25 * u),
            });
            if (s == LinkState.On)
            {
                using var b = new SolidBrush(ColorFor(s));
                g.FillRectangle(b, 14 * u, 19 * u, 4 * u, 6 * u);
            }
        }
        var h = bmp.GetHicon();
        ic = (Icon)Icon.FromHandle(h).Clone();
        DestroyIcon(h);
        Cache[s] = ic;
        return ic;
    }
}
