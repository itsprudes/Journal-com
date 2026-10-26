import Foundation

/// CBT: картинки, сложенные в TAR.
///
/// TAR не сжимает файлы, а кладёт их подряд, и перед каждым стоит заголовок
/// на 512 байт. При открытии читаем только заголовки и запоминаем, где лежит
/// каждая страница, а саму картинку читаем, когда она понадобится.
nonisolated final class TarComicArchive: ComicArchive, @unchecked Sendable {
    private struct Page {
        let name: String
        let offset: UInt64
        let size: Int
    }

    let pageNames: [String]
    private let pages: [Page]
    private let fileHandle: FileHandle
    private let lock = NSLock()

    init(url: URL) throws {
        do {
            fileHandle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ComicArchiveError.damaged
        }
        let allFiles: [Page]
        do {
            allFiles = try Self.readFileList(fileHandle)
        } catch {
            try? fileHandle.close()
            throw ComicArchiveError.damaged
        }
        pages = ComicPages.pages(from: allFiles, path: \.name)
        guard !pages.isEmpty else {
            try? fileHandle.close()
            throw ComicArchiveError.noPages
        }
        pageNames = pages.map(\.name)
    }

    deinit {
        try? fileHandle.close()
    }

    func dataForPage(at index: Int) throws -> Data {
        guard pages.indices.contains(index) else { throw ComicArchiveError.pageOutOfRange }
        let page = pages[index]
        lock.lock()
        defer { lock.unlock() }
        try fileHandle.seek(toOffset: page.offset)
        guard let data = try fileHandle.read(upToCount: page.size), data.count == page.size else {
            throw ComicArchiveError.damaged
        }
        return data
    }

    // MARK: - Разбор заголовков

    private static let blockSize: UInt64 = 512

    private static func readFileList(_ handle: FileHandle) throws -> [Page] {
        let fileSize = try handle.seekToEnd()
        var files: [Page] = []
        var offset: UInt64 = 0
        // Длинные имена файлов хранятся в отдельной записи перед самим файлом.
        var pendingLongName: String?

        while true {
            try handle.seek(toOffset: offset)
            guard let block = try handle.read(upToCount: Int(blockSize)), block.count == Int(blockSize) else { break }
            let header = [UInt8](block)
            // Пустой блок означает конец архива.
            if header.allSatisfy({ $0 == 0 }) { break }

            // Контрольная сумма отличает настоящий заголовок от случайных данных.
            let dataOffset = offset + blockSize
            guard hasValidChecksum(header),
                  let size = number(in: header[124..<136]),
                  size <= fileSize - min(dataOffset, fileSize)
            else { throw ComicArchiveError.damaged }

            switch header[156] {
            case UInt8(ascii: "L"):
                // GNU: длинное имя следующего файла.
                pendingLongName = try readString(handle, at: dataOffset, size: size)
            case UInt8(ascii: "x"):
                // PAX: дополнительные сведения о следующем файле, в том числе имя.
                let records = try readString(handle, at: dataOffset, size: size)
                pendingLongName = paxValue(for: "path", in: records) ?? pendingLongName
            case 0, UInt8(ascii: "0"), UInt8(ascii: "7"):
                let name = pendingLongName ?? headerName(header)
                files.append(Page(name: name, offset: dataOffset, size: Int(size)))
                pendingLongName = nil
            default:
                // Папки, ссылки и прочее страницами не бывают.
                pendingLongName = nil
            }

            offset = dataOffset + (size + blockSize - 1) / blockSize * blockSize
        }
        return files
    }

    /// Имя из заголовка. В формате ustar длинный путь делится на «префикс» и «имя».
    private static func headerName(_ header: [UInt8]) -> String {
        let name = string(from: header[0..<100])
        let isUstar = string(from: header[257..<262]) == "ustar"
        let prefix = isUstar ? string(from: header[345..<500]) : ""
        return prefix.isEmpty ? name : prefix + "/" + name
    }

    /// Сумма всех байтов заголовка, где поле самой суммы (байты 148–155) считается пробелами.
    private static func hasValidChecksum(_ header: [UInt8]) -> Bool {
        guard let stored = number(in: header[148..<156]) else { return false }
        let sum = header.indices.reduce(UInt64(0)) { sum, index in
            sum + UInt64((148..<156).contains(index) ? UInt8(ascii: " ") : header[index])
        }
        return sum == stored
    }

    /// Числа в TAR записаны восьмеричными цифрами. Очень большие — двоичным кодом.
    private static func number(in field: ArraySlice<UInt8>) -> UInt64? {
        guard let first = field.first else { return nil }
        if first & 0x80 != 0 {
            return field.dropFirst().reduce(UInt64(first & 0x7F)) { ($0 << 8) | UInt64($1) }
        }
        let digits = string(from: field).trimmingCharacters(in: .whitespaces)
        return digits.isEmpty ? 0 : UInt64(digits, radix: 8)
    }

    private static func string(from bytes: ArraySlice<UInt8>) -> String {
        let text = bytes.prefix { $0 != 0 }
        return String(bytes: text, encoding: .utf8) ?? String(decoding: text, as: UTF8.self)
    }

    private static func readString(_ handle: FileHandle, at offset: UInt64, size: UInt64) throws -> String {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: Int(size)) ?? Data()
        return string(from: ArraySlice([UInt8](data)))
    }

    /// Записи PAX выглядят так: «30 path=Папка/страница 01.jpg\n».
    private static func paxValue(for key: String, in records: String) -> String? {
        for line in records.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let record = line[line.index(after: space)...]
            guard let equals = record.firstIndex(of: "="), record[..<equals] == key else { continue }
            return String(record[record.index(after: equals)...])
        }
        return nil
    }
}
