//
//  ComicJApp.swift
//  ComicJ
//
//  Created by Igor.Prudnikov on 26.10.2026.
//

import SwiftData
import SwiftUI

@main
struct ComicJApp: App {
    @State private var importer = ComicImporter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(importer)
        }
        // База данных библиотеки: комиксы, прогресс чтения и папки.
        .modelContainer(for: [Comic.self, Folder.self, FolderItem.self])
    }
}
