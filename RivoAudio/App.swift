import SwiftUI

@main struct RivoAudioApp: App {
    @StateObject private var library = MusicLibrary()
    @StateObject private var player = AudioPlayer()
    @StateObject private var history = ListeningHistory()
    @StateObject private var ftp = FTPServer()
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(history)
                .environmentObject(ftp)
                .tint(.pink)
                .onAppear { player.library = library; player.history = history; ftp.library = library }
        }
    }
}
