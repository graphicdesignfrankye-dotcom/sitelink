import SwiftUI
import AppKit

@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func show(model: LinkModel) {
        NSApp.activate(ignoringOtherApps: true)
        if let w = window, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let view = SetupView(model: model) { window?.close(); window = nil }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Configura SiteLink"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }
}

struct SiteForm {
    var name = ""
    var subnet = ""
    var gateway = ""
    var token = ""
}

final class SetupDraft: ObservableObject {
    @Published var a = SiteForm()
    @Published var b = SiteForm()
    @Published var port = "8765"

    init(from cfg: AppConfig?) {
        guard let cfg, cfg.sites.count == 2 else { return }
        func form(_ s: Site) -> SiteForm { SiteForm(name: s.name, subnet: s.subnet, gateway: s.gateway, token: s.token) }
        a = form(cfg.sites[0]); b = form(cfg.sites[1])
        if let u = URL(string: cfg.sites[0].agentURL), let p = u.port { port = String(p) }
    }

    func errors(_ f: SiteForm, label: String) -> [String] {
        var e: [String] = []
        if f.name.trimmingCharacters(in: .whitespaces).isEmpty { e.append("\(label): manca il nome") }
        if CIDR(f.subnet) == nil { e.append("\(label): rete non valida (esempio 10.0.1.0/24)") }
        if CIDR.parse(f.gateway) == nil { e.append("\(label): IP del router non valido") }
        else if let n = CIDR(f.subnet), let g = CIDR.parse(f.gateway), !n.contains(g) {
            e.append("\(label): l'IP del router non è dentro la rete indicata")
        }
        if f.token.count < 24 { e.append("\(label): token troppo corto (almeno 24 caratteri)") }
        return e
    }

    var allErrors: [String] {
        var e = errors(a, label: "Sede 1") + errors(b, label: "Sede 2")
        if let p = Int(port), (1...65535).contains(p) {} else { e.append("Porta non valida") }
        if let x = CIDR(a.subnet), let y = CIDR(b.subnet), x.network == y.network { e.append("Le due sedi devono avere reti diverse") }
        return e
    }

    func sites() -> [Site] {
        func site(_ f: SiteForm) -> Site {
            let name = f.name.trimmingCharacters(in: .whitespaces)
            let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
            return Site(id: slug.isEmpty ? "sede" : slug, name: name, subnet: f.subnet.trimmingCharacters(in: .whitespaces),
                        gateway: f.gateway.trimmingCharacters(in: .whitespaces),
                        agentURL: "http://\(f.gateway.trimmingCharacters(in: .whitespaces)):\(port)",
                        token: f.token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var s = [site(a), site(b)]
        if s[0].id == s[1].id { s[1] = Site(id: s[1].id + "2", name: s[1].name, subnet: s[1].subnet, gateway: s[1].gateway, agentURL: s[1].agentURL, token: s[1].token) }
        return s
    }
}

struct TestLine: Identifiable {
    let id = UUID()
    let ok: Bool?
    let text: String
}

struct SetupView: View {
    @ObservedObject var model: LinkModel
    let onClose: () -> Void
    @StateObject private var draft = SetupDraft(from: try? AppConfig.load())
    @State private var step = 0
    @State private var lines: [TestLine] = []
    @State private var testing = false
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case 0: intro
            case 1: form
            default: test
            }
        }
        .padding(22)
        .frame(width: 520, height: 560, alignment: .topLeading)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Benvenuto in SiteLink").font(.title2.bold())
            Text("Questa app accende e spegne il collegamento tra due sedi, per esempio il tuo ufficio e casa. Prima di configurarla, deve essere già stato fatto tutto il resto:")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                bullet("Su ciascun router che collega la sede (uno per sede) è installato e funzionante l'agent SiteLink.")
                bullet("I due agent sono configurati per raggiungersi tra loro (peer).")
                bullet("Il collegamento tra le due reti (VPN) è già configurato sui router e le route verso l'altra sede sono pronte.")
                bullet("Questo Mac non è già collegato all'altra rete con una VPN installata sul computer: il collegamento passa dalla route che SiteLink aggiunge.")
            }
            Text("Ti serviranno, per ogni sede: un nome, la rete (es. 10.0.1.0/24), l'IP del router con l'agent e il token dell'agent.")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Spacer()
                Button("Continua") { step = 1 }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(t).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Le due sedi").font(.title2.bold())
            Form {
                siteSection("Sede 1", $draft.a, nameHint: "Ufficio", netHint: "10.0.1.0/24", gwHint: "10.0.1.31")
                siteSection("Sede 2", $draft.b, nameHint: "Casa", netHint: "10.0.2.0/24", gwHint: "10.0.2.2")
                Section("Avanzate") {
                    TextField("Porta degli agent", text: $draft.port)
                }
            }
            .formStyle(.grouped)
            let errs = draft.allErrors
            if !errs.isEmpty, !isPristine {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(errs.prefix(3), id: \.self) { Text($0).font(.caption).foregroundColor(.orange) }
                }
            }
            HStack {
                Button("Indietro") { step = 0 }
                Spacer()
                Button("Avanti") { step = 2; Task { await runTest() } }
                    .keyboardShortcut(.defaultAction).disabled(!errs.isEmpty)
            }
        }
    }

    private var isPristine: Bool { draft.a.name.isEmpty && draft.b.name.isEmpty && draft.a.token.isEmpty && draft.b.token.isEmpty }

    private func siteSection(_ title: String, _ f: Binding<SiteForm>, nameHint: String, netHint: String, gwHint: String) -> some View {
        Section(title) {
            TextField("Nome", text: f.name, prompt: Text(nameHint))
            TextField("Rete", text: f.subnet, prompt: Text(netHint))
            TextField("IP del router (agent)", text: f.gateway, prompt: Text(gwHint))
            SecureField("Token", text: f.token)
        }
    }

    private var test: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prova e salvataggio").font(.title2.bold())
            if testing { HStack { ProgressView().controlSize(.small); Text("Provo la connessione…") } }
            ForEach(lines) { l in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: l.ok == true ? "checkmark.circle.fill" : (l.ok == false ? "xmark.circle.fill" : "info.circle"))
                        .foregroundColor(l.ok == true ? .green : (l.ok == false ? .red : .secondary))
                    Text(l.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            HStack {
                Button("Indietro") { step = 1 }.disabled(saving)
                Spacer()
                Button(lines.contains { $0.ok == false } ? "Salva comunque" : "Salva e chiudi") { Task { await save() } }
                    .keyboardShortcut(.defaultAction).disabled(testing || saving)
            }
            Text("Dopo il salvataggio macOS potrebbe chiedere la password di amministratore, una sola volta, per autorizzare le route.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runTest() async {
        testing = true
        lines = []
        defer { testing = false }
        let sites = draft.sites()
        let ips = NetInfo.ipv4Addresses()
        guard let here = sites.first(where: { s in CIDR(s.subnet).map { n in ips.contains(where: n.contains) } ?? false }) else {
            lines = [TestLine(ok: nil, text: "Questo Mac non è collegato a nessuna delle due reti, quindi non posso provare ora. Puoi salvare: la prova vera avverrà alla prima apertura in una delle due sedi.")]
            return
        }
        lines.append(TestLine(ok: nil, text: "Questo Mac è nella sede «\(here.name)»."))
        do {
            let st = try await AgentClient(site: here, timeout: 6).status()
            lines.append(TestLine(ok: true, text: "L'agent di «\(here.name)» risponde e il token è corretto (VPN \(st.vpnUp ? "attiva" : "spenta"))."))
            do {
                _ = try await AgentClient(site: here, timeout: 12, viaPeer: true).status()
                lines.append(TestLine(ok: true, text: "L'altra sede risponde tramite l'agent: i due router sono collegati tra loro."))
            } catch {
                lines.append(TestLine(ok: false, text: "L'altra sede non risponde: \(error.localizedDescription). Controlla la configurazione peer sui router."))
            }
        } catch {
            let m = (error as? AgentError)?.errorDescription ?? "agent non raggiungibile"
            lines.append(TestLine(ok: false, text: "\(m). Controlla IP, porta e token."))
        }
    }

    private func save() async {
        saving = true
        let cfg = AppConfig(sites: draft.sites(), pollSeconds: 10, controlRemoteAgent: true)
        do { try cfg.save() }
        catch {
            lines.append(TestLine(ok: false, text: "Impossibile salvare la configurazione: \(error.localizedDescription)"))
            saving = false
            return
        }
        onClose()
        await model.afterSetup()
    }
}
