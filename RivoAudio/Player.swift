import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor final class PlaybackClock: ObservableObject { @Published var elapsed: TimeInterval = 0 }

@MainActor final class AudioPlayer: ObservableObject {
    @Published private(set) var song: Song?
    @Published private(set) var playing = false
    @Published private(set) var preparingAudio = false
    @Published private(set) var audioFormat = ""
    @Published private(set) var activeAudioURL: URL?
    private var lyricTask: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    private var resumeAfterPreparation = true
    let clock = PlaybackClock()
    private var position: TimeInterval = 0
    var elapsed: TimeInterval {
        get { position }
        set { position = newValue; if interfaceActive { clock.elapsed = newValue } }
    }
    private var mediaAccess: MediaAccess?
    var isEngineRunning: Bool { engine.isRunning }
    var progressTimerInterval: TimeInterval? { timer?.timeInterval }
    @Published var error: String?
    @Published private(set) var videoPlayer: AVPlayer?
    @Published private(set) var currentVideo: Song?
    @Published private(set) var outputName = "Salida del sistema"
    @Published private(set) var outputSymbol = "speaker.wave.2"
    @Published private(set) var isVideoMode = false
    @Published private(set) var switchingMedia = false
    @Published private(set) var videoDuration: Double = 0
    private var videoEndObserver: NSObjectProtocol?
    private var videoFailureObserver: NSKeyValueObservation?
    private var videoSeeking = false
    var lastFM: LastFMClient?
    var playbackDuration: Double { isVideoMode ? videoDuration : (song?.duration ?? 0) }
    var videoMatches: [MediaMatch] {
        guard let song, !song.isVideo else { return [] }
        return MediaMatcher.candidates(for: song, in: library?.songs ?? [])
    }
    var canSwitchToAudio: Bool { song?.isVideo == false }
    @Published var presetName = "Plano"
    @Published var eqEnabled = true { didSet { updateDSP(); saveEQ() } }
    @Published var bandCount = 10 { didSet { configureBands(); saveEQ() } }
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
    private let timePitch = AVAudioUnitTimePitch()
    @Published var playbackRate: Float = 1 { didSet { timePitch.rate = playbackRate; updateDSP(); if playing && isVideoMode { videoPlayer?.rate = playbackRate }; UserDefaults.standard.set(playbackRate, forKey: "audio.rate"); updateNowPlaying() } }
    @Published var preamp: Float = 0 { didSet { eq.globalGain = preamp; updateDSP(); UserDefaults.standard.set(preamp, forKey: "audio.preamp") } }
    private var file: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var queue: [Song] = []
    var queuedSongs: [Song] { queue }
    private var currentIndex = 0
    private var timer: Timer?
    private var interfaceActive = true
    private var lastNowPlayingUpdate: TimeInterval = -1
    private var playStartedAt: Date?
    private var scrobbled = false
    private var generation = 0
    private var listenedSeconds: TimeInterval = 0
    private var lastSamplePosition: TimeInterval?
    private var restoringEQ = true
    weak var library: MusicLibrary?
    var history: ListeningHistory?

    init() {
        engine.attach(node); engine.attach(eq); engine.attach(timePitch)
        let rate = UserDefaults.standard.float(forKey: "audio.rate")
        playbackRate = rate >= 0.5 && rate <= 2 ? rate : 1
        timePitch.rate = playbackRate
        preamp = max(-12, min(0, UserDefaults.standard.float(forKey: "audio.preamp")))
        eq.globalGain = preamp
        for (index, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Self.frequencies[index]
            band.bandwidth = 1
            band.gain = 0
            band.bypass = !Self.activeIndices(bandCount).contains(index)
        }
        if let saved = UserDefaults.standard.array(forKey: "eq.gains") as? [Double], saved.count == 31 {
            gains = saved.map(Float.init)
            for index in gains.indices { eq.bands[index].gain = gains[index] }
        }
        let count = UserDefaults.standard.integer(forKey: "eq.bands")
        bandCount = [10, 15, 31].contains(count) ? count : 10
        if UserDefaults.standard.object(forKey: "eq.enabled") != nil { eqEnabled = UserDefaults.standard.bool(forKey: "eq.enabled") }
        presetName = UserDefaults.standard.string(forKey: "eq.preset") ?? "Plano"
        configureBands()
        restoringEQ = false
        engine.connect(node, to: eq, format: nil)
        engine.connect(eq, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        updateDSP()
        updateOutput()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.updateOutput() } }
        setupCommands()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notice in
            if let raw = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
    }

    private func updateOutput() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        outputName = outputs.map(\.portName).joined(separator: ", ")
        let name = outputName.lowercased()
        outputSymbol = name.contains("beats") ? "beats.studiobuds" : name.contains("airpods") ? "airpods" : outputs.contains(where: { $0.portType == .headphones || $0.portType == .bluetoothA2DP }) ? "headphones" : "speaker.wave.2"
    }
    func setInterfaceActive(_ active: Bool) {
        if !active { tick() }
        interfaceActive = active
        if active { tick(); clock.elapsed = elapsed; updateOutput() }
        scheduleProgressTimer()
    }
    private func scheduleProgressTimer() {
        timer?.invalidate(); timer = nil
        guard playing else { return }
        // Playback is driven by AVAudioEngine/AVPlayer, never by this UI timer.
        let interval = interfaceActive ? 1.0 : 30.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = interfaceActive ? 0.2 : 5.0
    }

    func setPreset(_ name: String) {
        guard let values = Self.presets[name] else { return }
        presetName = name
        // Interpolate the ten reference gains in logarithmic frequency space.
        let reference = Self.tenBands.map { Self.frequencies[$0] }
        for index in gains.indices {
            let frequency = Self.frequencies[index]
            let upper = reference.firstIndex(where: { $0 >= frequency }) ?? 9
            let lower = max(0, upper - 1)
            let value: Float
            if frequency <= reference[0] { value = values[0] }
            else if frequency >= reference[9] { value = values[9] }
            else {
                let fraction = log2(frequency / reference[lower]) / log2(reference[upper] / reference[lower])
                value = values[lower] + fraction * (values[upper] - values[lower])
            }
            gains[index] = value; eq.bands[index].gain = value
        }
        saveEQ()
    }
    private func updateDSP() {
        timePitch.bypass = abs(playbackRate - 1) < 0.001
        let active = Self.activeIndices(bandCount)
        eq.bypass = !eqEnabled || (abs(preamp) < 0.001 && active.allSatisfy { abs(gains[$0]) < 0.001 })
    }
    private func saveEQ() {
        updateDSP()
        guard !restoringEQ else { return }
        UserDefaults.standard.set(gains.map(Double.init), forKey: "eq.gains")
        UserDefaults.standard.set(bandCount, forKey: "eq.bands")
        UserDefaults.standard.set(eqEnabled, forKey: "eq.enabled")
        UserDefaults.standard.set(presetName, forKey: "eq.preset")
    }
    private func configureBands() {
        guard [10, 15, 31].contains(bandCount) else { bandCount = 10; return }
        let active = Self.activeIndices(bandCount)
        for (index, band) in eq.bands.enumerated() { band.bypass = !active.contains(index); band.bandwidth = bandCount == 31 ? 1.0 / 3.0 : (bandCount == 15 ? 2.0 / 3.0 : 1.0) }
    }
    func setGain(_ value: Float, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = value; eq.bands[band].gain = value; presetName = "Personalizado"; saveEQ()
    }

    func play(_ selected: Song, from collection: [Song]) {
        lyricTask?.cancel()
        let lyricSource = selected.isVideo ? (MediaMatcher.automaticMatch(MediaMatcher.candidates(for: selected, in: library?.songs ?? [])) ?? selected) : selected
        lyricTask = Task { [weak self] in await self?.library?.autoLyrics(for: lyricSource) }
        if switchingMedia { generation += 1; switchingMedia = false }
        // A video playlist keeps videos. Album/track queues replace the paired
        // audio in place, preserving the next song instead of creating a one-item loop.
        let allVideo = !collection.isEmpty && collection.allSatisfy(\.isVideo)
        let paired = selected.isVideo ? MediaMatcher.automaticMatch(MediaMatcher.candidates(for: selected, in: library?.songs ?? [])) : nil
        let logical = allVideo ? selected : (paired ?? selected)
        if allVideo { queue = collection }
        else {
            var seen = Set<String>()
            queue = collection.compactMap { item in
                let resolved = item.isVideo ? (MediaMatcher.automaticMatch(MediaMatcher.candidates(for: item, in: library?.songs ?? [])) ?? item) : item
                return seen.insert(resolved.id).inserted ? resolved : nil
            }
        }
        if !queue.contains(where: { $0.id == logical.id }) { queue.insert(logical, at: 0) }
        currentIndex = queue.firstIndex(where: { $0.id == logical.id }) ?? 0
        history?.record(logical, startedAt: Date())
        if selected.isVideo {
            pause(); song = logical; elapsed = 0; listenedSeconds = 0; scrobbled = false; playStartedAt = Date()
            Task { await switchToVideo(selected, startPlaying: true) }
        } else { open(selected, at: 0) }
    }
    func switchToVideo(_ video: Song, startPlaying: Bool? = nil) async {
        guard video.isVideo, let library, let logical = song, !switchingMedia else { return }
        let shouldPlay = startPlaying ?? playing
        if playing { tick() }
        let position = elapsed
        generation += 1; let epoch = generation
        switchingMedia = true
        preparation?.cancel(); preparation = nil; preparingAudio = false
        node.stop(); engine.stop(); videoPlayer?.pause(); playing = false
        updateNowPlaying()
        defer { if generation == epoch { switchingMedia = false } }
        do {
            let access = try library.access(for: video)
            let asset = AVURLAsset(url: access.url)
            guard try await asset.load(.isPlayable) else { throw ServiceError(message: "El video no es compatible.") }
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            guard duration.isFinite, duration > 0 else { throw ServiceError(message: "El video no tiene una duración válida.") }
            let target = min(max(0, position), max(0, duration - 0.05))
            let item = AVPlayerItem(asset: asset)
            let candidate = AVPlayer(playerItem: item)
            candidate.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            let seekSucceeded = await candidate.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard generation == epoch else { candidate.pause(); return }
            guard seekSucceeded else { throw ServiceError(message: "No se pudo posicionar el video.") }
            if let observer = videoEndObserver { NotificationCenter.default.removeObserver(observer) }
            mediaAccess = access
            videoPlayer = candidate; currentVideo = video; videoDuration = duration; isVideoMode = true; elapsed = target; lastSamplePosition = target
            videoEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == epoch, self.isVideoMode else { return }
                    self.tick(); self.advanceAtEnd()
                }
            }
            videoFailureObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                if observed.status == .failed {
                    Task { @MainActor in
                        guard let self, self.generation == epoch else { return }
                        self.playing = false; self.error = "No se pudo reproducir el video."; self.updateNowPlaying()
                    }
                }
            }
            try AVAudioSession.sharedInstance().setActive(true)
            if shouldPlay { candidate.playImmediately(atRate: playbackRate); playing = true }
            scheduleProgressTimer()
            if startPlaying == true { lastFM?.nowPlaying(logical) }
            updateNowPlaying()
        } catch {
            guard generation == epoch else { return }
            if !logical.isVideo { open(logical, at: position, preservingListen: true); if !shouldPlay { pause() } }
            if logical.isVideo { videoPlayer = nil; isVideoMode = false; song = nil; updateNowPlaying() }
            self.error = "No se pudo cambiar al video: \(error.localizedDescription)"
        }
    }
    func switchToAudio() {
        guard isVideoMode, let song, !song.isVideo else { return }
        let shouldPlay = playing
        if playing { tick() }
        let position = elapsed
        open(song, at: min(position, max(0, song.duration - 0.05)), preservingListen: true)
        if !shouldPlay { pause() }
    }
    private func open(_ selected: Song, at seconds: TimeInterval, preservingListen: Bool = false, preparedURL: URL? = nil, startPlaying: Bool = true) {
        preparation?.cancel(); preparation = nil; preparingAudio = false
        error = nil
        if !preservingListen {
            listenedSeconds = 0; scrobbled = false; playStartedAt = Date()
        }
        lastSamplePosition = nil
        videoPlayer?.pause(); videoPlayer = nil; currentVideo = nil; isVideoMode = false; switchingMedia = false; videoSeeking = false
        if let observer = videoEndObserver { NotificationCenter.default.removeObserver(observer); videoEndObserver = nil }
        videoFailureObserver = nil
        generation += 1
        let scheduledGeneration = generation
        node.stop(); engine.stop(); playing = false; file = nil
        let source = library?.url(for: selected) ?? URL(fileURLWithPath: selected.id)
        var openingFile = true
        do {
            mediaAccess = try library?.access(for: selected)
            try MediaFiles.validate(source)
            let audio = try AVAudioFile(forReading: preparedURL ?? source)
            openingFile = false
            file = audio
            activeAudioURL = preparedURL ?? source
            var loadedSong = selected
            loadedSong.duration = Double(audio.length) / audio.processingFormat.sampleRate
            song = loadedSong
            audioFormat = "\(source.pathExtension.uppercased()) · \(Int(audio.processingFormat.sampleRate)) Hz · \(audio.processingFormat.channelCount) canales"
            startFrame = max(0, min(audio.length, AVAudioFramePosition(seconds * audio.processingFormat.sampleRate)))
            let remaining = audio.length - startFrame
            guard remaining > 0 else { playing = false; error = "El archivo está vacío o el formato no se puede reproducir"; return }
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(timePitch)
            engine.connect(node, to: eq, format: audio.processingFormat)
            engine.connect(eq, to: timePitch, format: audio.processingFormat)
            engine.connect(timePitch, to: engine.mainMixerNode, format: audio.processingFormat)
            if startPlaying { try AVAudioSession.sharedInstance().setActive(true) }
            updateDSP()
            if startPlaying { try engine.start() }
            node.scheduleSegment(audio, startingFrame: startFrame, frameCount: AVAudioFrameCount(min(remaining, Int64(UInt32.max))), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == scheduledGeneration, self.playing else { return }
                    self.advanceAtEnd()
                }
            }
            elapsed = seconds
            lastSamplePosition = seconds
            if startPlaying { node.play(); playing = true }
            scheduleProgressTimer()
            if !preservingListen, let song { lastFM?.nowPlaying(song) }
            updateNowPlaying()
            Task { [weak self] in
                guard let self else { return }
                _ = await self.library?.loadArtwork(selected)
                if self.song?.id == selected.id { self.updateNowPlaying() }
            }
        } catch {
            engine.stop()
            playing = false; file = nil; scheduleProgressTimer()
            if openingFile, preparedURL == nil, (try? MediaFiles.validate(source)) != nil {
                song = selected; elapsed = seconds; preparingAudio = true; resumeAfterPreparation = startPlaying
                updateNowPlaying()
                preparation = Task { [weak self] in
                    do {
                        let decoded = try await AudioFileLoader.shared.decode(source)
                        guard let self, self.generation == scheduledGeneration, !Task.isCancelled else { return }
                        let shouldPlay = self.resumeAfterPreparation
                        self.open(selected, at: seconds, preservingListen: true, preparedURL: decoded, startPlaying: shouldPlay)
                        if shouldPlay, !preservingListen, self.error == nil { self.lastFM?.nowPlaying(selected) }
                    } catch {
                        guard let self, self.generation == scheduledGeneration, !Task.isCancelled else { return }
                        self.preparingAudio = false
                        self.error = "No se pudo leer \(source.lastPathComponent). \(error.localizedDescription) Prueba el original en Archivos y vuelve a importarlo si está incompleto."
                        self.updateNowPlaying()
                    }
                }
            } else {
                song = selected; elapsed = seconds; updateNowPlaying()
                self.error = "No se pudo reproducir \(source.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }
    func toggle() { playing ? pause() : resume() }
    func pause() {
        if preparingAudio { resumeAfterPreparation = false; return }
        guard playing else { return }
        tick(); node.pause(); engine.pause(); videoPlayer?.pause(); playing = false; scheduleProgressTimer(); updateNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func resume() {
        if preparingAudio { resumeAfterPreparation = true; return }
        guard !playing, !switchingMedia else { return }
        if isVideoMode {
            try? AVAudioSession.sharedInstance().setActive(true)
            videoPlayer?.playImmediately(atRate: playbackRate); playing = true; lastSamplePosition = elapsed; scheduleProgressTimer(); updateNowPlaying(); return
        }
        guard file != nil else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            node.play(); playing = true; lastSamplePosition = elapsed; scheduleProgressTimer(); updateNowPlaying()
        } catch { self.error = error.localizedDescription }
    }
    func seek(to seconds: TimeInterval) {
        guard let song else { return }
        let wasPlaying = playing
        if isVideoMode, let videoPlayer {
            if playing { tick() }
            let position = max(0, min(videoDuration - 0.05, seconds))
            let epoch = generation
            videoSeeking = true; videoPlayer.pause()
            videoPlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] success in
                Task { @MainActor in
                    guard let self, self.generation == epoch else { return }
                    self.videoSeeking = false
                    if success { self.elapsed = position; self.lastSamplePosition = position }
                    if wasPlaying { videoPlayer.playImmediately(atRate: self.playbackRate) }
                    self.updateNowPlaying()
                }
            }
            return
        }
        if playing { tick() }
        open(song, at: max(0, min(song.duration - 0.01, seconds)), preservingListen: true, startPlaying: wasPlaying)
    }
    func advanceAtEnd() {
        if repeatOne {
            if isVideoMode { seek(to: 0); return }
            if let song { play(song, from: queue) }; return
        }
        guard !queue.isEmpty else { pause(); return }
        if shuffle && queue.count > 1 { let choices = queue.indices.filter { $0 != currentIndex }; play(queue[choices.randomElement()!], from: queue); return }
        guard currentIndex + 1 < queue.count else { pause(); return }
        play(queue[currentIndex + 1], from: queue)
    }
    func next() {
        guard !queue.isEmpty else { return }
        let nextIndex = shuffle && queue.count > 1 ? queue.indices.filter { $0 != currentIndex }.randomElement()! : (currentIndex + 1) % queue.count
        play(queue[nextIndex], from: queue)
    }
    func previous() {
        guard !queue.isEmpty else { return }
        if elapsed > 3 { seek(to: 0); return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        play(queue[currentIndex], from: queue)
    }
    private func tick() {
        guard playing, !videoSeeking, let song else { return }
        if isVideoMode {
            guard let videoPlayer, videoPlayer.timeControlStatus == .playing else { return }
            let position = CMTimeGetSeconds(videoPlayer.currentTime())
            guard position.isFinite else { return }
            elapsed = min(videoDuration, position)
        } else {
            guard let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render) else { return }
            elapsed = min(song.duration, Double(startFrame + time.sampleTime) / time.sampleRate)
        }
        if let last = lastSamplePosition { listenedSeconds += max(0, elapsed - last) / Double(playbackRate) }
        lastSamplePosition = elapsed
        if !scrobbled && song.duration > 30 && listenedSeconds >= min(240, song.duration / 2) {
            scrobbled = true
            library?.markPlayed(song)
            lastFM?.enqueue(song, startedAt: playStartedAt ?? Date())
        }
        // The system extrapolates lock-screen progress from elapsed time and rate.
        // Rebuilding artwork/NowPlaying every few seconds wastes energy.
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
        lastNowPlayingUpdate = elapsed
        var info: [String: Any] = [MPMediaItemPropertyTitle: song.title,
                                   MPMediaItemPropertyArtist: song.artist,
                                   MPMediaItemPropertyAlbumTitle: song.album,
                                   MPMediaItemPropertyPlaybackDuration: playbackDuration,
                                   MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
                                   MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(playbackRate) : 0.0]
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
    var album: String? = nil
}

@MainActor final class ListeningHistory: ObservableObject {
    @Published private(set) var entries: [Listen] = []
    private let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("listening-history.json")
    init() { if ProcessInfo.processInfo.arguments.contains("--ui-fixture") { return }; if let data = try? Data(contentsOf: path), let value = try? JSONDecoder().decode([Listen].self, from: data) { entries = value } }
    func record(_ song: Song, startedAt: Date) {
        entries.insert(Listen(songID: song.id, title: song.title, artist: song.artist, startedAt: startedAt, album: song.album), at: 0)
        if entries.count > 500 { entries = Array(entries.prefix(500)) }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: path, options: .atomic) }
    }
}
