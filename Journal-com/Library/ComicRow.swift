import SwiftUI

/// Строка комикса в списке: значок формата, название, размер и прогресс.
struct ComicRow: View {
    let comic: Comic
    /// Номер в очереди папки. `nil` — не показывать.
    var position: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let position {
                Text("\(position)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
            }

            Image(systemName: comic.format == .pdf ? "doc.richtext" : "book.closed")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 60)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(comic.title)
                    .font(.headline)
                    .lineLimit(2)

                Text("\(comic.format.displayName) · \(comic.fileSize.formatted(.byteCount(style: .file)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(comic.isFinished ? Color.green : Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var progressText: String {
        if comic.isFinished {
            return "Прочитано"
        }
        if comic.hasStartedReading, comic.pageCount > 0 {
            return "Страница \(comic.currentPageIndex + 1) из \(comic.pageCount)"
        }
        return "Не начат"
    }
}
