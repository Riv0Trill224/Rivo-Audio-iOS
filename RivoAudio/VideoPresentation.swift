import SwiftUI

struct VideoLyricsToggle: View {
    @AppStorage("video.lyrics") private var visible = true
    var body: some View { Button(visible ? "Ocultar letra" : "Mostrar letra") { visible.toggle() }.font(.caption) }
}
struct VideoLyricsOverlay: View {
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var player: AudioPlayer
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
                let text = lines.last(where: { $0.time <= player.elapsed })?.text ?? (lines.isEmpty ? plain : "")
                if !text.isEmpty { Text(text).font(.headline).multilineTextAlignment(.center).foregroundStyle(.white).padding(8).frame(maxWidth: .infinity).background(.black.opacity(0.6)).allowsHitTesting(false) }
            }
        }.task(id: lyricSong?.id) {
            let raw = lyricSong.flatMap { library.localLyrics(for: $0) } ?? ""
            lines = LRC.parse(raw); plain = lines.isEmpty ? raw : ""
        }
    }
}
struct FullscreenVideoView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let video = player.videoPlayer {
                    VideoSurface(player: video).frame(width: geometry.size.width, height: geometry.size.height).overlay(alignment: .bottom) { VideoLyricsOverlay().padding(.bottom, 70) }
                }
                VStack {
                    HStack { Button("Cerrar", systemImage: "xmark") { dismiss() }; Spacer(); VideoLyricsToggle() }.padding().background(.black.opacity(0.6))
                    Spacer()
                    HStack {
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                        Slider(value: Binding(get: { player.elapsed }, set: { player.seek(to: $0) }), in: 0...max(1, player.playbackDuration)).accessibilityLabel("Posición del video")
                    }.padding().background(.black.opacity(0.6))
                }.foregroundStyle(.white)
            }
        }.onChange(of: player.isVideoMode) { _, video in if !video { dismiss() } }
    }
}
