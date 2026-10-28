import SwiftUI
import UIKit

/// Страницы с анимацией перелистывания «загибающейся бумагой» (page curl).
///
/// В SwiftUI такой анимации нет, поэтому внутри работает UIPageViewController из UIKit.
/// Управление:
/// - провести пальцем — перелистнуть, как в Apple Books;
/// - тап у левого или правого края — предыдущая или следующая страница;
/// - тап в центре — показать или спрятать панели;
/// - щипок или двойной тап — увеличить страницу.
struct PageCurlView: UIViewControllerRepresentable {
    let model: ReaderModel
    /// Какую страницу показать. Меняется, например, когда двигают ползунок.
    let currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )
        controller.isDoubleSided = false
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .black
        // Свои правила для жестов перелистывания: см. gestureRecognizerShouldBegin.
        for recognizer in controller.gestureRecognizers {
            recognizer.delegate = context.coordinator
        }
        controller.setViewControllers(
            [context.coordinator.makePage(at: currentPage)],
            direction: .forward,
            animated: false
        )
        context.coordinator.pageViewController = controller
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.show(page: currentPage, animated: false)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
        UIGestureRecognizerDelegate
    {
        let model: ReaderModel
        weak var pageViewController: UIPageViewController?
        /// Пока страница переворачивается, новые команды игнорируем.
        private var isTransitioning = false

        init(model: ReaderModel) {
            self.model = model
        }

        private var visiblePage: PageViewController? {
            pageViewController?.viewControllers?.first as? PageViewController
        }

        func makePage(at index: Int) -> PageViewController {
            let page = PageViewController(index: index, model: model)
            page.onTap = { [weak self] x, width in
                self?.handleTap(atX: x, width: width)
            }
            return page
        }

        /// Показать страницу не жестом, а командой: тапом у края или ползунком.
        func show(page index: Int, animated: Bool) {
            guard let controller = pageViewController,
                  !isTransitioning,
                  let visible = visiblePage,
                  visible.index != index,
                  (0..<model.pageCount).contains(index)
            else { return }
            let direction: UIPageViewController.NavigationDirection = index > visible.index ? .forward : .reverse
            isTransitioning = animated
            controller.setViewControllers([makePage(at: index)], direction: direction, animated: animated) { [weak self] _ in
                self?.isTransitioning = false
            }
        }

        private func handleTap(atX x: CGFloat, width: CGFloat) {
            guard !isTransitioning, let visible = visiblePage else { return }
            let edgeWidth = width * 0.25
            let target: Int
            if x < edgeWidth {
                target = visible.index - 1
            } else if x > width - edgeWidth {
                target = visible.index + 1
            } else {
                model.toggleChrome()
                return
            }
            guard (0..<model.pageCount).contains(target) else { return }
            show(page: target, animated: true)
            model.pageDidChange(to: target)
        }

        // MARK: Источник страниц

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let page = viewController as? PageViewController, page.index > 0 else { return nil }
            return makePage(at: page.index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let page = viewController as? PageViewController, page.index + 1 < model.pageCount else { return nil }
            return makePage(at: page.index + 1)
        }

        // MARK: Перелистывание пальцем

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isTransitioning = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isTransitioning = false
            if completed, let page = visiblePage {
                model.pageDidChange(to: page.index)
            }
        }

        // MARK: Жесты

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Тапы обрабатывает сама страница: края листают, центр показывает панели.
            if gestureRecognizer is UITapGestureRecognizer {
                return false
            }
            // Если страница увеличена, палец двигает картинку, а не листает.
            return !(visiblePage?.isZoomed ?? false)
        }
    }
}

/// Одна страница: картинка, которую можно увеличить щипком или двойным тапом.
final class PageViewController: UIViewController, UIScrollViewDelegate {
    let index: Int
    /// Тап по странице: координата X и ширина страницы.
    var onTap: ((CGFloat, CGFloat) -> Void)?

    private let model: ReaderModel
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)

    var isZoomed: Bool {
        scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    init(index: Int, model: ReaderModel) {
        self.index = index
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.isScrollEnabled = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.startAnimating()
        view.addSubview(spinner)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        loadImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        if !isZoomed {
            imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // При повороте экрана возвращаем обычный масштаб, чтобы страница встала на место.
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }

    private func loadImage() {
        let model = model
        let index = index
        Task { [weak self] in
            let image = await model.image(at: index)
            guard let self else { return }
            spinner.stopAnimating()
            if let image {
                imageView.image = image
            } else {
                showError()
            }
        }
    }

    private func showError() {
        let label = UILabel()
        label.text = "Не удалось показать страницу"
        label.textColor = .lightGray
        label.font = .preferredFont(forTextStyle: .body)
        label.sizeToFit()
        label.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        label.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        view.addSubview(label)
    }

    // MARK: Жесты

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        onTap?(recognizer.location(in: view).x, view.bounds.width)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if isZoomed {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = recognizer.location(in: imageView)
        let scale: CGFloat = 2.5
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        scrollView.zoom(to: rect, animated: true)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Двигать картинку пальцем можно, только когда она увеличена.
        scrollView.isScrollEnabled = isZoomed
    }
}
