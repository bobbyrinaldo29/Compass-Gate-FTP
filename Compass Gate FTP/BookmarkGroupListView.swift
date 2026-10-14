//
//  BookmarkGroupListView.swift
//  Compass Gate FTP
//

import SwiftUI
import SwiftData

struct BookmarkGroupListView: View {
    @Environment(\.modelContext) private var modelContext
    let title: String
    let iconName: String
    let group: String?
    let connections: [SSHConnection]
    let searchText: String
    @Bindable var sftpService: SFTPService
    var sessionTabs: [SessionTab] = []

    var onConnect: (SSHConnection) -> Void
    var onEdit: (SSHConnection) -> Void
    var onDuplicate: (SSHConnection) -> Void
    var onDelete: (SSHConnection) -> Void
    var onAdd: (String?) -> Void
    var onImport: (() -> Void)? = nil
    var onMoveGroup: ((SSHConnection, String) -> Void)? = nil
    var onBrowseFiles: () -> Void
    var onSwitchToTab: ((SessionTab) -> Void)? = nil

    @State private var isSelectionMode: Bool = false
    @State private var selectedConnectionIDs: Set<UUID> = []
    @State private var lastSelectedConnectionID: UUID? = nil

    private var filteredConnections: [SSHConnection] {
        let baseList: [SSHConnection]
        if let group = group {
            baseList = connections.filter { $0.groupRaw == group }
        } else {
            baseList = connections
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return baseList
        } else {
            return baseList.filter {
                $0.name.lowercased().contains(query) ||
                $0.host.lowercased().contains(query) ||
                $0.username.lowercased().contains(query)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text("\(filteredConnections.count) \(filteredConnections.count == 1 ? "server configured" : "servers configured")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if !filteredConnections.isEmpty {
                        if isSelectionMode {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSelectionMode = false
                                    selectedConnectionIDs.removeAll()
                                    lastSelectedConnectionID = nil
                                }
                            } label: {
                                Label("Done", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        } else {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSelectionMode = true
                                }
                            } label: {
                                Label("Select", systemImage: "checklist")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }

                    if !isSelectionMode {
                        Button {
                            onImport?()
                        } label: {
                            Label("Import...", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button {
                            onAdd(group)
                        } label: {
                            Label("Add Server", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)

            Divider()

            // Multi-selection Action Banner
            if isSelectionMode {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.headline)

                    Text("\(selectedConnectionIDs.count) of \(filteredConnections.count) server\(filteredConnections.count == 1 ? "" : "s") selected")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Menu {
                        ForEach(BookmarkGroupManager.shared.allGroups) { targetGroup in
                            Button {
                                moveSelectedConnections(to: targetGroup.name)
                            } label: {
                                Label(targetGroup.name, systemImage: targetGroup.iconName)
                            }
                            .disabled(group == targetGroup.name)
                        }
                    } label: {
                        Label("Move To...", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(selectedConnectionIDs.isEmpty)

                    Button(selectedConnectionIDs.count == filteredConnections.count ? "Deselect All" : "Select All") {
                        if selectedConnectionIDs.count == filteredConnections.count {
                            selectedConnectionIDs.removeAll()
                        } else {
                            selectedConnectionIDs = Set(filteredConnections.map(\.id))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelectionMode = false
                            selectedConnectionIDs.removeAll()
                            lastSelectedConnectionID = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12))

                Divider()
            }

            // Content
            if filteredConnections.isEmpty {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label(
                            group != nil ? "No Servers in \(title)" : "No Saved Bookmarks",
                            systemImage: iconName
                        )
                    } description: {
                        Text(
                            group != nil
                            ? "There are no servers in this group yet. Click Add Server to configure one."
                            : "You haven't saved any server bookmarks yet."
                        )
                    } actions: {
                        HStack(spacing: 12) {
                            Button {
                                onAdd(group)
                            } label: {
                                Label("Add Server", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                onImport?()
                            } label: {
                                Label("Import Connections...", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List(selection: $selectedConnectionIDs) {
                    ForEach(filteredConnections) { conn in
                        bookmarkRow(for: conn)
                            .tag(conn.id)
                            .listRowSeparator(.visible)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 20))
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func bookmarkRow(for conn: SSHConnection) -> some View {
        let openTab = sessionTabs.first(where: { $0.connection.id == conn.id })
        let isConnectedInTab = openTab?.service.state == .connected
        let isCurrentConnected = isConnectedInTab || (sftpService.state == .connected && sftpService.activeConnection?.id == conn.id)
        let isSelected = selectedConnectionIDs.contains(conn.id)

        HStack(spacing: 14) {
            if isSelectionMode {
                Toggle("", isOn: Binding(
                    get: { selectedConnectionIDs.contains(conn.id) },
                    set: { _ in
                        handleSelectionClick(for: conn)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .transition(.scale.combined(with: .opacity))
            }

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(conn.tagColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: conn.groupIconName)
                    .font(.title3)
                    .foregroundStyle(conn.tagColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(conn.tagColor)
                        .frame(width: 8, height: 8)
                    Text(conn.name)
                        .font(.headline)

                    if isCurrentConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(openTab != nil ? "Open in Tab" : "Connected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    }

                    if group == nil {
                        Text(conn.groupRaw)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Text("\(conn.username)@\(conn.host):\(conn.port)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text("Path: \(conn.remotePath)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(conn.authType.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if let openTab = openTab {
                    Button {
                        if let onSwitch = onSwitchToTab {
                            onSwitch(openTab)
                        } else {
                            onBrowseFiles()
                        }
                    } label: {
                        Label("Switch to Tab", systemImage: "folder.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else if isCurrentConnected {
                    Button {
                        onBrowseFiles()
                    } label: {
                        Label("Browse Files", systemImage: "folder.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button {
                        sftpService.disconnect()
                    } label: {
                        Image(systemName: "eject.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Disconnect")
                } else {
                    Button {
                        onConnect(conn)
                    } label: {
                        Label("Connect", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                Button {
                    onEdit(conn)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Edit Connection")

                Button(role: .destructive) {
                    onDelete(conn)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Delete Connection")
            }
        }
        .padding(.horizontal, isSelectionMode ? 8 : 0)
        .padding(.vertical, isSelectionMode ? 4 : 0)
        .background(
            isSelectionMode && isSelected
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            if isSelectionMode {
                handleSelectionClick(for: conn)
            }
        }
        .onTapGesture(count: 2) {
            guard !isSelectionMode else { return }
            if let openTab = openTab {
                if let onSwitch = onSwitchToTab {
                    onSwitch(openTab)
                } else {
                    onBrowseFiles()
                }
            } else if isCurrentConnected {
                onBrowseFiles()
            } else {
                onConnect(conn)
            }
        }
        .contextMenu {
            if let openTab = openTab {
                Button("Switch to Tab") {
                    if let onSwitch = onSwitchToTab {
                        onSwitch(openTab)
                    } else {
                        onBrowseFiles()
                    }
                }
                Button("Close Tab") {
                    openTab.service.disconnect()
                }
            } else if isCurrentConnected {
                Button("Browse Files") {
                    onBrowseFiles()
                }
                Button("Disconnect") {
                    sftpService.disconnect()
                }
            } else {
                Button("Connect in New Tab") {
                    onConnect(conn)
                }
            }
            Divider()
            Button("Edit Connection...") {
                onEdit(conn)
            }
            Button("Duplicate") {
                onDuplicate(conn)
            }
            if isSelected && selectedConnectionIDs.count > 1 {
                Menu("Move \(selectedConnectionIDs.count) Selected to...") {
                    ForEach(BookmarkGroupManager.shared.allGroups) { targetGroup in
                        Button {
                            moveSelectedConnections(to: targetGroup.name)
                        } label: {
                            Label(targetGroup.name, systemImage: targetGroup.iconName)
                        }
                    }
                }
                Button("Deselect All") {
                    selectedConnectionIDs.removeAll()
                    lastSelectedConnectionID = nil
                }
            } else {
                Menu("Move To") {
                    ForEach(BookmarkGroupManager.shared.allGroups) { targetGroup in
                        Button {
                            if let onMove = onMoveGroup {
                                onMove(conn, targetGroup.name)
                            } else {
                                conn.groupRaw = targetGroup.name
                                try? modelContext.save()
                            }
                        } label: {
                            Label(targetGroup.name, systemImage: targetGroup.iconName)
                        }
                        .disabled(conn.groupRaw == targetGroup.name)
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete(conn)
            }
        }
    }

    private func handleSelectionClick(for conn: SSHConnection) {
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        if isShiftHeld, let lastID = lastSelectedConnectionID,
           let lastIdx = filteredConnections.firstIndex(where: { $0.id == lastID }),
           let currentIdx = filteredConnections.firstIndex(where: { $0.id == conn.id }) {
            let start = min(lastIdx, currentIdx)
            let end = max(lastIdx, currentIdx)
            let rangeIDs = filteredConnections[start...end].map(\.id)
            selectedConnectionIDs.formUnion(rangeIDs)
        } else {
            if selectedConnectionIDs.contains(conn.id) {
                selectedConnectionIDs.remove(conn.id)
            } else {
                selectedConnectionIDs.insert(conn.id)
            }
            lastSelectedConnectionID = conn.id
        }
    }

    private func moveSelectedConnections(to targetGroupName: String) {
        let targets = connections.filter { selectedConnectionIDs.contains($0.id) }
        for conn in targets {
            if let onMove = onMoveGroup {
                onMove(conn, targetGroupName)
            } else {
                conn.groupRaw = targetGroupName
            }
        }
        try? modelContext.save()
        selectedConnectionIDs.removeAll()
        lastSelectedConnectionID = nil
        isSelectionMode = false
    }
}
