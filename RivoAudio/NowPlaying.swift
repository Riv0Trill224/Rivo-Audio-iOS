import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var showEQ = false
    @State private var dragProgress: Double?
    var body: some View {
        NavigationStack {
            if let song = player.song {
                VStack(spacing: 24) {
                    Spacer()
                    ArtworkView(image: library.image(for: song), size: min(340, UIScreen.main.bounds.width - 50))
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 15)
                    VStack(spacing: 4) {
                        Text(song.title).font(.title2.bold()).lineLimit(2)
                        Text(song.artist).foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { dragProgress ?? player.elapsed }, set: { dragProgress = $0 }), in: 0...max(1, song.duration)) { editing in
                        if !editing, let position = dragProgress { player.seek(to: position); dragProgress = nil }
                    }
                    HStack {
                        Text(format(player.elapsed)); Spacer(); Text(format(song.duration))
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    HStack(spacing: 48) {
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 68)) }
                        Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                    }.font(.title).buttonStyle(.plain)
                    HStack {
                        Button { player.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.shuffle ? Color.pink : Color.primary) }
                        Spacer()
                        Button { showLyrics = true } label: { Image(systemName: "text.quote") }
                        Spacer()
                        Button { showEQ = true } label: { Image(systemName: "slider.vertical.3") }
                        Spacer()
                        Button { player.repeatOne.toggle() } label: { Image(systemName: "repeat.1").foregroundStyle(player.repeatOne ? Color.pink : Color.primary) }
                    }.font(.title3).buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .navigationTitle("Reproduciendo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
                .sheet(isPresented: $showLyrics) { LyricsView(songID: song.id) }
                .sheet(isPresented: $showEQ) { NavigationStack { EqualizerView().navigationTitle("Ecualizador") } }
            }
        }
    }
    private func format(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}

struct LyricsView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    let songID: String
    @State private var lyrics = ""
    @State private var suggestions: [(title: String, artist: String, lyrics: String)] = []
    @State private var searching = false
    @State private var status: String?
    private var song: Song? { library.songs.first { $0.id == songID } }
    private var lines: [LyricLine] { LRC.parse(lyrics) }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !lines.isEmpty {
                            ForEach(lines) { line in
                                Button {
                                    if player.song?.id == songID { player.seek(to: line.time) }
                                } label: {
                                    Text(line.text.isEmpty ? "♪" : line.text)
                                        .font(.title3.weight(line.time <= player.elapsed ? .semibold : .regular))
                                        .foregroundStyle(line.time <= player.elapsed ? .primary : .secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain).id(line.id)
                            }
                        } else if !lyrics.isEmpty {
                            Text(lyrics).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ContentUnavailableView("Sin letra sincronizada", systemImage: "text.quote")
                        }
                        if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button("Usar: \(suggestion.title) — \(suggestion.artist)") { save(suggestion.lyrics) }
                        }
                    }.padding()
                }
                .onChange(of: player.elapsed) { _, elapsed in
                    guard player.song?.id == songID, let active = lines.last(where: { $0.time <= elapsed }) else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(active.id, anchor: .center) }
                }
            }
            .navigationTitle("Letras")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(searching ? "Buscando…" : "Buscar") { Task { await lookup() } }.disabled(searching)
                }
            }
            .onAppear { if let song { lyrics = library.localLyrics(for: song) ?? "" } }
        }
    }
    private func save(_ value: String) {
        guard var song else { return }
        song.lyrics = value; library.update(song); lyrics = value
        suggestions = []; status = "Letra guardada en tu biblioteca"
    }
    private func lookup() async {
        guard let song else { return }
        searching = true; defer { searching = false }
        do {
            if let match = try await LyricSearch.fetch(song: song) { save(match); return }
            suggestions = try await LyricSearch.suggested(song: song)
            status = suggestions.isEmpty ? "Sin coincidencias. Puedes agregar un archivo .lrc junto a la canción." : "Elige una coincidencia para evitar asignar la letra equivocada."
        } catch { status = "No se pudo consultar la letra: \(error.localizedDescription)" }
    }
}
