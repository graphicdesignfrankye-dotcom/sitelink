import Foundation

enum LinkState { case on, off, partial, unknown }

struct SiteState: Identifiable {
    var id: String { site.id }
    let site: SiteEntry
    var status: AgentStatus?
    /// true: lo stato arriva tramite l'agent dell'altra sede (la sede non è raggiungibile direttamente).
    var viaPeer = false
    var error: String?
    /// true: l'agent ha risposto con un errore (per esempio token errato): il peer non cambierebbe nulla.
    var errorIsFinal = false
}

struct Snapshot {
    var states: [SiteState]
    var message: String?

    var state: LinkState {
        let s = states.compactMap { $0.status?.linkEnabled }
        guard s.count == states.count, !s.isEmpty else { return .unknown }
        if s.allSatisfy({ $0 }) { return .on }
        if s.allSatisfy({ !$0 }) { return .off }
        return .partial
    }
    /// Basta raggiungere un agent direttamente: l'altro si comanda tramite il peer.
    var canControl: Bool { states.contains { $0.status != nil && !$0.viaPeer } }
}

/// Logica del collegamento, senza interfaccia: la usano sia l'app sia i Comandi rapidi.
/// L'iPhone parla SOLO con gli agent; non tocca le route di iOS.
enum LinkController {
    // MARK: chiamate

    private final class HostCache: @unchecked Sendable {
        private var good: [String: String] = [:]
        private let lock = NSLock()
        func get(_ id: String) -> String? { lock.lock(); defer { lock.unlock() }; return good[id] }
        func set(_ id: String, _ h: String) { lock.lock(); good[id] = h; lock.unlock() }
    }
    private static let cache = HostCache()

    /// Prova gli indirizzi della sede (prima l'ultimo che ha funzionato).
    static func call(_ site: SiteEntry, _ s: AppSettings, _ path: String, post: Bool = false,
                     viaPeer: Bool = false, timeout: TimeInterval = 4) async throws -> AgentStatus {
        var hosts = site.hosts
        if let g = cache.get(site.id), let i = hosts.firstIndex(of: g) { hosts.insert(hosts.remove(at: i), at: 0) }
        var last: Error = AgentError("Agent \(site.name): indirizzo mancante", isFinal: true)
        for h in hosts {
            do {
                let r = try await AgentClient(host: h, port: s.port, token: site.token, siteName: site.name)
                    .call(path, post: post, viaPeer: viaPeer, timeout: timeout)
                cache.set(site.id, h)
                return r
            } catch let e as AgentError where e.isFinal { throw e }
            catch { last = error }
        }
        throw last
    }

    // MARK: stato

    static func snapshot(_ s: AppSettings) async -> Snapshot {
        async let ra = Result { try await call(s.sites[0], s, "status") }
        async let rb = Result { try await call(s.sites[1], s, "status") }
        var a = SiteState(site: s.sites[0]), b = SiteState(site: s.sites[1])
        func fill(_ x: inout SiteState, _ r: Result<AgentStatus, Error>) {
            switch r {
            case .success(let st): x.status = st
            case .failure(let e): x.error = e.localizedDescription; x.errorIsFinal = (e as? AgentError)?.isFinal ?? false
            }
        }
        fill(&a, await ra); fill(&b, await rb)
        // Una sede fuori portata si legge tramite l'agent dell'altra (canale tra i router).
        if a.status == nil, !a.errorIsFinal, b.status != nil, let st = try? await call(s.sites[1], s, "status", viaPeer: true, timeout: 12) {
            a.status = st; a.viaPeer = true; a.error = nil
        }
        if b.status == nil, !b.errorIsFinal, a.status != nil, !a.viaPeer, let st = try? await call(s.sites[0], s, "status", viaPeer: true, timeout: 12) {
            b.status = st; b.viaPeer = true; b.error = nil
        }
        var snap = Snapshot(states: [a, b])
        if a.status == nil && b.status == nil { snap.message = "Nessun agent raggiungibile: sei in una delle due reti o collegato con Tailscale?" }
        else if let e = (a.error ?? b.error) { snap.message = e }
        return snap
    }

    // MARK: comando

    /// Accende o spegne il collegamento. Ordine come sull'app Mac: acceso = agent raggiunto, poi l'altro;
    /// spento = prima l'altro, poi quello raggiunto (finché il canale tra i router c'è).
    @discardableResult
    static func set(_ on: Bool, _ s: AppSettings) async throws -> Snapshot {
        let before = await snapshot(s)
        guard let entryIdx = before.states.firstIndex(where: { $0.status != nil && !$0.viaPeer }) else {
            throw AgentError(before.message ?? "Nessun agent raggiungibile")
        }
        let entry = before.states[entryIdx].site
        let other = before.states[1 - entryIdx]

        func setOther() async -> String? {
            do {
                if other.status != nil && !other.viaPeer { _ = try await call(other.site, s, on ? "enable" : "disable", post: true) }
                else { _ = try await call(entry, s, on ? "enable" : "disable", post: true, viaPeer: true, timeout: 12) }
                return nil
            } catch { return "Altra sede: " + error.localizedDescription }
        }

        var problem: String?
        if on {
            _ = try await call(entry, s, "enable", post: true)
            problem = await setOther()
        } else {
            problem = await setOther()
            _ = try await call(entry, s, "disable", post: true)
        }
        var after = await snapshot(s)
        if let problem { after.message = problem }
        return after
    }
}

extension Result where Failure == Error {
    init(_ body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
