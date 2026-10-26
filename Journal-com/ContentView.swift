//
//  ContentView.swift
//  Journal-com
//
//  Created by Igor.Prudnikov on 26.10.2026.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ComicImporter.self) private var importer

    var body: some View {
        LibraryView()
            .safeAreaInset(edge: .bottom) {
                if let progress = importer.progress {
                    ImportProgressBanner(progress: progress)
                }
            }
            .alert(
                importer.lastReport?.title ?? "",
                isPresented: Binding(
                    get: { importer.lastReport != nil },
                    set: { isPresented in
                        if !isPresented {
                            importer.lastReport = nil
                        }
                    }
                ),
                presenting: importer.lastReport
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { report in
                Text(report.summary)
            }
            // Файлы, которые открыли в приложении через «Открыть в…» или «Поделиться».
            .onOpenURL { url in
                guard url.isFileURL else { return }
                importer.enqueue([url], context: modelContext)
            }
    }
}

/// Плашка внизу экрана, пока идёт импорт.
private struct ImportProgressBanner: View {
    let progress: ComicImporter.Progress

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(progress.total > 0 ? "Импорт: \(progress.completed) из \(progress.total)" : "Подготовка импорта…")
                .font(.subheadline)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 8)
    }
}

#Preview {
    ContentView()
        .environment(ComicImporter())
        .modelContainer(for: [Comic.self, Folder.self, FolderItem.self], inMemory: true)
}
