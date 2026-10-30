using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace SiteLink;

public static class NetInfo
{
    /// <summary>Indirizzi IPv4 delle interfacce attive (esclude loopback).</summary>
    public static List<uint> Ipv4Addresses()
    {
        var result = new List<uint>();
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var ua in nic.GetIPProperties().UnicastAddresses)
            {
                if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                var b = ua.Address.GetAddressBytes();
                result.Add((uint)b[0] << 24 | (uint)b[1] << 16 | (uint)b[2] << 8 | b[3]);
            }
        }
        return result;
    }
}
