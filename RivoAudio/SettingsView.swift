import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct RivoSettingsView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @AppStorage("visual.artwork") private var artwork = true
    @AppStorage("visual.motion") private var motion = true
    @AppStorage("visual.lyricSize") private var lyricSize = 30.0
    @AppStorage("lyrics.auto") private var automatic = true
    var body: some View {
        Form {
            Section("Biblioteca") { Button(library.scanning ? "Escaneando…" : "Escanear biblioteca completa") { Task { await library.fullScan() } }.disabled(library.scanning) }
            Section("Opciones visuales") {
                Toggle("Fondo de carátula", isOn: $artwork)
                Toggle("Animar letras", isOn: $motion)
                LabeledContent("Tamaño de letra", value: "\(Int(lyricSize))")
                Slider(value: $lyricSize, in: 20...40, step: 1)
                Text("RIVØ Audio · Vista previa").font(.system(size: lyricSize, weight: .semibold))
            }
            Section("Letras") {
                Toggle("Buscar letras automáticamente", isOn: $automatic)
                NavigationLink("Administrar letras descargadas") { LyricsManagerView() }
                Text("Las coincidencias ambiguas requieren selección manual. Las letras se guardan en Documents/Lyrics.").font(.footnote)
            }
            Section("Motor de audio") {
                NavigationLink("Ecualizador y presets") { EqualizerView() }
                Toggle("Ecualizador activo", isOn: $player.eqEnabled)
                LabeledContent("Velocidad", value: String(format: "%.2f×", player.playbackRate))
                Slider(value: $player.playbackRate, in: 0.5...2, step: 0.05)
                LabeledContent("Preamplificación", value: "\(Int(player.preamp)) dB")
                Slider(value: $player.preamp, in: -12...0, step: 1)
                Text(player.audioFormat.isEmpty ? "Sin audio activo" : player.audioFormat)
                LabeledContent("Salida", value: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", "))
                LabeledContent("Frecuencia de salida", value: "\(Int(AVAudioSession.sharedInstance().sampleRate)) Hz")
                Text("iOS administra la ruta y la frecuencia de salida. El EQ se aplica al audio; el video usa su propio reproductor.").font(.footnote)
            }
        }.navigationTitle("Ajustes")
    }
}

struct LyricsManagerView: View {
    @EnvironmentObject var library: MusicLibrary
    @State private var search = ""
    var body: some View {
        List(library.songs.filter { !$0.isVideo && (search.isEmpty || "\($0.title) \($0.artist)".localizedCaseInsensitiveContains(search)) }) { song in
            NavigationLink { LyricEditorView(songID: song.id) } label: {
                VStack(alignment: .leading) {
                    Text(song.title)
                    Text(library.lyricRecords()[song.id]?.source ?? "Sin letra descargada").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.searchable(text: $search).navigationTitle("Letras descargadas")
    }
}

struct LyricEditorView: View {
    @EnvironmentObject var library: MusicLibrary
    let songID: String
    @State private var text = ""
    @State private var importing = false
    @State private var searching = false
    @State private var deleting = false
    @State private var status = ""
    @State private var matches: [(title: String, artist: String, lyrics: String)] = []
    private var song: Song? { library.songs.first { $0.id == songID } }
    var body: some View {
        Form {
            Section("Texto y tiempos LRC") {
                TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 260)
                Button("Guardar cambios") { save(text, source: "Edición manual") }
            }
            Section("Administrar") {
                Button("Reemplazar desde Archivos") { importing = true }
                if let song, let file = library.lyricFile(for: song) { ShareLink("Compartir LRC", item: file) }
                Button(searching ? "Buscando…" : "Buscar en LRCLIB") {
                    guard let song else { return }
                    searching = true
                    Task {
                        defer { searching = false }
                        do { matches = try await LyricSearch.suggested(song: song); status = matches.isEmpty ? "Sin resultados" : "Selecciona la letra correcta" }
                        catch { status = error.localizedDescription }
                    }
                }.disabled(searching)
                ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                    Button("\(match.title) · \(match.artist)") { save(match.lyrics, source: "LRCLIB · selección manual"); matches = [] }
                }
                Button("Eliminar letra", role: .destructive) { deleting = true }
                Text(status).font(.footnote)
            }
        }.navigationTitle(song?.title ?? "Letra")
        .onAppear { if let song { text = library.localLyrics(for: song) ?? ""; status = library.lyricRecords()[song.id]?.source ?? "Sin letra" } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .data]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                save(try String(contentsOf: url, encoding: .utf8), source: "Archivo importado")
            } catch { status = error.localizedDescription }
        }
        .confirmationDialog("¿Eliminar esta letra? La canción se conserva.", isPresented: $deleting) {
            Button("Eliminar", role: .destructive) {
                guard let song else { return }
                do { try library.deleteLyrics(for: song); text = ""; status = "Letra eliminada" }
                catch { status = error.localizedDescription }
            }
        }
    }
    private func save(_ value: String, source: String) {
        guard let song else { return }
        do { try library.saveLyrics(value, for: song, source: source); text = value; status = "Guardada · \(source)" }
        catch { status = error.localizedDescription }
    }
}
