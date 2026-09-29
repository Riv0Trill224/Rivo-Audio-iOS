import SwiftUI
import AVFoundation

struct TrackDetails: Codable {
    var genre = ""
    var year = ""
    var credits = ""
    var source = ""
}
struct LocalPlaylist: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var video: Bool
    var songIDs: [String] = []
}
struct LibraryExtras: Codable {
    var details: [String: TrackDetails] = [:]
    var playlists: [LocalPlaylist] = []
    var artists: [String: String] = [:]
}
extension MusicLibrary {
    func loadExtras() {
        if let data = try? Data(contentsOf: documents.appendingPathComponent("extras.json")), let value = try? JSONDecoder().decode(LibraryExtras.self, from: data) { extras = value }
    }
    func saveExtras() {
        do { try JSONEncoder().encode(extras).write(to: documents.appendingPathComponent("extras.json"), options: .atomic) }
        catch { message = "No se pudieron guardar los cambios: \(error.localizedDescription)" }
    }
    func details(_ song: Song) -> TrackDetails { extras.details[song.id] ?? TrackDetails() }
    func setDetails(_ info: TrackDetails, for song: Song) { extras.details[song.id] = info; saveExtras() }
    func fullScan() async {
        guard !scanning else { return }
        scanning = true; defer { scanning = false }
        var failures: [String] = []
        for folder in folders {
            await rescanFolder(folder)
            if let result = message, result.hasPrefix("No se pudo") { failures.append(result) }
            message = nil
        }
        await scan(force: true)
        message = "Escaneo completo: \(songs.count) pistas." + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
    }
}

struct LibrarySections: View {
    var body: some View {
        Section("Explorar biblioteca") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                NavigationLink("Artistas") { CollectionBrowser(kind: "Artistas") }
                NavigationLink("Álbumes") { CollectionBrowser(kind: "Álbumes") }
                NavigationLink("Géneros") { CollectionBrowser(kind: "Géneros") }
                NavigationLink("Tracks") { CollectionTracks(title: "Tracks", kind: "Tracks", key: "") }
                NavigationLink("Playlists") { PlaylistsView(video: false) }
                NavigationLink("Mejores Puntuados") { CollectionTracks(title: "Mejores Puntuados", kind: "Rating", key: "") }
                NavigationLink("Playlists de video") { PlaylistsView(video: true) }
            }.font(.subheadline).padding(.vertical, 6)
        }
    }
}
struct CollectionBrowser: View {
    @EnvironmentObject var library: MusicLibrary
    let kind: String
    var values: [String] { Array(Set(library.songs.map { key($0) })).sorted() }
    func key(_ s: Song) -> String {
        if kind == "Artistas" { return s.artist }
        if kind == "Álbumes" { return s.album }
        let genre = library.details(s).genre; return genre.isEmpty ? "Sin género" : genre
    }
    var body: some View {
        List(values, id: \.self) { value in
            if kind == "Artistas" { NavigationLink(value) { ArtistView(artist: value) } }
            else { NavigationLink(value) { CollectionTracks(title: value, kind: kind, key: value) } }
        }.navigationTitle(kind)
    }
}
struct CollectionTracks: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    let title: String
    let kind: String
    let key: String
    @State private var showPlayer = false
    var tracks: [Song] {
        library.songs.filter { s in
            switch kind {
            case "Álbumes": return s.album == key
            case "Géneros": return (library.details(s).genre.isEmpty ? "Sin género" : library.details(s).genre) == key
            case "Rating": return s.rating > 0
            default: return true
            }
        }.sorted { kind == "Rating" && $0.rating != $1.rating ? $0.rating > $1.rating : $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
    var body: some View {
        List(tracks) { song in
            Button { player.play(song, from: tracks); showPlayer = true } label: { SongRow(song: song) }.buttonStyle(.plain)
        }.navigationTitle(title).fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
    }
}
struct PlaylistsView: View {
    @EnvironmentObject var library: MusicLibrary
    let video: Bool
    @State private var adding = false
    @State private var name = ""
    var body: some View {
        List {
            ForEach(library.extras.playlists.filter { $0.video == video }) { list in
                NavigationLink(list.name) { PlaylistDetail(playlistID: list.id) }
                    .swipeActions { Button("Eliminar", role: .destructive) { library.extras.playlists.removeAll { $0.id == list.id }; library.saveExtras() } }
            }
        }.navigationTitle(video ? "Playlists de video" : "Playlists")
            .toolbar { Button("Crear playlist") { adding = true } }
            .alert("Nueva playlist", isPresented: $adding) {
                TextField("Nombre", text: $name)
                Button("Crear") { let value = name.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { library.extras.playlists.append(LocalPlaylist(name: value, video: video)); library.saveExtras(); name = "" } }
                Button("Cancelar", role: .cancel) {}
            }
    }
}
struct PlaylistDetail: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    let playlistID: String
    @State private var picking = false
    @State private var renaming = false
    @State private var name = ""
    @State private var showPlayer = false
    var list: LocalPlaylist? { library.extras.playlists.first { $0.id == playlistID } }
    func change(_ action: (inout LocalPlaylist) -> Void) {
        guard let index = library.extras.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        action(&library.extras.playlists[index]); library.saveExtras()
    }
    var tracks: [Song] { (list?.songIDs ?? []).compactMap { id in library.songs.first { $0.id == id } } }
    var body: some View {
        List {
            Button("Añadir pistas") { picking = true }
            Button("Cambiar nombre") { name = list?.name ?? ""; renaming = true }
            ForEach(tracks) { song in
                Button { player.play(song, from: tracks); showPlayer = true } label: { SongRow(song: song) }.buttonStyle(.plain)
            }.onDelete { offsets in let ids = offsets.map { tracks[$0].id }; change { $0.songIDs.removeAll { ids.contains($0) } } }
             .onMove { offsets, to in var ids = tracks.map(\.id); ids.move(fromOffsets: offsets, toOffset: to); change { $0.songIDs = ids } }
        }.navigationTitle(list?.name ?? "Playlist").toolbar { EditButton() }
            .alert("Nombre", isPresented: $renaming) { TextField("Nombre", text: $name); Button("Guardar") { if !name.trimmingCharacters(in: .whitespaces).isEmpty { change { $0.name = name } } }; Button("Cancelar", role: .cancel) {} }
            .sheet(isPresented: $picking) {
                NavigationStack {
                    List(library.songs.filter { $0.isVideo == list?.video }) { song in
                        Button { change { if !$0.songIDs.contains(song.id) { $0.songIDs.append(song.id) } } } label: { HStack { SongRow(song: song); if list?.songIDs.contains(song.id) == true { Image(systemName: "checkmark") } } }
                    }.navigationTitle("Añadir pistas").toolbar { Button("Listo") { picking = false } }
                }
            }.fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
    }
}

actor MusicBrainzCatalog {
    static let shared = MusicBrainzCatalog()
    private var nextRequest = Date.distantPast
    func json(_ endpoint: String, params: [String: String] = [:]) async throws -> [String: Any] {
        let reserved = max(Date(), nextRequest); nextRequest = reserved.addingTimeInterval(1.1)
        let delay = reserved.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try await OnlineSupport.json(OnlineSupport.url("https://musicbrainz.org/ws/2/" + endpoint, params.merging(["fmt": "json"]) { _, b in b }))
    }
    func search(title: String, artist: String) async throws -> [CatalogCandidate] {
        let clean: (String) -> String = { $0.replacingOccurrences(of: "\\", with: " ").replacingOccurrences(of: "\"", with: " ") }
        let result = try await json("recording", params: ["query": "recording:\"\(clean(title))\" AND artist:\"\(clean(artist))\"", "limit": "10"])
        return (result["recordings"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let names = (item["artist-credit"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            return CatalogCandidate(id: id, label: "\(item["title"] as? String ?? "") · \(names) · \(item["first-release-date"] as? String ?? "Sin fecha") · \((item["length"] as? Int ?? 0) / 1000)s")
        }
    }
    func credits(_ id: String) async throws -> TrackDetails {
        let item = try await json("recording/" + id, params: ["inc": "artist-credits+artist-rels+work-rels+work-level-rels+releases+genres"])
        return Self.parseCredits(item, id: id)
    }
    static func parseCredits(_ item: [String: Any], id: String) -> TrackDetails {
        var lines: [String] = []
        for artist in item["artist-credit"] as? [[String: Any]] ?? [] { if let name = artist["name"] as? String { lines.append("Intérprete: " + name) } }
        let roles = ["producer": "Productor", "engineer": "Ingeniero de audio", "mix": "Mezcla", "mastering": "Masterización", "lyricist": "Letrista", "composer": "Compositor", "writer": "Autor", "vocal": "Voz", "instrument": "Instrumentista"]
        func relations(_ object: [String: Any]) {
            for rel in object["relations"] as? [[String: Any]] ?? [] {
                if let artist = rel["artist"] as? [String: Any], let name = artist["name"] as? String {
                    let type = rel["type"] as? String ?? "Crédito"; let attributes = (rel["attributes"] as? [String] ?? []).joined(separator: ", ")
                    lines.append("\(roles[type] ?? type)\(attributes.isEmpty ? "" : " (\(attributes))"): \(name)")
                }
                if let work = rel["work"] as? [String: Any] { relations(work) }
            }
        }
        relations(item)
        let date = item["first-release-date"] as? String ?? (item["releases"] as? [[String: Any]] ?? []).compactMap { $0["date"] as? String }.sorted().first ?? ""
        let genre = (item["genres"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
        var seen = Set<String>(); lines = lines.filter { seen.insert($0).inserted }
        return TrackDetails(genre: genre, year: String(date.prefix(4)), credits: lines.joined(separator: "\n"), source: "https://musicbrainz.org/recording/" + id)
    }
    func artist(_ name: String) async throws -> String {
        let clean = name.replacingOccurrences(of: "\"", with: " ").replacingOccurrences(of: "\\", with: " ")
        let response = try await json("artist", params: ["query": "artist:\"\(clean)\"", "limit": "10"])
        let matches = (response["artists"] as? [[String: Any]] ?? []).filter { OnlineSupport.normalized($0["name"] as? String ?? "") == OnlineSupport.normalized(name) }
        guard matches.count == 1, let id = matches[0]["id"] as? String else { throw ServiceError(message: "Identidad ambigua o sin resultados. No se asignó información.") }
        let value = try await json("artist/" + id, params: ["inc": "genres+url-rels"])
        let life = value["life-span"] as? [String: Any] ?? [:]
        let area = value["area"] as? [String: Any] ?? [:]
        return ["Nombre: \(value["name"] as? String ?? name)", "Tipo: \(value["type"] as? String ?? "No disponible")", "País: \(value["country"] as? String ?? area["name"] as? String ?? "No disponible")", "Inicio: \(life["begin"] as? String ?? "No disponible")", "Fin: \(life["end"] as? String ?? "No disponible")", value["disambiguation"] as? String ?? "", "Fuente: https://musicbrainz.org/artist/\(id)"].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
struct CatalogCandidate: Identifiable { let id: String; let label: String }
struct CreditsView: View {
    @EnvironmentObject var library: MusicLibrary
    let song: Song
    @State private var info = TrackDetails()
    @State private var candidates: [CatalogCandidate] = []
    @State private var busy = false
    @State private var status = ""
    var body: some View {
        Form {
            Section("Información de la canción") { Text(song.title); Text(song.artist); TextField("Género", text: $info.genre); TextField("Año de publicación", text: $info.year) }
            Section("Créditos") {
                Text("Cantante, productor, ingeniero de audio, letrista, compositor y otros participantes.").font(.caption)
                TextEditor(text: $info.credits).frame(minHeight: 180)
                Button("Guardar créditos") { library.setDetails(info, for: song); status = "Guardados" }
                if info.credits.isEmpty { Text("Sin créditos adicionales disponibles. Puedes agregarlos manualmente.").font(.caption) }
            }
            Section("Consultar MusicBrainz") {
                Button(busy ? "Consultando…" : "Buscar grabación") {
                    busy = true
                    Task { defer { busy = false }; do { candidates = try await MusicBrainzCatalog.shared.search(title: song.title, artist: song.artist); status = candidates.isEmpty ? "Sin resultados" : "Selecciona la grabación. Revisa la versión antes de importar." } catch { status = error.localizedDescription } }
                }.disabled(busy)
                ForEach(candidates) { candidate in
                    Button("Importar: " + candidate.label) {
                        busy = true
                        Task { defer { busy = false }; do { let fetched = try await MusicBrainzCatalog.shared.credits(candidate.id); if info.genre.isEmpty { info.genre = fetched.genre }; if info.year.isEmpty { info.year = fetched.year }; let existing = info.credits.components(separatedBy: "\n"); let added = fetched.credits.components(separatedBy: "\n").filter { !existing.contains($0) && !$0.isEmpty }; info.credits = (existing.filter { !$0.isEmpty } + added).joined(separator: "\n"); info.source = fetched.source; library.setDetails(info, for: song); candidates = []; status = "Créditos importados; campos ausentes no disponibles en la fuente." } catch { status = error.localizedDescription } }
                    }.disabled(busy)
                }
                if let url = URL(string: info.source), url.scheme == "https" { Link("Ver fuente de los créditos", destination: url) }
                Text(status).font(.caption)
            }
        }.navigationTitle("Créditos e información").onAppear { info = library.details(song); if info.credits.isEmpty { info.credits = "Intérprete: " + song.artist } }
    }
}
struct ArtistInfoView: View {
    @EnvironmentObject var library: MusicLibrary
    let artist: String
    @State private var busy = false
    @State private var status = ""
    var body: some View {
        List {
            Text(library.extras.artists[artist] ?? "Sin información descargada.").textSelection(.enabled)
            Button(busy ? "Consultando…" : "Consultar información del artista") {
                busy = true
                Task { defer { busy = false }; do { library.extras.artists[artist] = try await MusicBrainzCatalog.shared.artist(artist); library.saveExtras(); status = "Información guardada para consulta sin conexión." } catch { status = error.localizedDescription } }
            }.disabled(busy)
            Text(status).font(.caption)
        }.navigationTitle(artist)
    }
}
