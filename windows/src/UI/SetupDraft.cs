namespace SiteLink.UI;

public sealed class SiteForm
{
    public string Name = "", Subnet = "", Gateway = "", Token = "";
}

/// <summary>Dati inseriti nel wizard, con la stessa validazione dell'app Mac.</summary>
public sealed class SetupDraft
{
    public SiteForm A = new(), B = new();
    public string Port = "8765";

    public SetupDraft() { }

    public SetupDraft(AppConfig? cfg)
    {
        if (cfg == null || cfg.Sites.Count != 2) return;
        static SiteForm Form(Site s) => new() { Name = s.Name, Subnet = s.Subnet, Gateway = s.Gateway, Token = s.Token };
        A = Form(cfg.Sites[0]); B = Form(cfg.Sites[1]);
        if (Uri.TryCreate(cfg.Sites[0].AgentUrl, UriKind.Absolute, out var u)) Port = u.Port.ToString();
    }

    public static List<string> Errors(SiteForm f, string label)
    {
        var e = new List<string>();
        if (string.IsNullOrWhiteSpace(f.Name)) e.Add($"{label}: manca il nome");
        var netOk = Cidr.TryParse(f.Subnet, out var net);
        if (!netOk) e.Add($"{label}: rete non valida (esempio 10.0.1.0/24)");
        if (!Cidr.TryParseIp(f.Gateway, out var gw)) e.Add($"{label}: IP del router non valido");
        else if (netOk && !net.Contains(gw)) e.Add($"{label}: l'IP del router non è dentro la rete indicata");
        if (f.Token.Trim().Length < 24) e.Add($"{label}: token troppo corto (almeno 24 caratteri)");
        return e;
    }

    public List<string> AllErrors()
    {
        var e = Errors(A, "Sede 1").Concat(Errors(B, "Sede 2")).ToList();
        if (!int.TryParse(Port, out var p) || p < 1 || p > 65535) e.Add("Porta non valida");
        if (Cidr.TryParse(A.Subnet, out var x) && Cidr.TryParse(B.Subnet, out var y) && x.Network == y.Network)
            e.Add("Le due sedi devono avere reti diverse");
        return e;
    }

    public List<Site> Sites()
    {
        Site Make(SiteForm f)
        {
            var name = f.Name.Trim();
            var slug = new string(name.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());
            var gw = f.Gateway.Trim();
            return new Site { Id = slug.Length == 0 ? "sede" : slug, Name = name, Subnet = f.Subnet.Trim(), Gateway = gw, AgentUrl = $"http://{gw}:{Port.Trim()}", Token = f.Token.Trim() };
        }
        var s = new List<Site> { Make(A), Make(B) };
        if (s[0].Id == s[1].Id) s[1].Id += "2";
        return s;
    }
}
