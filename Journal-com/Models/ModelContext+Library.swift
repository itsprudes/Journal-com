import Foundation
import SwiftData

extension ModelContext {
    /// Удалить комикс из библиотеки и из всех папок. Файл комикса тоже удаляется.
    func deleteComic(_ comic: Comic) {
        let fileName = comic.storedFileName
        for item in comic.folderItems ?? [] {
            delete(item)
        }
        delete(comic)
        ComicFileStore.removeFile(named: fileName)
    }

    /// Удалить папку. Комиксы из неё остаются в библиотеке.
    func deleteFolder(_ folder: Folder) {
        for item in folder.items ?? [] {
            delete(item)
        }
        delete(folder)
    }
}
