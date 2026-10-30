import Foundation

/// Gestione della route locale verso l'altra sede.
/// Le modifiche passano da `sudo -n` e funzionano senza password solo per i comandi
/// esatti autorizzati da install-routes.sh.
enum RouteManager {
    static func isPresent(probe: String, via gateway: String) async -> Bool {
        guard let out = try? await run("/sbin/route", ["-n", "get", probe]) else { return false }
        for line in out.stdout.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("gateway:") {
                return t.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces) == gateway
            }
        }
        return false
    }

    static func add(subnet: String, via gateway: String) async throws {
        try await sudoRoute(["-n", "add", "-net", subnet, gateway])
    }

    static func remove(subnet: String, via gateway: String) async throws {
        try await sudoRoute(["-n", "delete", "-net", subnet, gateway])
    }

    private static func sudoRoute(_ args: [String]) async throws {
        let r = try await run("/usr/bin/sudo", ["-n", "/sbin/route"] + args)
        if r.status != 0 {
            let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if err.contains("password is required") || err.contains("a terminal is required") {
                throw AgentError(errorDescription: "Permessi route mancanti: esegui install-routes.sh")
            }
            throw AgentError(errorDescription: "route: " + (err.isEmpty ? r.stdout : err))
        }
    }

    struct Output { let status: Int32; let stdout: String; let stderr: String }

    static func run(_ exe: String, _ args: [String]) async throws -> Output {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let o = Pipe(), e = Pipe()
            p.standardOutput = o
            p.standardError = e
            p.terminationHandler = { proc in
                let so = String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let se = String(data: e.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: Output(status: proc.terminationStatus, stdout: so, stderr: se))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
