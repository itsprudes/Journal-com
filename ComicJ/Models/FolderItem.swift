import Foundation
import SwiftData

/// Место комикса в очереди папки.
///
/// Отдельная модель нужна, потому что SwiftData не хранит порядок элементов
/// в списках. Порядок задаёт поле `position`.
@Model
final class FolderItem {
    /// Номер в очереди папки: 0 — первый.
    var position: Int = 0
    var addedAt: Date = Date.now
    var folder: Folder?
    var comic: Comic?

    init(position: Int, addedAt: Date = .now) {
        self.position = position
        self.addedAt = addedAt
    }
}
