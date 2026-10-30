namespace SiteLink.UI;

/// <summary>Icona nella tray: clic sinistro apre il popup, destro il menu.</summary>
public sealed class TrayApp : ApplicationContext
{
    private readonly LinkModel model = new();
    private readonly NotifyIcon tray = new() { Visible = true };
    private readonly PopupForm popup;
    private SetupForm? setup;
    private readonly ToolStripMenuItem autostartItem = new("Avvia con Windows") { CheckOnClick = true };

    public TrayApp()
    {
        popup = new PopupForm(model);
        var menu = new ContextMenuStrip();
        menu.Items.Add("Apri", null, (_, _) => popup.Toggle());
        menu.Items.Add("Impostazioni…", null, (_, _) => model.ShowSetup());
        autostartItem.Checked = Autostart.IsEnabled;
        autostartItem.CheckedChanged += (_, _) => Autostart.IsEnabled = autostartItem.Checked;
        menu.Items.Add(autostartItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Esci", null, (_, _) => Application.Exit());
        tray.ContextMenuStrip = menu;
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) popup.Toggle(); };

        model.Changed += UpdateTray;
        model.SetupRequested += ShowSetup;
        UpdateTray();
        model.Start();
    }

    private void ShowSetup()
    {
        if (setup is { IsDisposed: false }) { setup.Activate(); return; }
        setup = new SetupForm(model);
        setup.Show();
        setup.Activate();
    }

    private void UpdateTray()
    {
        tray.Icon = Icons.For(model.State);
        var state = model.State switch { LinkState.On => "Connesso", LinkState.Off => "Disconnesso", LinkState.Partial => "Parziale", _ => "Stato sconosciuto" };
        var text = "SiteLink — " + state + (model.Local != null ? $" ({model.Local.Name})" : "");
        tray.Text = text.Length > 120 ? text[..120] : text;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { tray.Visible = false; tray.Dispose(); popup.Dispose(); }
        base.Dispose(disposing);
    }
}
