using System.Globalization;

namespace SiteLink;

/// <summary>Rete IPv4 in notazione CIDR e controllo di appartenenza.</summary>
public readonly struct Cidr
{
    public uint Network { get; }
    public uint Mask { get; }

    private Cidr(uint network, uint mask) { Network = network; Mask = mask; }

    public string NetworkText => ToText(Network);
    public string MaskText => ToText(Mask);

    public bool Contains(uint ip) => (ip & Mask) == Network;

    public static bool TryParse(string? s, out Cidr cidr)
    {
        cidr = default;
        var parts = (s ?? "").Trim().Split('/');
        if (parts.Length != 2 || !TryParseIp(parts[0], out var ip)) return false;
        if (!int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var bits) || bits > 32) return false;
        var mask = bits == 0 ? 0u : uint.MaxValue << (32 - bits);
        cidr = new Cidr(ip & mask, mask);
        return true;
    }

    public static bool TryParseIp(string? s, out uint ip)
    {
        ip = 0;
        var o = (s ?? "").Trim().Split('.');
        if (o.Length != 4) return false;
        foreach (var part in o)
        {
            if (!byte.TryParse(part, NumberStyles.None, CultureInfo.InvariantCulture, out var b)) return false;
            ip = ip << 8 | b;
        }
        return true;
    }

    public static string ToText(uint ip) => $"{ip >> 24}.{(ip >> 16) & 255}.{(ip >> 8) & 255}.{ip & 255}";
}
