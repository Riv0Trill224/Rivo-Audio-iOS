import SwiftUI
import PhotosUI

struct ArtworkView: View {
    let image: UIImage?
    var size: CGFloat = 52
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Color(.secondarySystemFill); Image(systemName: "waveform").foregroundStyle(.secondary) } }
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
