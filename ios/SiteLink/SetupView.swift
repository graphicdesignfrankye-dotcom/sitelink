import SwiftUI
import UniformTypeIdentifiers

struct SiteForm {
    var name = ""
    var host = ""
    var altHost = ""
    var token = ""
}

/// Dati inseriti nella configurazione guidata, con validazione.
final class SetupDraft: ObservableObject {
    @Published var a = SiteForm()
    @Published var b = SiteForm()
    @Published var port = "8765"

    init(from s: AppSettings?) {
        guard let s, s.sites.count == 2 else { return }
        func form(_ x: SiteEntry) -> SiteForm { SiteForm(name: x.name, host: x.host, altHost: x.altHost, token: x.token) }
        a = form(s.sites[0]); b = form(s.sites[1]); port = String(s.port)
    }

    private static func hostOK(_ h: String) -> Bool {
        let t = h.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)   // host oppure host:porta
        guard parts.count <= 2, let name = parts.first, !name.isEmpty else { return false }
        if parts.count == 2, !(Int(parts[1]).map { (1...65535).contains($0) } ?? false) { return false }
        return !name.contains(where: { $0 == " " || $0 == "/" || $0 == "@" })
    }

    func errors(_ f: SiteForm, label: String) -> [String] {
        var e: [String] = []
        if f.name.trimmingCharacters(in: .whitespaces).isEmpty { e.append("\(label): manca il nome") }
        if !Self.hostOK(f.host) { e.append("\(label): indirizzo dell'agent non valido (esempio 10.0.1.31)") }
        if !f.altHost.trimmingCharacters(in: .whitespaces).isEmpty, !Self.hostOK(f.altHost) { e.append("\(label): indirizzo alternativo non valido") }
        if f.token.trimmingCharacters(in: .whitespacesAndNewlines).count < 24 { e.append("\(label): token troppo corto (almeno 24 caratteri)") }
        return e
    }

    var allErrors: [String] {
        var e = errors(a, label: "Sede 1") + errors(b, label: "Sede 2")
        if let p = Int(port), (1...65535).contains(p) {} else { e.append("Porta non valida") }
        if !a.name.isEmpty, a.name.lowercased() == b.name.lowercased() { e.append("Le due sedi devono avere nomi diversi") }
        return e
    }

    var isPristine: Bool { a.name.isEmpty && b.name.isEmpty && a.token.isEmpty && b.token.isEmpty }

    func settings() -> AppSettings {
        func site(_ f: SiteForm) -> SiteEntry {
            let name = f.name.trimmingCharacters(in: .whitespaces)
            let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
            return SiteEntry(id: slug.isEmpty ? "sede" : slug, name: name, host: f.host.trimmingCharacters(in: .whitespaces),
                             altHost: f.altHost.trimmingCharacters(in: .whitespaces),
                             token: f.token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var s = [site(a), site(b)]
        if s[0].id == s[1].id { s[1].id += "2" }
        return AppSettings(sites: s, port: Int(port) ?? 8765)
    }

    /// Legge il config.json dell'app Mac/Windows (nome, agent_url, token di ciascuna sede).
    func importMacConfig(_ data: Data) throws {
        struct F: Decodable { let sites: [S]; struct S: Decodable { let name: String; let agent_url: String; let token: String } }
        let f = try JSONDecoder().decode(F.self, from: data)
        guard f.sites.count == 2 else { throw AgentError("Il file deve contenere esattamente 2 sedi") }
        func form(_ s: F.S) -> SiteForm {
            SiteForm(name: s.name, host: URL(string: s.agent_url)?.host ?? "", altHost: "", token: s.token)
        }
        a = form(f.sites[0]); b = form(f.sites[1])
        if let p = URL(string: f.sites[0].agent_url)?.port { port = String(p) }
    }
}

struct TestLine: Identifiable {
    let id = UUID()
    let ok: Bool?
    let text: String
}

struct SetupView: View {
    @EnvironmentObject var model: LinkModel
    let onClose: () -> Void
    @StateObject private var draft = SetupDraft(from: Store.load())
    @State private var step = 0
    @State private var lines: [TestLine] = []
    @State private var testing = false
    @State private var importing = false
    @State private var importError: String?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: intro
                case 1: form
                default: test
                }
            }
            .navigationTitle("Configura SiteLink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.settings != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { onClose() } }
                }
            }
        }
        .interactiveDismissDisabled(model.settings == nil)
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Benvenuto in SiteLink").font(.title2.bold())
                Text("Questa app accende e spegne il collegamento tra due sedi, per esempio il tuo ufficio e casa, parlando con gli agent installati sui router. Prima di configurarla deve essere già stato fatto tutto il resto:")
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Su ciascun router che collega la sede (uno per sede) è installato e funzionante l'agent SiteLink.")
                    bullet("I due agent sono configurati per raggiungersi tra loro (peer).")
                    bullet("Il collegamento tra le due reti (VPN) è già configurato sui router.")
                    bullet("L'iPhone non modifica le sue route: deve poter raggiungere almeno uno dei due agent, stando nella sua rete o con una VPN (per esempio Tailscale) attiva.")
                }
                Text("Ti serviranno, per ogni sede: un nome, l'indirizzo dell'agent e il suo token.").foregroundStyle(.secondary)
                Button("Continua") { step = 1 }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(20)
        }
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) { Text("•"); Text(t) }
    }

    private var form: some View {
        Form {
            Section {
                Button { importing = true } label: { Label("Importa da config.json (Mac)…", systemImage: "square.and.arrow.down") }
                if let e = importError { Text(e).font(.caption).foregroundStyle(.orange) }
            } footer: { Text("Facoltativo: legge nomi, indirizzi e token dal file dell'app Mac.") }
            siteSection("Sede 1", $draft.a, nameHint: "Ufficio", hostHint: "10.0.1.31")
            siteSection("Sede 2", $draft.b, nameHint: "Casa", hostHint: "10.0.2.2")
            Section("Avanzate") { TextField("Porta degli agent", text: $draft.port).keyboardType(.numberPad) }
            let errs = draft.allErrors
            if !errs.isEmpty, !draft.isPristine {
                Section { ForEach(errs.prefix(3), id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }
            }
            Section {
                HStack {
                    Button("Indietro") { step = 0 }
                    Spacer()
                    Button("Avanti") { step = 2; Task { await runTest() } }.disabled(!errs.isEmpty).buttonStyle(.borderedProminent)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importError = nil
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try draft.importMacConfig(Data(contentsOf: url))
            } catch { importError = "Importazione non riuscita: \(error.localizedDescription)" }
        }
    }

    private func siteSection(_ title: String, _ f: Binding<SiteForm>, nameHint: String, hostHint: String) -> some View {
        Section(title) {
            TextField("Nome", text: f.name, prompt: Text(nameHint))
            TextField("Indirizzo dell'agent", text: f.host, prompt: Text(hostHint))
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Indirizzo alternativo (facoltativo)", text: f.altHost, prompt: Text("IP Tailscale del router"))
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Token", text: f.token).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private var test: some View {
        VStack(alignment: .leading, spacing: 12) {
            if testing { HStack { ProgressView(); Text("Provo la connessione…") } }
            ForEach(lines) { l in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: l.ok == true ? "checkmark.circle.fill" : (l.ok == false ? "xmark.circle.fill" : "info.circle"))
                        .foregroundStyle(l.ok == true ? .green : (l.ok == false ? .red : .secondary))
                    Text(l.text)
                }
            }
            if let e = saveError { Text(e).foregroundStyle(.red) }
            Spacer()
            HStack {
                Button("Indietro") { step = 1 }
                Spacer()
                Button(lines.contains { $0.ok == false } ? "Salva comunque" : "Salva e chiudi") { save() }
                    .buttonStyle(.borderedProminent).disabled(testing)
            }
            Text("Dall'iPhone basta raggiungere un agent: l'altro viene comandato tramite il peer.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func runTest() async {
        testing = true
        lines = []
        let snap = await LinkController.snapshot(draft.settings())
        for st in snap.states {
            if let s = st.status {
                lines.append(TestLine(ok: true, text: "«\(st.site.name)» risponde" + (st.viaPeer ? " (tramite l'altra sede)" : " e il token è corretto") + " — VPN \(s.vpnUp ? "attiva" : "spenta")."))
            } else {
                lines.append(TestLine(ok: nil, text: "«\(st.site.name)»: \(st.error ?? "non raggiungibile")."))
            }
        }
        if snap.states.allSatisfy({ $0.status == nil }) {
            lines.append(TestLine(ok: false, text: "Nessun agent raggiungibile. Controlla indirizzi, porta e token, e di essere nella rete di una sede o con la VPN attiva."))
        } else if !snap.canControl {
            lines.append(TestLine(ok: false, text: "Nessun agent è raggiungibile direttamente."))
        }
        testing = false
    }

    private func save() {
        do {
            try Store.save(draft.settings())
            model.reload()
            onClose()
        } catch { saveError = error.localizedDescription }
    }
}
