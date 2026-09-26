import SwiftUI
import AVFoundation

struct NowPlayingView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var showEQ = false
    @State private var showEditor = false
    @State private var showQueue = false
    @State private var chooseVideo = false
    @State private var dragProgress: Double?
    @State private var cover: UIImage?
    @State private var peaks: [Float] = []
    var body: some View {
        NavigationStack {
            ZStack {
                PlayerBackdrop(image: cover)
                if let song = player.song {
                    GeometryReader { geometry in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 14) {
                                header(song)
                                media(song, width: max(1, min(geometry.size.width - 48, geometry.size.height * 0.34, 380)))
                                title(song)
                                sourceSwitch
                                options
                                timeline
                                transport
                                Text(player.isVideoMode ? "VIDEO LOCAL" : player.audioFormat)
                                    .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                footer
                            }
                            .frame(width: max(1, min(geometry.size.width, 500) - 48), alignment: .leading)
                            .padding(.horizontal, 24).padding(.vertical, 20)
                            .frame(width: geometry.size.width, alignment: .center)
                        }
                    }
                } else {
                    ContentUnavailableView("Selecciona una canción", systemImage: "music.note")
                        .toolbar { Button("Cerrar") { dismiss() } }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .tint(PlayerStyle.accent)
            .task(id: player.song?.id) { if let song = player.song { cover = library.image(for: song) } }
            .task(id: player.activeAudioURL) {
                peaks = []
                if let url = player.activeAudioURL { peaks = await WaveformReader.shared.peaks(url) }
            }
            .confirmationDialog("Elige el video", isPresented: $chooseVideo, titleVisibility: .visible) {
                ForEach(player.videoMatches) { match in
                    Button("\(match.song.title) · \(match.song.id)") { Task { await player.switchToVideo(match.song) } }
                }
            } message: { Text("El cambio conserva la posición. Las versiones pueden tener introducciones diferentes.") }
            .sheet(isPresented: $showLyrics) { if let song = player.song { LyricsView(songID: song.id) } }
            .sheet(isPresented: $showEQ) { NavigationStack { EqualizerView().navigationTitle("Ecualizador").toolbar { Button("Cerrar") { showEQ = false } } } }
            .sheet(isPresented: $showEditor) { if let song = player.song { SongEditor(songID: song.id) } }
            .sheet(isPresented: $showQueue) { queueView }
            .alert("No se pudo reproducir", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) {
                Button("Aceptar") { player.error = nil }
            } message: { Text(player.error ?? "") }
        }
    }
    private func header(_ song: Song) -> some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 40, height: 40).background(.white.opacity(0.07), in: Circle()) }.accessibilityLabel("Cerrar reproductor")
            Spacer()
            VStack(spacing: 3) {
                Text("RIVØ AUDIO").font(.caption.bold()).tracking(3)
                Text("TU BIBLIOTECA").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Editar información y carátula") { showEditor = true }
                Button("Letras sincronizadas") { showLyrics = true }
                Button("Ver cola") { showQueue = true }
            } label: { Image(systemName: "ellipsis").frame(width: 40, height: 40).background(.white.opacity(0.07), in: Circle()) }.accessibilityLabel("Opciones de canción")
        }.foregroundStyle(.white)
    }
    private func media(_ song: Song, width: CGFloat) -> some View {
        Group {
            if player.isVideoMode, let video = player.videoPlayer {
                VideoSurface(player: video).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                ArtworkView(image: cover, size: width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cover == nil ? "Sin carátula" : "Carátula del álbum")
                    .accessibilityIdentifier("playerArtwork")
                    .overlay(alignment: .bottomTrailing) {
                        Text(song.id.split(separator: ".").last?.uppercased() ?? "AUDIO")
                            .font(.caption2.bold()).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(14)
                    }.shadow(color: .black.opacity(0.4), radius: 24, y: 16)
            }
        }.frame(maxWidth: .infinity)
    }
    private func title(_ song: Song) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(song.title).font(.title2.bold()).lineLimit(2).truncationMode(.tail)
                    .accessibilityIdentifier("playerTitle")
                Text(song.artist).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1).truncationMode(.tail)
                    .accessibilityIdentifier("playerArtist")
                Text(song.album).font(.caption).foregroundStyle(.white.opacity(0.4)).lineLimit(1).truncationMode(.tail)
                    .accessibilityIdentifier("playerAlbum")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                if var current = library.songs.first(where: { $0.id == song.id }) {
                    current.rating = current.rating == 5 ? 0 : 5; library.update(current)
                }
            } label: {
                Image(systemName: library.songs.first(where: { $0.id == song.id })?.rating == 5 ? "star.fill" : "star")
                    .font(.title3).frame(width: 44, height: 44)
            }.accessibilityLabel("Marcar con cinco estrellas")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var sourceSwitch: some View {
        if player.canSwitchToAudio && (!player.videoMatches.isEmpty || player.isVideoMode) {
            Picker("Fuente", selection: Binding(get: { player.isVideoMode }, set: { video in
                if !video { player.switchToAudio() }
                else if let match = MediaMatcher.automaticMatch(player.videoMatches) { Task { await player.switchToVideo(match) } }
                else { chooseVideo = true }
            })) { Text("Audio").tag(false); Text("Video").tag(true) }
                .pickerStyle(.segmented).disabled(player.switchingMedia || player.preparingAudio).accessibilityIdentifier("mediaSourceSwitch")
        }
        if player.preparingAudio || player.switchingMedia { ProgressView(player.preparingAudio ? "Preparando audio…" : "Cambiando…").font(.caption) }
        if player.isVideoMode { Text("Ecualizador disponible en modo Audio").font(.caption).foregroundStyle(.secondary) }
    }
    private var options: some View {
        HStack {
            Button { showEQ = true } label: { Label("EQ", systemImage: "slider.vertical.3").padding(.horizontal, 15).padding(.vertical, 9).background(.white.opacity(0.08), in: Capsule()) }
                .disabled(player.isVideoMode)
            Spacer()
            Button { player.repeatOne.toggle() } label: { Image(systemName: "repeat.1").foregroundStyle(player.repeatOne ? PlayerStyle.accent : .white.opacity(0.45)).frame(width: 44, height: 44) }.accessibilityLabel("Repetir canción").accessibilityValue(player.repeatOne ? "Activado" : "Desactivado")
            Button { player.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.shuffle ? PlayerStyle.accent : .white.opacity(0.45)).frame(width: 44, height: 44) }.accessibilityLabel("Aleatorio").accessibilityValue(player.shuffle ? "Activado" : "Desactivado")
        }.buttonStyle(.plain)
    }
    private var timeline: some View {
        VStack(spacing: 3) {
            if !peaks.isEmpty && !player.isVideoMode {
                PlaybackWaveform(peaks: peaks, progress: (dragProgress ?? player.elapsed) / max(1, player.playbackDuration))
            }
            Slider(value: Binding(get: { dragProgress ?? player.elapsed }, set: { dragProgress = $0 }), in: 0...max(1, player.playbackDuration)) { editing in
                if !editing, let position = dragProgress { player.seek(to: position); dragProgress = nil }
            }.accessibilityLabel("Posición de reproducción").disabled(player.preparingAudio || player.switchingMedia)
            HStack { Text(format(dragProgress ?? player.elapsed)); Spacer(); Text(format(player.playbackDuration)) }
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.55))
        }
    }
    private var transport: some View {
        HStack(spacing: 25) {
            TransportButton(symbol: "backward.end.fill", label: "Anterior") { player.previous() }
            TransportButton(symbol: player.playing ? "pause.fill" : "play.fill", label: player.playing ? "Pausar" : "Reproducir", large: true) { player.toggle() }
                .disabled(player.preparingAudio || player.switchingMedia)
            TransportButton(symbol: "forward.end.fill", label: "Siguiente") { player.next() }
        }.frame(maxWidth: .infinity)
    }
    private var footer: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "square.grid.2x2.fill").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Biblioteca")
            Button { showEQ = true } label: { Image(systemName: "slider.vertical.3").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Ecualizador")
            Button { showLyrics = true } label: { Image(systemName: "text.quote").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Letras")
            Button { showQueue = true } label: { Image(systemName: "list.bullet").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Cola")
        }.font(.title3).foregroundStyle(.white.opacity(0.75)).background(.white.opacity(0.06), in: Capsule())
    }
    private var queueView: some View {
        NavigationStack {
            List(player.queuedSongs) { song in
                Button { player.play(song, from: player.queuedSongs); showQueue = false } label: { SongRow(song: song) }.buttonStyle(.plain)
            }.navigationTitle("Cola de reproducción").toolbar { Button("Cerrar") { showQueue = false } }
        }
    }
    private func format(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        return String(format: "%d:%02d", Int(max(0, value)) / 60, Int(max(0, value)) % 60)
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
    @State private var cover: UIImage?
    private var song: Song? { library.songs.first { $0.id == songID } }
    private var lines: [LyricLine] { LRC.parse(lyrics) }
    private var activeID: Int? {
        guard player.song?.id == songID else { return nil }
        return lines.last(where: { $0.time <= player.elapsed })?.id
    }
    var body: some View {
        NavigationStack {
            ZStack {
                PlayerBackdrop(image: cover)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !lines.isEmpty {
                                ForEach(lines) { line in
                                    Button {
                                        if player.song?.id == songID { player.seek(to: line.time) }
                                    } label: {
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .font(.system(size: 32, weight: line.id == activeID ? .bold : .semibold, design: .rounded))
                                            .foregroundStyle(.white.opacity(line.id == activeID ? 1 : 0.42))
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(line.text)
                                    .id(line.id)
                                }
                            } else if !lyrics.isEmpty {
                                Text(lyrics)
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Esta letra no contiene tiempos; se muestra sin sincronización.")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                            } else {
                                ContentUnavailableView("Sin letra sincronizada", systemImage: "text.quote")
                            }
                            if let status { Text(status).font(.footnote).foregroundStyle(.white.opacity(0.7)) }
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                                Button("Usar: \(suggestion.title) — \(suggestion.artist)") { save(suggestion.lyrics) }
                            }
                        }
                        .padding(.horizontal, 26).padding(.vertical, 32)
                        .frame(maxWidth: 600, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: activeID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: lyrics) { _, _ in
                        if let id = activeID { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .navigationTitle("Letras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(searching ? "Buscando…" : "Buscar") { Task { await lookup() } }.disabled(searching)
                }
            }
            .tint(PlayerStyle.accent)
            .preferredColorScheme(.dark)
            .onAppear {
                if let song { lyrics = library.localLyrics(for: song) ?? ""; cover = library.image(for: song) }
            }
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
