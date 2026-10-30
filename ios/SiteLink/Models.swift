import Foundation

/// Una sede. Il token sta nel Keychain, non nel file delle impostazioni.
struct SiteEntry: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Indirizzo dell'agent (IP o nome), per esempio quello nella LAN della sede.
    var host: String
    /// Indirizzo alternativo facoltativo, per esempio l'IP Tailscale del router: serve fuori dalle due sedi.
    var altHost: String = ""
    var token: String = ""

    enum CodingKeys: String, CodingKey { case id, name, host, altHost }

    var hosts: [String] { [host, altHost].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

struct AppSettings: Codable, Equatable {
    var sites: [SiteEntry]
    var port: Int = 8765
}

enum Store {
    private static let key = "settings.v1"

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: key),
              var s = try? JSONDecoder().decode(AppSettings.self, from: data), s.sites.count == 2 else { return nil }
        for i in s.sites.indices { s.sites[i].token = Keychain.get(s.sites[i].id) ?? "" }
        return s.sites.allSatisfy { !$0.token.isEmpty } ? s : nil
    }

    static func save(_ s: AppSettings) throws {
        for site in s.sites { try Keychain.set(site.token, for: site.id) }
        UserDefaults.standard.set(try JSONEncoder().encode(s), forKey: key)
    }
}
