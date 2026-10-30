using System.Diagnostics;
using Microsoft.Win32;

namespace SiteLink;

/// <summary>Installazione per l'utente corrente (nessun amministratore) e disinstallazione.</summary>
public static class Installer
{
    private const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\SiteLink";

    public static string DefaultDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "SiteLink");

    public static string Version => typeof(Installer).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "1.0.0";

    private static string StartMenuLink => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "SiteLink.lnk");
    private static string DesktopLink => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "SiteLink.lnk");

    public static void Install(string dir, bool desktop, bool autostart)
    {
        Directory.CreateDirectory(dir);
        var target = Path.Combine(dir, "SiteLink.exe");
        StopRunning(target);
        File.Copy(Environment.ProcessPath!, target, overwrite: true);

        CreateShortcut(StartMenuLink, target);
        if (desktop) CreateShortcut(DesktopLink, target); else TryDelete(DesktopLink);
        Autostart.Set(target, autostart);

        using var k = Registry.CurrentUser.CreateSubKey(UninstallKey);
        k.SetValue("DisplayName", "SiteLink");
        k.SetValue("DisplayVersion", Version);
        k.SetValue("Publisher", "Francesco Argento");
        k.SetValue("DisplayIcon", target);
        k.SetValue("InstallLocation", dir);
        k.SetValue("UninstallString", $"\"{target}\" --uninstall");
        k.SetValue("NoModify", 1, RegistryValueKind.DWord);
        k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
    }

    public static void Launch(string dir) =>
        Process.Start(new ProcessStartInfo(Path.Combine(dir, "SiteLink.exe")) { UseShellExecute = true });

    public static int Uninstall()
    {
        var self = Environment.ProcessPath!;
        var dir = Path.GetDirectoryName(self)!;
        if (MessageBox.Show("Vuoi disinstallare SiteLink?", "Disinstalla SiteLink", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return 1;
        var wipe = MessageBox.Show(
            "Eliminare anche la configurazione (token compresi) e le autorizzazioni delle route?\n\nRichiede la conferma dell'amministratore.",
            "Disinstalla SiteLink", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;

        StopRunning(self);
        if (wipe)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo(self) { UseShellExecute = true, Verb = "runas", Arguments = $"--remove-tasks --config \"{AppConfig.ConfigPath}\"" });
                p?.WaitForExit();
            }
            catch { /* UAC annullato: le attività restano, si possono togliere dopo */ }
            TryDeleteDir(Path.GetDirectoryName(AppConfig.ConfigPath)!);
            try { Registry.CurrentUser.DeleteSubKeyTree(@"Software\SiteLink", throwOnMissingSubKey: false); } catch { }
        }
        TryDelete(StartMenuLink);
        TryDelete(DesktopLink);
        Autostart.Set(self, false);
        try { Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, throwOnMissingSubKey: false); } catch { }

        // Il file in uso non si può cancellare da sé: lo fa un comando dopo l'uscita.
        Process.Start(new ProcessStartInfo("cmd.exe", $"/c ping -n 3 127.0.0.1 >nul & rmdir /s /q \"{dir}\"") { CreateNoWindow = true, UseShellExecute = false });
        MessageBox.Show("SiteLink è stato disinstallato.", "Disinstalla SiteLink", MessageBoxButtons.OK, MessageBoxIcon.Information);
        return 0;
    }

    private static void StopRunning(string exePath)
    {
        foreach (var p in Process.GetProcessesByName("SiteLink"))
        {
            try
            {
                if (p.Id == Environment.ProcessId) continue;
                if (string.Equals(p.MainModule?.FileName, exePath, StringComparison.OrdinalIgnoreCase)) { p.Kill(); p.WaitForExit(3000); }
            }
            catch { }
        }
    }

    private static void CreateShortcut(string path, string target)
    {
        try
        {
            dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")!)!;
            dynamic link = shell.CreateShortcut(path);
            link.TargetPath = target;
            link.WorkingDirectory = Path.GetDirectoryName(target);
            link.IconLocation = target;
            link.Description = "SiteLink";
            link.Save();
        }
        catch { }
    }

    private static void TryDelete(string path) { try { File.Delete(path); } catch { } }
    private static void TryDeleteDir(string path) { try { Directory.Delete(path, true); } catch { } }
}
