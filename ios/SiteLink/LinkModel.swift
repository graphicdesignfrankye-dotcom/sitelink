import Foundation
import SwiftUI

@MainActor
final class LinkModel: ObservableObject {
    @Published var settings: AppSettings?
    @Published var snapshot: Snapshot?
    @Published var busy = false
    @Published var actionMessage: String?
    @Published var refreshing = false

    var message: String? { actionMessage ?? snapshot?.message }
    var state: LinkState { snapshot?.state ?? .unknown }

    init() { settings = Store.load() }

    func reload() { settings = Store.load(); snapshot = nil; actionMessage = nil }

    func refresh() async {
        guard let s = settings, !busy else { return }
        refreshing = true
        snapshot = await LinkController.snapshot(s)
        refreshing = false
    }

    func toggle() async {
        guard let s = settings, !busy else { return }
        busy = true
        actionMessage = nil
        do { snapshot = try await LinkController.set(state != .on, s) }
        catch { actionMessage = error.localizedDescription }
        busy = false
        if actionMessage != nil { await refresh() }
    }

    /// Aggiornamento periodico finché la schermata è visibile.
    func pollWhileVisible() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }
}
