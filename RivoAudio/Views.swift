import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct LibraryView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var ftp: FTPServer
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var showImportOptions = false
    @State private var showPlayer = false
    @State private var selection = 0
    @State private var relinkID: UUID?
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
                    .toolbar { Button { showImportOptions = true } label: { Image(systemName: "plus") }.accessibilityLabel("Añadir música") }
            }.safeAreaInset(edge: .bottom) { MiniPlayerBar(open: { showPlayer = true }) }
                .tabItem { Label("Inicio", systemImage: "house") }.tag(0)
            NavigationStack { LibraryHubView() }
                .safeAreaInset(edge: .bottom) { MiniPlayerBar(open: { showPlayer = true }) }
                .tabItem { Label("Biblioteca", systemImage: "square.stack") }.tag(1)
            NavigationStack { PlaylistsView(video: false) }
                .safeAreaInset(edge: .bottom) { MiniPlayerBar(open: { showPlayer = true }) }
                .tabItem { Label("Playlists", systemImage: "music.note.list") }.tag(2)
            NavigationStack { settings }
                .safeAreaInset(edge: .bottom) { MiniPlayerBar(open: { showPlayer = true }) }
                .tabItem { Label("Ajustes", systemImage: "gearshape") }.tag(3)
        }
        .fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
        .confirmationDialog("Vincular música sin copiar", isPresented: $showImportOptions) {
            Button("Seleccionar carpeta") { showFolderImporter = true }
            Button("Seleccionar archivos") { showImporter = true }
        }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                let id = relinkID; relinkID = nil
                Task { if let id { await library.relinkFolder(id, source: url) } else { await library.importFolder(url) } }
            case .failure(let error): relinkID = nil; library.message = error.localizedDescription
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
    private var settings: some View {
        Form {
            Section("Reproducción") {
                NavigationLink("Ajustes visuales y de audio") { RivoSettingsView() }
                NavigationLink("Ecualizador") { EqualizerView().navigationTitle("Ecualizador") }
                NavigationLink("Last.fm y escuchas") { LastFMView() }
                NavigationLink("Administrar letras descargadas") { LyricsManagerView() }
            }
            Section("Biblioteca sin duplicados") {
                Button(library.scanning ? "Escaneando…" : "Escanear biblioteca completa") { Task { await library.fullScan() } }.disabled(library.scanning)
                Button("Vincular carpeta desde Archivos") { relinkID = nil; showFolderImporter = true }.disabled(library.scanning)
                Button("Vincular originales y liberar copias verificadas") { player.pause(); Task { await library.migrateAndReleaseCopies() } }.disabled(library.scanning)
                Text("Los nuevos audios y videos se leen de su ubicación original. Para la biblioteca anterior, liberar copias compara cada archivo antes de borrar únicamente la copia interna idéntica. Conserva puntuaciones y playlists.").font(.footnote)
                ForEach(library.folders) { folder in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(folder.name).font(.headline)
                        Text(folder.linked == true ? "Vinculada · sin copia" : "Biblioteca anterior · copia local").font(.caption).foregroundStyle(.secondary)
                        Button("Volver a escanear") { Task { await library.rescanFolder(folder) } }.disabled(library.scanning)
                        if folder.singleFile != true { Button("Volver a vincular carpeta") { relinkID = folder.id; showFolderImporter = true } }
                        Button("Quitar vínculo", role: .destructive) { Task { await library.removeFolder(folder) } }
                    }.buttonStyle(.borderless)
                }
                Text("Los originales de iCloud deben estar descargados para reproducir sin conexión. Si cambia el permiso o la ubicación, vuelve a vincular la carpeta. Nunca se crea una copia de respaldo silenciosa.").font(.footnote)
            }
            Section("Transferencia FTP · misma red Wi-Fi") {
                Toggle("Activar FTP", isOn: Binding(get: { ftp.running }, set: { $0 ? ftp.start() : ftp.stop() }))
                if ftp.running {
                    LabeledContent("Servidor", value: "\(ftp.address):2121")
                    LabeledContent("Usuario", value: "rivo")
                    LabeledContent("Clave temporal", value: ftp.password)
                }
                Text(ftp.status).font(.footnote)
                Text("FTP se detiene al salir de la app para ahorrar batería. Los archivos enviados por FTP se almacenan una sola vez en Music.").font(.footnote)
            }
            Section("Archivos compartidos") {
                Text("Puedes guardar tu única copia directamente en RIVØ Audio/Music desde Archivos, Finder o Apple Devices; después escanea la biblioteca.").font(.footnote)
            }
            Section { NavigationLink("Acerca de") { AboutView() } }
        }.navigationTitle("Ajustes")
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject var player: AudioPlayer
    let open: () -> Void
    var body: some View {
        if let song = player.song {
            HStack(spacing: 10) {
                Button(action: open) {
                    HStack { SongArtwork(song: song, size: 44); VStack(alignment: .leading) { Text(song.title).font(.subheadline.bold()).lineLimit(1); Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(minLength: 0) }
                }.buttonStyle(.plain).accessibilityLabel("Abrir reproductor")
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 40, height: 44) }.disabled(player.preparingAudio).accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 36, height: 44) }.accessibilityLabel("Siguiente")
            }.padding(10).background(PlayerStyle.surface, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 12)
        }
    }
}

struct SongRow: View {
    @EnvironmentObject var library: MusicLibrary
    let song: Song
    var body: some View {
        HStack(spacing: 12) {
            SongArtwork(song: song)
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
            Section { NavigationLink("Información del artista") { ArtistInfoView(artist: artist) } }
            Section("\(songs.count) canciones en tu biblioteca") {
                ForEach(songs) { song in
                    Button {
                        player.play(song, from: songs)
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
