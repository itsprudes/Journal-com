import SwiftData
import SwiftUI

/// Временный экран папки: комиксы в порядке чтения.
/// Порядок меняется перетаскиванием, свайп влево убирает комикс из папки.
struct FolderView: View {
    let folder: Folder

    @State private var pickerMode: ImportPickerMode = .files
    @State private var isPickerPresented = false

    var body: some View {
        let items = folder.orderedItems

        List {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let comic = item.comic {
                    ComicRow(comic: comic, position: index + 1)
                }
            }
            .onMove { source, destination in
                folder.moveItems(fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                folder.removeItems(atOffsets: offsets)
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Папка пуста",
                    systemImage: "folder",
                    description: Text("Добавьте комиксы кнопкой «+». Порядок чтения можно менять перетаскиванием.")
                )
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                EditButton()
                Menu {
                    Button {
                        presentPicker(.files)
                    } label: {
                        Label("Файлы…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        presentPicker(.folder)
                    } label: {
                        Label("Папку целиком…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .comicImportPicker(isPresented: $isPickerPresented, mode: pickerMode, into: folder)
    }

    private func presentPicker(_ mode: ImportPickerMode) {
        pickerMode = mode
        isPickerPresented = true
    }
}
