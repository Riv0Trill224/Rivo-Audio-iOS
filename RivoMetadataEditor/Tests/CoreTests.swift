import XCTest
@testable import RivoMetadataEditor

final class CoreTests: XCTestCase {
    private func track(title: String = "Antarctica", duration: Double = 126, album: String = "Dark Side of the Clouds") -> Track {
        Track(folderID: UUID(), relativePath: "Subfolder/$uicideboy$ - Antarctica.mp3",
              tags: Tags(fields: ["TITLE": title, "ARTIST": "$uicideboy$", "ALBUM": album]), duration: duration,
              bitrate: 320, sampleRate: 44100, stamp: FileStamp(size: 10, modified: Date()), hasLRC: false)
    }
    private func candidate(id: Int = 1, title: String = "Antarctica", duration: Double = 126, lyric: String = "[00:01.00]Test") -> LyricsCandidate {
        LyricsCandidate(id: id, trackName: title, artistName: "$uicideboy$", albumName: "Dark Side of the Clouds",
                        duration: duration, instrumental: false, plainLyrics: "Test", syncedLyrics: lyric)
    }
    func testVersionMismatchRequiresReview() {
        XCTAssertNil(Match.automatic([candidate(title: "Antarctica (Live)")], track: track()))
        XCTAssertNil(Match.automatic([candidate(duration: 138)], track: track()))
        XCTAssertNotNil(Match.automatic([candidate(duration: 127.9)], track: track()))
    }
    func testDifferentLyricsNeverAutoOverwrite() {
        XCTAssertNil(Match.automatic([candidate(), candidate(id: 2, lyric: "[00:02]Other")], track: track()))
        XCTAssertNil(Match.automatic([candidate()], track: track(title: "")))
    }
    func testSidecarKeepsExactUnicodeFilenameAndFolder() {
        XCTAssertEqual(LRC.filename(audio: "Rap/$uicideboy$ - canción.final.MP3"), "Rap/$uicideboy$ - canción.final.lrc")
    }
    func testTimestampShiftPreservesMetadataAndMultitimeLines() {
        let text = "[ar:RIVØ]\n[offset:100]\n[00:01.2][00:04.340]Hola 🌙\n[00:00.05]Inicio"
        XCTAssertEqual(LRC.shift(text, milliseconds: -100), "[ar:RIVØ]\n[offset:100]\n[00:01.100][00:04.240]Hola 🌙\n[00:00.000]Inicio")
        XCTAssertThrowsError(try LRC.validate("[00:78.2]Invalid"))
        XCTAssertThrowsError(try LRC.validate("Texto sin sincronizar"))
    }
    func testAdvisoryIsIndependentOfStarRating() {
        var tags = Tags(fields: ["TITLE": "Example", "POPULARIMETER": "255"])
        tags.advisory = .explicit
        XCTAssertEqual(tags["ITUNESADVISORY"], "1")
        XCTAssertEqual(tags["POPULARIMETER"], "255")
        tags.advisory = .clean; XCTAssertEqual(tags["ITUNESADVISORY"], "2")
    }
    func testBridgeSavesExplicitAndArtworkWithoutChangingDuration() throws {
        for name in ["lame_vbr.mp3", "no-tags.m4a", "no-tags.flac", "test.ogg", "empty.wav", "empty.aiff"] {
            let bundle = Bundle(for: Self.self)
            let resources = try XCTUnwrap(bundle.resourceURL)
            let flat = resources.appendingPathComponent(name)
            let nested = resources.appendingPathComponent("Fixtures/" + name)
            let source = FileManager.default.fileExists(atPath: flat.path) ? flat : nested
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
            try FileManager.default.copyItem(at: source, to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }
            let before = RMEBridge.read(path: copy.path, artwork: false)
            XCTAssertNil(before["error"], "\(name)")
            let result = RMEBridge.write(path: copy.path, fields: ["TITLE": "Canción Ø", "ITUNESADVISORY": "1"], artwork: nil, removeArtwork: false)
            XCTAssertNil(result["error"], "\(name)")
            let after = RMEBridge.read(path: copy.path, artwork: false)
            XCTAssertEqual((after["fields"] as? [String: String])?["TITLE"], "Canción Ø")
            XCTAssertEqual((after["fields"] as? [String: String])?["ITUNESADVISORY"], "1")
            XCTAssertEqual(after["duration"] as? Double, before["duration"] as? Double)
        }
    }
    func testLRCLIBResponseDecode() throws {
        let json = #"{"id":3,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":120.2,"instrumental":false,"plainLyrics":null,"syncedLyrics":"[00:01]Hi"}"#
        let result = try JSONDecoder().decode(LyricsCandidate.self, from: Data(json.utf8))
        XCTAssertTrue(result.isSynced)
    }
}
