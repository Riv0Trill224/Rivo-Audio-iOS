import SwiftUI
import PhotosUI

struct ArtworkView: View {
    let image: UIImage?
    var size: CGFloat = 52
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { LinearGradient(colors: [Color.purple.opacity(0.65), PlayerStyle.ink, Color.indigo.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "waveform").font(.system(size: size * 0.22, weight: .ultraLight)).foregroundStyle(.white.opacity(0.55)) } }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.13))
    }
}

struct PhotoPicker: View {
    let label: String
    let onImage: (Data) -> Void
    @State private var selected: PhotosPickerItem?
    var body: some View {
        PhotosPicker(selection: $selected, matching: .images) { Label(label, systemImage: "photo") }
            .onChange(of: selected) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) {
                        onImage(jpeg)
                    }
                }
            }
    }
}
