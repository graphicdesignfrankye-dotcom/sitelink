using SiteLink.UI;

namespace SiteLink;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // Modalità elevata (UAC): crea/rimuove le attività pianificate per le route.
        if (args.Contains("--install-tasks") || args.Contains("--remove-tasks")) return Authorizer.RunElevated(args);

        // SiteLink-Setup.exe (o --install): installazione. --uninstall: disinstallazione.
        var exeName = Path.GetFileNameWithoutExtension(Environment.ProcessPath) ?? "";
        if (args.Contains("--uninstall")) return Installer.Uninstall();
        if (args.Contains("--install") || exeName.Contains("Setup", StringComparison.OrdinalIgnoreCase))
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
            return 0;
        }

        using var mutex = new Mutex(true, @"Local\SiteLinkTray", out var first);
        if (!first) return 0;

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new TrayApp());
        return 0;
    }
}
