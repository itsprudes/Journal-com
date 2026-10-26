import Foundation
import Observation
import UIKit

/// Состояние экрана чтения: какой комикс открыт, на какой странице мы и видны ли панели.
///
/// Страницы загружаются заранее (следующие и предыдущая), поэтому
/// перелистывание не ждёт распаковки архива.
@Observable
final class ReaderModel {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let comic: Comic
    /// Папка, из которой открыли комикс: по ней ищем следующий выпуск.
    let folder: Folder?

    private(set) var state: State = .loading
    private(set) var pageCount = 0
    private(set) var currentPage = 0
    var isChromeVisible = true

    /// Длинная сторона страницы в пикселях: хватает для чёткой картинки и увеличения.
    static let pageMaxPixelSize = 3072

    @ObservationIgnored private var source: (any PageSource)?
    @ObservationIgnored private let imageCache = NSCache<NSNumber, UIImage>()
    @ObservationIgnored private var loadingTasks: [Int: Task<UIImage?, Never>] = [:]

    init(comic: Comic, folder: Folder? = nil) {
        self.comic = comic
        self.folder = folder
        imageCache.countLimit = 8
    }

    var isReady: Bool {
        state == .ready
    }

    var isOnLastPage: Bool {
        pageCount > 0 && currentPage == pageCount - 1
    }

    /// Следующий выпуск в папке, если комикс открыт из папки.
    var nextComic: Comic? {
        folder?.comic(after: comic)
    }

    // MARK: - Открытие

    func load() async {
        guard source == nil else { return }
        state = .loading
        let url = comic.fileURL
        let format = comic.format
        do {
            let source = try await Task.detached(priority: .userInitiated) {
                try PageSourceFactory.open(url, format: format)
            }.value
            self.source = source
            pageCount = source.pageCount

            // Открываем там, где остановились. Если комикс дочитан до конца — с начала.
            let lastPage = pageCount - 1
            let isReadToTheEnd = comic.isFinished && comic.currentPageIndex >= lastPage
            currentPage = isReadToTheEnd ? 0 : min(max(comic.currentPageIndex, 0), lastPage)
            comic.updateProgress(pageIndex: currentPage, pageCount: pageCount)

            state = .ready
            prefetch(around: currentPage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Страницы

    /// Картинка страницы. Если она уже загружается, ждём ту же загрузку.
    func image(at index: Int) async -> UIImage? {
        let key = NSNumber(value: index)
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        if let task = loadingTasks[index] {
            return await task.value
        }
        guard let source, (0..<pageCount).contains(index) else { return nil }

        let maxPixelSize = Self.pageMaxPixelSize
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = try? source.image(at: index, maxPixelSize: maxPixelSize) else { return nil }
            return UIImage(cgImage: image)
        }
        loadingTasks[index] = task
        let image = await task.value
        loadingTasks[index] = nil
        if let image {
            imageCache.setObject(image, forKey: key)
        }
        return image
    }

    /// Вызывается, когда на экране оказалась другая страница.
    func pageDidChange(to index: Int) {
        guard (0..<pageCount).contains(index) else { return }
        currentPage = index
        comic.updateProgress(pageIndex: index, pageCount: pageCount)
        // На последней странице показываем панель с кнопкой следующего выпуска.
        if isOnLastPage, nextComic != nil {
            isChromeVisible = true
        }
        prefetch(around: index)
    }

    func goToPage(_ index: Int) {
        pageDidChange(to: min(max(index, 0), pageCount - 1))
    }

    private func prefetch(around index: Int) {
        for neighbor in [index + 1, index + 2, index - 1] where (0..<pageCount).contains(neighbor) {
            Task {
                _ = await image(at: neighbor)
            }
        }
    }

    // MARK: - Действия

    func toggleChrome() {
        isChromeVisible.toggle()
    }

    func startOver() {
        comic.resetProgress()
        goToPage(0)
    }

    func markAsFinished() {
        comic.markAsFinished()
    }

    func save() {
        try? comic.modelContext?.save()
    }
}
