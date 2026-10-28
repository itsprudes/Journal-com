import SwiftUI
import UIKit

/// Обложка комикса. Пока картинка грузится или её нет — значок формата.
struct CoverView: View {
    let comic: Comic
    var width: CGFloat = 44

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: comic.format == .pdf ? "doc.richtext" : "book.closed")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
        // Пропорции обычной страницы комикса — примерно 2 к 3.
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: comic.id) {
            image = await CoverStore.shared.cover(for: comic.id, comicFileURL: comic.fileURL, format: comic.format)
        }
    }
}
