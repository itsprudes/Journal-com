import Foundation
import Observation
import SwiftData

/// Импортирует файлы комиксов в библиотеку.
///
/// Откуда приходят файлы:
/// - системное окно выбора файлов (можно выбрать сразу несколько);
/// - выбранная папка целиком: для неё в библиотеке появляется папка
///   с тем же именем, а комиксы встают в порядке имён файлов;
/// - «Открыть в…» / «Поделиться» из других приложений.
///
/// Если запросов несколько, они выполняются по очереди.
@Observable
final class ComicImporter {
    struct Progress: Equatable {
        var completed: Int
        var total: Int
    }

    /// Прогресс текущего импорта. `nil` — сейчас ничего не импортируется.
    private(set) var progress: Progress?
    /// Итог последнего импорта, чтобы показать его пользователю.
    /// Интерфейс обнуляет его, когда сообщение закрыли.
    var lastReport: ImportReport?

    @ObservationIgnored private var queue: Task<Void, Never>?

    var isImporting: Bool {
        progress != nil
    }

    /// Поставить файлы и папки в очередь на импорт.
    ///
    /// - Parameter folder: если задана, все комиксы попадут в конец этой папки.
    func enqueue(_ urls: [URL], into folder: Folder? = nil, context: ModelContext) {
        guard !urls.isEmpty else { return }
        let previous = queue
        queue = Task {
            await previous?.value
            await run(urls, into: folder, context: context)
        }
    }

    /// Показать ошибку системного окна выбора файлов.
    func reportPickerError(_ error: Error) {
        var report = ImportReport()
        report.failures.append(ImportReport.Failure(fileName: "Выбор файлов", message: error.localizedDescription))
        lastReport = report
    }

    // MARK: - Импорт

    private func run(_ urls: [URL], into folder: Folder?, context: ModelContext) async {
        // Файлы из «Файлов» и iCloud Drive доступны, только пока мы об этом явно попросили.
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in accessedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        progress = Progress(completed: 0, total: 0)
        let plan = await Task.detached(priority: .userInitiated) {
            ImportScanner.makePlan(for: urls)
        }.value
        progress = Progress(completed: 0, total: plan.fileCount)

        var report = ImportReport()
        report.unsupportedFileNames = plan.unsupportedFileNames
        report.skippedInFoldersCount = plan.skippedInFoldersCount

        for group in plan.groups {
            var targetFolder = folder
            if targetFolder == nil, let folderName = group.folderName, !group.files.isEmpty {
                targetFolder = existingFolder(named: folderName, context: context)
                if targetFolder == nil {
                    targetFolder = makeFolder(named: folderName, context: context)
                    report.createdFolderNames.append(folderName)
                }
            }

            for fileURL in group.files {
                do {
                    switch try await importFile(at: fileURL, context: context) {
                    case .added(let comic):
                        report.addedCount += 1
                        targetFolder?.append([comic])
                    case .alreadyInLibrary(let comic):
                        report.duplicateCount += 1
                        targetFolder?.append([comic])
                    }
                } catch {
                    report.failures.append(
                        ImportReport.Failure(fileName: fileURL.lastPathComponent, message: error.localizedDescription)
                    )
                }
                progress?.completed += 1
            }
        }

        for url in urls where ComicFileStore.isTemporaryInboxFile(url) {
            try? FileManager.default.removeItem(at: url)
        }
        try? context.save()
        progress = nil
        lastReport = report
    }

    private enum FileOutcome {
        case added(Comic)
        case alreadyInLibrary(Comic)
    }

    private func importFile(at url: URL, context: ModelContext) async throws -> FileOutcome {
        let fileName = url.lastPathComponent

        // Тот же файл (имя и размер совпадают) второй раз не копируем.
        let sourceSize = Self.fileSize(of: url)
        if let sourceSize, let existing = comic(named: fileName, size: sourceSize, context: context) {
            return .alreadyInLibrary(existing)
        }

        let id = UUID()
        let stored = try await Task.detached(priority: .userInitiated) {
            try ComicFileStore.copyIntoLibrary(from: url, id: id)
        }.value

        // Размер файла из iCloud, который ещё не был скачан, узнаём только после копирования.
        if sourceSize == nil, let existing = comic(named: fileName, size: stored.size, context: context) {
            ComicFileStore.removeFile(named: stored.fileName)
            return .alreadyInLibrary(existing)
        }

        let comic = Comic(
            id: id,
            title: Self.title(fromFileName: fileName),
            originalFileName: fileName,
            storedFileName: stored.fileName,
            format: stored.format,
            fileSize: stored.size
        )
        context.insert(comic)
        return .added(comic)
    }

    // MARK: - Помощники

    private func comic(named fileName: String, size: Int64, context: ModelContext) -> Comic? {
        var descriptor = FetchDescriptor<Comic>(
            predicate: #Predicate<Comic> { comic in
                comic.originalFileName == fileName && comic.fileSize == size
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func existingFolder(named name: String, context: ModelContext) -> Folder? {
        var descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { folder in
                folder.name == name
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func makeFolder(named name: String, context: ModelContext) -> Folder {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let nextIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        let folder = Folder(name: name, sortIndex: nextIndex)
        context.insert(folder)
        return folder
    }

    private static func fileSize(of url: URL) -> Int64? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return Int64(size)
    }

    /// «Saga_001.cbz» → «Saga 001».
    static func title(fromFileName fileName: String) -> String {
        let name = (fileName as NSString).deletingPathExtension
        let title = name
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fileName : title
    }
}

/// Итог импорта: что получилось, а что нет.
struct ImportReport {
    struct Failure {
        let fileName: String
        let message: String
    }

    var addedCount = 0
    var duplicateCount = 0
    var createdFolderNames: [String] = []
    var unsupportedFileNames: [String] = []
    var skippedInFoldersCount = 0
    var failures: [Failure] = []

    var title: String {
        if addedCount == 0, duplicateCount == 0, !(failures.isEmpty && unsupportedFileNames.isEmpty) {
            return "Не удалось импортировать"
        }
        return "Импорт завершён"
    }

    var summary: String {
        var lines = ["Добавлено комиксов: \(addedCount)"]
        if duplicateCount > 0 {
            lines.append("Уже были в библиотеке: \(duplicateCount)")
        }
        if !createdFolderNames.isEmpty {
            lines.append("Новые папки: \(createdFolderNames.joined(separator: ", "))")
        }
        if !unsupportedFileNames.isEmpty {
            lines.append("Не комиксы: \(unsupportedFileNames.joined(separator: ", "))")
        }
        if skippedInFoldersCount > 0 {
            lines.append("Пропущено файлов других типов: \(skippedInFoldersCount)")
        }
        for failure in failures {
            lines.append("«\(failure.fileName)»: \(failure.message)")
        }
        return lines.joined(separator: "\n")
    }
}
