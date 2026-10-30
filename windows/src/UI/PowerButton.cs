using System.Drawing.Drawing2D;

namespace SiteLink.UI;

/// <summary>Grande pulsante rotondo con il simbolo di accensione.</summary>
public sealed class PowerButton : Control
{
    private Color tint = Color.Gray;
    private bool busy;

    public Color Tint { get => tint; set { tint = value; Invalidate(); } }
    public bool Busy { get => busy; set { busy = value; Invalidate(); } }

    public PowerButton()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
        Size = new Size(100, 100);
        Cursor = Cursors.Hand;
    }

    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Cursor = Enabled ? Cursors.Hand : Cursors.Default; Invalidate(); }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Parent?.BackColor ?? BackColor);
        var c = Enabled ? tint : Color.FromArgb(160, tint);
        var r = new RectangleF(3, 3, Width - 7, Height - 7);
        using (var fill = new SolidBrush(Color.FromArgb(Enabled ? 40 : 20, c))) g.FillEllipse(fill, r);
        using (var ring = new Pen(c, 3f)) g.DrawEllipse(ring, r);

        if (busy)
        {
            using var f = new Font("Segoe UI", 18f, FontStyle.Bold);
            TextRenderer.DrawText(g, "…", f, Rectangle.Round(r), c, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            return;
        }
        using var pen = new Pen(c, 5f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        var cx = Width / 2f; var cy = Height / 2f; var rad = Width * 0.2f;
        g.DrawArc(pen, cx - rad, cy - rad + 3, rad * 2, rad * 2, -60, 300);
        g.DrawLine(pen, cx, cy - rad - 2, cx, cy + 2);
    }
}
