import Foundation
import SWCompression

/// CB7: картинки, упакованные в 7-Zip.
///
/// 7-Zip обычно сжимает все файлы одним потоком, и достать одну страницу,
/// не распаковав предыдущие, нельзя. Поэтому при открытии архив распаковывается
/// в память целиком. Формат редкий, а комиксы в нём обычно небольшие.
nonisolated final class SevenZipComicArchive: ComicArchive, @unchecked Sendable {
    let pageNames: [String]
    private let pages: [Data]

    init(url: URL) throws {
        let entries: [SevenZipEntry]
        do {
            let container = try Data(contentsOf: url, options: .alwaysMapped)
            entries = try SevenZipContainer.open(container: container)
        } catch SevenZipError.encryptionNotSupported {
            throw ComicArchiveError.passwordProtected
        } catch SevenZipError.compressionNotSupported {
            throw ComicArchiveError.unsupportedCompression
        } catch {
            throw ComicArchiveError.damaged
        }
        let pageEntries = ComicPages.pages(
            from: entries.filter { $0.info.type == .regular && $0.data != nil },
            path: \.info.name
        )
        guard !pageEntries.isEmpty else { throw ComicArchiveError.noPages }
        pageNames = pageEntries.map(\.info.name)
        pages = pageEntries.compactMap(\.data)
    }

    func dataForPage(at index: Int) throws -> Data {
        guard pages.indices.contains(index) else { throw ComicArchiveError.pageOutOfRange }
        return pages[index]
    }
}
