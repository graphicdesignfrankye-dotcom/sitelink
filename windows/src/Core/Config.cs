using System.Text.Json;
using System.Text.Json.Serialization;

namespace SiteLink;

public sealed class Site
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("subnet")] public string Subnet { get; set; } = "";
    [JsonPropertyName("gateway")] public string Gateway { get; set; } = "";
    [JsonPropertyName("agent_url")] public string AgentUrl { get; set; } = "";
    [JsonPropertyName("token")] public string Token { get; set; } = "";
}

/// <summary>Stesso formato del file config.json dell'app Mac.</summary>
public sealed class AppConfig
{
    [JsonPropertyName("sites")] public List<Site> Sites { get; set; } = new();
    [JsonPropertyName("poll_seconds")] public double? PollSeconds { get; set; }
    [JsonPropertyName("control_remote_agent")] public bool? ControlRemoteAgent { get; set; }

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static string ConfigPath =>
        Environment.GetEnvironmentVariable("SITELINK_CONFIG")
        ?? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SiteLink", "config.json");

    public void Save(string? path = null)
    {
        path ??= ConfigPath;
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(this, Json));
        File.Move(tmp, path, overwrite: true);
    }

    public static AppConfig Load(string? path = null)
    {
        var cfg = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(path ?? ConfigPath))
                  ?? throw new InvalidDataException("file vuoto");
        if (cfg.Sites.Count != 2) throw new InvalidDataException("La config deve avere esattamente 2 sedi");
        return cfg;
    }
}
