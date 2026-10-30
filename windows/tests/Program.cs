using System.Net;
using System.Text;
using SiteLink;

var failed = 0;
void Check(string name, bool ok) { Console.WriteLine((ok ? "ok    " : "FALLITO ") + name); if (!ok) failed++; }

// --- Cidr ---
Check("cidr parse", Cidr.TryParse("10.0.1.0/24", out var c) && c.NetworkText == "10.0.1.0" && c.MaskText == "255.255.255.0");
Check("cidr normalizza host", Cidr.TryParse("10.0.2.5/24", out var c2) && c2.NetworkText == "10.0.2.0");
Check("cidr contiene", Cidr.TryParseIp("10.0.1.77", out var ip) && c.Contains(ip));
Check("cidr non contiene", Cidr.TryParseIp("10.0.2.2", out var ip2) && !c.Contains(ip2));
Check("cidr rifiuta", !Cidr.TryParse("10.0.1.0", out _) && !Cidr.TryParse("300.1.1.1/24", out _) && !Cidr.TryParse("1.2.3.4/33", out _) && !Cidr.TryParse("a.b.c.d/8", out _));
Check("ip rifiuta", !Cidr.TryParseIp("1.2.3", out _) && !Cidr.TryParseIp("", out _) && !Cidr.TryParseIp("1.2.3.-4", out _));

// --- route print ---
const string rp = """
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0    10.0.1.1  10.0.1.50     25
      10.0.2.0    255.255.255.0   10.0.1.31  10.0.1.50     26
    10.0.1.0    255.255.255.0         On-link   10.0.1.50    281
""";
Check("route presente", RouteManager.HasRoute(rp, "10.0.2.0", "255.255.255.0", "10.0.1.31"));
Check("route gateway diverso", !RouteManager.HasRoute(rp, "10.0.2.0", "255.255.255.0", "10.0.1.1"));
Check("route assente", !RouteManager.HasRoute(rp, "10.0.0.0", "255.0.0.0", "10.0.1.31"));

// --- attività pianificate ---
var here = new Site { Name = "Ufficio", Subnet = "10.0.1.0/24", Gateway = "10.0.1.31" };
var there = new Site { Name = "Casa & co", Subnet = "10.0.2.0/24", Gateway = "10.0.2.2" };
Check("args add", Authorizer.RouteArguments("add", there, here) == "add 10.0.2.0 mask 255.255.255.0 10.0.1.31");
Check("args delete", Authorizer.RouteArguments("delete", there, here) == "delete 10.0.2.0 mask 255.255.255.0 10.0.1.31");
Check("nome task", Authorizer.TaskName("add", there, here) == @"SiteLink\add-10.0.2.0_24-via-10.0.1.31");
var xml = Authorizer.BuildTaskXml("add", there, here, @"PC\Francesco");
Check("xml ben formato", System.Xml.Linq.XDocument.Parse(xml.Replace("UTF-16", "UTF-8")).Root != null);
Check("xml contenuto", xml.Contains("HighestAvailable") && xml.Contains("<Arguments>add 10.0.2.0 mask 255.255.255.0 10.0.1.31</Arguments>") && xml.Contains(@"PC\Francesco") && xml.Contains("Casa &amp; co"));

// --- config ---
var tmp = Path.Combine(Path.GetTempPath(), "sitelink-test-" + Guid.NewGuid() + ".json");
new AppConfig { Sites = { here, there }, PollSeconds = 10 }.Save(tmp);
var raw = File.ReadAllText(tmp);
Check("config chiavi come sul Mac", raw.Contains("\"agent_url\"") && raw.Contains("\"poll_seconds\""));
Check("config roundtrip", AppConfig.Load(tmp).Sites[1].Name == "Casa & co");
File.WriteAllText(tmp, "{\"sites\":[]}");
try { AppConfig.Load(tmp); Check("config con 0 sedi rifiutata", false); } catch (InvalidDataException) { Check("config con 0 sedi rifiutata", true); }
File.Delete(tmp);
// il file scritto dall'app Mac si legge
File.WriteAllText(tmp, """{"sites":[{"id":"a","name":"A","subnet":"10.0.0.0/24","gateway":"10.0.0.1","agent_url":"http://10.0.0.1:8765","token":"x"},{"id":"b","name":"B","subnet":"10.0.1.0/24","gateway":"10.0.1.1","agent_url":"http://10.0.1.1:8765","token":"y"}],"control_remote_agent":false}""");
Check("legge config del Mac", AppConfig.Load(tmp) is { ControlRemoteAgent: false } m && m.Sites[0].AgentUrl == "http://10.0.0.1:8765");
File.Delete(tmp);

// --- client agent con finto server ---
Check("parse v2", AgentClient.Parse("""{"site":"u","link_enabled":true,"vpn":{"up":true},"ping":{"reachable":true}}""") is { LinkEnabled: true, VpnUp: true, PingReachable: true });
Check("parse v1 (tailscale)", AgentClient.Parse("""{"site":"u","link_enabled":false,"tailscale":{"up":true}}""") is { LinkEnabled: false, VpnUp: true });

var port = 18000 + Random.Shared.Next(1000);
using var srv = new HttpListener();
srv.Prefixes.Add($"http://127.0.0.1:{port}/");
srv.Start();
var seen = new List<string>();
_ = Task.Run(async () =>
{
    while (true)
    {
        HttpListenerContext ctx;
        try { ctx = await srv.GetContextAsync(); } catch { return; }
        seen.Add(ctx.Request.HttpMethod + " " + ctx.Request.Url!.AbsolutePath);
        string body; int code = 200;
        if (ctx.Request.Headers["Authorization"] != "Bearer good") { code = 401; body = """{"error":"unauthorized"}"""; }
        else if (ctx.Request.Url.AbsolutePath == "/status") body = """{"site":"u","link_enabled":false,"vpn":{"up":true},"ping":{"reachable":false}}""";
        else if (ctx.Request.Url.AbsolutePath == "/peer/enable") body = """{"site":"casa","link_enabled":true,"vpn":{"up":true},"ping":{"reachable":true}}""";
        else { code = 500; body = """{"error":"boom"}"""; }
        ctx.Response.StatusCode = code;
        var b = Encoding.UTF8.GetBytes(body);
        await ctx.Response.OutputStream.WriteAsync(b);
        ctx.Response.Close();
    }
});
var site = new Site { Name = "T", AgentUrl = $"http://127.0.0.1:{port}", Token = "good" };
Check("status via HTTP", (await new AgentClient(site).StatusAsync()) is { Site: "u", LinkEnabled: false, VpnUp: true });
Check("peer enable via HTTP", (await new AgentClient(site, 4, viaPeer: true).SetLinkAsync(true)) is { Site: "casa", LinkEnabled: true });
Check("richieste attese", seen.SequenceEqual(new[] { "GET /status", "POST /peer/enable" }));
try { await new AgentClient(new Site { Name = "T", AgentUrl = site.AgentUrl, Token = "bad" }).StatusAsync(); Check("token errato", false); }
catch (AgentException e) { Check("token errato -> messaggio", e.Message == "Agent T: unauthorized"); }
try { await new AgentClient(site).SetLinkAsync(false); Check("errore 500", false); }
catch (AgentException e) { Check("errore 500 -> messaggio dell'agent", e.Message == "Agent T: boom"); }
srv.Stop();
try { await new AgentClient(site, 1).StatusAsync(); Check("agent spento", false); }
catch (AgentException e) { Check("agent spento -> non raggiungibile", e.Message.Contains("non raggiungibile") || e.Message.Contains("timeout")); }

Console.WriteLine(failed == 0 ? "\nTutti i test passati" : $"\n{failed} test falliti");
return failed == 0 ? 0 : 1;
