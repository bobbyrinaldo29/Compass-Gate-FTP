//
//  NewGroupView.swift
//  Compass Gate FTP
//

import SwiftUI

struct NewGroupView: View {
    @Environment(\.dismiss) private var dismiss

    var onGroupCreated: ((BookmarkGroup) -> Void)? = nil

    @State private var groupName: String = ""
    @State private var selectedIcon: String = "folder.fill"
    @State private var selectedColor: ServerColorTag = .blue

    private let availableIcons: [String] = [
        "folder.fill", "server.rack", "lock.shield.fill", "hammer.fill",
        "cloud.fill", "network", "globe", "cpu",
        "internaldrive.fill", "externaldrive.fill", "shippingbox.fill",
        "tray.2.fill", "archivebox.fill", "tag.fill",
        "star.fill", "terminal.fill"
    ]

    private var isValid: Bool {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !BookmarkGroupManager.shared.allGroups.contains(where: {
            $0.name.lowercased() == trimmed.lowercased()
        })
    }

    private var isDuplicate: Bool {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return BookmarkGroupManager.shared.allGroups.contains(where: {
            $0.name.lowercased() == trimmed.lowercased()
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Server Group")
                        .font(.headline)
                    Text("Create a group to organize your server bookmarks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    // Live Preview Card
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedColor.color.opacity(0.18))
                                .frame(width: 48, height: 48)

                            Image(systemName: selectedIcon)
                                .font(.title3)
                                .foregroundStyle(selectedColor.color)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Group Name" : groupName)
                                .font(.headline)
                                .foregroundStyle(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)

                            Text("Preview as shown in sidebar & menus")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    // Group Name Input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Group Name")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("e.g. Database Clusters, Asia-Pacific, Client A", text: $groupName)
                            .textFieldStyle(.roundedBorder)

                        if isDuplicate {
                            Text("A group with this name already exists.")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    // Color Tag Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color Tag")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(ServerColorTag.allCases) { tag in
                                Button {
                                    selectedColor = tag
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(tag.color)
                                            .frame(width: 22, height: 22)

                                        if selectedColor == tag {
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: 2)
                                                .frame(width: 22, height: 22)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }

                    // Icon Selection Grid
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedIcon == icon ? selectedColor.color.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                                            .frame(height: 36)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(selectedIcon == icon ? selectedColor.color : Color.clear, lineWidth: 1.5)
                                            )

                                        Image(systemName: icon)
                                            .font(.body)
                                            .foregroundStyle(selectedIcon == icon ? selectedColor.color : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer actions
            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Group") {
                    if let newGroup = BookmarkGroupManager.shared.addGroup(
                        name: groupName,
                        iconName: selectedIcon,
                        color: selectedColor
                    ) {
                        onGroupCreated?(newGroup)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 440, height: 420)
    }
}
