import SwiftUI
import AVFoundation

@MainActor final class PreviewPlayer: ObservableObject {
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    private var audio: AVAudioPlayer?
    private var root: URL?
    private var timer: Timer?
    func load(_ track: Track) async throws {
        stop()
        let (url, root) = try await FileService.shared.playbackURL(track)
        self.root = root
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            audio = try AVAudioPlayer(contentsOf: url); audio?.prepareToPlay(); duration = audio?.duration ?? 0
        } catch { stop(); throw error }
    }
    func toggle() {
        guard let audio else { return }
        if playing { audio.pause(); timer?.invalidate(); timer = nil; playing = false }
        else {
            try? AVAudioSession.sharedInstance().setActive(true)
            playing = audio.play()
            guard playing else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let p = self.audio else { return }
                    self.position = p.currentTime
                    if !p.isPlaying { self.playing = false; self.timer?.invalidate(); self.timer = nil }
                }
            }
        }
    }
    func seek(_ time: Double) { audio?.currentTime = time; position = time }
    func stop() {
        timer?.invalidate(); timer = nil; audio?.stop(); audio = nil; playing = false; position = 0
        root?.stopAccessingSecurityScopedResource(); root = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct LRCEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let track: Track
    @StateObject private var player = PreviewPlayer()
    @State private var text = ""
    @State private var existingHash: String?
    @State private var busy = true
    @State private var search = false
    @State private var overwrite = false
    @State private var source = ""
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 36, height: 36) }
                Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(1, player.duration))
                Text(String(format: "%02d:%02d", Int(player.position) / 60, Int(player.position) % 60)).font(.caption.monospacedDigit())
            }.padding(12).rivoGlass()
            HStack {
                ForEach([-500, -100, 100, 500], id: \.self) { shift in
                    Button("\(shift > 0 ? "+" : "")\(shift) ms") { text = LRC.shift(text, milliseconds: shift) }.font(.caption).buttonStyle(.bordered)
                }
            }
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(8).background(RivoStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Contenido LRC editable")
            Text(source).font(.caption).foregroundStyle(RivoStyle.accent)
            Text(LRC.filename(audio: track.relativePath)).font(.caption).foregroundStyle(.secondary)
            Text("Edita texto, tiempos o cabeceras [ti:], [ar:] y [al:]. Guardar crea o actualiza el archivo junto al audio.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(RivoStyle.ink).navigationTitle("Letra sincronizada").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Buscar") { search = true }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { if existingHash != nil { overwrite = true } else { save() } }.disabled(busy || !LRC.hasTimestamps(text)) }
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
        }
        .overlay { if busy { ProgressView().padding(22).rivoGlass() } }
        .task {
            do {
                let d = try await FileService.shared.detail(track); text = d.lrc; existingHash = d.lrcHash
                source = d.lrcHash != nil ? "Origen: LRC junto al audio" : d.lrc.isEmpty ? "Sin letra incrustada ni LRC" : "Origen: letra incrustada; guardar exporta un LRC"
                do { try await player.load(track) } catch { store.raise(error) }
            } catch { store.raise(error) }
            busy = false
        }
        .onDisappear { player.stop() }
        .onChange(of: phase) { _, phase in if phase != .active { player.stop() } }
        .sheet(isPresented: $search) {
            NavigationStack { LyricsSearchView(track: track, choose: { candidate in text = candidate.syncedLyrics ?? ""; search = false }) }.environmentObject(store)
        }
        .confirmationDialog("Reemplazar la letra existente", isPresented: $overwrite, titleVisibility: .visible) {
            Button("Guardar y conservar recuperación") { save() }
        }
    }
    private func save() {
        busy = true
        Task {
            do {
                try await store.saveLRC(track, text: text, hash: existingHash)
                existingHash = try await FileService.shared.detail(track).lrcHash
            } catch { store.raise(error) }
            busy = false
        }
    }
}

struct LyricsSearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let track: Track
    var initial: [LyricsCandidate] = []
    var choose: ((LyricsCandidate) -> Void)?
    @State private var candidates: [LyricsCandidate] = []
    @State private var title = ""
    @State private var artist = ""
    @State private var busy = false
    @State private var preview: LyricsCandidate?
    @State private var genius: [GeniusCandidate] = []
    @State private var geniusBusy = false
    @State private var geniusMessage = ""
    var body: some View {
        List {
            Section("Buscar en LRCLIB") {
                TextField("Título", text: $title)
                TextField("Artista", text: $artist)
                Button("Buscar LRCLIB") { search() }.disabled(busy || geniusBusy || title.isEmpty)
            }
            Section("Contrastar con Genius") {
                Button("Buscar Genius en la app") { searchGenius() }.disabled(busy || geniusBusy || title.isEmpty)
                Link("Buscar letra en Genius · web", destination: GeniusCandidate.searchURL(title: title, artist: artist))
                Text("Comprueba letra, título, artista y versión. Una coincidencia de datos no garantiza que los tiempos del LRC sean correctos.").font(.footnote).foregroundStyle(.secondary)
                if geniusBusy { ProgressView("Consultando Genius…") }
                if !geniusMessage.isEmpty { Text(geniusMessage).font(.footnote).foregroundStyle(.secondary) }
                ForEach(genius) { song in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(song.title).font(.headline)
                        Text(song.artist).font(.subheadline)
                        if song.matches(title: title, artist: artist) {
                            Label("Título y artista coinciden", systemImage: "checkmark.circle").font(.caption).foregroundStyle(RivoStyle.accent)
                        } else { Text("Revisar identidad y versión").font(.caption).foregroundStyle(.orange) }
                        if let url = song.pageURL { Link("Consultar letra en Genius", destination: url) }
                        Button("Buscar LRC para esta canción") { title = song.title; artist = song.artist; search() }.disabled(busy || geniusBusy)
                    }.padding(.vertical, 6)
                }
            }
            if busy { ProgressView("Buscando letras…") }
            ForEach(candidates) { candidate in
                Button { preview = candidate } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(candidate.trackName).font(.headline)
                        Text(candidate.id < 0 ? "Origen: letra incrustada" : "Origen: LRCLIB").font(.caption).foregroundStyle(.secondary)
                        Text(candidate.artistName + " · " + candidate.albumName).font(.subheadline)
                        if genius.contains(where: { $0.matches(title: candidate.trackName, artist: candidate.artistName) }) {
                            Label("Título/artista también en Genius", systemImage: "checkmark.circle").font(.caption).foregroundStyle(RivoStyle.accent)
                        }
                        Text("\(Int(candidate.duration)) s · \(Int(Match.score(candidate, track) * 100))% similitud · \(candidate.isSynced ? "LRC" : candidate.instrumental ? "Instrumental" : "Sin tiempos")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !busy && candidates.isEmpty { Text("No se encontraron coincidencias. Prueba modificando título o artista.").font(.footnote) }
        }.navigationTitle("Elegir letra").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        .onAppear { title = track.title; artist = track.artist; candidates = initial; if initial.isEmpty { search() } }
        .sheet(item: $preview) { c in
            NavigationStack {
                ScrollView { Text(c.syncedLyrics ?? c.plainLyrics ?? "Sin letra").font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
                    .navigationTitle(c.trackName).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { preview = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(choose == nil ? "Guardar LRC" : "Usar letra") {
                                if let choose { choose(c); preview = nil; dismiss() }
                                else {
                                    Task {
                                        do { try await store.acceptLyrics(track, candidate: c); preview = nil; dismiss() }
                                        catch { store.raise(error); preview = nil }
                                    }
                                }
                            }.disabled(!c.isSynced || store.isWorking)
                        }
                    }
            }
        }
    }
    private func searchGenius() {
        geniusBusy = true; geniusMessage = ""; genius = []
        let queryTitle = title, queryArtist = artist
        Task {
            do {
                genius = try await MusicServices.shared.genius(title: queryTitle, artist: queryArtist)
                if genius.isEmpty { geniusMessage = "Genius no encontró coincidencias. Prueba la búsqueda web." }
            } catch { geniusMessage = error.localizedDescription }
            geniusBusy = false
        }
    }
    private func search() {
        busy = true; var t = track; t.tags["TITLE"] = title; t.tags["ARTIST"] = artist
        Task { do { candidates = try await MusicServices.shared.lyrics(t) } catch { store.raise(error) }; busy = false }
    }
}
