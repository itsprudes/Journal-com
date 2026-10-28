import CoreGraphics
import Foundation
import ImageIO

/// Источник страниц комикса: сколько их и как получить картинку нужной страницы.
nonisolated protocol PageSource: AnyObject, Sendable {
    var pageCount: Int { get }
    /// Картинка страницы. Длинная сторона — не больше `maxPixelSize` пикселей.
    /// Долгая операция: вызывайте не на главном потоке.
    func image(at index: Int, maxPixelSize: Int) throws -> CGImage
}

nonisolated enum PageSourceFactory {
    static func open(_ url: URL, format: ComicFormat) throws -> any PageSource {
        if format == .pdf {
            return try PDFPageSource(url: url)
        }
        return ArchivePageSource(archive: try ComicArchiveFactory.open(url, format: format))
    }
}

/// Страницы из архива: картинки, которые нужно только раскодировать.
nonisolated final class ArchivePageSource: PageSource, @unchecked Sendable {
    private let archive: any ComicArchive

    init(archive: any ComicArchive) {
        self.archive = archive
    }

    var pageCount: Int {
        archive.pageNames.count
    }

    func image(at index: Int, maxPixelSize: Int) throws -> CGImage {
        try ImageDecoder.decode(archive.dataForPage(at: index), maxPixelSize: maxPixelSize)
    }
}

/// Страницы PDF: каждую страницу рисуем в картинку нужного размера.
nonisolated final class PDFPageSource: PageSource, @unchecked Sendable {
    let pageCount: Int
    private let document: CGPDFDocument
    private let lock = NSLock()

    init(url: URL) throws {
        guard let document = CGPDFDocument(url as CFURL) else { throw ComicArchiveError.damaged }
        if !document.isUnlocked && !document.unlockWithPassword("") {
            throw ComicArchiveError.passwordProtected
        }
        guard document.numberOfPages > 0 else { throw ComicArchiveError.noPages }
        self.document = document
        self.pageCount = document.numberOfPages
    }

    func image(at index: Int, maxPixelSize: Int) throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        // В PDF страницы нумеруются с единицы.
        guard let page = document.page(at: index + 1) else { throw ComicArchiveError.pageOutOfRange }

        let box = page.getBoxRect(.cropBox)
        let isRotated = abs(page.rotationAngle) % 180 == 90
        let pageSize = isRotated ? CGSize(width: box.height, height: box.width) : box.size
        guard pageSize.width > 0, pageSize.height > 0 else { throw ComicArchiveError.badImage }

        let scale = CGFloat(maxPixelSize) / max(pageSize.width, pageSize.height)
        let width = max(Int(pageSize.width * scale), 1)
        let height = max(Int(pageSize.height * scale), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ComicArchiveError.badImage }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.concatenate(
            page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pageSize), rotate: 0, preserveAspectRatio: true)
        )
        context.drawPDFPage(page)

        guard let image = context.makeImage() else { throw ComicArchiveError.badImage }
        return image
    }
}

/// Раскодирует картинку (JPEG, PNG, WebP…) сразу в нужном размере.
///
/// Страница комикса бывает 2000×3000 пикселей и больше. Если раскодировать её
/// целиком, приложение быстро съест память, поэтому уменьшаем ещё при чтении.
nonisolated enum ImageDecoder {
    static func decode(_ data: Data, maxPixelSize: Int) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ComicArchiveError.badImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ComicArchiveError.badImage
        }
        return image
    }
}

/// Первое знакомство с только что импортированным комиксом.
nonisolated enum ComicInspector {
    /// Считает страницы и сохраняет обложку. Возвращает число страниц
    /// или `nil`, если файл не удалось открыть.
    static func inspect(fileAt url: URL, format: ComicFormat, id: UUID) -> Int? {
        guard let source = try? PageSourceFactory.open(url, format: format) else { return nil }
        _ = try? CoverStore.saveCover(from: source, id: id)
        return source.pageCount
    }
}
