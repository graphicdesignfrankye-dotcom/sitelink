import Foundation

struct AgentError: LocalizedError {
    let message: String
    /// true: l'agent ha risposto (token errato, errore interno): provare un altro indirizzo non serve.
    var isFinal = false
    init(_ message: String, isFinal: Bool = false) { self.message = message; self.isFinal = isFinal }
    var errorDescription: String? { message }
}

struct AgentStatus: Decodable, Equatable {
    struct Vpn: Decodable, Equatable { let up: Bool }
    let site: String
    let linkEnabled: Bool
    /// API v2: "vpn". Gli agent v1 (solo Tailscale) usano ancora "tailscale".
    private let vpn: Vpn?
    private let tailscale: Vpn?
    var vpnUp: Bool { (vpn ?? tailscale)?.up ?? false }
}

/// Chiamata HTTP a un singolo indirizzo di un agent (stessa API usata dall'app Mac e Windows).
struct AgentClient {
    let host: String
    let port: Int
    let token: String
    let siteName: String

    func call(_ path: String, post: Bool = false, viaPeer: Bool = false, timeout: TimeInterval = 4) async throws -> AgentStatus {
        // "host" può già contenere la porta ("10.0.2.2:9000"); altrimenti vale quella comune.
        let authority = host.contains(":") ? host : "\(host):\(port)"
        guard let url = URL(string: "http://\(authority)\(viaPeer ? "/peer/" : "/")\(path)") else {
            throw AgentError("Indirizzo non valido (\(siteName))", isFinal: true)
        }
        func fail(_ m: String, final: Bool = false) -> AgentError { AgentError(viaPeer ? m : "Agent \(siteName): \(m)", isFinal: final) }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = post ? "POST" : "GET"
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch let e as URLError {
            switch e.code {
            case .timedOut: throw fail("nessuna risposta (timeout)")
            case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost:
                throw fail("non raggiungibile")
            default: throw fail(e.localizedDescription)
            }
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            var msg = code == 401 ? "token non valido" : "errore HTTP \(code)"
            if code != 401, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let e = obj["error"] as? String { msg = e }
            throw fail(msg, final: true)
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(AgentStatus.self, from: data)
    }
}
