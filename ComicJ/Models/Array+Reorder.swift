import Foundation

extension Array {
    /// Переставляет элементы так же, как SwiftUI-список при перетаскивании (`onMove`).
    ///
    /// `destination` — позиция в исходном массиве, перед которой вставить элементы.
    nonisolated mutating func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        let insertionIndex = destination - source.count(in: 0..<destination)
        for index in source.reversed() {
            remove(at: index)
        }
        insert(contentsOf: moving, at: insertionIndex)
    }
}
