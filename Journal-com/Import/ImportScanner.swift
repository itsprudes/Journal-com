import Foundation

/// Разбирает выбранные пользователем файлы и папки: что импортировать и в каком порядке.
nonisolated enum ImportScanner {
    /// План импорта.
    nonisolated struct Plan: Sendable {
        /// Группа файлов. Для каждой выбранной папки — своя группа.
        nonisolated struct Group: Sendable {
            /// Имя выбранной папки. `nil` — файлы выбраны поштучно.
            var folderName: String?
            /// Файлы комиксов. Внутри папки — в «человеческом» порядке имён:
            /// «Выпуск 2» идёт раньше, чем «Выпуск 10».
            var files: [URL]
        }

        var groups: [Group] = []
        /// Файлы, выбранные поштучно, которые не являются комиксами.
        var unsupportedFileNames: [String] = []
        /// Сколько файлов других типов (картинки, тексты…) пропущено внутри папок.
        var skippedInFoldersCount = 0

        var fileCount: Int {
            groups.reduce(0) { $0 + $1.files.count }
        }
    }

    /// Долгая операция для больших папок: вызывайте не на главном потоке.
    static func makePlan(for urls: [URL]) -> Plan {
        var plan = Plan()
        var looseFiles: [URL] = []

        for url in urls {
            if isDirectory(url) {
                let (files, skippedCount) = comicFiles(inFolder: url)
                plan.groups.append(Plan.Group(folderName: url.lastPathComponent, files: files))
                plan.skippedInFoldersCount += skippedCount
            } else if ComicFormat(fileExtension: url.pathExtension) != nil {
                looseFiles.append(url)
            } else {
                plan.unsupportedFileNames.append(url.lastPathComponent)
            }
        }

        if !looseFiles.isEmpty {
            plan.groups.insert(Plan.Group(folderName: nil, files: looseFiles), at: 0)
        }
        return plan
    }

    /// Все комиксы внутри папки, включая вложенные папки.
    static func comicFiles(inFolder folder: URL) -> (files: [URL], skippedCount: Int) {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return ([], 0)
        }

        var files: [URL] = []
        var skippedCount = 0
        for case let url as URL in enumerator {
            guard !isDirectory(url) else { continue }
            guard let fileURL = visibleFileURL(for: url) else { continue }
            if ComicFormat(fileExtension: fileURL.pathExtension) != nil {
                files.append(fileURL)
            } else {
                skippedCount += 1
            }
        }

        let basePath = folder.standardizedFileURL.path
        files.sort { lhs, rhs in
            relativePath(of: lhs, basePath: basePath)
                .localizedStandardCompare(relativePath(of: rhs, basePath: basePath)) == .orderedAscending
        }
        return (files, skippedCount)
    }

    /// Пропускает скрытые служебные файлы (.DS_Store и т. п.).
    ///
    /// Файл из iCloud, который ещё не скачан, выглядит как скрытый «.Имя.cbz.icloud».
    /// Для него возвращаем адрес настоящего файла: при копировании система его скачает.
    static func visibleFileURL(for url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix(".") else { return url }

        let placeholderSuffix = ".icloud"
        guard name.hasSuffix(placeholderSuffix), name.count > placeholderSuffix.count + 1 else { return nil }
        let realName = String(name.dropFirst().dropLast(placeholderSuffix.count))
        return url.deletingLastPathComponent().appendingPathComponent(realName, isDirectory: false)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func relativePath(of url: URL, basePath: String) -> String {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return path }
        return String(path.dropFirst(basePath.count))
    }
}
