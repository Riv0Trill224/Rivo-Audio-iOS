import SwiftUI

@main struct RivoAudioApp: App {
    @StateObject private var library = MusicLibrary()
    @StateObject private var player = AudioPlayer()
    @StateObject private var history = ListeningHistory()
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lastFM = LastFMClient()
    @StateObject private var ftp = FTPServer()
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(history)
                .environmentObject(ftp)
                .environmentObject(lastFM)
                .tint(PlayerStyle.accent)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    player.setInterfaceActive(phase == .active)
                    if phase == .active { Task { await lastFM.flush() } }
                }
                .task { library.migrateLyrics() }
                .onAppear { player.library = library; player.history = history; player.lastFM = lastFM; ftp.library = library }
        }
    }
}
