using System.ComponentModel;
using System.Diagnostics;
using System.Security;
using System.Security.Principal;
using System.Text;

namespace SiteLink;

/// <summary>
/// Autorizzazione delle route (una volta, con UAC). Per ogni direzione e verbo (add/delete)
/// crea un'attività pianificata nella cartella "SiteLink" che esegue SOLO quel comando route.
/// L'utente la avvia senza privilegi con "schtasks /run"; modificarla richiede un amministratore.
/// </summary>
public static class Authorizer
{
    private const string Folder = "SiteLink";

    public static string TaskName(string verb, Site there, Site here)
    {
        Cidr.TryParse(there.Subnet, out var net);
        return $@"{Folder}\{verb}-{net.NetworkText}_{System.Numerics.BitOperations.PopCount(net.Mask)}-via-{here.Gateway.Trim()}";
    }

    public static string RouteArguments(string verb, Site there, Site here)
    {
        Cidr.TryParse(there.Subnet, out var net);
        return $"{verb} {net.NetworkText} mask {net.MaskText} {here.Gateway.Trim()}";
    }

    public static string BuildTaskXml(string verb, Site there, Site here, string user)
    {
        var exe = Path.Combine(Environment.SystemDirectory, "route.exe");
        return $"""
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>SiteLink: {SecurityElement.Escape($"route {verb} verso {there.Name}")}</Description></RegistrationInfo>
  <Triggers />
  <Principals>
    <Principal id="Author">
      <UserId>{SecurityElement.Escape(user)}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{SecurityElement.Escape(exe)}</Command>
      <Arguments>{SecurityElement.Escape(RouteArguments(verb, there, here))}</Arguments>
    </Exec>
  </Actions>
</Task>
""";
    }

    /// <summary>Autorizzate se l'attività "add" di questa direzione esiste con il comando esatto e privilegi elevati.</summary>
    public static async Task<bool> IsAuthorizedAsync(Site here, Site there)
    {
        try
        {
            var r = await Proc.RunAsync("schtasks.exe", $"/query /tn \"{TaskName("add", there, here)}\" /xml").ConfigureAwait(false);
            return r.Code == 0
                   && r.Out.Contains($"<Arguments>{SecurityElement.Escape(RouteArguments("add", there, here))}</Arguments>")
                   && r.Out.Contains("HighestAvailable");
        }
        catch { return false; }
    }

    /// <summary>Lancia questo stesso programma con UAC per creare le attività. Restituisce un errore o null.</summary>
    public static async Task<string?> AuthorizeAsync()
    {
        return await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo(Environment.ProcessPath!)
                {
                    UseShellExecute = true,
                    Verb = "runas",
                    Arguments = $"--install-tasks --user \"{WindowsIdentity.GetCurrent().Name}\" --config \"{AppConfig.ConfigPath}\"",
                };
                using var p = Process.Start(psi);
                p!.WaitForExit();
                return p.ExitCode == 0 ? null : "Autorizzazione non riuscita";
            }
            catch (Win32Exception e) when (e.NativeErrorCode == 1223) { return "Autorizzazione annullata"; }
            catch (Exception e) { return "Autorizzazione non riuscita: " + e.Message; }
        });
    }

    /// <summary>Modalità elevata: --install-tasks --user X --config Y (oppure --remove-tasks).</summary>
    public static int RunElevated(string[] args)
    {
        string? Arg(string name) { var i = Array.IndexOf(args, name); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }
        try
        {
            if (args.Contains("--remove-tasks"))
            {
                RunSync("/delete /tn \"" + Folder + "\" /f");
                var cfg0 = AppConfig.Load(Arg("--config"));
                foreach (var (a, b) in Pairs(cfg0)) foreach (var v in new[] { "add", "delete" })
                    RunSync($"/delete /tn \"{TaskName(v, b, a)}\" /f");
                return 0;
            }
            var user = Arg("--user") ?? WindowsIdentity.GetCurrent().Name;
            var cfg = AppConfig.Load(Arg("--config"));
            foreach (var (here, there) in Pairs(cfg))
                foreach (var verb in new[] { "add", "delete" })
                {
                    var tmp = Path.Combine(Path.GetTempPath(), "sitelink-" + Guid.NewGuid().ToString("N") + ".xml");
                    try
                    {
                        File.WriteAllText(tmp, BuildTaskXml(verb, there, here, user), Encoding.Unicode);
                        if (RunSync($"/create /tn \"{TaskName(verb, there, here)}\" /xml \"{tmp}\" /f") != 0) return 1;
                    }
                    finally { try { File.Delete(tmp); } catch { } }
                }
            return 0;
        }
        catch { return 1; }
    }

    private static IEnumerable<(Site here, Site there)> Pairs(AppConfig c)
    {
        yield return (c.Sites[0], c.Sites[1]);
        yield return (c.Sites[1], c.Sites[0]);
    }

    private static int RunSync(string args)
    {
        using var p = Process.Start(new ProcessStartInfo("schtasks.exe", args) { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true })!;
        p.StandardOutput.ReadToEnd(); p.StandardError.ReadToEnd();
        p.WaitForExit();
        return p.ExitCode;
    }
}
