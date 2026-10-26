import Foundation
import SwiftData

/// Папка — подборка комиксов со своим порядком чтения.
///
/// Работает как плейлист: один комикс может лежать в нескольких папках,
/// и в каждой папке у него своё место в очереди.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    /// Место папки в списке папок.
    var sortIndex: Int = 0

    /// Комиксы папки вместе с их местом в очереди. Удаляем папку — удаляются
    /// и эти записи, а сами комиксы остаются в библиотеке.
    @Relationship(deleteRule: .cascade, inverse: \FolderItem.folder)
    var items: [FolderItem]? = []

    init(name: String, sortIndex: Int = 0, createdAt: Date = .now) {
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    /// Записи папки в порядке чтения. Записи без комикса пропускаются.
    var orderedItems: [FolderItem] {
        (items ?? [])
            .filter { $0.comic != nil }
            .sorted { $0.position < $1.position }
    }

    /// Комиксы папки в порядке чтения.
    var comics: [Comic] {
        orderedItems.compactMap(\.comic)
    }

    func contains(_ comic: Comic) -> Bool {
        (items ?? []).contains { $0.comic?.persistentModelID == comic.persistentModelID }
    }

    /// Следующий комикс в очереди: его можно предложить, когда текущий дочитан.
    func comic(after comic: Comic) -> Comic? {
        let ordered = comics
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == comic.persistentModelID }),
              index + 1 < ordered.count
        else { return nil }
        return ordered[index + 1]
    }

    /// Первый недочитанный комикс в очереди: с него удобно продолжить чтение папки.
    var firstUnfinishedComic: Comic? {
        comics.first { !$0.isFinished }
    }

    // MARK: Изменение состава и порядка

    /// Добавить комиксы в конец очереди. Те, что уже есть в папке, пропускаются.
    ///
    /// Папка должна быть уже добавлена в `ModelContext`.
    func append(_ newComics: [Comic]) {
        guard let modelContext else {
            assertionFailure("Сначала добавьте папку в ModelContext")
            return
        }
        var nextPosition = (orderedItems.last?.position ?? -1) + 1
        for comic in newComics where !contains(comic) {
            let item = FolderItem(position: nextPosition)
            modelContext.insert(item)
            item.folder = self
            item.comic = comic
            nextPosition += 1
        }
    }

    /// Переставить комиксы. Параметры такие же, как у `onMove` в SwiftUI-списке.
    func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = orderedItems
        ordered.reorder(fromOffsets: source, toOffset: destination)
        renumber(ordered)
    }

    /// Убрать комиксы из папки (из библиотеки они не удаляются).
    /// Параметр такой же, как у `onDelete` в SwiftUI-списке.
    func removeItems(atOffsets offsets: IndexSet) {
        let ordered = orderedItems
        let removed = offsets.map { ordered[$0] }
        for item in removed {
            modelContext?.delete(item)
        }
        renumber(ordered.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
    }

    /// Расставить номера мест подряд: 0, 1, 2…
    private func renumber(_ ordered: [FolderItem]) {
        for (position, item) in ordered.enumerated() where item.position != position {
            item.position = position
        }
    }
}
