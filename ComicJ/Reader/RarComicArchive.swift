import Foundation
import Unrar

/// CBR: картинки, упакованные в RAR.
nonisolated final class RarComicArchive: ComicArchive, @unchecked Sendable {
    let pageNames: [String]
    private let archive: Unrar.Archive
    private let entries: [Unrar.Entry]
    /// Библиотека unrar не рассчитана на работу из нескольких потоков одновременно.
    private let lock = NSLock()

    init(url: URL) throws {
        let allEntries: [Unrar.Entry]
        do {
            archive = try Unrar.Archive(fileURL: url)
            allEntries = try archive.entries()
        } catch {
            throw ComicArchiveError.damaged
        }
        if allEntries.contains(where: \.encrypted) {
            throw ComicArchiveError.passwordProtected
        }
        entries = ComicPages.pages(from: allEntries.filter { !$0.directory }, path: \.fileName)
        guard !entries.isEmpty else { throw ComicArchiveError.noPages }
        pageNames = entries.map(\.fileName)
    }

    func dataForPage(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else { throw ComicArchiveError.pageOutOfRange }
        lock.lock()
        defer { lock.unlock() }
        return try archive.extract(entries[index])
    }
}
