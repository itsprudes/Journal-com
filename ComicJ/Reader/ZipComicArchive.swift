import Foundation
import ZIPFoundation

/// CBZ: картинки, упакованные в ZIP. Читаем нужную страницу, не распаковывая весь архив.
nonisolated final class ZipComicArchive: ComicArchive, @unchecked Sendable {
    let pageNames: [String]
    private let archive: ZIPFoundation.Archive
    private let entries: [ZIPFoundation.Entry]
    /// Архив нельзя читать из нескольких потоков одновременно.
    private let lock = NSLock()

    init(url: URL) throws {
        do {
            archive = try ZIPFoundation.Archive(url: url, accessMode: .read)
        } catch {
            throw ComicArchiveError.damaged
        }
        entries = ComicPages.pages(from: archive.filter { $0.type == .file }, path: \.path)
        guard !entries.isEmpty else { throw ComicArchiveError.noPages }
        pageNames = entries.map(\.path)
    }

    func dataForPage(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else { throw ComicArchiveError.pageOutOfRange }
        let entry = entries[index]
        lock.lock()
        defer { lock.unlock() }
        var data = Data(capacity: Int(entry.uncompressedSize))
        _ = try archive.extract(entry, skipCRC32: true) { chunk in
            data.append(chunk)
        }
        return data
    }
}
