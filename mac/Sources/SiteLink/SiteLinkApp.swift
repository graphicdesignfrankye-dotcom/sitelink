import SwiftUI

@main
struct SiteLinkApp: App {
    @StateObject private var model = LinkModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            Image(nsImage: MenuIcon.image(for: model.state))
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: LinkModel

    private var title: String {
        switch model.state {
        case .on: return "Connesso"
        case .off: return "Disconnesso"
        case .partial: return "Parziale"
        case .unknown: return "Stato sconosciuto"
        }
    }

    private var color: Color {
        switch model.state {
        case .on: return .green
        case .off: return .gray
        case .partial: return .orange
        case .unknown: return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if let err = model.configError {
                Text("SiteLink non è ancora configurato.").font(.caption).foregroundColor(.secondary)
                Button("Configura…") { model.showSetup() }
            } else {
                Text(model.local.map { "Sei in: \($0.name)" } ?? "Fuori dalle sedi")
                    .font(.caption).foregroundColor(.secondary)

                Button {
                    Task { await model.setLink(model.state != .on) }
                } label: {
                    ZStack {
                        Circle().fill(color.opacity(0.18)).frame(width: 96, height: 96)
                        Circle().stroke(color, lineWidth: 3).frame(width: 96, height: 96)
                        if model.busy { ProgressView() }
                        else { Image(systemName: "power").font(.system(size: 38, weight: .semibold)).foregroundColor(color) }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.busy || model.needsSetup || model.local == nil || model.localStatus == nil)

                Text(title).font(.title3.bold())

                if model.needsSetup {
                    VStack(spacing: 6) {
                        Text("Primo avvio: servono i permessi per gestire le route (una volta sola).")
                            .font(.caption).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Autorizza…") { Task { await model.authorizeRoutes() } }
                    }
                }

                if model.local != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        row(model.local?.name ?? "", status: model.localStatus)
                        row(model.remote?.name ?? "", status: model.remoteStatus)
                        HStack {
                            Text("Route locale").foregroundColor(.secondary)
                            Spacer()
                            Text(model.routePresent ? "presente" : "assente")
                        }.font(.caption)
                    }
                }
            }

            if let m = model.message {
                Text(m).font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Aggiorna") { Task { model.actionMessage = nil; await model.refresh() } }
                Spacer()
                Button("Impostazioni…") { model.showSetup() }
                Spacer()
                Button("Esci") { NSApplication.shared.terminate(nil) }
            }.buttonStyle(.link)
        }
        .padding(16)
        .frame(width: 290)
    }

    private func row(_ name: String, status: AgentStatus?) -> some View {
        HStack {
            Circle().fill(status == nil ? Color.red : (status!.linkEnabled ? .green : .gray)).frame(width: 8, height: 8)
            Text(name)
            Spacer()
            Text(status.map { $0.linkEnabled ? "attivo" : "spento" } ?? "offline").foregroundColor(.secondary)
        }.font(.caption)
    }
}
