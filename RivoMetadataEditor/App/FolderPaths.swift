import Foundation

// Compare canonical existing directories; preserve the picked URL for scoped access.
// New sidecars have no filesystem entry yet. Standardizing their full paths can
// disagree with an existing /private/var root on iOS.
enum FolderPaths {
    static func relative(_ url: URL, root: URL) throws -> String {
        let base = root.resolvingSymlinksInPath().pathComponents
        let canonical = FileManager.default.fileExists(atPath: url.path) ? url.resolvingSymlinksInPath()
            : url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
        let parts = canonical.pathComponents
        guard parts.count > base.count, Array(parts.prefix(base.count)) == base else {
            throw RivoError.message("Ruta fuera de la carpeta autorizada.")
        }
        return parts.dropFirst(base.count).joined(separator: "/")
    }
    static func resolve(_ relative: String, root: URL) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !relative.contains("\0"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw RivoError.message("Ruta fuera de la carpeta autorizada.")
        }
        let url = root.appendingPathComponent(relative)
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &directory), directory.boolValue else {
            throw RivoError.message("La carpeta del audio ya no está disponible. Vuelve a escanear.")
        }
        let target = FileManager.default.fileExists(atPath: url.path)
            ? url.resolvingSymlinksInPath() : parent.appendingPathComponent(url.lastPathComponent)
        _ = try self.relative(target, root: root)
        // The permission belongs to root; never replace it with a canonical URL.
        return url
    }
}
