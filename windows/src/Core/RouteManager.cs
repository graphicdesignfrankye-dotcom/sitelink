namespace SiteLink;

/// <summary>
/// Gestione della route locale verso l'altra sede.
/// Le modifiche partono da attività pianificate "su richiesta" con privilegi elevati,
/// create una volta sola da <see cref="Authorizer"/>: ogni attività esegue un solo comando fisso.
/// </summary>
public static class RouteManager
{
    private static string RouteExe => Path.Combine(Environment.SystemDirectory, "route.exe");

    public static async Task<bool> IsPresentAsync(Site there, Site here)
    {
        if (!Cidr.TryParse(there.Subnet, out var net)) return false;
        try
        {
            var r = await Proc.RunAsync(RouteExe, "print -4").ConfigureAwait(false);
            return r.Code == 0 && HasRoute(r.Out, net.NetworkText, net.MaskText, here.Gateway.Trim());
        }
        catch { return false; }
    }

    /// <summary>Cerca nell'output di "route print -4" la riga: rete, maschera, gateway.</summary>
    public static bool HasRoute(string routePrint, string network, string mask, string gateway)
    {
        foreach (var line in routePrint.Split('\n'))
        {
            var t = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (t.Length >= 3 && t[0] == network && t[1] == mask && t[2] == gateway) return true;
        }
        return false;
    }

    public static Task AddAsync(Site there, Site here) => ApplyAsync("add", there, here, wantPresent: true);
    public static Task RemoveAsync(Site there, Site here) => ApplyAsync("delete", there, here, wantPresent: false);

    private static async Task ApplyAsync(string verb, Site there, Site here, bool wantPresent)
    {
        var r = await Proc.RunAsync("schtasks.exe", $"/run /tn \"{Authorizer.TaskName(verb, there, here)}\"").ConfigureAwait(false);
        if (r.Code != 0)
            throw new AgentException("Permessi route mancanti: usa «Autorizza…» (una volta sola)");
        // L'attività parte in modo asincrono: aspetta che la tabella di routing cambi.
        for (var i = 0; i < 50; i++)
        {
            if (await IsPresentAsync(there, here).ConfigureAwait(false) == wantPresent) return;
            await Task.Delay(200).ConfigureAwait(false);
        }
        throw new AgentException(wantPresent ? "route non aggiunta (controlla il gateway e i permessi)" : "route non rimossa");
    }
}
