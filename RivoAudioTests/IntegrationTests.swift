import XCTest
import AVFoundation
@testable import RivoAudio

final class IntegrationTests: XCTestCase {
    func song(_ title: String, artist: String = "Example", video: Bool = false) -> Song {
        Song(id: title + (video ? ".mov" : ".wav"), title: title, artist: artist, album: "Album", duration: 180, isVideo: video)
    }
    func testExactFilenameMatching() {
        let audio = song("My Song")
        let exact = song("My Song", video: true)
        let official = song("My Song Official Video", video: true)
        XCTAssertEqual(MediaMatcher.candidates(for: audio, in: [exact, official]).map(\.id), [exact.id])
        XCTAssertTrue(MediaMatcher.candidates(for: audio, in: [song("my song", video: true)]).isEmpty)
        var second = exact; second.id = "other/My Song.mov"
        XCTAssertNil(MediaMatcher.automaticMatch(MediaMatcher.candidates(for: audio, in: [exact, second])))
    }
    @MainActor func testExtrasSurviveScanAndReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(documents: directory, scanOnStart: false)
        let track = song("Saved")
        try makeTone(at: library.url(for: track))
        await library.scan()
        var saved = try XCTUnwrap(library.songs.first); saved.rating = 5; library.update(saved)
        library.setDetails(TrackDetails(genre: "Jazz", year: "2020", credits: "Productor: Example", source: "manual"), for: saved)
        library.extras.playlists = [LocalPlaylist(name: "Mis pistas", video: false, songIDs: [saved.id]), LocalPlaylist(name: "Mis videos", video: true)]
        library.saveExtras(); await library.fullScan()
        let reload = MusicLibrary(documents: directory, scanOnStart: false)
        XCTAssertEqual(reload.songs.first?.rating, 5)
        XCTAssertEqual(reload.extras.playlists.count, 2)
        XCTAssertEqual(reload.details(saved).credits, "Productor: Example")
    }
    func testCreditsIncludeRecordingAndWorkParticipants() async {
        let info = await MusicBrainzCatalog.parseCredits(["artist-credit": [["name": "Singer"]], "first-release-date": "2020-01-02", "relations": [["type": "producer", "artist": ["name": "Producer"]], ["work": ["relations": [["type": "lyricist", "artist": ["name": "Writer"]]]]]]], id: "test")
        XCTAssertTrue(info.credits.contains("Productor: Producer")); XCTAssertTrue(info.credits.contains("Letrista: Writer")); XCTAssertEqual(info.year, "2020")
    }
    @MainActor func testVideoCompletionKeepsNextSongAndDoesNotLoop() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(documents: directory, scanOnStart: false)
        let first = song("First"), next = song("Next"), video = song("First", video: true)
        try makeTone(at: library.url(for: first)); try makeTone(at: library.url(for: next)); try await makeVideo(at: library.url(for: video)); await library.scan()
        let player = AudioPlayer(); player.library = library
        player.play(first, from: [first, next]); player.pause()
        await player.switchToVideo(video)
        XCTAssertEqual(player.videoPlayer?.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)
        player.advanceAtEnd(); XCTAssertEqual(player.song?.id, next.id)
        player.advanceAtEnd(); XCTAssertFalse(player.playing); XCTAssertEqual(player.song?.id, next.id)
    }
    func testLastFMSignatureAndEncoding() {
        let parameters = ["api_key": "abc", "method": "auth.getSession", "token": "xyz", "format": "json"]
        XCTAssertEqual(LastFMProtocol.signature(parameters, secret: "secret"), "f81f920d21fa903b7fa44ae2857c6bbd")
        XCTAssertEqual(LastFMProtocol.form(["artist": "A+B & C"]), "artist=A%2BB%20%26%20C")
        XCTAssertFalse(LastFMProtocol.accepted(["scrobbles": ["@attr": ["accepted": "0", "ignored": "1"]]]))
        XCTAssertTrue(LastFMProtocol.accepted(["scrobbles": ["@attr": ["accepted": "1", "ignored": "0"]]]))
    }
    func testArtistPhotoUsesLinkedIdentityAndRetainsAttribution() async throws {
        let source = ArtistPhotoSource(jsonRequest: { url in
            if url.host == "musicbrainz.org", URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "query" }) == true {
                return ["artists": [["id": "artist-id", "name": "Example"]]]
            }
            if url.host == "musicbrainz.org" {
                return ["relations": [["type": "wikidata", "url": ["resource": "https://www.wikidata.org/wiki/Q123"]]]]
            }
            if url.host == "www.wikidata.org" {
                return ["entities": ["Q123": ["claims": ["P18": [["rank": "normal", "mainsnak": ["datavalue": ["value": "Example.jpg"]]]]]]]]
            }
            return ["query": ["pages": [["imageinfo": [["thumburl": "https://upload.wikimedia.org/example.jpg",
                "descriptionurl": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                "extmetadata": ["Artist": ["value": "<b>Photographer</b>"], "LicenseShortName": ["value": "CC BY 4.0"], "LicenseUrl": ["value": "https://creativecommons.org/licenses/by/4.0/"]]]]]]]]
        }, imageRequest: { url in
            XCTAssertEqual(url.host, "upload.wikimedia.org")
            return Data([1, 2, 3])
        })
        let (data, credit) = try await source.download(artist: "Example")
        XCTAssertEqual(data, Data([1, 2, 3]))
        XCTAssertEqual(credit.author, "Photographer")
        XCTAssertEqual(credit.license, "CC BY 4.0")
        XCTAssertEqual(credit.musicBrainzID, "artist-id")
    }
    func testAmbiguousArtistDoesNotDownloadAPhoto() async {
        let source = ArtistPhotoSource(jsonRequest: { _ in
            ["artists": [["id": "one", "name": "Example"], ["id": "two", "name": "Example"]]]
        }, imageRequest: { _ in XCTFail("An ambiguous artist must not download a photo"); return Data() })
        do { _ = try await source.download(artist: "Example"); XCTFail("Expected ambiguous identity error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("identidad")) }
    }
    @MainActor func testAudioVideoSwitchPreservesPausedPosition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(documents: directory, scanOnStart: false)
        let audio = Song(id: "tone.wav", title: "Tone", artist: "Example", album: "Test", duration: 3)
        let video = Song(id: "tone.mov", title: "Tone", artist: "Example", album: "Test", duration: 3, isVideo: true)
        try makeTone(at: library.url(for: audio))
        try await makeVideo(at: library.url(for: video))
        let player = AudioPlayer(); player.library = library
        player.play(audio, from: [audio]); player.pause(); player.seek(to: 1.2)
        XCTAssertNil(player.error)
        XCTAssertFalse(player.playing)
        XCTAssertEqual(player.elapsed, 1.2, accuracy: 0.1)
        await player.switchToVideo(video)
        XCTAssertNil(player.error)
        XCTAssertTrue(player.isVideoMode)
        XCTAssertFalse(player.playing)
        XCTAssertEqual(player.elapsed, 1.2, accuracy: 0.15)
        player.switchToAudio()
        XCTAssertFalse(player.isVideoMode)
        XCTAssertFalse(player.playing)
        XCTAssertEqual(player.elapsed, 1.2, accuracy: 0.15)
        player.pause()
    }
    @MainActor func testCoordinatedImportWithUnicodeAndReservedCharactersPlays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Ácido #100% [Prod. by Artist].wav")
        try makeTone(at: source)
        let library = MusicLibrary(documents: directory.appendingPathComponent("Library"), scanOnStart: false)
        await library.importFiles([source])
        let imported = try XCTUnwrap(library.songs.first)
        XCTAssertEqual(imported.id, source.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: library.url(for: imported)), try Data(contentsOf: source))
        let player = AudioPlayer(); player.library = library
        player.play(imported, from: [imported])
        XCTAssertNil(player.error)
        XCTAssertTrue(player.playing)
        player.pause()
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.musicDirectory.appendingPathComponent(imported.id).path))
        let reloaded = MusicLibrary(documents: library.documents, scanOnStart: false)
        XCTAssertEqual(try reloaded.access(for: XCTUnwrap(reloaded.songs.first)).url.resolvingSymlinksInPath(), source.resolvingSymlinksInPath())
        // A symlink alias must produce the same relative ID as its canonical directory.
        let alias = directory.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        XCTAssertEqual(MediaFiles.relativePath(of: alias.appendingPathComponent(imported.id), under: directory), imported.id)
        XCTAssertNil(MediaFiles.relativePath(of: source, under: library.musicDirectory))
    }
    @MainActor func testFolderImportKeepsSubfoldersAndDoesNotDuplicateOnRescan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Colección/Artist/Album", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let original = source.appendingPathComponent("Track.wav")
        try makeTone(at: original)
        let library = MusicLibrary(documents: root.appendingPathComponent("App"), scanOnStart: false)
        await library.importFolder(root.appendingPathComponent("Colección"))
        XCTAssertEqual(library.folders.count, 1)
        XCTAssertEqual(library.songs.map(\.id), ["Colección/Artist/Album/Track.wav"])
        let saved = try XCTUnwrap(library.folders.first)
        await library.rescanFolder(saved)
        XCTAssertEqual(library.songs.count, 1)
        await library.removeFolder(saved)
        XCTAssertTrue(library.songs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }
    @MainActor func testAACCompatibilityDecodePreservesAudioAndSupportsEQPlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = MusicLibrary(documents: directory, scanOnStart: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wav = library.musicDirectory.appendingPathComponent("original.wav")
        try makeTone(at: wav)
        let compressed = library.musicDirectory.appendingPathComponent("compressed.m4a")
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: wav), presetName: AVAssetExportPresetAppleM4A))
        exporter.outputURL = compressed; exporter.outputFileType = .m4a
        await exporter.export()
        XCTAssertEqual(exporter.status, .completed)
        let before = try Data(contentsOf: compressed)
        let decoded = try await AudioFileLoader.shared.decode(compressed)
        let file = try AVAudioFile(forReading: decoded)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 3, accuracy: 0.15)
        XCTAssertEqual(try Data(contentsOf: compressed), before)
        let peaks = await WaveformReader.shared.peaks(decoded)
        XCTAssertEqual(peaks.count, 56)
        XCTAssertGreaterThan(peaks.max() ?? 0, 0)
        let player = AudioPlayer()
        let audio = Song(id: decoded.path, title: "Decoded", artist: "Test", album: "Test", duration: 3)
        player.setPreset("Graves"); player.play(audio, from: [audio])
        XCTAssertTrue(player.playing); XCTAssertNil(player.error)
        player.pause(); player.seek(to: 1)
        XCTAssertFalse(player.playing); XCTAssertEqual(player.elapsed, 1, accuracy: 0.1)
    }
    @MainActor func testEmptyAndMissingFilesHaveActionableErrors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = MusicLibrary(documents: directory, scanOnStart: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = Song(id: "empty.mp3", title: "Empty", artist: "Test", album: "Test", duration: 0)
        try Data().write(to: library.url(for: empty))
        let player = AudioPlayer(); player.library = library
        player.play(empty, from: [empty])
        XCTAssertFalse(player.playing); XCTAssertFalse(player.preparingAudio)
        XCTAssertTrue(player.error?.contains("vacío") == true)
        try FileManager.default.removeItem(at: library.url(for: empty))
        player.play(empty, from: [empty])
        XCTAssertNotNil(player.error); XCTAssertFalse(player.playing)
    }
    @MainActor func testLinkedFolderReloadAndVerifiedCopyMigration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let original = source.appendingPathComponent("Track.wav")
        try makeTone(at: original)
        let library = MusicLibrary(documents: root.appendingPathComponent("App"), scanOnStart: false)
        await library.importFolder(source); await library.importFolder(source)
        XCTAssertEqual(library.folders.count, 1); XCTAssertEqual(library.songs.count, 1)
        var track = try XCTUnwrap(library.songs.first)
        let copy = library.musicDirectory.appendingPathComponent(track.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(library.url(for: track).resolvingSymlinksInPath(), original.resolvingSymlinksInPath())
        track.rating = 5; library.update(track)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: original, to: copy)
        track.sourceFolderID = nil; track.sourceRelativePath = nil
        library.update(track); library.folders[0].linked = nil; library.save()
        await library.migrateAndReleaseCopies()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        let reloaded = MusicLibrary(documents: library.documents, scanOnStart: false)
        XCTAssertEqual(reloaded.songs.first?.rating, 5)
        XCTAssertEqual(try reloaded.access(for: XCTUnwrap(reloaded.songs.first)).url.resolvingSymlinksInPath(), original.resolvingSymlinksInPath())
        try Data("different retained copy".utf8).write(to: copy)
        await reloaded.migrateAndReleaseCopies()
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }
    @MainActor func testPauseStopsEngineAndBackgroundUsesSparseTimer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MusicLibrary(documents: root, scanOnStart: false)
        let track = song("Battery")
        try makeTone(at: library.url(for: track))
        let player = AudioPlayer(); player.library = library
        player.play(track, from: [track])
        XCTAssertTrue(player.isEngineRunning)
        player.setInterfaceActive(false)
        XCTAssertEqual(player.progressTimerInterval, 30)
        player.pause()
        XCTAssertFalse(player.isEngineRunning)
        XCTAssertNil(player.progressTimerInterval)
        player.seek(to: 1)
        XCTAssertFalse(player.isEngineRunning)
    }
    func testAlbumGroupingKeepsCollaboratorsAndDiscOrder() {
        var first = song("First", artist: "Main feat Guest")
        first.albumArtist = "Main"; first.discNumber = 1; first.trackNumber = 2
        var second = song("Second", artist: "Main")
        second.albumArtist = "Main"; second.discNumber = 1; second.trackNumber = 1
        let albums = AlbumCollection.grouped([first, second])
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.tracks.map(\.id), [second.id, first.id])
    }
    private func makeTone(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132300)!
        buffer.frameLength = 132300
        for channel in 0..<2 {
            for frame in 0..<132300 { buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 440 * 2 * .pi / 44100)) * 0.01 }
        }
        try file.write(from: buffer)
    }
    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ServiceError(message: "Video fixture failed") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<31 {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000); attempts += 1
                if attempts > 1000 { throw ServiceError(message: "Video fixture timeout") }
            }
            var pixel: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixel)
            guard let pixel else { throw ServiceError(message: "No pixel buffer") }
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 0, CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else { throw writer.error ?? ServiceError(message: "Cannot append video") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ServiceError(message: "Cannot finish video") }
    }
}

final class LyricsPersistenceTests: XCTestCase {
    @MainActor func testMigrationRenameAndDeleteSurviveReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Music"), withIntermediateDirectories: true)
        var song = Song(id: "track.wav", title: "Before", artist: "Example", album: "Test", duration: 180)
        song.lyrics = "[00:01.00]Hello"
        try JSONEncoder().encode([song]).write(to: dir.appendingPathComponent("library.json"))
        let library = MusicLibrary(documents: dir, scanOnStart: false)
        library.migrateLyrics()
        XCTAssertEqual(library.localLyrics(for: library.songs[0]), "[00:01.00]Hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(library.lyricFile(for: song)).path))
        var renamed = library.songs[0]; renamed.title = "After"; library.update(renamed)
        let reloaded = MusicLibrary(documents: dir, scanOnStart: false)
        XCTAssertEqual(reloaded.localLyrics(for: reloaded.songs[0]), "[00:01.00]Hello")
        try "[00:01]Legacy".write(to: dir.appendingPathComponent("Music/track.lrc"), atomically: true, encoding: .utf8)
        try reloaded.deleteLyrics(for: reloaded.songs[0])
        let deleted = MusicLibrary(documents: dir, scanOnStart: false)
        deleted.migrateLyrics()
        XCTAssertNil(deleted.localLyrics(for: deleted.songs[0]))
        XCTAssertNil(deleted.lyricFile(for: deleted.songs[0]))
    }
}
