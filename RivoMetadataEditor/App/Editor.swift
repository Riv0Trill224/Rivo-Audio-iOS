import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct TrackEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.openURL) private var openURL
    @State var track: Track
    @State private var tags = Tags()
    @State private var originalTags = Tags()
    @State private var artwork = Data()
    @State private var artworkChanged = false
    @State private var removeArtwork = false
    @State private var loading = true
    @State private var saving = false
    @State private var metadata = false
    @State private var lyrics = false
    @State private var imageFile = false
    @State private var photo: PhotosPickerItem?
    @State private var linkPrompt = false
    @State private var imageLink = ""
    private let fields = [("TITLE", "Título"), ("ARTIST", "Artista"), ("ALBUM", "Álbum"), ("ALBUMARTIST", "Artista del álbum"),
                          ("DATE", "Año / fecha"), ("GENRE", "Género"), ("TRACKNUMBER", "Pista / total"), ("DISCNUMBER", "Disco / total"),
                          ("COMPOSER", "Compositor"), ("ISRC", "ISRC"), ("COMMENT", "Comentario")]
    private var dirty: Bool { tags != originalTags || artworkChanged || removeArtwork }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CoverView(data: artwork, size: 210).padding(.top, 12)
                VStack(spacing: 6) {
                    Text(track.title).font(.title2.bold()).multilineTextAlignment(.center).lineLimit(3)
                    Text((store.tracks.first { $0.id == track.id } ?? track).lyricsStatus).font(.caption).foregroundStyle(RivoStyle.accent)
                    Text(track.filename).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("\(track.bitrate) kbps · \(track.sampleRate) Hz · \(Int(track.duration) / 60):\(String(format: "%02d", Int(track.duration) % 60))").font(.caption).foregroundStyle(RivoStyle.accent)
                }.frame(maxWidth: .infinity)
                HStack(spacing: 18) {
                    Button { metadata = true } label: { Label("Datos", systemImage: "sparkle.magnifyingglass") }
                    Menu {
                        Button("Buscar en MusicBrainz") { metadata = true }
                        Button("Imagen desde Archivos") { imageFile = true }
                        Button("Enlace directo de imagen") { linkPrompt = true }
                        Button("Buscar en Google") { google() }
                        Button("Quitar portada frontal", role: .destructive) { artwork = Data(); artworkChanged = false; removeArtwork = true }
                    } label: { Label("Portada", systemImage: "photo") }
                    Button { lyrics = true } label: { Label("LRC", systemImage: "text.quote") }
                }.font(.subheadline).padding(16).frame(maxWidth: .infinity).rivoGlass()
                PhotosPicker(selection: $photo, matching: .images) { Label("Portada desde Fotos", systemImage: "photo.on.rectangle") }.font(.footnote)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(fields, id: \.0) { key, label in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(label).font(.caption).foregroundStyle(RivoStyle.accent)
                            TextField(label, text: Binding(get: { tags[key] }, set: { tags[key] = $0 }))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Picker("Clasificación", selection: Binding(get: { tags.advisory }, set: { tags.advisory = $0 })) {
                        ForEach(Advisory.allCases) { Text($0.label).tag($0) }
                    }
                    Text("En M4A/MP4 se guarda el indicador de Apple rtng. En los demás formatos la insignia depende del reproductor.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Etiquetas adicionales") {
                        ForEach(["LYRICS", "MUSICBRAINZ_TRACKID", "MUSICBRAINZ_ALBUMID"], id: \.self) { key in
                            TextField(key, text: Binding(get: { tags[key] }, set: { tags[key] = $0 }), axis: .vertical).font(.footnote)
                        }
                    }
                }.padding(20).rivoGlass()
                Text(track.relativePath).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 20).padding(.bottom, 30)
        }.background(RivoStyle.ink).navigationTitle("Editar canción").navigationBarTitleDisplayMode(.inline)
        .overlay { if loading || saving { ZStack { Color.black.opacity(0.4); ProgressView(saving ? "Verificando y guardando…" : "Leyendo archivo…").padding(24).rivoGlass() } } }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(!dirty || loading || saving || store.isWorking) } }
        .disabled(loading || saving || store.isWorking)
        .task { await load() }
        .sheet(isPresented: $metadata) {
            NavigationStack {
                MetadataSearchView(track: currentSearchTrack(), apply: { candidate in tags = candidate.tags(from: tags) }, cover: { data in setCover(data) })
            }.environmentObject(store)
        }
        .sheet(isPresented: $lyrics) { NavigationStack { LRCEditor(track: track) }.environmentObject(store) }
        .fileImporter(isPresented: $imageFile, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                guard size <= 20_000_000 else { throw RivoError.message("La imagen supera 20 MB.") }
                setCover(try Data(contentsOf: url))
            } catch { store.raise(error) }
        }
        .onChange(of: photo) { _, p in
            Task { do { if let bytes = try await p?.loadTransferable(type: Data.self) { setCover(bytes) } } catch { store.raise(error) } }
        }
        .alert("Enlace HTTPS a una portada", isPresented: $linkPrompt) {
            TextField("https://…/cover.jpg", text: $imageLink).textInputAutocapitalization(.never)
            Button("Descargar") { Task { do { guard let url = URL(string: imageLink) else { throw RivoError.message("Enlace inválido.") }; setCover(try await MusicServices.shared.artwork(url: url)) } catch { store.raise(error) } } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Desde Google puedes guardar una imagen en Fotos o copiar su enlace directo.") }
    }
    private func currentSearchTrack() -> Track { var t = track; t.tags = tags; return t }
    private func load() async {
        do {
            track = try await FileService.shared.refresh(track)
            let d = try await FileService.shared.detail(track)
            tags = d.tags; originalTags = d.tags; artwork = d.artwork
            store.update(track)
        } catch { store.raise(error) }
        loading = false
    }
    private func setCover(_ bytes: Data) {
        do { artwork = try ArtworkCodec.prepare(bytes); artworkChanged = true; removeArtwork = false }
        catch { store.raise(error) }
    }
    private func save() {
        saving = true
        Task {
            do {
                // Track tags remain the last verified source; only changed keys are passed to TagLib.
                var source = track; source.tags = originalTags
                track = try await store.save(source, tags: tags, artwork: artworkChanged ? artwork : nil, removeArtwork: removeArtwork)
                originalTags = track.tags; tags = track.tags; artworkChanged = false; removeArtwork = false
                store.dismissReview(track.id, metadata: true)
            } catch { store.raise(error) }
            saving = false
        }
    }
    private func google() {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: "\(tags["ARTIST"]) \(tags["ALBUM"]) album cover")]
        if let u = c.url { openURL(u) }
    }
}

struct MetadataSearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let apply: (MetadataCandidate) -> Void
    let cover: (Data) -> Void
    @State private var candidates: [MetadataCandidate] = []
    @State private var busy = false
    @State private var title = ""
    @State private var artist = ""
    var body: some View {
        List {
            Section("Búsqueda") {
                TextField("Título", text: $title)
                TextField("Artista", text: $artist)
                Button("Buscar MusicBrainz") { search() }.disabled(busy || title.isEmpty)
            }
            if busy { ProgressView("Buscando…") }
            ForEach(candidates) { c in
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.title).font(.headline)
                    Text(c.artist + " · " + c.album).font(.subheadline)
                    Text("\(c.date) · \(Int(c.duration)) s · MusicBrainz \(c.score)%").font(.caption).foregroundStyle(.secondary)
                    Button("Usar estos datos") { apply(c); dismiss() }
                    Button("Usar portada de esta edición") {
                        busy = true
                        Task {
                            do { cover(try await MusicServices.shared.cover(releaseID: c.releaseID)); dismiss() }
                            catch ServiceError.notFound { store.raise(RivoError.message("Esta edición no tiene portada en Cover Art Archive.")) }
                            catch { store.raise(error) }
                            busy = false
                        }
                    }.disabled(c.releaseID.isEmpty || busy)
                }.padding(.vertical, 6)
            }
            if candidates.isEmpty && !busy { Text("Sin resultados todavía").foregroundStyle(.secondary) }
        }.navigationTitle("Buscar datos").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        .onAppear {
            title = track.title; artist = track.artist
            if let pending = store.metadataReviews.first(where: { $0.id == track.id }), !pending.candidates.isEmpty { candidates = pending.candidates }
            else { search() }
        }
    }
    private func search() {
        busy = true
        var t = track; t.tags["TITLE"] = title; t.tags["ARTIST"] = artist
        Task { do { candidates = try await MusicServices.shared.metadata(t) } catch { store.raise(error) }; busy = false }
    }
}
