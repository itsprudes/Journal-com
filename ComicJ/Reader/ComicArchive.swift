import Foundation

/// Архив со страницами комикса (CBZ, CBR, CB7, CBT).
///
/// Страницы — это картинки внутри архива в «человеческом» порядке имён:
/// «2.jpg» идёт раньше «10.jpg». Остальные файлы (тексты, служебные) пропускаются.
nonisolated protocol ComicArchive: AnyObject, Sendable {
    /// Пути к картинкам страниц внутри архива в порядке чтения.
    var pageNames: [String] { get }
    /// Содержимое картинки страницы. Можно вызывать с любого потока.
    func dataForPage(at index: Int) throws -> Data
}

nonisolated enum ComicArchiveError: LocalizedError {
    case unsupportedFormat(ComicFormat)
    case noPages
    case damaged
    case passwordProtected
    case unsupportedCompression
    case pageOutOfRange
    case badImage

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(.cba):
            "Формат CBA (архив ACE) пока не поддерживается. Сконвертируйте файл в CBZ."
        case .unsupportedFormat(let format):
            "Формат \(format.displayName) не поддерживается."
        case .noPages:
            "В файле не нашлось страниц."
        case .damaged:
            "Файл повреждён или имеет неизвестный формат."
        case .passwordProtected:
            "Файл защищён паролем."
        case .unsupportedCompression:
            "Архив сжат способом, который пока не поддерживается. Пересожмите его в CBZ."
        case .pageOutOfRange:
            "Такой страницы нет."
        case .badImage:
            "Не удалось показать страницу."
        }
    }
}

nonisolated enum ComicArchiveFactory {
    /// Открывает архив нужным способом в зависимости от формата.
    static func open(_ url: URL, format: ComicFormat) throws -> any ComicArchive {
        switch format {
        case .cbz: try ZipComicArchive(url: url)
        case .cbr: try RarComicArchive(url: url)
        case .cb7: try SevenZipComicArchive(url: url)
        case .cbt: try TarComicArchive(url: url)
        case .cba, .pdf: throw ComicArchiveError.unsupportedFormat(format)
        }
    }
}

/// Какие файлы архива считать страницами и в каком порядке их читать.
nonisolated enum ComicPages {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif", "avif", "jxl",
    ]

    static func isPage(_ path: String) -> Bool {
        let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        guard let name = components.last else { return false }
        // Служебные файлы: «.DS_Store», «__MACOSX/…» и всё внутри скрытых папок.
        if components.contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" }) {
            return false
        }
        return imageExtensions.contains((String(name) as NSString).pathExtension.lowercased())
    }

    /// Оставляет только картинки и сортирует их по пути, как Finder.
    static func pages<Item>(from items: [Item], path: (Item) -> String) -> [Item] {
        items
            .filter { isPage(path($0)) }
            .sorted { path($0).localizedStandardCompare(path($1)) == .orderedAscending }
    }
}
