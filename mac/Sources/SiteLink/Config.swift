import Foundation

struct Site: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let subnet: String
    let gateway: String
    let agentURL: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case id, name, subnet, gateway, token
        case agentURL = "agent_url"
    }
}

struct AppConfig: Codable {
    let sites: [Site]
    let pollSeconds: Double?
    let controlRemoteAgent: Bool?

    enum CodingKeys: String, CodingKey {
        case sites
        case pollSeconds = "poll_seconds"
        case controlRemoteAgent = "control_remote_agent"
    }

    static var path: String {
        if let p = ProcessInfo.processInfo.environment["SITELINK_CONFIG"] { return p }
        return NSHomeDirectory() + "/Library/Application Support/SiteLink/config.json"
    }

    func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let path = AppConfig.path
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try enc.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    static func load() throws -> AppConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let cfg = try JSONDecoder().decode(AppConfig.self, from: data)
        guard cfg.sites.count == 2 else {
            throw NSError(domain: "SiteLink", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "La config deve avere esattamente 2 sedi"])
        }
        return cfg
    }
}

/// Rete IPv4 in notazione CIDR e controllo di appartenenza.
struct CIDR {
    let network: UInt32
    let mask: UInt32

    init?(_ s: String) {
        let parts = s.split(separator: "/")
        guard parts.count == 2, let ip = CIDR.parse(String(parts[0])),
              let bits = Int(parts[1]), (0...32).contains(bits) else { return nil }
        mask = bits == 0 ? 0 : UInt32.max << UInt32(32 - bits)
        network = ip & mask
    }

    func contains(_ ip: UInt32) -> Bool { ip & mask == network }

    static func parse(_ s: String) -> UInt32? {
        let o = s.split(separator: ".").compactMap { UInt32($0) }
        guard o.count == 4, o.allSatisfy({ $0 < 256 }) else { return nil }
        return o[0] << 24 | o[1] << 16 | o[2] << 8 | o[3]
    }
}
