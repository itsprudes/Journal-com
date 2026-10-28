import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Что выбирать в системном окне: отдельные файлы или папку целиком.
enum ImportPickerMode {
    case files
    case folder

    var contentTypes: [UTType] {
        switch self {
        case .files: ComicFormat.importableContentTypes
        case .folder: [.folder]
        }
    }
}

extension View {
    /// Системное окно выбора файлов. Выбранное отправляется в `ComicImporter`.
    ///
    /// - Parameter folder: если задана, комиксы добавятся в конец этой папки.
    func comicImportPicker(
        isPresented: Binding<Bool>,
        mode: ImportPickerMode,
        into folder: Folder? = nil
    ) -> some View {
        modifier(ComicImportPicker(isPresented: isPresented, mode: mode, folder: folder))
    }
}

private struct ComicImportPicker: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(ComicImporter.self) private var importer

    @Binding var isPresented: Bool
    let mode: ImportPickerMode
    let folder: Folder?

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: mode.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importer.enqueue(urls, into: folder, context: modelContext)
            case .failure(let error):
                importer.reportPickerError(error)
            }
        }
    }
}
