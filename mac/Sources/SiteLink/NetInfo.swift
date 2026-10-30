import Foundation
import Darwin

enum NetInfo {
    /// Indirizzi IPv4 delle interfacce attive (esclude loopback).
    static func ipv4Addresses() -> [UInt32] {
        var result: [UInt32] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let flags = Int32(cur.pointee.ifa_flags)
            if let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
               flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 {
                let addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                result.append(UInt32(bigEndian: addr))
            }
            p = cur.pointee.ifa_next
        }
        return result
    }
}
