import Foundation
import SwiftUI

enum LinkState { case off, on, partial, unknown }

@MainActor
final class LinkModel: ObservableObject {
    @Published var configError: String?
    @Published var local: Site?
    @Published var remote: Site?
    @Published var localStatus: AgentStatus?
    @Published var remoteStatus: AgentStatus?
    @Published var routePresent = false
    @Published var busy = false
    @Published var needsSetup = false
    @Published var statusMessage: String?
    @Published var actionMessage: String?
    var message: String? { actionMessage ?? statusMessage }

    private var config: AppConfig?
    private var wantOn: Bool {
        get { UserDefaults.standard.bool(forKey: "wantOn") }
        set { UserDefaults.standard.set(newValue, forKey: "wantOn") }
    }

    var state: LinkState {
        guard local != nil, localStatus != nil else { return .unknown }
        let agent = localStatus?.linkEnabled == true
        if agent && routePresent { return .on }
        if !agent && !routePresent { return .off }
        return .partial
    }

    init() {
        loadConfig()
        if config == nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                self.showSetup()
            }
        }
        Task { await pollLoop() }
    }

    func showSetup() { SetupWindow.show(model: self) }

    /// Dopo il salvataggio dalla finestra guidata: ricarica, aggiorna e, se serve, chiede i permessi route.
    func afterSetup() async {
        loadConfig()
        await refresh()
        if needsSetup, local != nil { await authorizeRoutes() }
    }

    func loadConfig() {
        do { config = try AppConfig.load(); configError = nil }
        catch { config = nil; configError = "Config non valida (\(AppConfig.path)): \(error.localizedDescription)" }
    }

    private func pollLoop() async {
        while true {
            if !busy { await refresh() }
            try? await Task.sleep(nanoseconds: UInt64((config?.pollSeconds ?? 10) * 1e9))
        }
    }

    private func detectSite() -> (Site, Site)? {
        guard let cfg = config else { return nil }
        let ips = NetInfo.ipv4Addresses()
        for (i, s) in cfg.sites.enumerated() {
            if let net = CIDR(s.subnet), ips.contains(where: net.contains) {
                return (s, cfg.sites[1 - i])
            }
        }
        return nil
    }

    func refresh() async {
        if config == nil { loadConfig() }
        guard config != nil else { return }
        guard let (here, there) = detectSite() else {
            local = nil; remote = nil; localStatus = nil; remoteStatus = nil; routePresent = false
            statusMessage = "Rete non riconosciuta: nessuna delle due sedi"
            return
        }
        local = here; remote = there
        needsSetup = !(await LinkModel.routesAuthorized(here: here, there: there))
        async let ls = try? AgentClient(site: here).status()
        // L'altra sede si raggiunge SEMPRE tramite l'agent locale (canale tra i router), mai attraverso la route.
        async let rs = Self.remoteStatus(here)
        async let rp = RouteManager.isPresent(probe: there.gateway, via: here.gateway)
        localStatus = await ls
        let remoteResult = await rs
        remoteStatus = try? remoteResult.get()
        routePresent = await rp
        if localStatus == nil { statusMessage = "Agent \(here.name) non raggiungibile" }
        else if case .failure(let e) = remoteResult { statusMessage = "Altra sede: " + e.localizedDescription }
        else { statusMessage = nil }

        // Dopo un cambio di rete o un riavvio la route sparisce: la ripristina se il collegamento è voluto.
        if wantOn, !routePresent, localStatus != nil, !busy, !needsSetup {
            do { try await RouteManager.add(subnet: there.subnet, via: here.gateway); routePresent = true }
            catch { actionMessage = error.localizedDescription }
        }
    }

    private static func remoteStatus(_ here: Site) async -> Result<AgentStatus, Error> {
        do { return .success(try await AgentClient(site: here, timeout: 12, viaPeer: true).status()) }
        catch { return .failure(error) }
    }

    func setLink(_ on: Bool) async {
        guard let here = local, let there = remote, !busy else { return }
        busy = true
        actionMessage = nil
        wantOn = on
        let both = config?.controlRemoteAgent ?? true
        do {
            if on {
                localStatus = try await AgentClient(site: here).setLink(true)
                if !routePresent { try await RouteManager.add(subnet: there.subnet, via: here.gateway) }
                if both { await remoteBestEffort(here, true) }
            } else {
                if both { await remoteBestEffort(here, false) }  // prima, finché la route c'è
                localStatus = try await AgentClient(site: here).setLink(false)
                if routePresent { try await RouteManager.remove(subnet: there.subnet, via: here.gateway) }
            }
        } catch {
            actionMessage = error.localizedDescription
        }
        busy = false
        await refresh()
    }

    private func remoteBestEffort(_ here: Site, _ on: Bool) async {
        do { remoteStatus = try await AgentClient(site: here, timeout: 12, viaPeer: true).setLink(on) }
        catch { actionMessage = "Altra sede: " + error.localizedDescription }
    }
}
