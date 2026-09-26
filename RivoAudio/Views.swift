import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct LibraryView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var history: ListeningHistory
    @EnvironmentObject var ftp: FTPServer
    @State private var search = ""
    @State private var showImporter = false
    @State private var showPlayer = false
    @State private var selection = 0

    private var filtered: [Song] {
        guard !search.isEmpty else { return library.songs }
        return library.songs.filter { "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                List {
                    if library.songs.isEmpty {
                        ContentUnavailableView("Tu música vive aquí", systemImage: "music.note.list", description: Text("Importa desde Archivos o copia música a la carpeta Music de RIVØ Audio desde tu computadora."))
                    }
                    ForEach(filtered) { song in
                        NavigationLink {
                            SongDetailView(songID: song.id)
                        } label: {
                            SongRow(song: song).contentShape(Rectangle())
                        }.swipeActions(edge: .leading) {
                            Button { play(song) } label: { Label("Reproducir", systemImage: "play.fill") }.tint(.pink)
                        }
                    }
                }
                .navigationTitle("Biblioteca")
                .searchable(text: $search, prompt: "Canción, artista o álbum")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { Task { await library.scan() } } label: { Image(systemName: "arrow.clockwise") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showImporter = true } label: { Image(systemName: "plus") } }
                }
            }.tabItem { Label("Canciones", systemImage: "music.note") }.tag(0)

            NavigationStack {
                List(library.songs.map(\.artist).uniqued().sorted(), id: \.self) { artist in
                    NavigationLink { ArtistView(artist: artist) } label: {
                        HStack {
                            ArtworkView(image: library.artistImage(artist), size: 46)
                            VStack(alignment: .leading) {
                                Text(artist)
                                Text("\(library.songs.filter { $0.artist == artist }.count) canciones").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.navigationTitle("Artistas")
            }.tabItem { Label("Artistas", systemImage: "person.2") }.tag(1)

            NavigationStack { EqualizerView().navigationTitle("Ecualizador") }
                .tabItem { Label("EQ", systemImage: "slider.vertical.3") }.tag(2)

            NavigationStack {
                List {
                    Section("En este dispositivo") {
                        Text("\(history.entries.count) reproducciones registradas")
                        ForEach(history.entries.prefix(100)) { item in
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text("\(item.artist) · \(item.startedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section { Text("Conexión a Last.fm disponible tras configurar una API key y autorizar tu cuenta. El historial local ya se registra sin conexión.").font(.footnote) }
                }.navigationTitle("Scrobbling")
            }.tabItem { Label("Escuchas", systemImage: "chart.bar") }.tag(3)

            NavigationStack {
                Form {
                    Section("Transferencia FTP · misma red Wi-Fi") {
                        Toggle("Activar FTP", isOn: Binding(get: { ftp.running }, set: { $0 ? ftp.start() : ftp.stop() }))
                        if ftp.running {
                            LabeledContent("Servidor", value: "\(ftp.address):2121")
                            LabeledContent("Usuario", value: "rivo")
                            LabeledContent("Clave temporal", value: ftp.password)
                        }
                        Text(ftp.status).font(.footnote).foregroundStyle(.secondary)
                        Text("Conecta tu PC por FTP en modo pasivo. Mantén RIVØ Audio abierta mientras transfieres. La clave cambia cada vez que enciendes el servidor.").font(.footnote)
                    }
                    Section("Archivos compartidos") {
                        Text("En Finder, Apple Devices o iTunes para PC abre Archivos compartidos de RIVØ Audio y copia la música dentro de Documents/Music. Después pulsa actualizar en Biblioteca.").font(.footnote)
                    }
                }.navigationTitle("Transferir")
            }.tabItem { Label("Transferir", systemImage: "wifi") }.tag(4)
        }
        .safeAreaInset(edge: .bottom) {
            if let song = player.song {
                Button { showPlayer = true } label: {
                    HStack(spacing: 12) {
                        ArtworkView(image: library.image(for: song), size: 42)
                        VStack(alignment: .leading) {
                            Text(song.title).font(.subheadline.bold()).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title3) }
                            .buttonStyle(.plain)
                    }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 12)
                }.buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showPlayer) { NowPlayingView() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importFiles(urls) }
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        .alert("RIVØ Audio", isPresented: Binding(get: { library.message != nil || player.error != nil }, set: { if !$0 { library.message = nil; player.error = nil } })) {
            Button("Aceptar") { library.message = nil; player.error = nil }
        } message: { Text(library.message ?? player.error ?? "") }
    }
    private func play(_ song: Song) { player.play(song, from: filtered.filter { !$0.isVideo }); showPlayer = true }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] { Array(Set(self)) }
}

struct SongRow: View {
    @EnvironmentObject var library: MusicLibrary
    let song: Song
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(image: library.image(for: song))
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.body.weight(.medium)).lineLimit(1)
                Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if song.isVideo { Image(systemName: "play.rectangle").foregroundStyle(.secondary) }
            else if song.rating > 0 { Text("★ \(song.rating)").font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct SongDetailView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    let songID: String
    @State private var showEditor = false
    @State private var showLyrics = false
    @State private var showVideo = false
    private var song: Song? { library.songs.first { $0.id == songID } }
    var body: some View {
        Group {
            if let song {
                List {
                    Section {
                        HStack { Spacer(); ArtworkView(image: library.image(for: song), size: 220); Spacer() }
                        Text(song.title).font(.title2.bold())
                        NavigationLink(song.artist) { ArtistView(artist: song.artist) }
                        Text(song.album).foregroundStyle(.secondary)
                    }
                    Section {
                        Button(song.isVideo ? "Ver video" : "Reproducir") {
                            if song.isVideo { showVideo = true }
                            else { player.play(song, from: library.songs.filter { !$0.isVideo }) }
                        }
                        Button("Letras sincronizadas") { showLyrics = true }
                        Button("Editar información y carátula") { showEditor = true }
                    }
                    Section("Mi biblioteca") {
                        LabeledContent("Puntuación", value: song.rating == 0 ? "Sin puntuar" : "\(song.rating)/5")
                        if !song.chartNote.isEmpty { LabeledContent("Dato de lista", value: song.chartNote) }
                        LabeledContent("Reproducciones", value: "\(song.playCount)")
                    }
                }
                .sheet(isPresented: $showEditor) { SongEditor(songID: songID) }
                .sheet(isPresented: $showLyrics) { LyricsView(songID: songID) }
                .sheet(isPresented: $showVideo) { VideoView(url: library.url(for: song)) }
            }
        }.navigationTitle("Canción").navigationBarTitleDisplayMode(.inline)
    }
}

struct SongEditor: View {
    @EnvironmentObject var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    let songID: String
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var rating = 0
    @State private var chartNote = ""
    private var song: Song? { library.songs.first { $0.id == songID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Metadatos de la biblioteca") {
                    TextField("Título", text: $title)
                    TextField("Artista", text: $artist)
                    TextField("Álbum", text: $album)
                    PhotoPicker(label: "Cambiar carátula") { data in
                        if let song { try? library.setArtwork(data, for: song) }
                    }
                }
                Section("Puntuación y listas") {
                    Picker("Mi puntuación", selection: $rating) {
                        Text("Sin puntuar").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) estrellas").tag($0) }
                    }
                    TextField("Ej. Billboard Hot 100 #12, 1998", text: $chartNote)
                    Text("El dato de Billboard se captura manualmente; no se atribuyen posiciones sin una fuente comprobada.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Editar canción")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") {
                    if var value = song {
                        value.title = title; value.artist = artist; value.album = album
                        value.rating = rating; value.chartNote = chartNote
                        library.update(value)
                    }
                    dismiss()
                } }
            }
            .onAppear {
                guard let song else { return }
                title = song.title; artist = song.artist; album = song.album
                rating = song.rating; chartNote = song.chartNote
            }
        }
    }
}

struct ArtistView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    let artist: String
    private var songs: [Song] { library.songs.filter { $0.artist.localizedCaseInsensitiveCompare(artist) == .orderedSame } }
    var body: some View {
        List {
            Section {
                HStack { Spacer(); ArtworkView(image: library.artistImage(artist), size: 180); Spacer() }
                PhotoPicker(label: "Elegir foto del artista") { data in try? library.setArtistPhoto(data, for: artist) }
            }
            Section("\(songs.count) canciones en tu biblioteca") {
                ForEach(songs) { song in
                    Button {
                        if !song.isVideo { player.play(song, from: songs.filter { !$0.isVideo }) }
                    } label: { SongRow(song: song) }.buttonStyle(.plain)
                }
            }
        }.navigationTitle(artist)
    }
}

struct EqualizerView: View {
    @EnvironmentObject var player: AudioPlayer
    var body: some View {
        Form {
            Toggle("EQ activo", isOn: $player.eqEnabled)
            Picker("Bandas", selection: $player.bandCount) {
                Text("10 bandas").tag(10); Text("15 bandas").tag(15); Text("31 bandas").tag(31)
            }
            Picker("Preset", selection: $player.presetName) {
                ForEach(AudioPlayer.presets.keys.sorted(), id: \.self) { Text($0).tag($0) }
                Text("Personalizado").tag("Personalizado")
            }.onChange(of: player.presetName) { _, name in player.setPreset(name) }
            Section("\(player.bandCount) bandas · ±12 dB") {
                ForEach(AudioPlayer.activeIndices(player.bandCount), id: \.self) { index in
                    let frequency = AudioPlayer.frequencies[index]
                    HStack {
                        Text(frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))")
                            .frame(width: 35, alignment: .leading).font(.caption.monospacedDigit())
                        Slider(value: Binding(get: { Double(player.gains[index]) }, set: { player.setGain(Float($0), band: index) }), in: -12...12, step: 0.5)
                        Text(String(format: "%+.1f", player.gains[index])).font(.caption.monospacedDigit()).frame(width: 42)
                    }
                }
            }
            Text("Las 10 bandas clásicas son el perfil inicial. Puedes activar 15 o 31 y ajustar las frecuencias adicionales.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct VideoView: View {
    let url: URL
    var body: some View {
        VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
    }
}
