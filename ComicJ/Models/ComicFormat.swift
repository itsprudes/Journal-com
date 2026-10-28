import Foundation
import UniformTypeIdentifiers

/// Формат файла комикса.
///
/// Буква после «cb» означает, каким архиватором упакованы картинки страниц:
/// z — ZIP, r — RAR, 7 — 7-Zip, t — TAR, a — ACE. PDF — обычный PDF-документ.
nonisolated enum ComicFormat: String, Codable, CaseIterable, Sendable {
    case cbz
    case cbr
    case cb7
    case cbt
    case cba
    case pdf

    /// Определяет формат по расширению файла («Saga 01.CBZ» → `.cbz`).
    init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }

    /// Короткое название для интерфейса.
    var displayName: String {
        rawValue.uppercased()
    }

    /// Тип файла для системного окна выбора файлов.
    ///
    /// Для cbz/cbr/… берём тот тип, который система назначила расширению:
    /// это может быть наш тип из Info.plist или тип другого приложения-читалки.
    /// Так окно выбора покажет нужные файлы в любом случае.
    var contentType: UTType {
        if self == .pdf {
            return .pdf
        }
        return UTType(filenameExtension: rawValue, conformingTo: .data) ?? .data
    }

    /// Все типы файлов, которые можно импортировать.
    static var importableContentTypes: [UTType] {
        allCases.map(\.contentType)
    }
}

// MARK: - Определение формата по содержимому

nonisolated extension ComicFormat {
    /// Сколько первых байт файла нужно прочитать, чтобы узнать формат.
    static let signatureLength = 1024

    /// Узнаёт настоящий формат по первым байтам файла.
    ///
    /// Комиксы часто лежат с «неправильным» расширением: например, файл .cbr
    /// на самом деле оказывается ZIP-архивом. Читалке важно знать настоящий формат.
    /// Возвращает `nil`, если формат не удалось распознать.
    static func detect(fileAt url: URL) -> ComicFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: signatureLength) else { return nil }
        return detect(header: header)
    }

    static func detect(header: Data) -> ComicFormat? {
        let bytes = [UInt8](header)

        func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset..<offset + signature.count]) == signature
        }

        if matches([0x50, 0x4B, 0x03, 0x04]) || matches([0x50, 0x4B, 0x05, 0x06]) {
            return .cbz
        }
        if matches(Array("Rar!".utf8) + [0x1A, 0x07]) {
            return .cbr
        }
        if matches([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
            return .cb7
        }
        if matches(Array("**ACE**".utf8), at: 7) {
            return .cba
        }
        if matches(Array("ustar".utf8), at: 257) {
            return .cbt
        }
        // По стандарту заголовок PDF может стоять не в самом начале, а в первых 1024 байтах.
        if header.range(of: Data("%PDF-".utf8)) != nil {
            return .pdf
        }
        return nil
    }
}
