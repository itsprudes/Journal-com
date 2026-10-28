import Foundation
import SwiftData

/// Комикс в библиотеке: один импортированный файл и прогресс его чтения.
///
/// У всех полей есть значения по умолчанию, а связи необязательные:
/// так модель потом можно будет синхронизировать через iCloud между iPhone и iPad.
@Model
final class Comic {
    /// Постоянный идентификатор. По нему же назван файл в хранилище.
    var id: UUID = UUID()
    /// Название для интерфейса. По умолчанию это имя файла без расширения.
    var title: String = ""
    /// Имя файла, под которым его импортировали («Saga_001.cbz»).
    var originalFileName: String = ""
    /// Имя копии файла внутри приложения (см. `ComicFileStore`).
    var storedFileName: String = ""
    /// Формат хранится строкой: так надёжнее для SwiftData. Снаружи используйте `format`.
    var formatRawValue: String = "cbz"
    /// Размер файла в байтах.
    var fileSize: Int64 = 0
    /// Когда комикс добавили в библиотеку.
    var addedAt: Date = Date.now

    // MARK: Прогресс чтения

    /// Номер страницы, на которой остановились. Считается с нуля: первая страница — 0.
    var currentPageIndex: Int = 0
    /// Сколько всего страниц. 0 — ещё не знаем: читалка заполнит при первом открытии.
    var pageCount: Int = 0
    /// Когда комикс открывали последний раз. `nil` — ещё ни разу не открывали.
    var lastReadAt: Date?
    /// Когда дочитали до конца. `nil` — ещё не дочитан.
    var finishedAt: Date?

    /// В каких папках лежит комикс. Удаляем комикс — удаляются и эти записи,
    /// а сами папки остаются.
    @Relationship(deleteRule: .cascade, inverse: \FolderItem.comic)
    var folderItems: [FolderItem]? = []

    init(
        id: UUID = UUID(),
        title: String,
        originalFileName: String,
        storedFileName: String,
        format: ComicFormat,
        fileSize: Int64,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.formatRawValue = format.rawValue
        self.fileSize = fileSize
        self.addedAt = addedAt
    }

    var format: ComicFormat {
        get { ComicFormat(rawValue: formatRawValue) ?? .cbz }
        set { formatRawValue = newValue.rawValue }
    }

    /// Где лежит файл комикса на устройстве.
    var fileURL: URL {
        ComicFileStore.fileURL(forStoredFileName: storedFileName)
    }
}

// MARK: - Прогресс чтения

extension Comic {
    /// Комикс уже открывали.
    var hasStartedReading: Bool {
        lastReadAt != nil
    }

    /// Комикс дочитан.
    var isFinished: Bool {
        finishedAt != nil
    }

    /// Доля прочитанного от 0 до 1. Удобно для полоски прогресса.
    var readingProgress: Double {
        guard pageCount > 0 else { return 0 }
        if isFinished { return 1 }
        return min(Double(currentPageIndex + 1) / Double(pageCount), 1)
    }

    /// Запомнить страницу, на которой читатель сейчас.
    ///
    /// Читалка вызывает это при каждом перелистывании. Когда дошли
    /// до последней страницы, комикс отмечается дочитанным.
    func updateProgress(pageIndex: Int, pageCount newPageCount: Int? = nil) {
        if let newPageCount, newPageCount > 0 {
            pageCount = newPageCount
        }
        let lastPageIndex = max(pageCount - 1, 0)
        currentPageIndex = min(max(pageIndex, 0), lastPageIndex)
        lastReadAt = .now
        if pageCount > 0, currentPageIndex == lastPageIndex, finishedAt == nil {
            finishedAt = .now
        }
    }

    /// Отметить дочитанным, не листая до конца.
    func markAsFinished() {
        finishedAt = .now
        lastReadAt = lastReadAt ?? .now
    }

    /// Начать сначала: сбросить прогресс.
    func resetProgress() {
        currentPageIndex = 0
        lastReadAt = nil
        finishedAt = nil
    }
}
