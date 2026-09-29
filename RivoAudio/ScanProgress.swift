import SwiftUI

@MainActor final class ScanProgress: ObservableObject {
    struct State { var label = ""; var done = 0; var total = 0; var running = false }
    @Published var state = State()
    func set(_ label: String, done: Int = 0, total: Int = 0) { state = State(label: label, done: done, total: total, running: true) }
    func finish() { state.running = false }
}
struct ScanProgressView: View {
    @ObservedObject var progress: ScanProgress
    var body: some View {
        if !progress.state.label.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(progress.state.label).font(.subheadline)
                if progress.state.total > 0 {
                    ProgressView(value: Double(progress.state.done), total: Double(progress.state.total))
                    Text("\(progress.state.done) de \(progress.state.total) archivos · \(Int(100 * Double(progress.state.done) / Double(progress.state.total)))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else if progress.state.running { ProgressView() }
                if !progress.state.running { Text("Proceso finalizado. Revisa el resultado del escaneo.").font(.caption) }
            }.accessibilityIdentifier("scanProgress")
        }
    }
}
extension MusicLibrary {
    func persistScan() async throws {
        var merged = extras
        for (id, details) in pendingDetails { merged.details[id] = details }
        pendingDetails.removeAll()
        extras = merged
        let tracks = songs, sources = folders, root = documents
        try await Task.detached(priority: .utility) {
            try JSONEncoder().encode(tracks).write(to: root.appendingPathComponent("library.json"), options: .atomic)
            try JSONEncoder().encode(sources).write(to: root.appendingPathComponent("musicFolders.json"), options: .atomic)
            try JSONEncoder().encode(merged).write(to: root.appendingPathComponent("extras.json"), options: .atomic)
        }.value
    }
}
