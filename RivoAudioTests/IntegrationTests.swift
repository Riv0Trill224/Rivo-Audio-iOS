import XCTest
import AVFoundation
@testable import RivoAudio

final class IntegrationTests: XCTestCase {
    func song(_ title: String, artist: String = "Example", video: Bool = false) -> Song {
        Song(id: title + (video ? ".mov" : ".wav"), title: title, artist: artist, album: "Album", duration: 180, isVideo: video)
    }
    func testMediaMatchingKeepsVersionsAndArtistsDistinct() {
        let audio = song("My Song")
        let official = song("My Song (Official Music Video)", video: true)
        let live = song("My Song live", video: true)
        let other = song("My Song", artist: "Another Artist", video: true)
        let matches = MediaMatcher.candidates(for: audio, in: [official, live, other])
        XCTAssertEqual(matches.map(\.id), [official.id])
        XCTAssertEqual(MediaMatcher.automaticMatch(matches)?.id, official.id)
    }
    func testAmbiguousMatchRequiresChoice() {
        let audio = song("My Song")
        var first = song("My Song Official Video", video: true)
        var second = first; first.id = "first.mov"; second.id = "second.mov"
        XCTAssertNil(MediaMatcher.automaticMatch(MediaMatcher.candidates(for: audio, in: [first, second])))
        let unknown = song("My Song", artist: "Artista desconocido", video: true)
        XCTAssertNil(MediaMatcher.automaticMatch(MediaMatcher.candidates(for: audio, in: [unknown])))
    }
    func testSimilarSpellingIsSuggestedButNeedsConfirmation() {
        let audio = song("Blinding Lights")
        let video = song("Blinding Ligths Official Video", video: true)
        let matches = MediaMatcher.candidates(for: audio, in: [video])
        XCTAssertEqual(matches.count, 1)
        XCTAssertNil(MediaMatcher.automaticMatch(matches))
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
