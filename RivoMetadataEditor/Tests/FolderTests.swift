import XCTest
@testable import RivoMetadataEditor

final class FolderTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Rivo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func fixture(_ name: String) throws -> URL {
        let root = try XCTUnwrap(Bundle(for: CoreTests.self).resourceURL)
        let flat = root.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: flat.path) ? flat : root.appendingPathComponent("Fixtures/" + name)
    }
    func testNewSidecarWorksThroughExistingDirectoryAlias() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("Rap Ø", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let alias = root.deletingLastPathComponent().appendingPathComponent("alias-" + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        let target = try FolderPaths.resolve("Rap Ø/canción.final.lrc", root: alias)
        XCTAssertEqual(target.path, alias.appendingPathComponent("Rap Ø/canción.final.lrc").path)
        try Data("[00:01]Hola".utf8).write(to: target)
        XCTAssertEqual(try FolderPaths.relative(target, root: root), "Rap Ø/canción.final.lrc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sub.appendingPathComponent("canción.final.lrc").path))
    }
    func testTraversalAndOutsideSymlinksAreRejected() throws {
        let root = try directory(), outside = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        for path in ["../escape.lrc", "/escape.lrc", "sub/../../escape.lrc", "sub//file.lrc", "./file.lrc", ""] {
            XCTAssertThrowsError(try FolderPaths.resolve(path, root: root), path)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        XCTAssertThrowsError(try FolderPaths.resolve("escape/file.lrc", root: root))
        let external = outside.appendingPathComponent("secret.lrc")
        try Data("private".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("file.lrc"), withDestinationURL: external)
        XCTAssertThrowsError(try FolderPaths.resolve("file.lrc", root: root))
    }
    func testIOSPrivateVarAliasForMissingSidecar() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let canonical = root.resolvingSymlinksInPath()
        let path = canonical.path
        let alias: URL
        if path.hasPrefix("/private/var/") { alias = URL(fileURLWithPath: String(path.dropFirst(8))) }
        else if path.hasPrefix("/var/") { alias = URL(fileURLWithPath: "/private" + path) }
        else { throw XCTSkip("Simulator temporary folder does not expose the /private/var alias") }
        guard FileManager.default.fileExists(atPath: alias.path) else { throw XCTSkip("No equivalent alias available") }
        let target = try FolderPaths.resolve("New song.lrc", root: alias)
        try Data("[00:01]Test".utf8).write(to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("New song.lrc").path))
    }
    func testScanEmbeddedLyricsAndWriteBesideOriginalAudio() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("Álbum", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let audio = sub.appendingPathComponent("canción.final.MP3")
        try FileManager.default.copyItem(at: fixture("lame_vbr.mp3"), to: audio)
        let write = RMEBridge.write(path: audio.path, fields: ["LYRICS": "[00:01.000]Mi letra Ø"], artwork: nil, removeArtwork: false)
        XCTAssertNil(write["error"])
        let service = FileService()
        let folder = try await service.folder(from: root)
        let scanned = try await service.scan([folder]) { _, _, _ in }
        let track = try XCTUnwrap(scanned.first)
        XCTAssertNil(track.error)
        XCTAssertEqual(track.relativePath, "Álbum/canción.final.MP3")
        XCTAssertTrue(track.hasEmbeddedLyrics)
        XCTAssertFalse(track.hasLRC)
        XCTAssertEqual(track.embeddedLRC, "[00:01.000]Mi letra Ø")
        let detail = try await service.detail(track)
        XCTAssertEqual(detail.lrc, track.embeddedLRC)
        let updated = try await service.saveLRC(track, text: try XCTUnwrap(track.embeddedLRC))
        XCTAssertEqual(updated.lrcState, .synchronized)
        XCTAssertTrue(updated.hasLRC)
        XCTAssertEqual(try String(contentsOf: sub.appendingPathComponent("canción.final.lrc"), encoding: .utf8), "[00:01.000]Mi letra Ø")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("canción.final.lrc").path))
        do { _ = try await service.saveLRC(updated, text: "[00:02]Overwrite"); XCTFail("Existing sidecar must be protected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Ya existe")) }
        let history = try await service.loadHistory()
        let entry = try XCTUnwrap(history.first { $0.folderID == folder.id })
        try await service.undo(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sub.appendingPathComponent("canción.final.lrc").path))
    }
    func testUppercaseInvalidLRCIsDetectedAndReplacedInSameLocation() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("Song.mp3"), sidecar = root.appendingPathComponent("Song.LRC")
        try FileManager.default.copyItem(at: fixture("lame_vbr.mp3"), to: audio)
        try Data("plain text".utf8).write(to: sidecar)
        let service = FileService(), folder = try await service.folder(from: root)
        let scanned = try await service.scan([folder]) { _, _, _ in }
        let track = try XCTUnwrap(scanned.first)
        XCTAssertTrue(track.hasLRC)
        XCTAssertEqual(track.lrcState, .invalid)
        let detail = try await service.detail(track)
        let updated = try await service.saveLRC(track, text: "[00:01]Fixed", expectedExistingHash: detail.lrcHash)
        XCTAssertEqual(updated.lrcState, .synchronized)
        XCTAssertEqual(try String(contentsOf: sidecar, encoding: .utf8), "[00:01]Fixed")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names.filter { ($0 as NSString).pathExtension.lowercased() == "lrc" }, ["Song.LRC"])
        let history = try await service.loadHistory()
        try await service.undo(try XCTUnwrap(history.first { $0.folderID == folder.id }))
        XCTAssertEqual(try String(contentsOf: sidecar, encoding: .utf8), "plain text")
    }
    func testSYLTMillisecondsDetectedWithoutChangingOriginal() throws {
        let result = RMEBridge.read(path: try fixture("embedded-sylt.mp3").path, artwork: false)
        XCTAssertNil(result["error"])
        XCTAssertEqual(result["hasEmbeddedLyrics"] as? Bool, true)
        XCTAssertEqual(result["embeddedSyncedLyrics"] as? String, "[00:01.250]Primera línea Ø\n[00:02.500]Segunda línea\n")
        let frames = RMEBridge.read(path: try fixture("embedded-sylt-frames.mp3").path, artwork: false)
        XCTAssertEqual(frames["hasEmbeddedLyrics"] as? Bool, true)
        XCTAssertEqual(frames["embeddedSyncedLyrics"] as? String, "")
    }
}
