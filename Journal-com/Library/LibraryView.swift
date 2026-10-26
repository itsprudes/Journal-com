import SwiftData
import SwiftUI

/// Временный экран библиотеки: проверить импорт, прогресс и папки.
/// Настоящий интерфейс сделаем по макетам из Figma.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(sort: \Comic.addedAt, order: .reverse) private var comics: [Comic]

    @State private var pickerMode: ImportPickerMode = .files
    @State private var isPickerPresented = false
    @State private var openedComic: Comic?

    var body: some View {
        NavigationStack {
            List {
                if !continueReading.isEmpty {
                    Section("Продолжить чтение") {
                        ForEach(continueReading) { comic in
                            comicButton(comic)
                        }
                    }
                }

                if !folders.isEmpty {
                    Section("Папки") {
                        ForEach(folders) { folder in
                            NavigationLink(value: folder) {
                                LabeledContent {
                                    Text("\(folder.comics.count)")
                                } label: {
                                    Label(folder.name, systemImage: "folder")
                                }
                            }
                        }
                        .onMove(perform: moveFolders)
                        .onDelete(perform: deleteFolders)
                    }
                }

                if !comics.isEmpty {
                    Section("Все комиксы") {
                        ForEach(comics) { comic in
                            comicButton(comic)
                        }
                        .onDelete(perform: deleteComics)
                    }
                }
            }
            .overlay {
                if folders.isEmpty && comics.isEmpty {
                    ContentUnavailableView {
                        Label("Библиотека пуста", systemImage: "books.vertical")
                    } description: {
                        Text("Добавьте комиксы в форматах CBZ, CBR, CB7, CBT, CBA или PDF.")
                    } actions: {
                        Button("Добавить файлы") {
                            presentPicker(.files)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Библиотека")
            .navigationDestination(for: Folder.self) { folder in
                FolderView(folder: folder)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .primaryAction) {
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
            .comicImportPicker(isPresented: $isPickerPresented, mode: pickerMode)
            .fullScreenCover(item: $openedComic) { comic in
                ReaderView(comic: comic)
            }
        }
    }

    /// Начатые и недочитанные комиксы, сначала те, что открывали последними.
    private var continueReading: [Comic] {
        let started = comics.filter { $0.hasStartedReading && !$0.isFinished }
        let sorted = started.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        return Array(sorted.prefix(3))
    }

    private func comicButton(_ comic: Comic) -> some View {
        Button {
            openedComic = comic
        } label: {
            ComicRow(comic: comic)
        }
        .tint(.primary)
    }

    private func presentPicker(_ mode: ImportPickerMode) {
        pickerMode = mode
        isPickerPresented = true
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        var ordered = folders
        ordered.reorder(fromOffsets: source, toOffset: destination)
        for (index, folder) in ordered.enumerated() where folder.sortIndex != index {
            folder.sortIndex = index
        }
    }

    private func deleteFolders(at offsets: IndexSet) {
        for folder in offsets.map({ folders[$0] }) {
            modelContext.deleteFolder(folder)
        }
    }

    private func deleteComics(at offsets: IndexSet) {
        for comic in offsets.map({ comics[$0] }) {
            modelContext.deleteComic(comic)
        }
    }
}
