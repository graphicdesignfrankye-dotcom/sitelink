namespace SiteLink.UI;

/// <summary>Finestra a comparsa vicino alla tray: pulsante grande, stato delle due sedi, comandi.</summary>
public sealed class PopupForm : Form
{
    private readonly LinkModel model;
    private readonly Label lblSite = Lbl(9f, FontStyle.Regular, Color.DimGray);
    private readonly PowerButton power = new();
    private readonly Label lblTitle = Lbl(14f, FontStyle.Bold, Color.Black);
    private readonly Label lblNotConfigured = Lbl(9f, FontStyle.Regular, Color.DimGray);
    private readonly Button btnConfigure = new() { Text = "Configura…", AutoSize = true };
    private readonly Label lblSetup = Lbl(9f, FontStyle.Regular, Color.Black);
    private readonly Button btnAuthorize = new() { Text = "Autorizza…", AutoSize = true };
    private readonly TableLayoutPanel rows = new() { AutoSize = true, ColumnCount = 3, Dock = DockStyle.Top };
    private readonly Label lblMessage = Lbl(9f, FontStyle.Regular, Color.FromArgb(200, 110, 0));
    private readonly FlowLayoutPanel stack = new() { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink };
    private DateTime hiddenAt = DateTime.MinValue;

    private const int W = 270;

    public PopupForm(LinkModel model)
    {
        this.model = model;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        BackColor = Color.White;
        Padding = new Padding(16);
        Font = new Font("Segoe UI", 9f);

        foreach (var l in new[] { lblSite, lblTitle, lblNotConfigured, lblSetup, lblMessage })
        {
            l.AutoSize = false; l.Width = W; l.TextAlign = ContentAlignment.MiddleCenter;
        }
        lblSite.Height = 20; lblTitle.Height = 32;
        power.Margin = new Padding((W - 100) / 2, 4, 0, 4);
        power.BackColor = BackColor;
        power.Click += async (_, _) => await model.SetLinkAsync(model.State != LinkState.On);
        btnConfigure.Click += (_, _) => { Hide(); model.ShowSetup(); };
        btnAuthorize.Click += async (_, _) => { Hide(); await model.AuthorizeRoutesAsync(); };

        rows.Width = W; rows.Margin = new Padding(0, 8, 0, 4);
        rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 18));
        rows.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        rows.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var sep = new Label { Height = 1, Width = W, BackColor = Color.Gainsboro, Margin = new Padding(0, 8, 0, 6) };
        var bottom = new TableLayoutPanel { Width = W, Height = 28, ColumnCount = 3 };
        for (var i = 0; i < 3; i++) bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.3f));
        bottom.Controls.Add(Link("Aggiorna", async () => { model.ActionMessage = null; await model.RefreshAsync(); }), 0, 0);
        bottom.Controls.Add(Link("Impostazioni…", () => { Hide(); model.ShowSetup(); }), 1, 0);
        bottom.Controls.Add(Link("Esci", () => Application.Exit()), 2, 0);

        lblNotConfigured.Text = "SiteLink non è ancora configurato.";
        lblSetup.Text = "Primo avvio: servono i permessi per gestire le route (una volta sola).";
        lblSetup.Height = 36;
        btnConfigure.Margin = new Padding((W - 90) / 2, 0, 0, 0);
        btnAuthorize.Margin = new Padding((W - 90) / 2, 0, 0, 0);

        stack.Controls.AddRange(new Control[] { lblSite, lblNotConfigured, btnConfigure, power, lblTitle, lblSetup, btnAuthorize, rows, lblMessage, sep, bottom });
        Controls.Add(stack);

        Deactivate += (_, _) => { if (Visible) { hiddenAt = DateTime.UtcNow; Hide(); } };
        model.Changed += () => { if (Visible) UpdateView(); };
        UpdateView();
    }

    protected override CreateParams CreateParams
    {
        get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; /* ombra */ return cp; }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using var pen = new Pen(Color.FromArgb(200, 200, 200));
        e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
    }

    /// <summary>Alterna la finestra; ignora il clic sull'icona che ha appena causato la chiusura per perdita del fuoco.</summary>
    public void Toggle()
    {
        if (Visible) { Hide(); return; }
        if ((DateTime.UtcNow - hiddenAt).TotalMilliseconds < 300) return;
        UpdateView();
        PerformLayout();
        var wa = Screen.FromPoint(Cursor.Position).WorkingArea;
        var x = Math.Clamp(Cursor.Position.X - Width / 2, wa.Left + 8, wa.Right - Width - 8);
        var y = Math.Clamp(Cursor.Position.Y - Height - 12, wa.Top + 8, wa.Bottom - Height - 8);
        Location = new Point(x, y);
        Show();
        Activate();
        _ = model.RefreshAsync();
    }

    private void UpdateView()
    {
        var configured = model.ConfigError == null;
        lblNotConfigured.Visible = btnConfigure.Visible = !configured;
        lblSite.Visible = power.Visible = lblTitle.Visible = rows.Visible = configured;
        lblSetup.Visible = btnAuthorize.Visible = configured && model.NeedsSetup;

        lblSite.Text = model.Local != null ? $"Sei in: {model.Local.Name}" : "Fuori dalle sedi";
        power.Tint = Icons.ColorFor(model.State);
        power.Busy = model.Busy;
        power.Enabled = !model.Busy && !model.NeedsSetup && model.Local != null && model.LocalStatus != null;
        lblTitle.Text = model.State switch
        {
            LinkState.On => "Connesso", LinkState.Off => "Disconnesso", LinkState.Partial => "Parziale", _ => "Stato sconosciuto",
        };

        rows.SuspendLayout();
        rows.Controls.Clear();
        rows.RowStyles.Clear();
        if (model.Local != null)
        {
            AddRow(model.Local.Name, model.LocalStatus);
            AddRow(model.Remote?.Name ?? "", model.RemoteStatus);
            AddRow("Route locale", null, model.RoutePresent ? "presente" : "assente", Color.Gray);
        }
        rows.ResumeLayout();

        lblMessage.Text = model.Message ?? "";
        lblMessage.Visible = !string.IsNullOrEmpty(model.Message);
        lblMessage.AutoSize = false;
        lblMessage.Height = lblMessage.Visible ? TextRenderer.MeasureText(lblMessage.Text, lblMessage.Font, new Size(W, 0), TextFormatFlags.WordBreak).Height + 6 : 0;
    }

    private void AddRow(string name, AgentStatus? st, string? text = null, Color? dot = null)
    {
        var color = dot ?? (st == null ? Color.IndianRed : st.LinkEnabled ? Color.SeaGreen : Color.Gray);
        var label = text ?? (st == null ? "offline" : st.LinkEnabled ? "attivo" : "spento");
        var row = rows.RowCount++;
        rows.Controls.Add(new Label { Text = dot == null ? "●" : "", ForeColor = color, AutoSize = true, Margin = new Padding(0, 1, 0, 1) }, 0, row);
        rows.Controls.Add(new Label { Text = name, AutoSize = true, Margin = new Padding(0, 1, 0, 1) }, 1, row);
        rows.Controls.Add(new Label { Text = label, ForeColor = Color.Gray, AutoSize = true, Anchor = AnchorStyles.Right, Margin = new Padding(0, 1, 0, 1) }, 2, row);
    }

    private static Label Lbl(float size, FontStyle style, Color color) =>
        new() { Font = new Font("Segoe UI", size, style), ForeColor = color, Margin = new Padding(0, 2, 0, 2) };

    private static LinkLabel Link(string text, Action click)
    {
        var l = new LinkLabel { Text = text, AutoSize = true, Anchor = AnchorStyles.None, LinkColor = Color.FromArgb(0, 102, 204), ActiveLinkColor = Color.FromArgb(0, 70, 150) };
        l.LinkClicked += (_, _) => click();
        return l;
    }
}
