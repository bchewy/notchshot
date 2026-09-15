// SPDX-License-Identifier: MIT
import Foundation

/// Batch selection is independent of the shot currently shown in details.
struct ShelfSelection {
    private(set) var isActive = false
    private(set) var ids: Set<UUID> = []
    private(set) var anchor: UUID?

    mutating func begin() { isActive = true }

    mutating func end() {
        isActive = false
        ids.removeAll()
        anchor = nil
    }

    mutating func toggle(_ id: UUID, orderedIDs: [UUID]) {
        guard orderedIDs.contains(id) else { return }
        isActive = true
        if !ids.insert(id).inserted { ids.remove(id) }
        anchor = id
    }

    mutating func extend(to id: UUID, orderedIDs: [UUID]) {
        guard let end = orderedIDs.firstIndex(of: id) else { return }
        isActive = true
        guard let anchor, let start = orderedIDs.firstIndex(of: anchor) else {
            ids.insert(id)
            self.anchor = id
            return
        }
        ids.formUnion(orderedIDs[min(start, end)...max(start, end)])
    }

    mutating func selectAll(orderedIDs: [UUID]) {
        isActive = true
        ids = Set(orderedIDs)
        anchor = orderedIDs.first
    }

    mutating func reconcile(orderedIDs: [UUID]) {
        ids.formIntersection(orderedIDs)
        if let anchor, !orderedIDs.contains(anchor) { self.anchor = nil }
        if orderedIDs.isEmpty { end() }
    }
}
