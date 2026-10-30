namespace SiteLink.UI;

/// <summary>Finestra di installazione di SiteLink-Setup.exe.</summary>
public sealed class InstallerForm : Form
{
    private readonly TextBox dir = new() { Text = Installer.DefaultDir, Location = new Point(20, 128), Width = 440 };
    private readonly CheckBox desktop = new() { Text = "Crea un collegamento sul Desktop", Location = new Point(20, 168), AutoSize = true, Checked = true };
    private readonly CheckBox autostart = new() { Text = "Avvia SiteLink all'accesso a Windows", Location = new Point(20, 194), AutoSize = true, Checked = true };
    private readonly CheckBox launch = new() { Text = "Avvia SiteLink al termine", Location = new Point(20, 220), AutoSize = true, Checked = true };
    private readonly Button install = new() { Text = "Installa", Size = new Size(110, 32), Location = new Point(240, 290) };
    private readonly Button cancel = new() { Text = "Annulla", Size = new Size(110, 32), Location = new Point(360, 290) };
    private readonly Label status = new() { AutoSize = false, Location = new Point(20, 250), Size = new Size(450, 36), ForeColor = Color.DimGray };

    public InstallerForm()
    {
        Text = $"Installazione di SiteLink {Installer.Version}";
        Font = new Font("Segoe UI", 9.5f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(490, 346);
        BackColor = Color.White;
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!);

        Controls.Add(new Label { Text = "Installa SiteLink", Font = new Font("Segoe UI", 16f, FontStyle.Bold), AutoSize = true, Location = new Point(18, 16) });
        Controls.Add(new Label
        {
            Text = "Accende e spegne il collegamento tra due sedi, dalla barra delle applicazioni.\nL'installazione è solo per il tuo utente: non servono permessi di amministratore.",
            Location = new Point(20, 58), Size = new Size(450, 44),
        });
        Controls.Add(new Label { Text = "Cartella di installazione", Location = new Point(20, 106), AutoSize = true });
        Controls.AddRange(new Control[] { dir, desktop, autostart, launch, status, install, cancel });
        AcceptButton = install; CancelButton = cancel;
        cancel.Click += (_, _) => Close();
        install.Click += (_, _) => Run();
    }

    private void Run()
    {
        try
        {
            install.Enabled = cancel.Enabled = false;
            status.Text = "Installazione in corso…";
            Update();
            var d = dir.Text.Trim();
            Installer.Install(d, desktop.Checked, autostart.Checked);
            if (launch.Checked) Installer.Launch(d);
            MessageBox.Show("SiteLink è installato." + (launch.Checked ? "\nCerca l'icona nella barra delle applicazioni (vicino all'orologio): al primo avvio parte la configurazione." : ""),
                "SiteLink", MessageBoxButtons.OK, MessageBoxIcon.Information);
            Close();
        }
        catch (Exception e)
        {
            status.ForeColor = Color.IndianRed;
            status.Text = "Installazione non riuscita: " + e.Message;
            install.Enabled = cancel.Enabled = true;
        }
    }
}
