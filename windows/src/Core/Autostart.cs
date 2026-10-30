using Microsoft.Win32;

namespace SiteLink;

public static class Autostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool IsEnabled
    {
        get { try { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue("SiteLink") != null; } catch { return false; } }
        set => Set(Environment.ProcessPath!, value);
    }

    public static void Set(string exePath, bool enabled)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enabled) k.SetValue("SiteLink", $"\"{exePath}\"");
            else k.DeleteValue("SiteLink", throwOnMissingValue: false);
        }
        catch { }
    }
}
