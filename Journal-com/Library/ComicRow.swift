import SwiftUI

/// Строка комикса в списке: обложка, название, формат, размер и прогресс.
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

            CoverView(comic: comic)

            VStack(alignment: .leading, spacing: 4) {
                Text(comic.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(detailsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(comic.isFinished ? Color.green : Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detailsText: String {
        var parts = [comic.format.displayName]
        if comic.pageCount > 0 {
            parts.append("\(comic.pageCount) стр.")
        }
        parts.append(comic.fileSize.formatted(.byteCount(style: .file)))
        return parts.joined(separator: " · ")
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
