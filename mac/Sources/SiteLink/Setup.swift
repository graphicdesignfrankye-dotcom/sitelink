import Foundation

/// Autorizzazione delle route (una volta, con password admin).
extension LinkModel {
    /// Le route sono autorizzate se l'elenco dei permessi sudo (senza password) contiene il comando esatto.
    static func routesAuthorized(here: Site, there: Site) async -> Bool {
        guard let r = try? await RouteManager.run("/usr/bin/sudo", ["-k", "-n", "-l"]), r.status == 0 else { return false }
        return r.stdout.contains("NOPASSWD") &&
            r.stdout.contains("/sbin/route -n add -net \(there.subnet) \(here.gateway)")
    }

    /// Installa /etc/sudoers.d/sitelink con i soli comandi route delle due sedi.
    func authorizeRoutes() async {
        guard let cfg = try? AppConfig.load() else { return }
        let user = NSUserName()
        var cmds: [String] = []
        for (a, b) in [(cfg.sites[0], cfg.sites[1]), (cfg.sites[1], cfg.sites[0])] {
            for verb in ["add", "delete"] {
                cmds.append("/sbin/route -n \(verb) -net \(b.subnet) \(a.gateway)")
            }
        }
        let content = "# generato da SiteLink\n\(user) ALL=(root) NOPASSWD: \(cmds.joined(separator: ", "))\n"
        let tmp = NSTemporaryDirectory() + "sitelink-sudoers-\(UUID().uuidString)"
        do { try content.write(toFile: tmp, atomically: true, encoding: .utf8) }
        catch { actionMessage = "Impossibile preparare l'autorizzazione"; return }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let shell = "/usr/sbin/visudo -cf \(tmp) && /usr/bin/install -m 440 -o root -g wheel \(tmp) /etc/sudoers.d/sitelink"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let r = try? await RouteManager.run("/usr/bin/osascript", ["-e", script])
        if r?.status != 0 {
            let err = r?.stderr ?? ""
            actionMessage = err.contains("-128") ? "Autorizzazione annullata" : "Autorizzazione non riuscita"
        } else {
            actionMessage = nil
        }
        await refresh()
    }
}
