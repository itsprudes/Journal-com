import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Обложки комиксов для библиотеки.
///
/// Обложка — уменьшенная первая страница. Она создаётся при импорте и лежит
/// в папке Caches/Covers. Если система очистила кэш, обложка создастся заново.
nonisolated final class CoverStore: @unchecked Sendable {
    static let shared = CoverStore()

    /// Длинная сторона обложки в пикселях: хватает для крупной плитки на iPad.
    static let maxPixelSize = 600

    private let memoryCache = NSCache<NSString, UIImage>()

    static var directory: URL {
        URL.cachesDirectory.appendingPathComponent("Covers", isDirectory: true)
    }

    static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg", isDirectory: false)
    }

    /// Обложка для показа: из памяти, с диска или созданная заново.
    func cover(for id: UUID, comicFileURL: URL, format: ComicFormat) async -> UIImage? {
        let key = id.uuidString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let image = await Task.detached(priority: .utility) {
            CoverStore.loadOrCreateCover(id: id, comicFileURL: comicFileURL, format: format)
        }.value
        if let image {
            memoryCache.setObject(image, forKey: key)
        }
        return image
    }

    func removeCover(for id: UUID) {
        memoryCache.removeObject(forKey: id.uuidString as NSString)
        try? FileManager.default.removeItem(at: Self.fileURL(for: id))
    }

    private static func loadOrCreateCover(id: UUID, comicFileURL: URL, format: ComicFormat) -> UIImage? {
        if let image = UIImage(contentsOfFile: fileURL(for: id).path) {
            return image
        }
        guard let source = try? PageSourceFactory.open(comicFileURL, format: format) else { return nil }
        return try? saveCover(from: source, id: id)
    }

    /// Создаёт обложку из первой страницы и сохраняет её на диск.
    @discardableResult
    static func saveCover(from source: any PageSource, id: UUID) throws -> UIImage {
        let image = try source.image(at: 0, maxPixelSize: maxPixelSize)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL(for: id) as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw ComicArchiveError.badImage }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ComicArchiveError.badImage }
        return UIImage(cgImage: image)
    }
}
