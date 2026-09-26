import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor final class AudioPlayer: ObservableObject {
    @Published private(set) var song: Song?
    @Published private(set) var playing = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var error: String?
    @Published var presetName = "Plano"
    @Published var eqEnabled = true { didSet { eq.bypass = !eqEnabled } }
    @Published var bandCount = 10 { didSet { configureBands() } }
    @Published var gains: [Float] = Array(repeating: 0, count: 31)
    @Published var repeatOne = false
    @Published var shuffle = false

    static let frequencies: [Float] = [20, 25, 31, 40, 50, 62, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
                                      800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
    static let tenBands = [2, 5, 8, 11, 14, 17, 20, 23, 26, 29]
    static func activeIndices(_ count: Int) -> [Int] {
        switch count {
        case 15: return [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 29]
        case 31: return Array(0..<31)
        default: return tenBands
        }
    }
    static let presets: [String: [Float]] = [
        "Plano": Array(repeating: 0, count: 10),
        "Graves": [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
        "Hip-Hop": [5, 4, 2, 0, -1, 0, 1, 2, 2, 1],
        "Voces": [-2, -1, 0, 1, 2, 3, 3, 2, 0, -1],
        "Brillante": [0, 0, 0, 0, 0, 1, 2, 3, 4, 3]
    ]
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 31)
    private var file: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var queue: [Song] = []
    private var currentIndex = 0
    private var timer: Timer?
    private var playStartedAt: Date?
    private var scrobbled = false
    private var generation = 0
    weak var library: MusicLibrary?
    var history: ListeningHistory?

    init() {
        engine.attach(node); engine.attach(eq)
        for (index, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Self.frequencies[index]
            band.bandwidth = 1
            band.gain = 0
            band.bypass = !Self.activeIndices(bandCount).contains(index)
        }
        engine.connect(node, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupCommands()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notice in
            if let raw = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
    }

    func setPreset(_ name: String) {
        guard let values = Self.presets[name] else { return }
        presetName = name
        for index in 0..<31 { gains[index] = 0; eq.bands[index].gain = 0 }
        for (position, value) in values.enumerated() {
            let index = Self.tenBands[position]
            gains[index] = value; eq.bands[index].gain = value
        }
    }
    private func configureBands() {
        guard [10, 15, 31].contains(bandCount) else { bandCount = 10; return }
        let active = Self.activeIndices(bandCount)
        for (index, band) in eq.bands.enumerated() { band.bypass = !active.contains(index) }
    }
    func setGain(_ value: Float, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = value; eq.bands[band].gain = value; presetName = "Personalizado"
    }

    func play(_ selected: Song, from collection: [Song]) {
        queue = collection
        currentIndex = collection.firstIndex(of: selected) ?? 0
        open(selected, at: 0)
    }
    private func open(_ selected: Song, at seconds: TimeInterval) {
        generation += 1
        let scheduledGeneration = generation
        node.stop(); engine.stop()
        do {
            let audio = try AVAudioFile(forReading: library?.url(for: selected) ?? URL(fileURLWithPath: selected.id))
            file = audio; song = selected
            startFrame = max(0, min(audio.length, AVAudioFramePosition(seconds * audio.processingFormat.sampleRate)))
            let remaining = audio.length - startFrame
            guard remaining > 0 else { playing = false; error = "El archivo está vacío o el formato no se puede reproducir"; return }
            engine.connect(node, to: eq, format: audio.processingFormat)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            node.scheduleSegment(audio, startingFrame: startFrame, frameCount: AVAudioFrameCount(min(remaining, Int64(UInt32.max))), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == scheduledGeneration, self.playing else { return }
                    self.next()
                }
            }
            elapsed = seconds
            playStartedAt = Date().addingTimeInterval(-seconds)
            scrobbled = false
            node.play(); playing = true
            updateNowPlaying()
        } catch {
            playing = false; self.error = "No se pudo reproducir \(selected.title): \(error.localizedDescription)"
        }
    }
    func toggle() { playing ? pause() : resume() }
    func pause() {
        guard playing else { return }
        tick(); node.pause(); playing = false; updateNowPlaying()
    }
    func resume() {
        guard file != nil, !playing else { return }
        if !engine.isRunning { try? engine.start() }
        node.play(); playing = true; updateNowPlaying()
    }
    func seek(to seconds: TimeInterval) {
        guard let song else { return }
        open(song, at: max(0, min(song.duration - 0.01, seconds)))
    }
    func next() {
        guard !queue.isEmpty else { return }
        if repeatOne, let song { open(song, at: 0); return }
        currentIndex = shuffle ? Int.random(in: queue.indices) : (currentIndex + 1) % queue.count
        open(queue[currentIndex], at: 0)
    }
    func previous() {
        guard !queue.isEmpty else { return }
        if elapsed > 3 { seek(to: 0); return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        open(queue[currentIndex], at: 0)
    }
    private func tick() {
        guard playing, let song, let render = node.lastRenderTime,
              let time = node.playerTime(forNodeTime: render) else { return }
        elapsed = min(song.duration, Double(startFrame + time.sampleTime) / time.sampleRate)
        if !scrobbled && elapsed >= min(240, max(30, song.duration / 2)) {
            scrobbled = true
            library?.markPlayed(song)
            history?.record(song, startedAt: playStartedAt ?? Date())
        }
        if Int(elapsed) % 3 == 0 { updateNowPlaying() }
    }
    private func setupCommands() {
        let controls = MPRemoteCommandCenter.shared()
        controls.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        controls.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        controls.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        controls.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        controls.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        controls.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }; return .success
        }
    }
    private func updateNowPlaying() {
        guard let song else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: song.title,
                                   MPMediaItemPropertyArtist: song.artist,
                                   MPMediaItemPropertyAlbumTitle: song.album,
                                   MPMediaItemPropertyPlaybackDuration: song.duration,
                                   MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
                                   MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
        if let image = library?.image(for: song) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

struct Listen: Codable, Identifiable {
    var id = UUID()
    let songID: String
    let title: String
    let artist: String
    let startedAt: Date
}

@MainActor final class ListeningHistory: ObservableObject {
    @Published private(set) var entries: [Listen] = []
    private let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("listening-history.json")
    init() { if let data = try? Data(contentsOf: path), let value = try? JSONDecoder().decode([Listen].self, from: data) { entries = value } }
    func record(_ song: Song, startedAt: Date) {
        entries.insert(Listen(songID: song.id, title: song.title, artist: song.artist, startedAt: startedAt), at: 0)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: path, options: .atomic) }
    }
}
