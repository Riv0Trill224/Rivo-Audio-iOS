import SwiftUI

struct SongArtwork: View {
    @EnvironmentObject var library: MusicLibrary
    let song: Song
    var size: CGFloat = 52
    @State private var artwork: UIImage?
    var body: some View {
        ArtworkView(image: artwork, size: size)
            .task(id: song.id + (song.artworkFile ?? "")) { artwork = await library.loadArtwork(song) }
    }
}
struct AlbumCollection: Identifiable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Song]
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
    static func grouped(_ songs: [Song]) -> [AlbumCollection] {
        let audio = songs.filter { !$0.isVideo }
        let grouped = Dictionary(grouping: audio) { song -> String in
            let albumArtist = song.albumArtist ?? ""
            var folder = URL(fileURLWithPath: song.id).deletingLastPathComponent()
            if folder.lastPathComponent.lowercased().range(of: "^(cd|disc|disk|disco)[ _-]*[0-9]+$", options: .regularExpression) != nil { folder.deleteLastPathComponent() }
            return song.album + "\u{1f}" + (albumArtist.isEmpty ? folder.path : albumArtist)
        }
        return grouped.map { key, values in
            let tracks = values.sorted {
                if ($0.discNumber ?? 1) != ($1.discNumber ?? 1) { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
                if let a = $0.trackNumber, let b = $1.trackNumber, a != b { return a < b }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
            let artists = Set(values.map(\.artist))
            let artist = values.compactMap(\.albumArtist).first(where: { !$0.isEmpty }) ?? (artists.count == 1 ? values[0].artist : "Varios artistas")
            return AlbumCollection(id: key, title: values[0].album, artist: artist, tracks: tracks)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
struct LibraryHubView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                tile("Álbumes", "opticaldisc") { AlbumsGridView() }
                tile("Artistas", "person.2") { CollectionBrowser(kind: "Artistas") }
                tile("Tracks", "music.note") { TrackBrowserView() }
                tile("Géneros", "guitars") { CollectionBrowser(kind: "Géneros") }
                tile("Playlists", "music.note.list") { PlaylistsView(video: false) }
                tile("Mejores Puntuados", "star") { CollectionTracks(title: "Mejores Puntuados", kind: "Rating", key: "") }
                tile("Playlists de video", "play.rectangle") { PlaylistsView(video: true) }
                tile("Historial", "clock.arrow.circlepath") { HomeView(historyOnly: true) }
            }.padding(18)
        }.background(PlayerBackdrop()).navigationTitle("Biblioteca")
    }
    private func tile<Destination: View>(_ title: String, _ icon: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 10) { Image(systemName: icon).font(.title2).foregroundStyle(PlayerStyle.accent); Spacer(minLength: 0); Text(title).font(.headline).multilineTextAlignment(.trailing).foregroundStyle(.primary) }
                .padding(16).frame(maxWidth: .infinity, minHeight: 98)
                .background(PlayerStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("library-" + title)
    }
}
struct AlbumsGridView: View {
    @EnvironmentObject var library: MusicLibrary
    @State private var search = ""
    private var albums: [AlbumCollection] { AlbumCollection.grouped(library.songs).filter { search.isEmpty || "\($0.title) \($0.artist)".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        GeometryReader { geometry in
            let width = max(70, (geometry.size.width - 48) / 3)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 3), alignment: .leading, spacing: 20) {
                    ForEach(albums) { album in
                        NavigationLink { AlbumDetailView(album: album) } label: {
                            VStack(spacing: 4) {
                                if let song = album.tracks.first { SongArtwork(song: song, size: width) }
                                Text(album.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if let song = album.tracks.first { Text(library.details(song).year).font(.caption2).foregroundStyle(.secondary) }
                            }.frame(width: width).multilineTextAlignment(.center)
                        }.buttonStyle(.plain).accessibilityIdentifier("album-" + album.title)
                    }
                }.padding(12)
            }
        }.background(PlayerBackdrop()).navigationTitle("Álbumes").searchable(text: $search, prompt: "Álbum o artista")
    }
}
struct AlbumDetailView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    let album: AlbumCollection
    @State private var showPlayer = false
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    if let first = album.tracks.first { SongArtwork(song: first, size: 230) }
                    Text(album.title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(album.artist).font(.title3).foregroundStyle(.secondary)
                    if let first = album.tracks.first {
                        let info = library.details(first)
                        Text([info.genre, info.year].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Mezclar", systemImage: "shuffle") { player.shuffle = true; if let song = album.tracks.randomElement() { play(song) } }
                        Spacer()
                        Button("Reproducir", systemImage: "play.fill") { player.shuffle = false; if let song = album.tracks.first { play(song) } }
                    }.buttonStyle(.bordered)
                    HStack { Text("\(album.tracks.count) pistas"); Spacer(); Text(duration(album.duration)) }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical)
            }.listRowBackground(Color.clear)
            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, song in
                Button { play(song) } label: {
                    HStack(spacing: 12) {
                        Text("\(song.discNumber ?? 1).\(song.trackNumber ?? index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) { Text(song.title).lineLimit(2); Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(); Text(duration(song.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
        }.scrollContentBackground(.hidden).background(PlayerBackdrop())
            .navigationTitle("Álbum").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
    }
    private func play(_ song: Song) { player.play(song, from: album.tracks); showPlayer = true }
    private func duration(_ seconds: Double) -> String { let n = Int(max(0, seconds.isFinite ? seconds : 0)); return String(format: "%d:%02d", n / 60, n % 60) }
}
struct TrackBrowserView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @State private var search = ""
    @State private var showPlayer = false
    var tracks: [Song] { library.songs.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List(tracks) { song in
            Button { player.play(song, from: tracks); showPlayer = true } label: { SongRow(song: song) }.buttonStyle(.plain)
                .contextMenu { NavigationLink("Información") { SongDetailView(songID: song.id) } }
        }.navigationTitle("Tracks").searchable(text: $search, prompt: "Canción, artista o álbum").fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
    }
}
struct HomeView: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var history: ListeningHistory
    @EnvironmentObject var player: AudioPlayer
    var historyOnly = false
    @State private var showPlayer = false
    private var days: [Date] { Set(history.entries.map { Calendar.current.startOfDay(for: $0.startedAt) }).sorted(by: >) }
    var body: some View {
        List {
            if !historyOnly {
                Section {
                    Text("Tu colección, a tu ritmo.").font(.title2.bold())
                    Text("\(library.songs.count) pistas · sin duplicar tus archivos").font(.caption).foregroundStyle(.secondary)
                    NavigationLink("Explorar biblioteca", destination: LibraryHubView())
                }.listRowBackground(Color.clear)
            }
            if history.entries.isEmpty {
                Section("Últimos reproducidos") { Text("Aquí aparecerá lo que escuches.").foregroundStyle(.secondary) }
                if !historyOnly {
                    Section("Tu música") {
                        ForEach(Array(library.songs.prefix(8))) { song in
                            Button { play(song) } label: { SongRow(song: song) }.buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ForEach(Array(days.prefix(historyOnly ? 100 : 7)), id: \.self) { day in
                    Section(dayTitle(day)) {
                        ForEach(history.entries.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }) { entry in
                            Button {
                                if let song = library.songs.first(where: { $0.id == entry.songID }) { play(song) }
                            } label: {
                                HStack {
                                    if let song = library.songs.first(where: { $0.id == entry.songID }) { SongArtwork(song: song, size: 44) }
                                    VStack(alignment: .leading, spacing: 3) { Text(entry.title).lineLimit(1); Text([entry.artist, entry.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    Spacer(); Text(entry.startedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.scrollContentBackground(.hidden).background(PlayerBackdrop()).navigationTitle(historyOnly ? "Historial" : "Inicio")
            .fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
    }
    private func play(_ song: Song) { player.play(song, from: library.songs); showPlayer = true }
    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Últimos reproducidos · Hoy" }
        if Calendar.current.isDateInYesterday(day) { return "Ayer" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
struct AboutView: View {
    var body: some View {
        List {
            Section { Text("RIVØ Audio").font(.largeTitle.bold())
                Text("Desarrollado por @Riv0Trill224").font(.headline).textSelection(.enabled)
                Link("https://github.com/Riv0Trill224/Rivo-Audio-iOS", destination: URL(string: "https://github.com/Riv0Trill224/Rivo-Audio-iOS")!)
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text("Tu música, en su lugar."); LabeledContent("Versión", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")") }
            Section("Proyecto") { Text("Reproductor local para iPhone. Biblioteca vinculada, playlists, letras y créditos."); Link("Repositorio y desarrollo", destination: URL(string: "https://github.com/Riv0Trill224/Rivo-Audio-iOS")!) }
            Section("Fuentes") { Text("Créditos: MusicBrainz. Letras: LRCLIB. Fotografías: Wikimedia Commons, con la atribución indicada en cada artista.") }
            Section("Almacenamiento y energía") { Text("Los archivos vinculados permanecen en la carpeta elegida. Solo se guardan índices, ajustes, letras y miniaturas. La compatibilidad de algunos códecs puede necesitar una conversión temporal limitada a 64 MB. El reloj visual se detiene en segundo plano y el motor descansa al pausar.") }
        }.navigationTitle("Acerca de")
    }
}
