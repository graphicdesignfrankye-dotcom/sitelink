using System.Net.Http.Headers;
using System.Text.Json;

namespace SiteLink;

public sealed record AgentStatus(string Site, bool LinkEnabled, bool VpnUp, bool PingReachable);

public sealed class AgentException : Exception
{
    public AgentException(string message) : base(message) { }
}

public sealed class AgentClient
{
    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };

    private readonly Site site;
    private readonly TimeSpan timeout;
    /// <summary>true: la richiesta passa dall'agent locale e viene inoltrata all'altra sede.</summary>
    private readonly bool viaPeer;

    public AgentClient(Site site, double timeoutSeconds = 4, bool viaPeer = false)
    {
        this.site = site;
        timeout = TimeSpan.FromSeconds(timeoutSeconds);
        this.viaPeer = viaPeer;
    }

    public Task<AgentStatus> StatusAsync() => CallAsync("status", HttpMethod.Get);
    public Task<AgentStatus> SetLinkAsync(bool on) => CallAsync(on ? "enable" : "disable", HttpMethod.Post);

    private async Task<AgentStatus> CallAsync(string path, HttpMethod method)
    {
        if (!Uri.TryCreate(site.AgentUrl + (viaPeer ? "/peer/" : "/") + path, UriKind.Absolute, out var url))
            throw new AgentException($"URL agent non valido ({site.Name})");
        using var req = new HttpRequestMessage(method, url);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", site.Token);
        if (method == HttpMethod.Post) req.Content = new ByteArrayContent(Array.Empty<byte>());
        using var cts = new CancellationTokenSource(timeout);
        string body;
        int code;
        try
        {
            using var resp = await Http.SendAsync(req, cts.Token).ConfigureAwait(false);
            code = (int)resp.StatusCode;
            body = await resp.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { throw Fail("nessuna risposta (timeout)"); }
        catch (HttpRequestException) { throw Fail("non raggiungibile"); }

        if (code != 200)
        {
            var msg = code == 401 ? "token non valido" : $"errore HTTP {code}";
            try
            {
                using var d = JsonDocument.Parse(body);
                if (d.RootElement.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String) msg = e.GetString()!;
            }
            catch (JsonException) { }
            throw Fail(msg);
        }
        return Parse(body);
    }

    private AgentException Fail(string msg) => new(viaPeer ? msg : $"Agent {site.Name}: {msg}");

    public static AgentStatus Parse(string json)
    {
        using var d = JsonDocument.Parse(json);
        var r = d.RootElement;
        // API v2: "vpn". Gli agent v1 (solo Tailscale) usano ancora "tailscale".
        var vpnUp = false;
        foreach (var key in new[] { "vpn", "tailscale" })
            if (r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Object)
            {
                vpnUp = v.TryGetProperty("up", out var up) && up.ValueKind == JsonValueKind.True;
                break;
            }
        var ping = r.TryGetProperty("ping", out var p) && p.ValueKind == JsonValueKind.Object
                   && p.TryGetProperty("reachable", out var rc) && rc.ValueKind == JsonValueKind.True;
        return new AgentStatus(
            r.TryGetProperty("site", out var s) ? s.GetString() ?? "" : "",
            r.TryGetProperty("link_enabled", out var l) && l.ValueKind == JsonValueKind.True,
            vpnUp, ping);
    }
}
