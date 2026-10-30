import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: LinkModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSetup = false

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
        NavigationStack {
            Group {
                if model.settings == nil { notConfigured } else { main }
            }
            .navigationTitle("SiteLink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.settings != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSetup = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Impostazioni")
                    }
                }
            }
        }
        .sheet(isPresented: $showSetup) { SetupView { showSetup = false } .environmentObject(model) }
        .task(id: model.settings == nil) {
            if model.settings == nil { showSetup = true } else { await model.pollWhileVisible() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
    }

    private var notConfigured: some View {
        VStack(spacing: 14) {
            Image(systemName: "link.circle").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("SiteLink non è ancora configurato.").foregroundStyle(.secondary)
            Button("Configura…") { showSetup = true }.buttonStyle(.borderedProminent)
        }
    }

    private var main: some View {
        ScrollView {
            VStack(spacing: 22) {
                Button { Task { await model.toggle() } } label: {
                    ZStack {
                        Circle().fill(color.opacity(0.18))
                        Circle().stroke(color, lineWidth: 5)
                        if model.busy { ProgressView().controlSize(.large) }
                        else { Image(systemName: "power").font(.system(size: 72, weight: .semibold)).foregroundStyle(color) }
                    }
                    .frame(width: 190, height: 190)
                }
                .buttonStyle(.plain)
                .disabled(model.busy || !(model.snapshot?.canControl ?? false))
                .padding(.top, 24)
                .accessibilityLabel(model.state == .on ? "Spegni il collegamento" : "Accendi il collegamento")

                Text(title).font(.title.bold())

                if let snap = model.snapshot {
                    VStack(spacing: 0) {
                        ForEach(Array(snap.states.enumerated()), id: \.element.id) { i, st in
                            if i > 0 { Divider() }
                            row(st)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    ProgressView()
                }

                if let m = model.message {
                    Text(m).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
        }
        .refreshable { await model.refresh() }
    }

    private func row(_ st: SiteState) -> some View {
        HStack {
            Circle()
                .fill(st.status == nil ? Color.red : (st.status!.linkEnabled ? .green : .gray))
                .frame(width: 10, height: 10)
            Text(st.site.name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(st.status.map { $0.linkEnabled ? "attivo" : "spento" } ?? "offline").foregroundStyle(.secondary)
                if st.viaPeer { Text("tramite l'altra sede").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .padding(.vertical, 12)
    }
}
