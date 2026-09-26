import Foundation
import AVFoundation
import CryptoKit

/// File-provider imports must finish downloading before entering the local library.
enum MediaFiles {
    static func relativePath(of file: URL, under root: URL) -> String? {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let parts = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard parts.starts(with: base), parts.count > base.count else { return nil }
        return parts.dropFirst(base.count).joined(separator: "/")
    }

    static func validate(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ServiceError(message: "La ruta no corresponde a un archivo de música.") }
        guard (values.fileSize ?? 0) > 0 else { throw ServiceError(message: "El archivo está vacío. Vuelve a importarlo cuando termine de descargarse.") }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw ServiceError(message: "No se puede leer el archivo. Vuelve a importarlo desde Archivos.") }
    }

    static func copyForImport(from source: URL, to target: URL) async throws {
        // The caller holds the security-scoped grant until coordination and copying finish.
        try await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var copyError: Error?
            let staging = target.deletingLastPathComponent().appendingPathComponent(".import-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                do {
                    try validate(readable)
                    try FileManager.default.copyItem(at: readable, to: staging)
                    try validate(staging)
                    try FileManager.default.moveItem(at: staging, to: target)
                } catch { copyError = error }
            }
            if let error = coordinationError { throw error }
            if let error = copyError { throw error }
        }.value
    }
}

/// AVFoundation fallback decodes to a temporary PCM file, keeping AVAudioEngine's EQ.
/// It never changes the original music file or loads an entire song into memory.
actor AudioFileLoader {
    static let shared = AudioFileLoader()

    func decode(_ source: URL) async throws -> URL {
        try MediaFiles.validate(source)
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let identity = "\(source.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RivoDecoded", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(key).appendingPathExtension("caf")
        if let cached = try? AVAudioFile(forReading: target), cached.length > 0 { return target }
        let asset = AVURLAsset(url: source)
        guard !(try await asset.load(.hasProtectedContent)) else {
            throw ServiceError(message: "Este archivo tiene protección DRM. Importa una copia de audio sin protección.")
        }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ServiceError(message: "El archivo no contiene una pista de audio compatible con iOS.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { throw ServiceError(message: "No se pudo preparar el decodificador de audio.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ServiceError(message: "No se pudo abrir la pista de audio.") }
        let staging = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { reader.cancelReading(); try? FileManager.default.removeItem(at: staging) }
        var file: AVAudioFile?
        var framesWritten: Int64 = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let description = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                  let format = AVAudioFormat(streamDescription: asbd),
                  let block = CMSampleBufferGetDataBuffer(sample) else {
                throw ServiceError(message: "La pista contiene datos de audio no válidos.")
            }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { continue }
            buffer.frameLength = AVAudioFrameCount(frames)
            let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
            let bytes = CMBlockBufferGetDataLength(block)
            guard bytes <= Int(audioBuffer.mDataByteSize), let destination = audioBuffer.mData,
                  CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: destination) == noErr else {
                throw ServiceError(message: "No se pudo decodificar el contenido del archivo.")
            }
            if file == nil { file = try AVAudioFile(forWriting: staging, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: true) }
            try file?.write(from: buffer)
            framesWritten += Int64(frames)
        }
        guard reader.status == .completed, framesWritten > 0 else {
            throw reader.error ?? ServiceError(message: "El archivo está incompleto o su códec no es compatible con iOS.")
        }
        file = nil // Finalize the CAF header before opening for playback.
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: staging, to: target)
        return target
    }
}
