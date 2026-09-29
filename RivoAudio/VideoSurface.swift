import SwiftUI
import AVFoundation

final class VideoSurfaceUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    @Environment(\.scenePhase) private var scenePhase
    func makeUIView(context: Context) -> VideoSurfaceUIView {
        let view = VideoSurfaceUIView(); view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect; view.playerLayer.player = scenePhase == .active ? player : nil
        return view
    }
    func updateUIView(_ uiView: VideoSurfaceUIView, context: Context) { uiView.playerLayer.player = scenePhase == .active ? player : nil }
    static func dismantleUIView(_ uiView: VideoSurfaceUIView, coordinator: ()) { uiView.playerLayer.player = nil }
}
