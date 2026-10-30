import Foundation

// Prove della logica (LinkController) contro due agent veri in locale. Uso: tests/run_logic_test.sh
var failed = 0
func check(_ name: String, _ ok: Bool) { print((ok ? "  ok   " : "  FAIL ") + name); if !ok { failed += 1 } }

let env = ProcessInfo.processInfo.environment
let ta = env["TA"]!, tb = env["TB"]!

func settings(aHost: String = "127.0.0.1:18771", bHost: String = "127.0.0.1:18772", bAlt: String = "", bToken: String? = nil) -> AppSettings {
    AppSettings(sites: [SiteEntry(id: "a", name: "Ufficio", host: aHost, token: ta),
                        SiteEntry(id: "b", name: "Casa", host: bHost, altHost: bAlt, token: bToken ?? tb)])
}

@main struct T {
    static func main() async {
        var s = settings()
        print("Stato e comando con entrambi gli agent raggiungibili")
        var snap = await LinkController.snapshot(s)
        check("stato iniziale spento", snap.state == .off && snap.canControl && snap.message == nil)
        snap = try! await LinkController.set(true, s)
        check("acceso: entrambi attivi", snap.state == .on && snap.states.allSatisfy { $0.status?.linkEnabled == true && !$0.viaPeer })
        snap = try! await LinkController.set(false, s)
        check("spento: entrambi spenti", snap.state == .off)

        print("Una sede fuori portata: si comanda tramite il peer")
        s = settings(bHost: "127.0.0.1:19999")
        snap = await LinkController.snapshot(s)
        check("Casa letta tramite il peer", snap.states[1].viaPeer && snap.states[1].status != nil && snap.canControl)
        snap = try! await LinkController.set(true, s)
        check("acceso tramite peer", snap.state == .on && snap.states[1].viaPeer)
        snap = try! await LinkController.set(false, s)
        check("spento tramite peer", snap.state == .off)

        print("Indirizzo alternativo")
        s = settings(bHost: "127.0.0.1:19999", bAlt: "127.0.0.1:18772")
        snap = await LinkController.snapshot(s)
        check("usa l'alternativo, non il peer", snap.states[1].status != nil && !snap.states[1].viaPeer)

        print("Errori")
        s = settings(bToken: String(repeating: "z", count: 32))
        snap = await LinkController.snapshot(s)
        check("token errato segnalato", snap.states[1].status == nil && (snap.message ?? "").contains("token non valido"))
        s = settings(aHost: "127.0.0.1:19998", bHost: "127.0.0.1:19999")
        snap = await LinkController.snapshot(s)
        check("nessun agent: sconosciuto e non comandabile", snap.state == .unknown && !snap.canControl)
        do { _ = try await LinkController.set(true, s); check("set senza agent lancia errore", false) }
        catch { check("set senza agent lancia errore", true) }

        print("Parsing")
        let v1 = #"{"site":"u","link_enabled":true,"tailscale":{"up":true}}"#.data(using: .utf8)!
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        check("agent v1 (tailscale)", (try? d.decode(AgentStatus.self, from: v1))?.vpnUp == true)

        print(failed == 0 ? "\nTutti i test passati" : "\n\(failed) test falliti")
        exit(failed == 0 ? 0 : 1)
    }
}
