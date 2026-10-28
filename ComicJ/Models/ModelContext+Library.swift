import Foundation
import SwiftData

extension ModelContext {
    /// Удалить комикс из библиотеки и из всех папок. Файл и обложка тоже удаляются.
    func deleteComic(_ comic: Comic) {
        let fileName = comic.storedFileName
        let id = comic.id
        for item in comic.folderItems ?? [] {
            delete(item)
        }
        delete(comic)
        ComicFileStore.removeFile(named: fileName)
        CoverStore.shared.removeCover(for: id)
    }

    /// Удалить папку. Комиксы из неё остаются в библиотеке.
    func deleteFolder(_ folder: Folder) {
        for item in folder.items ?? [] {
            delete(item)
        }
        delete(folder)
    }
}
