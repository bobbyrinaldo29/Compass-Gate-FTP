//
//  BookmarkGroupManager.swift
//  Compass Gate FTP
//

import SwiftUI

struct BookmarkGroup: Identifiable, Hashable, Codable {
    var id: String { name }
    var name: String
    var iconName: String
    var colorRaw: String = ServerColorTag.blue.rawValue
    var isSystem: Bool = false

    var colorTag: ServerColorTag {
        get { ServerColorTag(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    static let production = BookmarkGroup(
        name: ConnectionGroup.production.rawValue,
        iconName: "lock.shield.fill",
        colorRaw: ServerColorTag.red.rawValue,
        isSystem: true
    )
    static let staging = BookmarkGroup(
        name: ConnectionGroup.staging.rawValue,
        iconName: "hammer.fill",
        colorRaw: ServerColorTag.green.rawValue,
        isSystem: true
    )
    static let general = BookmarkGroup(
        name: ConnectionGroup.general.rawValue,
        iconName: "server.rack",
        colorRaw: ServerColorTag.blue.rawValue,
        isSystem: true
    )

    static let defaultGroups: [BookmarkGroup] = [.production, .staging, .general]
}

@Observable
final class BookmarkGroupManager {
    static let shared = BookmarkGroupManager()

    var groups: [BookmarkGroup] = []

    init() {
        loadGroups()
    }

    var allGroups: [BookmarkGroup] {
        groups
    }

    func group(named name: String) -> BookmarkGroup? {
        groups.first { $0.name == name }
    }

    @discardableResult
    func addGroup(name: String, iconName: String = "folder.fill", color: ServerColorTag = .blue) -> BookmarkGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !groups.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else { return nil }

        let newGroup = BookmarkGroup(name: trimmed, iconName: iconName, colorRaw: color.rawValue, isSystem: false)
        groups.append(newGroup)
        saveGroups()
        return newGroup
    }

    func deleteGroup(named name: String) {
        guard groups.count > 1 else { return }
        groups.removeAll(where: { $0.name == name })
        saveGroups()
    }

    private func saveGroups() {
        if let encoded = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(encoded, forKey: "bookmark_groups_v2")
        }
    }

    private func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: "bookmark_groups_v2"),
           let decoded = try? JSONDecoder().decode([BookmarkGroup].self, from: data),
           !decoded.isEmpty {
            groups = decoded
        } else {
            var initial = BookmarkGroup.defaultGroups
            if let legacyData = UserDefaults.standard.data(forKey: "custom_bookmark_groups"),
               let legacyDecoded = try? JSONDecoder().decode([BookmarkGroup].self, from: legacyData) {
                for item in legacyDecoded {
                    if !initial.contains(where: { $0.name == item.name }) {
                        initial.append(item)
                    }
                }
            }
            groups = initial
            saveGroups()
        }
    }
}
