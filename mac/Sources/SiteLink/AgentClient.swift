import Foundation

struct AgentStatus: Decodable {
    struct Vpn: Decodable { let up: Bool }
    struct Ping: Decodable { let reachable: Bool; let rttMs: Double? }
    let site: String
    let linkEnabled: Bool
    /// API v2: "vpn". Gli agent v1 (solo Tailscale) usano ancora "tailscale".
    private let vpn: Vpn?
    private let tailscale: Vpn?
    let ping: Ping

    var vpnUp: Bool { (vpn ?? tailscale)?.up ?? false }
}

struct AgentError: LocalizedError {
    let errorDescription: String?
}

struct AgentClient {
    let site: Site
    var timeout: TimeInterval = 4
    /// true: la richiesta passa dall'agent locale e viene inoltrata all'altra sede.
    var viaPeer = false

    func status() async throws -> AgentStatus { try await call("status", method: "GET") }
    func setLink(_ on: Bool) async throws -> AgentStatus { try await call(on ? "enable" : "disable", method: "POST") }

    private func call(_ path: String, method: String) async throws -> AgentStatus {
        guard let url = URL(string: site.agentURL + (viaPeer ? "/peer/" : "/") + path) else {
            throw AgentError(errorDescription: "URL agent non valido (\(site.name))")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("Bearer " + site.token, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            var msg = code == 401 ? "token non valido" : "errore HTTP \(code)"
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let e = obj["error"] as? String { msg = e }
            throw AgentError(errorDescription: viaPeer ? msg : "Agent \(site.name): \(msg)")
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(AgentStatus.self, from: data)
    }
}
