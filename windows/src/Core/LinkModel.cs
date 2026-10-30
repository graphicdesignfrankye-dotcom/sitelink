using Microsoft.Win32;

namespace SiteLink;

public enum LinkState { Off, On, Partial, Unknown }

/// <summary>Stato e logica dell'app (equivalente di LinkModel.swift). Da usare dal thread dell'interfaccia.</summary>
public sealed class LinkModel
{
    public event Action? Changed;
    public event Action? SetupRequested;

    public string? ConfigError { get; private set; }
    public Site? Local { get; private set; }
    public Site? Remote { get; private set; }
    public AgentStatus? LocalStatus { get; private set; }
    public AgentStatus? RemoteStatus { get; private set; }
    public bool RoutePresent { get; private set; }
    public bool Busy { get; private set; }
    public bool NeedsSetup { get; private set; }
    public string? StatusMessage { get; private set; }
    public string? ActionMessage { get; set; }
    public string? Message => ActionMessage ?? StatusMessage;

    private AppConfig? config;

    private static bool WantOn
    {
        get { try { using var k = Registry.CurrentUser.OpenSubKey(@"Software\SiteLink"); return (int)(k?.GetValue("WantOn") ?? 0) == 1; } catch { return false; } }
        set { try { using var k = Registry.CurrentUser.CreateSubKey(@"Software\SiteLink"); k.SetValue("WantOn", value ? 1 : 0); } catch { } }
    }

    public LinkState State
    {
        get
        {
            if (Local == null || LocalStatus == null) return LinkState.Unknown;
            var agent = LocalStatus.LinkEnabled;
            if (agent && RoutePresent) return LinkState.On;
            if (!agent && !RoutePresent) return LinkState.Off;
            return LinkState.Partial;
        }
    }

    public void Start()
    {
        LoadConfig();
        if (config == null)
            _ = Task.Delay(600).ContinueWith(_ => SetupRequested?.Invoke(), TaskScheduler.FromCurrentSynchronizationContext());
        _ = PollLoopAsync();
    }

    public void ShowSetup() => SetupRequested?.Invoke();

    /// <summary>Dopo il salvataggio dalla finestra guidata: ricarica, aggiorna e, se serve, chiede i permessi route.</summary>
    public async Task AfterSetupAsync()
    {
        LoadConfig();
        await RefreshAsync();
        if (NeedsSetup && Local != null) await AuthorizeRoutesAsync();
    }

    public void LoadConfig()
    {
        try { config = AppConfig.Load(); ConfigError = null; }
        catch (Exception e) { config = null; ConfigError = $"Config non valida ({AppConfig.ConfigPath}): {e.Message}"; }
        Changed?.Invoke();
    }

    private async Task PollLoopAsync()
    {
        while (true)
        {
            if (!Busy) await RefreshAsync();
            await Task.Delay(TimeSpan.FromSeconds(config?.PollSeconds ?? 10));
        }
    }

    private (Site here, Site there)? DetectSite()
    {
        if (config == null) return null;
        var ips = NetInfo.Ipv4Addresses();
        for (var i = 0; i < config.Sites.Count; i++)
            if (Cidr.TryParse(config.Sites[i].Subnet, out var net) && ips.Any(net.Contains))
                return (config.Sites[i], config.Sites[1 - i]);
        return null;
    }

    public async Task RefreshAsync()
    {
        if (config == null) LoadConfig();
        if (config == null) return;
        var det = DetectSite();
        if (det is null)
        {
            Local = null; Remote = null; LocalStatus = null; RemoteStatus = null; RoutePresent = false;
            StatusMessage = "Rete non riconosciuta: nessuna delle due sedi";
            Changed?.Invoke();
            return;
        }
        var (here, there) = det.Value;
        Local = here; Remote = there;
        NeedsSetup = !await Authorizer.IsAuthorizedAsync(here, there);
        var ls = TryStatusAsync(here);
        // L'altra sede si raggiunge SEMPRE tramite l'agent locale (canale tra i router), mai attraverso la route.
        var rs = RemoteStatusAsync(here);
        var rp = RouteManager.IsPresentAsync(there, here);
        await Task.WhenAll(ls, rs, rp);
        LocalStatus = ls.Result;
        var (remoteSt, remoteErr) = rs.Result;
        RemoteStatus = remoteSt;
        RoutePresent = rp.Result;
        if (LocalStatus == null) StatusMessage = $"Agent {here.Name} non raggiungibile";
        else if (remoteErr != null) StatusMessage = "Altra sede: " + remoteErr;
        else StatusMessage = null;

        // Dopo un cambio di rete o un riavvio la route sparisce: la ripristina se il collegamento è voluto.
        if (WantOn && !RoutePresent && LocalStatus != null && !Busy && !NeedsSetup)
        {
            try { await RouteManager.AddAsync(there, here); RoutePresent = true; }
            catch (Exception e) { ActionMessage = e.Message; }
        }
        Changed?.Invoke();
    }

    private static async Task<AgentStatus?> TryStatusAsync(Site s)
    {
        try { return await new AgentClient(s).StatusAsync(); } catch { return null; }
    }

    private static async Task<(AgentStatus?, string?)> RemoteStatusAsync(Site here)
    {
        try { return (await new AgentClient(here, 12, viaPeer: true).StatusAsync(), null); }
        catch (Exception e) { return (null, e.Message); }
    }

    public async Task SetLinkAsync(bool on)
    {
        if (Local is not { } here || Remote is not { } there || Busy) return;
        Busy = true;
        ActionMessage = null;
        WantOn = on;
        Changed?.Invoke();
        var both = config?.ControlRemoteAgent ?? true;
        try
        {
            if (on)
            {
                LocalStatus = await new AgentClient(here).SetLinkAsync(true);
                if (!RoutePresent) await RouteManager.AddAsync(there, here);
                if (both) await RemoteBestEffortAsync(here, true);
            }
            else
            {
                if (both) await RemoteBestEffortAsync(here, false);  // prima, finché la route c'è
                LocalStatus = await new AgentClient(here).SetLinkAsync(false);
                if (RoutePresent) await RouteManager.RemoveAsync(there, here);
            }
        }
        catch (Exception e) { ActionMessage = e.Message; }
        Busy = false;
        await RefreshAsync();
    }

    private async Task RemoteBestEffortAsync(Site here, bool on)
    {
        try { RemoteStatus = await new AgentClient(here, 12, viaPeer: true).SetLinkAsync(on); }
        catch (Exception e) { ActionMessage = "Altra sede: " + e.Message; }
    }

    public async Task AuthorizeRoutesAsync()
    {
        var err = await Authorizer.AuthorizeAsync();
        ActionMessage = err;
        await RefreshAsync();
    }
}
