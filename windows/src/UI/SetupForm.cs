namespace SiteLink.UI;

/// <summary>Configurazione guidata in 3 passi (stessi campi e testi dell'app Mac).</summary>
public sealed class SetupForm : Form
{
    private readonly LinkModel model;
    private readonly SetupDraft draft = new(TryLoad());
    private readonly Panel[] steps = { new(), new(), new() };
    private readonly TextBox[] boxes = new TextBox[9];   // 0-3 sede 1, 4-7 sede 2, 8 porta
    private readonly Label lblErrors = new() { AutoSize = false, ForeColor = Color.FromArgb(200, 110, 0), Location = new Point(0, 392), Size = new Size(480, 50) };
    private readonly Button btnNext = new() { Text = "Avanti", Size = new Size(110, 32) };
    private readonly FlowLayoutPanel results = new() { FlowDirection = FlowDirection.TopDown, WrapContents = false, Location = new Point(0, 44), Size = new Size(480, 270), AutoScroll = true };
    private readonly Label lblTesting = new() { Text = "Provo la connessione…", AutoSize = true, Location = new Point(0, 44), Visible = false };
    private readonly Button btnSave = new() { Text = "Salva e chiudi", Size = new Size(130, 32), Enabled = false };
    private readonly CheckBox chkAutostart = new() { Text = "Avvia SiteLink all'accesso a Windows", AutoSize = true, Checked = true };
    private int step;
    private bool saving;

    private static AppConfig? TryLoad() { try { return AppConfig.Load(); } catch { return null; } }

    public SetupForm(LinkModel model)
    {
        this.model = model;
        Text = "Configura SiteLink";
        Font = new Font("Segoe UI", 9.5f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(520, 560);
        BackColor = Color.White;

        foreach (var p in steps) { p.Location = new Point(20, 20); p.Size = new Size(480, 520); p.Visible = false; Controls.Add(p); }
        BuildIntro(steps[0]);
        BuildForm(steps[1]);
        BuildTest(steps[2]);
        Show(0);
    }

    private void Show(int n)
    {
        step = n;
        for (var i = 0; i < steps.Length; i++) steps[i].Visible = i == n;
    }

    private static Label Title(string t) => new() { Text = t, Font = new Font("Segoe UI", 15f, FontStyle.Bold), AutoSize = true, Location = new Point(0, 0) };

    private static Label Para(string t, int y, int h, Color? c = null) =>
        new() { Text = t, Location = new Point(0, y), Size = new Size(480, h), ForeColor = c ?? Color.Black };

    private void BuildIntro(Panel p)
    {
        p.Controls.Add(Title("Benvenuto in SiteLink"));
        p.Controls.Add(Para("Questa app accende e spegne il collegamento tra due sedi, per esempio il tuo ufficio e casa. Prima di configurarla, deve essere già stato fatto tutto il resto:", 44, 56));
        p.Controls.Add(Para(
            "•  Su ciascun router che collega la sede (uno per sede) è installato e funzionante l'agent SiteLink.\n\n" +
            "•  I due agent sono configurati per raggiungersi tra loro (peer).\n\n" +
            "•  Il collegamento tra le due reti (VPN) è già configurato sui router e le route verso l'altra sede sono pronte.\n\n" +
            "•  Questo PC non è già collegato all'altra rete con una VPN installata sul computer: il collegamento passa dalla route che SiteLink aggiunge.", 108, 230));
        p.Controls.Add(Para("Ti serviranno, per ogni sede: un nome, la rete (es. 10.0.1.0/24), l'IP del router con l'agent e il token dell'agent.", 350, 50, Color.DimGray));
        var next = new Button { Text = "Continua", Size = new Size(110, 32), Location = new Point(370, 470) };
        next.Click += (_, _) => Show(1);
        p.Controls.Add(next);
        AcceptButton = next;
    }

    private void BuildForm(Panel p)
    {
        p.Controls.Add(Title("Le due sedi"));
        Group(p, "Sede 1", 0, 40, draft.A, "Ufficio", "10.0.1.0/24", "10.0.1.31");
        Group(p, "Sede 2", 4, 190, draft.B, "Casa", "10.0.2.0/24", "10.0.2.2");
        var l = new Label { Text = "Porta degli agent", Location = new Point(0, 346), AutoSize = true };
        boxes[8] = new TextBox { Location = new Point(190, 342), Width = 80, Text = draft.Port };
        boxes[8].TextChanged += (_, _) => { draft.Port = boxes[8].Text; Validate(); };
        p.Controls.AddRange(new Control[] { l, boxes[8], lblErrors });
        var back = new Button { Text = "Indietro", Size = new Size(110, 32), Location = new Point(0, 470) };
        back.Click += (_, _) => Show(0);
        btnNext.Location = new Point(370, 470);
        btnNext.Click += async (_, _) => { Show(2); await RunTestAsync(); };
        p.Controls.Add(back);
        p.Controls.Add(btnNext);
        Validate();
    }

    private void Group(Panel p, string title, int first, int top, SiteForm f, string nameHint, string netHint, string gwHint)
    {
        var g = new GroupBox { Text = title, Location = new Point(0, top), Size = new Size(480, 140) };
        void Row(int i, string label, string value, int y, string hint, Action<string> set, bool secret = false)
        {
            g.Controls.Add(new Label { Text = label, Location = new Point(12, y + 3), AutoSize = true });
            var t = new TextBox { Location = new Point(190, y), Width = 275, Text = value, PlaceholderText = hint, UseSystemPasswordChar = secret };
            t.TextChanged += (_, _) => { set(t.Text); Validate(); };
            boxes[first + i] = t;
            g.Controls.Add(t);
        }
        Row(0, "Nome", f.Name, 24, nameHint, v => f.Name = v);
        Row(1, "Rete", f.Subnet, 54, netHint, v => f.Subnet = v);
        Row(2, "IP del router (agent)", f.Gateway, 84, gwHint, v => f.Gateway = v);
        Row(3, "Token", f.Token, 112, "", v => f.Token = v, secret: true);
        p.Controls.Add(g);
    }

    private new void Validate()
    {
        var errs = draft.AllErrors();
        var pristine = draft.A.Name == "" && draft.B.Name == "" && draft.A.Token == "" && draft.B.Token == "";
        lblErrors.Text = pristine ? "" : string.Join("\n", errs.Take(3));
        btnNext.Enabled = errs.Count == 0;
    }

    private void BuildTest(Panel p)
    {
        p.Controls.Add(Title("Prova e salvataggio"));
        p.Controls.Add(lblTesting);
        p.Controls.Add(results);
        p.Controls.Add(Para("Dopo il salvataggio Windows chiederà la conferma dell'amministratore (UAC), una sola volta, per autorizzare le route.", 400, 40, Color.DimGray));
        chkAutostart.Location = new Point(0, 442);
        p.Controls.Add(chkAutostart);
        var back = new Button { Text = "Indietro", Size = new Size(110, 32), Location = new Point(0, 476) };
        back.Click += (_, _) => { if (!saving) Show(1); };
        btnSave.Location = new Point(350, 476);
        btnSave.Click += async (_, _) => await SaveAsync();
        p.Controls.Add(back);
        p.Controls.Add(btnSave);
    }

    private void AddLine(bool? ok, string text)
    {
        var glyph = ok == true ? "✔" : ok == false ? "✖" : "ℹ";
        var color = ok == true ? Color.SeaGreen : ok == false ? Color.IndianRed : Color.Gray;
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 0, 0, 8) };
        row.Controls.Add(new Label { Text = glyph, ForeColor = color, AutoSize = true, Font = new Font("Segoe UI Symbol", 11f), Margin = new Padding(0, 0, 8, 0) });
        var l = new Label { Text = text, AutoSize = false, Width = 440, Margin = new Padding(0) };
        l.Height = TextRenderer.MeasureText(text, l.Font, new Size(440, 0), TextFormatFlags.WordBreak).Height + 4;
        row.Controls.Add(l);
        results.Controls.Add(row);
        if (ok == false) { btnSave.Text = "Salva comunque"; }
    }

    private async Task RunTestAsync()
    {
        lblTesting.Visible = true;
        btnSave.Enabled = false; btnSave.Text = "Salva e chiudi";
        results.Controls.Clear();
        var sites = draft.Sites();
        var ips = NetInfo.Ipv4Addresses();
        var here = sites.FirstOrDefault(s => Cidr.TryParse(s.Subnet, out var n) && ips.Any(n.Contains));
        if (here == null)
        {
            AddLine(null, "Questo PC non è collegato a nessuna delle due reti, quindi non posso provare ora. Puoi salvare: la prova vera avverrà alla prima apertura in una delle due sedi.");
        }
        else
        {
            AddLine(null, $"Questo PC è nella sede «{here.Name}».");
            try
            {
                var st = await new AgentClient(here, 6).StatusAsync();
                AddLine(true, $"L'agent di «{here.Name}» risponde e il token è corretto (VPN {(st.VpnUp ? "attiva" : "spenta")}).");
                try
                {
                    await new AgentClient(here, 12, viaPeer: true).StatusAsync();
                    AddLine(true, "L'altra sede risponde tramite l'agent: i due router sono collegati tra loro.");
                }
                catch (Exception e) { AddLine(false, $"L'altra sede non risponde: {e.Message}. Controlla la configurazione peer sui router."); }
            }
            catch (Exception e) { AddLine(false, $"{e.Message}. Controlla IP, porta e token."); }
        }
        lblTesting.Visible = false;
        btnSave.Enabled = true;
    }

    private async Task SaveAsync()
    {
        saving = true; btnSave.Enabled = false;
        var cfg = new AppConfig { Sites = draft.Sites(), PollSeconds = 10, ControlRemoteAgent = true };
        try { cfg.Save(); }
        catch (Exception e)
        {
            AddLine(false, $"Impossibile salvare la configurazione: {e.Message}");
            saving = false; btnSave.Enabled = true;
            return;
        }
        Autostart.IsEnabled = chkAutostart.Checked;
        Close();
        await model.AfterSetupAsync();
    }
}
