import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cover cache (SPEC §5.4): originals keyed by sha256, three sizes
/// (64/256/1024 pt @2x) generated lazily on first request.
public struct CoverCache: Sendable {
    public static let sizes = [64, 256, 1024]

    private let root: URL

    /// Default root: ~/Library/Caches/Escapement/covers.
    public init(root: URL? = nil) throws {
        self.root =
            root
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Escapement/covers", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    /// Stores original image data, returns its hash (the album's cover_hash).
    /// Idempotent — same bytes land in the same file.
    public func store(_ data: Data) throws -> String {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = originalURL(hash: hash)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url)
        }
        return hash
    }

    /// URL of a rendition; generates it lazily. nil size → original.
    public func url(hash: String, size: Int? = nil) -> URL? {
        guard let size else {
            let original = originalURL(hash: hash)
            return FileManager.default.fileExists(atPath: original.path) ? original : nil
        }
        let rendition = renditionURL(hash: hash, size: size)
        if FileManager.default.fileExists(atPath: rendition.path) {
            return rendition
        }
        let original = originalURL(hash: hash)
        guard FileManager.default.fileExists(atPath: original.path),
            let source = CGImageSourceCreateWithURL(original as CFURL, nil),
            let thumb = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: size * 2,  // @2x
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary),
            let dest = CGImageDestinationCreateWithURL(
                rendition as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return rendition
    }

    private func originalURL(hash: String) -> URL {
        root.appendingPathComponent("\(hash).jpg")
    }

    private func renditionURL(hash: String, size: Int) -> URL {
        root.appendingPathComponent("\(hash)-\(size).jpg")
    }
}
