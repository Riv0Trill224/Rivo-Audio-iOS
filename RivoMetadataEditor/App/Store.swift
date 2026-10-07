import SwiftUI

struct MetadataReview: Identifiable, Codable, Sendable {
    var id: String { track.id }
    var track: Track
    var candidates: [MetadataCandidate]
    var reason: String
}

@MainActor final class LibraryStore: ObservableObject {
    @Published var folders: [MusicFolder] = []
    @Published var tracks: [Track] = []
    @Published var reviews: [ReviewItem] = []
    @Published var metadataReviews: [MetadataReview] = []
    @Published var history: [HistoryEntry] = []
    @Published var progress = JobProgress()
    @Published var isWorking = false
    @Published var status = "Selecciona una carpeta para comenzar"
    @Published var error: String?
    @Published var selected: Set<String> = []
    @Published var search = ""
    @Published var onlyAnalyze = false
    @Published var fillMetadata = true
    @Published var fillCovers = true
    private var job: Task<Void, Never>?
    private let files = FileService.shared
    private let services = MusicServices.shared
    private var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RivoQueue.json")
    }
    private struct Queue: Codable { var lyrics: [ReviewItem]; var metadata: [MetadataReview] }
    var filtered: [Track] {
        guard !search.isEmpty else { return tracks }
        return tracks.filter { [$0.title, $0.artist, $0.album, $0.filename].contains { $0.localizedCaseInsensitiveContains(search) } }
    }
    var targets: [Track] { selected.isEmpty ? tracks : tracks.filter { selected.contains($0.id) } }
    func raise(_ e: Error) { error = e.localizedDescription }
    private func persist() {
        if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: "musicFolders") }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Queue(lyrics: reviews, metadata: metadataReviews)).write(to: stateURL, options: .atomic)
        } catch { raise(error) }
    }
    func restore() async {
        if let data = UserDefaults.standard.data(forKey: "musicFolders"), let saved = try? JSONDecoder().decode([MusicFolder].self, from: data) {
            for folder in saved {
                do { folders.append(try await files.register(folder)) } catch { raise(error) }
            }
        }
        if let data = try? Data(contentsOf: stateURL), let q = try? JSONDecoder().decode(Queue.self, from: data) {
            reviews = q.lyrics; metadataReviews = q.metadata
        }
        do { history = try await files.loadHistory() } catch { raise(error) }
        if !folders.isEmpty { scan() }
    }
    func addFolder(_ url: URL) async {
        guard !isWorking else { return }
        do {
            let f = try await files.folder(from: url)
            if let i = folders.firstIndex(where: { $0.id == f.id }) { folders[i] = f } else { folders.append(f) }
            persist(); scan()
        } catch { raise(error) }
    }
    func removeFolder(_ id: UUID) {
        guard !isWorking else { return }
        folders.removeAll { $0.id == id }; tracks.removeAll { $0.folderID == id }
        reviews.removeAll { $0.track.folderID == id }; metadataReviews.removeAll { $0.track.folderID == id }
        persist()
    }
    func scan() {
        guard !isWorking, !folders.isEmpty else { return }
        isWorking = true; status = "Analizando archivos…"; progress = JobProgress()
        let snapshot = folders
        job = Task {
            do {
                let result = try await files.scan(snapshot) { done, total, current in
                    await MainActor.run { self.progress.completed = done; self.progress.total = total; self.progress.current = current }
                }
                tracks = result
                selected.formIntersection(Set(result.map(\.id)))
                status = "\(tracks.count) archivos · \(tracks.filter(\.hasLRC).count) con LRC"
            } catch is CancellationError { status = "Análisis detenido" }
            catch { raise(error); status = "No se pudo completar el análisis" }
            isWorking = false; job = nil
        }
    }
    func cancel() { job?.cancel() }
    func update(_ track: Track) {
        if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i] = track }
    }
    func save(_ track: Track, tags: Tags, artwork: Data?, removeArtwork: Bool) async throws -> Track {
        guard !isWorking else { throw RivoError.message("Espera a que termine el proceso actual.") }
        let updated = try await files.save(track, patch: tags.changes(from: track.tags), artwork: artwork, removeArtwork: removeArtwork)
        update(updated); history = try await files.loadHistory(); return updated
    }
    func acceptLyrics(_ track: Track, candidate: LyricsCandidate) async throws {
        guard candidate.isSynced, let text = candidate.syncedLyrics else { throw RivoError.message("Esta coincidencia no tiene letra sincronizada.") }
        let current = tracks.first { $0.id == track.id } ?? track
        update(try await files.saveLRC(current, text: text))
        reviews.removeAll { $0.id == track.id }; history = try await files.loadHistory(); persist()
    }
    func saveLRC(_ track: Track, text: String, hash: String?) async throws {
        update(try await files.saveLRC(track, text: text, expectedExistingHash: hash))
        reviews.removeAll { $0.id == track.id }; history = try await files.loadHistory(); persist()
    }
    func dismissReview(_ id: String, metadata: Bool = false) {
        if metadata { metadataReviews.removeAll { $0.id == id } } else { reviews.removeAll { $0.id == id } }
        persist()
    }
    func undo(_ entry: HistoryEntry) async {
        guard !isWorking else { return }
        do { try await files.undo(entry); history = try await files.loadHistory(); scan() } catch { raise(error) }
    }
    private func queueLyrics(_ item: ReviewItem) { reviews.removeAll { $0.id == item.id }; reviews.append(item); persist() }
    private func queueMetadata(_ item: MetadataReview) { metadataReviews.removeAll { $0.id == item.id }; metadataReviews.append(item); persist() }

    func automate() {
        guard !isWorking, !targets.isEmpty else { return }
        let snapshot = targets
        let analyze = onlyAnalyze, metadata = fillMetadata, covers = fillCovers
        isWorking = true; progress = JobProgress(total: snapshot.count); status = analyze ? "Analizando coincidencias" : "Automatización en curso"
        job = Task {
            for original in snapshot {
                if Task.isCancelled { break }
                var track = original
                let start = Date()
                progress.current = track.title
                if let reason = track.error {
                    progress.failed += 1
                    queueLyrics(ReviewItem(track: track, candidates: [], reason: reason))
                    progress.finish(seconds: Date().timeIntervalSince(start)); continue
                }
                do {
                    if metadata || (covers && !track.hasArtwork) {
                        let candidates = try await services.metadata(track)
                        let safe = candidates.filter { $0.isSafe(for: track) }
                        if safe.count == 1, let match = safe.first, !analyze {
                            let updated = metadata ? match.tags(from: track.tags, onlyEmpty: true) : track.tags
                            var art: Data?
                            if covers && !track.hasArtwork && !match.releaseID.isEmpty {
                                do { art = try await services.cover(releaseID: match.releaseID) }
                                catch ServiceError.notFound { /* No cover on this release. */ }
                            }
                            if !updated.changes(from: track.tags).isEmpty || art != nil {
                                track = try await files.save(track, patch: updated.changes(from: track.tags), artwork: art, removeArtwork: false)
                                update(track)
                            }
                        } else if !candidates.isEmpty && (metadata || !track.hasArtwork) {
                            queueMetadata(MetadataReview(track: track, candidates: candidates, reason: analyze ? "Propuesta: revisar antes de guardar" : "Varias ediciones o datos insuficientes"))
                        }
                    }
                } catch is CancellationError { break }
                catch {
                    queueMetadata(MetadataReview(track: track, candidates: [], reason: error.localizedDescription))
                }
                do {
                    try Task.checkCancellation()
                    track = try await files.refresh(track)
                    update(track)
                    if track.hasLRC { progress.skipped += 1 }
                    else {
                        let candidates = try await services.lyrics(track)
                        if let match = Match.automatic(candidates, track: track), let text = match.syncedLyrics, !analyze {
                            track = try await files.saveLRC(track, text: text)
                            update(track); reviews.removeAll { $0.id == track.id }; progress.found += 1
                        } else {
                            queueLyrics(ReviewItem(track: track, candidates: candidates,
                                                   reason: candidates.isEmpty ? "Sin coincidencia" : analyze ? "Propuesta: revisar antes de guardar" : "Requiere elegir una versión"))
                            progress.pending += 1
                        }
                    }
                } catch is CancellationError { break }
                catch { queueLyrics(ReviewItem(track: track, candidates: [], reason: error.localizedDescription)); progress.failed += 1 }
                progress.finish(seconds: Date().timeIntervalSince(start)); persist()
            }
            status = Task.isCancelled ? "Detenido · puedes reanudar; se omiten letras existentes" : "Proceso terminado"
            do { history = try await files.loadHistory() } catch { raise(error) }
            isWorking = false; job = nil; persist()
        }
    }
    func batch(_ patch: [String: String]) async {
        guard !isWorking, !patch.isEmpty else { return }
        let snapshot = targets
        isWorking = true; progress = JobProgress(total: snapshot.count); status = "Guardando etiquetas"
        // This task is stored so Stop actually cancels the batch as well.
        job = Task {
            for track in snapshot {
                if Task.isCancelled { break }
                progress.current = track.title; let start = Date()
                do { update(try await files.save(track, patch: patch, artwork: nil, removeArtwork: false)); progress.found += 1 }
                catch { progress.failed += 1; raise(error) }
                progress.finish(seconds: Date().timeIntervalSince(start))
            }
            do { history = try await files.loadHistory() } catch { raise(error) }
            status = Task.isCancelled ? "Edición detenida" : "Edición terminada"; isWorking = false; job = nil
        }
    }
}
