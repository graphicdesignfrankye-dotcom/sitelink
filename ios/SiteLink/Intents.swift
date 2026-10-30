import AppIntents

/// Errore mostrato da Comandi rapidi.
struct LinkIntentError: Error, CustomLocalizedStringResourceConvertible {
    let text: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: text) }
}

private func settingsOrThrow() throws -> AppSettings {
    guard let s = Store.load() else { throw LinkIntentError(text: "SiteLink non è configurato: apri l'app una volta.") }
    return s
}

private func name(_ s: LinkState) -> String {
    switch s {
    case .on: return "Connesso"
    case .off: return "Disconnesso"
    case .partial: return "Parziale"
    case .unknown: return "Stato sconosciuto"
    }
}

/// Imposta il collegamento su acceso o spento.
struct SetLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Imposta il collegamento"
    static let description = IntentDescription("Accende o spegne il collegamento tra le due sedi, tramite gli agent SiteLink.")

    @Parameter(title: "Acceso", default: true) var enabled: Bool

    static var parameterSummary: some ParameterSummary { Summary("Imposta il collegamento su \(\.$enabled)") }

    init() {}
    init(enabled: Bool) { self.enabled = enabled }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let s = try settingsOrThrow()
        do {
            let snap = try await LinkController.set(enabled, s)
            let text = name(snap.state) + (snap.message.map { " (\($0))" } ?? "")
            return .result(value: name(snap.state), dialog: IntentDialog(stringLiteral: text))
        } catch { throw LinkIntentError(text: error.localizedDescription) }
    }
}

/// Inverte lo stato corrente.
struct ToggleLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Inverti il collegamento"
    static let description = IntentDescription("Se il collegamento è acceso lo spegne, altrimenti lo accende.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let s = try settingsOrThrow()
        do {
            let now = await LinkController.snapshot(s).state
            let snap = try await LinkController.set(now != .on, s)
            return .result(value: name(snap.state), dialog: IntentDialog(stringLiteral: name(snap.state)))
        } catch { throw LinkIntentError(text: error.localizedDescription) }
    }
}

/// Restituisce lo stato (Connesso / Disconnesso / Parziale / Stato sconosciuto).
struct LinkStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stato del collegamento"
    static let description = IntentDescription("Restituisce lo stato del collegamento tra le due sedi.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let s = try settingsOrThrow()
        let text = name(await LinkController.snapshot(s).state)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct SiteLinkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetLinkIntent(enabled: true), phrases: ["Accendi il collegamento con \(.applicationName)"],
                    shortTitle: "Accendi", systemImageName: "power")
        AppShortcut(intent: SetLinkIntent(enabled: false), phrases: ["Spegni il collegamento con \(.applicationName)"],
                    shortTitle: "Spegni", systemImageName: "poweroff")
        AppShortcut(intent: LinkStatusIntent(), phrases: ["Stato del collegamento con \(.applicationName)"],
                    shortTitle: "Stato", systemImageName: "link")
    }
}
