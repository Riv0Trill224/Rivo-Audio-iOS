import SwiftUI
import UniformTypeIdentifiers

@main struct RivoMetadataEditorApp: App {
    @StateObject private var store = LibraryStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark).tint(RivoStyle.accent)
                .task { await store.restore() }
        }
    }
}

enum RivoStyle {
    // Exact components from Rivo Audio iOS / PlayerStyle.swift.
    static let accent = Color(red: 0.83, green: 0.68, blue: 1)
    static let ink = Color(red: 0.035, green: 0.045, blue: 0.08)
    static let surface = Color(red: 0.10, green: 0.105, blue: 0.16)
}
struct RivoGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(RivoStyle.accent.opacity(0.07)), in: RoundedRectangle(cornerRadius: 20))
        } else { content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)) }
    }
}
extension View { func rivoGlass() -> some View { modifier(RivoGlass()) } }

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView {
            NavigationStack { LibraryView() }.tabItem { Label("Biblioteca", systemImage: "music.note.list") }
            NavigationStack { AutomationView() }.tabItem { Label("Automatizar", systemImage: "wand.and.stars") }
            NavigationStack { PendingView() }.tabItem { Label("Pendientes", systemImage: "checklist") }
                .badge(store.reviews.count + store.metadataReviews.count)
            NavigationStack { SettingsView() }.tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
        .background(RivoStyle.ink)
        .alert("Rivo Metadata Editor", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Aceptar", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: phase) { _, new in
            // iOS may suspend network jobs; cancel cleanly and let existing sidecars resume the job.
            if new == .background && store.isWorking { store.cancel() }
        }
    }
}

struct CoverView: View {
    var data: Data = Data()
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { RivoStyle.surface; Image(systemName: "music.note").font(.system(size: size * 0.32)).foregroundStyle(RivoStyle.accent) } }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.08)))
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var pickFolder = false
    @State private var selectMode = false
    @State private var batch = false
    var body: some View {
        Group {
            if store.tracks.isEmpty && !store.isWorking {
                ContentUnavailableView {
                    Label("Tu música, bien organizada", systemImage: "waveform")
                } description: { Text("Selecciona una carpeta de Archivos. Tus canciones se editan en su ubicación original.") } actions: {
                    Button("Seleccionar carpeta") { pickFolder = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if store.isWorking { ProgressCard().listRowBackground(Color.clear) }
                    ForEach(store.filtered) { track in
                        if selectMode {
                            Button {
                                if !store.selected.insert(track.id).inserted { store.selected.remove(track.id) }
                            } label: {
                                HStack { Image(systemName: store.selected.contains(track.id) ? "checkmark.circle.fill" : "circle"); TrackRow(track: track) }
                            }.listRowBackground(RivoStyle.surface)
                        } else {
                            NavigationLink { TrackEditor(track: track) } label: { TrackRow(track: track) }
                                .listRowBackground(RivoStyle.surface)
                        }
                    }
                }.scrollContentBackground(.hidden)
            }
        }
        .background(RivoStyle.ink).navigationTitle("Biblioteca")
        .searchable(text: $store.search, prompt: "Canción, artista o álbum")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(selectMode ? "Listo" : "Seleccionar") { selectMode.toggle() }.disabled(store.tracks.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Añadir carpeta", systemImage: "folder.badge.plus") { pickFolder = true }
                    Button("Escanear nuevamente", systemImage: "arrow.clockwise") { store.scan() }
                    Button("Editar selección", systemImage: "pencil") { batch = true }.disabled(store.selected.isEmpty)
                    Button("Seleccionar visibles") { store.selected.formUnion(store.filtered.map(\.id)); selectMode = true }
                    Button("Limpiar selección") { store.selected.removeAll() }
                } label: { Image(systemName: "ellipsis.circle") }.disabled(store.isWorking)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.selected.isEmpty { Text("\(store.selected.count) canciones seleccionadas").font(.footnote).padding(12).rivoGlass().padding(.bottom, 6) }
        }
        .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
            switch result { case .success(let url): Task { await store.addFolder(url) }; case .failure(let e): store.raise(e) }
        }
        .sheet(isPresented: $batch) { NavigationStack { BatchEditor() }.environmentObject(store) }
    }
}
struct TrackRow: View {
    let track: Track
    @State private var cover = Data()
    var body: some View {
        HStack(spacing: 12) {
            CoverView(data: cover, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(track.title).font(.headline).lineLimit(1)
                    if track.tags.advisory == .explicit { Text("E").font(.caption2.bold()).padding(3).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3)) }
                    if track.tags.advisory == .clean { Text("CLEAN").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(track.lyricsStatus).font(.caption2).foregroundStyle(RivoStyle.accent).fixedSize(horizontal: false, vertical: true)
                Text(track.artist.isEmpty ? track.filename : track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Text((track.filename as NSString).pathExtension.uppercased())
                    if track.error != nil { Label("No legible", systemImage: "exclamationmark.triangle") }
                }.font(.caption2).foregroundStyle(RivoStyle.accent)
            }
        }.padding(.vertical, 4)
        .task(id: track.id + String(track.stamp.modified.timeIntervalSince1970)) {
            if track.hasArtwork { cover = (try? await FileService.shared.thumbnail(track)) ?? Data() }
            else { cover = Data() }
        }
    }
}

struct ProgressCard: View {
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(store.status).font(.headline); Spacer(); if store.isWorking { ProgressView() } }
            Text(store.progress.current).font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
            ProgressView(value: store.progress.fraction)
            HStack { Text("\(store.progress.completed) / \(store.progress.total)"); Spacer(); Text(store.progress.eta) }.font(.caption)
            HStack {
                Text("\(store.progress.found) guardadas")
                Text("\(store.progress.skipped) existentes")
                Text("\(store.progress.pending) revisar")
            }.font(.caption2).foregroundStyle(.secondary)
            if store.progress.failed > 0 { Text("\(store.progress.failed) errores").font(.caption).foregroundStyle(.orange) }
            if store.isWorking { Button("Detener", role: .destructive) { store.cancel() } }
        }.padding(18).rivoGlass()
    }
}
struct AutomationView: View {
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Completa tu biblioteca").font(.largeTitle.bold())
                Text("\(store.targets.count) canciones · \(store.targets.filter { !$0.hasLRC }.count) sin LRC").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Contrastar título y artista con Genius", isOn: $store.verifyGenius)
                    Text("Genius requiere un token en Ajustes para el contraste automático. Sin confirmación, la canción pasa a Pendientes. Puedes consultar Genius y elegir el LRC manualmente.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Solo analizar", isOn: $store.onlyAnalyze)
                    Toggle("Completar metadatos vacíos", isOn: $store.fillMetadata)
                    Toggle("Buscar portadas faltantes", isOn: $store.fillCovers)
                    Text("Las letras existentes se conservan. Solo se descargan automáticamente coincidencias con título, artista, versión y duración seguros. Al salir de la app se detiene el trabajo; al volver puedes reanudarlo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20).rivoGlass().disabled(store.isWorking)
                Button { store.automate() } label: {
                    Label(store.onlyAnalyze ? "Analizar coincidencias" : "Iniciar automatización", systemImage: "wand.and.stars").frame(maxWidth: .infinity).padding(8)
                }.buttonStyle(.borderedProminent).disabled(store.targets.isEmpty || store.isWorking)
                if store.progress.total > 0 || store.isWorking { ProgressCard() }
            }.padding(20)
        }.background(RivoStyle.ink).navigationTitle("Automatizar").navigationBarTitleDisplayMode(.inline)
    }
}
struct PendingView: View {
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        List {
            if store.reviews.isEmpty && store.metadataReviews.isEmpty { Text("No hay coincidencias pendientes").foregroundStyle(.secondary) }
            Section("Letras") {
                ForEach(store.reviews) { item in
                    NavigationLink { LyricsSearchView(track: item.track, initial: item.candidates) } label: {
                        VStack(alignment: .leading) { Text(item.track.title); Text(item.reason).font(.caption).foregroundStyle(.secondary) }
                    }.swipeActions { Button("Descartar", role: .destructive) { store.dismissReview(item.id) } }
                }
            }
            Section("Metadatos y portadas") {
                ForEach(store.metadataReviews) { item in
                    NavigationLink { TrackEditor(track: store.tracks.first { $0.id == item.id } ?? item.track) } label: {
                        VStack(alignment: .leading) { Text(item.track.title); Text(item.reason).font(.caption).foregroundStyle(.secondary) }
                    }.swipeActions { Button("Descartar", role: .destructive) { store.dismissReview(item.id, metadata: true) } }
                }
            }
        }.scrollContentBackground(.hidden).background(RivoStyle.ink).navigationTitle("Pendientes").disabled(store.isWorking)
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var geniusToken = ""
    @State private var tokenStatus = ""
    var body: some View {
        List {
            Section("Carpetas autorizadas") {
                ForEach(store.folders) { folder in
                    HStack { Label(folder.name, systemImage: "folder"); Spacer(); Button(role: .destructive) { store.removeFolder(folder.id) } label: { Image(systemName: "minus.circle") } }
                }
            }
            Section("Historial y recuperación") {
                ForEach(store.history) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text((entry.relativePath as NSString).lastPathComponent).lineLimit(1)
                        Text(entry.description + " · " + entry.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        Button("Deshacer") { Task { await store.undo(entry) } }
                    }
                }
                if store.history.isEmpty { Text("Los cambios guardados aparecerán aquí") }
            }
            Section("Clasificación de contenido") {
                Text("M4A/MP4 utiliza rtng: 0 sin clasificar, 1 explícito, 2 limpio. MP3, FLAC y otros formatos guardan ITUNESADVISORY. La insignia E depende del soporte del reproductor.").font(.footnote)
            }
            Section("Genius · segunda fuente") {
                SecureField("Client Access Token", text: $geniusToken).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Guardar token") {
                    do { try GeniusCredentials.save(geniusToken); geniusToken = ""; tokenStatus = "Token guardado en este iPhone" }
                    catch { store.raise(error) }
                }.disabled(geniusToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Eliminar token", role: .destructive) {
                    do { try GeniusCredentials.save(""); geniusToken = ""; tokenStatus = "Token eliminado" }
                    catch { store.raise(error) }
                }
                if !tokenStatus.isEmpty { Text(tokenStatus).font(.caption) }
                Link("Crear token en Genius", destination: URL(string: "https://genius.com/api-clients")!)
                Text("La búsqueda en la web funciona sin token. La búsqueda integrada contrasta título y artista, y enlaza a la letra de Genius. Los tiempos LRC provienen de LRCLIB o de tu archivo.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Acerca de") {
                Text("Rivo Metadata Editor · 0.2.0")
                Text("Riv0Trill224").foregroundStyle(RivoStyle.accent)
                Link("GitHub · Riv0Trill224", destination: URL(string: "https://github.com/Riv0Trill224")!)
                Link("Letras · Genius", destination: URL(string: "https://genius.com")!)
                Link("Letras · LRCLIB", destination: URL(string: "https://lrclib.net")!)
                Link("Metadatos · MusicBrainz", destination: URL(string: "https://musicbrainz.org")!)
                Text("Portadas: Cover Art Archive. Etiquetas: TagLib 2.3.2 (MPL 1.1 / LGPL 2.1). No se convierte ni recodifica el audio.").font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(RivoStyle.ink).navigationTitle("Ajustes").disabled(store.isWorking)
    }
}

struct BatchEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var enabled: Set<String> = []
    @State private var rating: Advisory = .none
    @State private var confirm = false
    private let fields = [("ARTIST", "Artista"), ("ALBUMARTIST", "Artista del álbum"), ("ALBUM", "Álbum"), ("DATE", "Año / fecha"), ("GENRE", "Género"), ("COMPOSER", "Compositor")]
    var body: some View {
        Form {
            Text("\(store.targets.count) canciones. Solo se cambian los campos activados; un campo activado vacío se elimina.").font(.footnote)
            ForEach(fields, id: \.0) { key, label in
                VStack(alignment: .leading) {
                    Toggle(label, isOn: Binding(get: { enabled.contains(key) }, set: { if $0 { enabled.insert(key) } else { enabled.remove(key) } }))
                    if enabled.contains(key) { TextField(label, text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })) }
                }
            }
            Toggle("Cambiar clasificación", isOn: Binding(get: { enabled.contains("ITUNESADVISORY") }, set: { if $0 { enabled.insert("ITUNESADVISORY") } else { enabled.remove("ITUNESADVISORY") } }))
            if enabled.contains("ITUNESADVISORY") { Picker("Contenido", selection: $rating) { ForEach(Advisory.allCases) { Text($0.label).tag($0) } } }
        }.navigationTitle("Edición múltiple")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Aplicar") { confirm = true }.disabled(enabled.isEmpty) }
        }
        .confirmationDialog("Guardar en \(store.targets.count) archivos", isPresented: $confirm, titleVisibility: .visible) {
            Button("Guardar cambios") {
                var patch: [String: String] = [:]
                for key in enabled { patch[key] = key == "ITUNESADVISORY" ? String(rating.rawValue) : values[key] ?? "" }
                Task { await store.batch(patch) }; dismiss()
            }
        }
    }
}
