import Foundation

/// Хранилище файлов комиксов внутри приложения.
///
/// При импорте файл копируется в папку Application Support/Comics и получает имя
/// по идентификатору комикса («5F1C…E2.cbz»). Так комикс не пропадёт, если
/// оригинал удалят или переименуют в «Файлах» или на iCloud Drive.
nonisolated enum ComicFileStore {
    /// Результат копирования файла в хранилище.
    nonisolated struct StoredFile: Sendable {
        let fileName: String
        let format: ComicFormat
        let size: Int64
    }

    nonisolated enum StoreError: LocalizedError {
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let fileName):
                "Формат файла «\(fileName)» не поддерживается"
            }
        }
    }

    /// Папка, где лежат все импортированные комиксы.
    static var comicsDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Comics", isDirectory: true)
    }

    static func fileURL(forStoredFileName fileName: String) -> URL {
        comicsDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Копирует файл в хранилище. Долгая операция: вызывайте не на главном потоке.
    ///
    /// Если файл лежит в iCloud и ещё не скачан на устройство, система
    /// сначала его скачает.
    static func copyIntoLibrary(from source: URL, id: UUID) throws -> StoredFile {
        let fileManager = FileManager.default
        let fileExtension = source.pathExtension.lowercased()
        guard let formatByExtension = ComicFormat(fileExtension: fileExtension) else {
            throw StoreError.unsupportedFormat(source.lastPathComponent)
        }

        try fileManager.createDirectory(at: comicsDirectory, withIntermediateDirectories: true)
        let fileName = "\(id.uuidString).\(fileExtension)"
        let destination = fileURL(forStoredFileName: fileName)

        try? fileManager.startDownloadingUbiquitousItem(at: source)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: source,
            options: .withoutChanges,
            error: &coordinationError
        ) { readableURL in
            do {
                try fileManager.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            try? fileManager.removeItem(at: destination)
            throw error
        }

        let attributes = try fileManager.attributesOfItem(atPath: destination.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let format = ComicFormat.detect(fileAt: destination) ?? formatByExtension
        return StoredFile(fileName: fileName, format: format, size: size)
    }

    /// Удаляет файл комикса из хранилища.
    static func removeFile(named fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: fileURL(forStoredFileName: fileName))
    }

    /// Файл лежит во временных папках самого приложения.
    ///
    /// Туда система кладёт копии файлов, которые прислали через «Поделиться»
    /// из других приложений. После импорта такие копии нужно удалить.
    static func isTemporaryInboxFile(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let temporaryFolders = [
            URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true),
            URL.temporaryDirectory,
        ]
        return temporaryFolders.contains { folder in
            path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
        }
    }
}
