import SwiftUI

/// Временный экран чтения: страница на весь экран, панели появляются по тапу в центре.
/// Настоящий интерфейс сделаем по макетам из Figma.
struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ReaderModel

    init(comic: Comic, folder: Folder? = nil) {
        _model = State(initialValue: ReaderModel(comic: comic, folder: folder))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .overlay(alignment: .top) {
            if showsChrome {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showsChrome && model.isReady {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isChromeVisible)
        .statusBarHidden(!showsChrome)
        .persistentSystemOverlays(showsChrome ? .automatic : .hidden)
        // Читалка всегда тёмная: так страница лучше смотрится, а панели не слепят.
        .preferredColorScheme(.dark)
        .task(id: model.comic.id) {
            await model.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.save()
            }
        }
        .onDisappear {
            model.save()
        }
    }

    /// Пока комикс не открылся, панель с кнопкой «Закрыть» видна всегда.
    private var showsChrome: Bool {
        model.isReady ? model.isChromeVisible : true
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось открыть комикс", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .ready:
            PageCurlView(model: model, currentPage: model.currentPage)
                .id(model.comic.id)
                .ignoresSafeArea()
        }
    }

    // MARK: - Панели

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Закрыть")

            VStack(spacing: 2) {
                Text(model.comic.title)
                    .font(.headline)
                    .lineLimit(1)
                if model.isReady {
                    Text("Страница \(model.currentPage + 1) из \(model.pageCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Menu {
                Button {
                    model.startOver()
                } label: {
                    Label("Читать сначала", systemImage: "arrow.counterclockwise")
                }
                Button {
                    model.markAsFinished()
                } label: {
                    Label("Отметить прочитанным", systemImage: "checkmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(!model.isReady)
            .accessibilityLabel("Ещё")
        }
        .tint(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if model.isOnLastPage, let next = model.nextComic {
                Button {
                    openNext(next)
                } label: {
                    Label("Дальше: \(next.title)", systemImage: "arrow.right.circle.fill")
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
            }
            if model.pageCount > 1 {
                Slider(value: pageBinding, in: 0...Double(model.pageCount - 1), step: 1)
                    .tint(.white)
                    .accessibilityValue("Страница \(model.currentPage + 1) из \(model.pageCount)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var pageBinding: Binding<Double> {
        Binding(
            get: { Double(model.currentPage) },
            set: { model.goToPage(Int($0.rounded())) }
        )
    }

    /// Следующий выпуск открывается прямо здесь, без возврата в библиотеку.
    private func openNext(_ comic: Comic) {
        model.save()
        model = ReaderModel(comic: comic, folder: model.folder)
    }
}
