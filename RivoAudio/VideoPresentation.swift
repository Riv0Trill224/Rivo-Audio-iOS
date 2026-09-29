import SwiftUI

struct VideoLyricsToggle: View {
    @AppStorage("video.lyrics") private var visible = true
    var body: some View { Button(visible ? "Ocultar letra" : "Mostrar letra") { visible.toggle() }.font(.caption) }
}
struct VideoLyricsOverlay: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var clock: PlaybackClock
    @AppStorage("video.lyrics") private var visible = true
    @State private var lines: [LyricLine] = []
    @State private var plain = ""
    private var lyricSong: Song? {
        guard let song = player.song else { return nil }
        return song.isVideo ? (MediaMatcher.automaticMatch(MediaMatcher.candidates(for: song, in: library.songs)) ?? song) : song
    }
    var body: some View {
        Group {
            if visible {
                let text = lines.last(where: { $0.time <= clock.elapsed })?.text ?? (lines.isEmpty ? plain : "")
                if !text.isEmpty { Text(text).font(.headline).multilineTextAlignment(.center).foregroundStyle(.white).padding(8).frame(maxWidth: .infinity).background(.black.opacity(0.6)).allowsHitTesting(false) }
            }
        }.task(id: lyricSong?.id) { loadLyrics() }
            .onReceive(library.$songs) { _ in loadLyrics() }
    }
    private func loadLyrics() {
        let raw = lyricSong.flatMap { library.localLyrics(for: $0) } ?? ""
        lines = LRC.parse(raw); plain = lines.isEmpty ? raw : ""
    }
}
struct FullscreenVideoView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var clock: PlaybackClock
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    private func revealControls() { controlsVisible = true; scheduleHide() }
    private func scheduleHide() {
        hideTask?.cancel()
        guard player.playing else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let video = player.videoPlayer {
                    VideoSurface(player: video).contentShape(Rectangle()).onTapGesture { if controlsVisible { hideTask?.cancel(); controlsVisible = false } else { revealControls() } }.frame(width: geometry.size.width, height: geometry.size.height).overlay(alignment: .bottom) { VideoLyricsOverlay().padding(.bottom, controlsVisible ? 70 : 12) }
                }
                if controlsVisible { VStack {
                    HStack { Button("Cerrar", systemImage: "xmark") { dismiss() }; Spacer(); VideoLyricsToggle() }.padding().background(.black.opacity(0.6))
                    Spacer()
                    HStack {
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir").accessibilityIdentifier("fullscreenTransport")
                        Slider(value: Binding(get: { clock.elapsed }, set: { player.seek(to: $0) }), in: 0...max(1, player.playbackDuration), onEditingChanged: { editing in if editing { hideTask?.cancel() } else { scheduleHide() } }).accessibilityLabel("Posición del video")
                    }.padding().background(.black.opacity(0.6))
                }.foregroundStyle(.white).simultaneousGesture(TapGesture().onEnded { scheduleHide() }) }
            }
        }.onAppear { OrientationDelegate.fullscreen(true); revealControls() }
        .onDisappear { hideTask?.cancel(); OrientationDelegate.fullscreen(false) }
        .onChange(of: player.playing) { _, playing in if playing { scheduleHide() } else { hideTask?.cancel(); controlsVisible = true } }
        .onChange(of: player.isVideoMode) { _, video in if !video { dismiss() } }
    }
}
