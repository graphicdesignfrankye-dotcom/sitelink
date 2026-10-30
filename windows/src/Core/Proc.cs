using System.Diagnostics;

namespace SiteLink;

public static class Proc
{
    public sealed record Result(int Code, string Out, string Err);

    /// <summary>Esegue un programma senza finestra e ne cattura l'output.</summary>
    public static async Task<Result> RunAsync(string file, string args, int timeoutMs = 15000)
    {
        var psi = new ProcessStartInfo(file, args)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        using var p = new Process { StartInfo = psi };
        p.Start();
        var o = p.StandardOutput.ReadToEndAsync();
        var e = p.StandardError.ReadToEndAsync();
        using var cts = new CancellationTokenSource(timeoutMs);
        try { await p.WaitForExitAsync(cts.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) { try { p.Kill(true); } catch { } return new Result(-1, "", "timeout"); }
        return new Result(p.ExitCode, await o.ConfigureAwait(false), await e.ConfigureAwait(false));
    }
}
