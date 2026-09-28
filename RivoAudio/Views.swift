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
    @State private var showFolderImporter = false
    @State private var showImportOptions = false
    @State private var showPlayer = false
    @State private var selection = 0
    @State private var editingSong: Song?

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
                    if !library.songs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RIVØ AUDIO").font(.caption.bold()).tracking(3).foregroundStyle(PlayerStyle.accent)
                            Text("Tu colección, a tu ritmo.").font(.title3.bold())
                            HStack {
                                Text("\(library.songs.count) pistas").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { if let first = filtered.randomElement() { player.shuffle = true; play(first) } } label: { Label("Mezclar", systemImage: "shuffle") }.buttonStyle(.bordered)
                            }
                        }.padding(.vertical, 8).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    ForEach(filtered) { song in
                        Button { play(song) } label: {
                            SongRow(song: song).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Reproducir") { play(song) }
                            Button("Editar información y carátula") { editingSong = song }
                        }.listRowBackground(PlayerStyle.surface.opacity(0.7))
                        .swipeActions(edge: .leading) {
                            Button { play(song) } label: { Label("Reproducir", systemImage: "play.fill") }.tint(.pink)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(PlayerBackdrop())
                .navigationTitle("Biblioteca")
                .searchable(text: $search, prompt: "Canción, artista o álbum")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { Task { await library.scan() } } label: { Image(systemName: "arrow.clockwise") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showImportOptions = true } label: { Image(systemName: "plus") }.accessibilityLabel("Añadir música") }
                }
            }.safeAreaInset(edge: .bottom) { miniPlayer }.tabItem { Label("Canciones", systemImage: "music.note") }.tag(0)

            NavigationStack {
                List(library.songs.map(\.artist).uniqued().sorted(), id: \.self) { artist in
                    NavigationLink { ArtistView(artist: artist) } label: {
                        HStack {
                            ArtworkView(image: library.artistImage(artist) ?? library.songs.first(where: { $0.artist == artist }).flatMap { library.image(for: $0) }, size: 46)
                            VStack(alignment: .leading) {
                                Text(artist)
                                Text("\(library.songs.filter { $0.artist == artist }.count) canciones").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.navigationTitle("Artistas")
            }.safeAreaInset(edge: .bottom) { miniPlayer }.tabItem { Label("Artistas", systemImage: "person.2") }.tag(1)

            NavigationStack { EqualizerView().navigationTitle("Ecualizador") }
                .safeAreaInset(edge: .bottom) { miniPlayer }.tabItem { Label("EQ", systemImage: "slider.vertical.3") }.tag(2)

            NavigationStack { LastFMView() }
                .safeAreaInset(edge: .bottom) { miniPlayer }.tabItem { Label("Escuchas", systemImage: "chart.bar") }.tag(3)

            NavigationStack {
                Form {
                    Section("Carpetas de música") {
                        Button("Añadir carpeta desde Archivos") { showFolderImporter = true }
                        ForEach(library.folders) { folder in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(folder.name).font(.headline)
                                HStack {
                                    Button("Volver a escanear") { Task { await library.rescanFolder(folder) } }
                                    Spacer()
                                    Button("Quitar de la biblioteca", role: .destructive) {
                                        Task { await library.removeFolder(folder) }
                                    }
                                }.font(.footnote)
                            }
                        }
                        Text("La música se copia conservando sus subcarpetas. Quitarla aquí no borra la carpeta original de Archivos.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
            }.safeAreaInset(edge: .bottom) { miniPlayer }.tabItem { Label("Transferir", systemImage: "wifi") }.tag(4)
        }
        .fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
        .sheet(item: $editingSong) { SongEditor(songID: $0.id) }
        .confirmationDialog("Añadir música", isPresented: $showImportOptions) {
            Button("Seleccionar carpeta") { showFolderImporter = true }
            Button("Seleccionar archivos") { showImporter = true }
        }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await library.importFolder(url) }
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importFiles(urls) }
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        .alert("RIVØ Audio", isPresented: Binding(get: { library.message != nil || (player.error != nil && !showPlayer) }, set: { if !$0 { library.message = nil; player.error = nil } })) {
            Button("Aceptar") { library.message = nil; player.error = nil }
        } message: { Text(library.message ?? player.error ?? "") }
    }
    @ViewBuilder private var miniPlayer: some View {
            if let song = player.song {
                HStack(spacing: 12) {
                    Button { showPlayer = true } label: {
                        HStack {
                            ArtworkView(image: library.image(for: song), size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title).font(.subheadline.bold()).lineLimit(1)
                                Text(player.preparingAudio ? "Preparando audio…" : song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Abrir reproductor")
                    Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.buttonStyle(.plain).disabled(player.preparingAudio)
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 36, height: 44) }.buttonStyle(.plain).accessibilityLabel("Siguiente")
                }.padding(10).background(PlayerStyle.surface, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 12)
            }
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
                            if song.isVideo { player.play(song, from: library.songs.filter { !$0.isVideo }); showVideo = true }
                            else { player.play(song, from: library.songs.filter { !$0.isVideo }); showVideo = true }
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
                .sheet(isPresented: $showVideo) { NowPlayingView() }
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
                        value.metadataVerified = !title.trimmingCharacters(in: .whitespaces).isEmpty && !artist.trimmingCharacters(in: .whitespaces).isEmpty && artist != "Artista desconocido"
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
                HStack { Spacer(); ArtworkView(image: library.artistImage(artist) ?? songs.first.flatMap { library.image(for: $0) }, size: 180); Spacer() }
                if let credit = library.photoCredits[artist] {
                    Text(credit.author).font(.caption)
                    Link(credit.license, destination: credit.sourceURL).font(.caption)
                    if let license = credit.licenseURL { Link("Licencia", destination: license).font(.caption) }
                }
                if let status = library.photoStatus[artist] { Text(status).font(.caption).foregroundStyle(.secondary) }
                Button("Actualizar foto automáticamente") { Task { await library.loadArtistPhoto(artist, refresh: true) } }
                    .disabled(library.photoRequests.contains(artist))
            }
            Section("\(songs.count) canciones en tu biblioteca") {
                ForEach(songs) { song in
                    Button {
                        player.play(song, from: songs.filter { !$0.isVideo })
                    } label: { SongRow(song: song) }.buttonStyle(.plain)
                }
            }
        }.navigationTitle(artist)
            .task { await library.loadArtistPhoto(artist) }
    }
}

struct EqualizerView: View {
    @EnvironmentObject var player: AudioPlayer
    var body: some View {
        ZStack {
            PlayerBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DALE TU SONIDO").font(.caption.bold()).tracking(2).foregroundStyle(PlayerStyle.accent)
                            Text(player.presetName).font(.largeTitle.bold())
                        }
                        Spacer()
                        Toggle("EQ activo", isOn: $player.eqEnabled).labelsHidden().accessibilityLabel("EQ activo")
                    }
                    Picker("Bandas", selection: $player.bandCount) {
                        Text("10 bandas").tag(10); Text("15 bandas").tag(15); Text("31 bandas").tag(31)
                    }.pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AudioPlayer.presets.keys.sorted(), id: \.self) { name in
                                Button { player.setPreset(name) } label: {
                                    Text(name).font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 11)
                                        .background(player.presetName == name ? PlayerStyle.accent.opacity(0.25) : .white.opacity(0.06), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack { Text("+12 dB"); Spacer(); Text("Desliza para ver más bandas") }.font(.caption2).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(AudioPlayer.activeIndices(player.bandCount), id: \.self) { index in band(index) }
                        }.padding(.horizontal, 8).padding(.vertical, 20)
                    }.background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))
                    HStack { Text("−12 dB"); Spacer(); Button("Restablecer") { player.setPreset("Plano") } }.font(.caption)
                    Text(player.isVideoMode ? "El ecualizador se aplica en modo Audio." : "Ajusta cada frecuencia. Tus cambios se guardan automáticamente.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
        }.tint(PlayerStyle.accent).preferredColorScheme(.dark)
    }
    private func band(_ index: Int) -> some View {
        let frequency = AudioPlayer.frequencies[index]
        return VStack(spacing: 10) {
            Text(String(format: "%+.1f", player.gains[index])).font(.caption2.monospacedDigit()).foregroundStyle(PlayerStyle.accent)
            Slider(value: Binding(get: { Double(player.gains[index]) }, set: { player.setGain(Float($0), band: index) }), in: -12...12, step: 0.5)
                .frame(width: 190).rotationEffect(.degrees(-90)).frame(width: 40, height: 200)
                .accessibilityLabel("\(Int(frequency)) hercios")
            Text(frequency >= 1000 ? String(format: "%gk", frequency / 1000) : "\(Int(frequency))").font(.caption2.monospacedDigit())
        }.frame(width: 44).padding(.vertical, 12).background(.black.opacity(0.25), in: Capsule())
    }
}

struct VideoView: View {
    @State private var videoPlayer: AVPlayer
    init(url: URL) { _videoPlayer = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VideoPlayer(player: videoPlayer).ignoresSafeArea()
            .onAppear { videoPlayer.play() }
            .onDisappear { videoPlayer.pause() }
    }
}
