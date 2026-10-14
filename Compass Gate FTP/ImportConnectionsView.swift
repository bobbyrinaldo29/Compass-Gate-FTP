//
//  ImportConnectionsView.swift
//  Compass Gate FTP
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportConnectionsView: View {
    @Environment(\.dismiss) private var dismiss

    var initialGroupName: String = "Production Servers"
    var onImport: ([SSHConnection]) -> Void

    init(initialGroupName: String = "Production Servers", onImport: @escaping ([SSHConnection]) -> Void) {
        self.initialGroupName = initialGroupName
        self.onImport = onImport
    }

    init(initialGroup: ConnectionGroup, onImport: @escaping ([SSHConnection]) -> Void) {
        self.init(initialGroupName: initialGroup.rawValue, onImport: onImport)
    }

    @State private var importedItems: [ImportedConnection] = []
    @State private var targetGroupName: String = "Production Servers" 
    @State private var searchText: String = ""
    @State private var errorMessage: String? = nil
    @State private var sourceLabel: String = ""
    @State private var defaultSSHCount: Int = 0

    private var filteredItems: [ImportedConnection] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return importedItems
        }
        return importedItems.filter {
            $0.name.lowercased().contains(q) ||
            $0.host.lowercased().contains(q) ||
            $0.username.lowercased().contains(q)
        }
    }

    private var selectedCount: Int {
        importedItems.filter { $0.isSelected }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Import Server Connections")
                        .font(.title2.weight(.bold))
                    Text("Quickly import servers from ~/.ssh/config, FileZilla, Transmit, or ForkLift.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.bar)

            Divider()

            // Source Action Bar
            HStack(spacing: 12) {
                Button {
                    loadFromDefaultSSHConfig()
                } label: {
                    Label(
                        defaultSSHCount > 0 ? "Load ~/.ssh/config (\(defaultSSHCount) found)" : "Load ~/.ssh/config",
                        systemImage: "terminal.fill"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    chooseFileToImport()
                } label: {
                    Label("Choose File (FileZilla, Transmit, ForkLift)...", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                if !importedItems.isEmpty {
                    Picker("Import to:", selection: $targetGroupName) {
                        ForEach(BookmarkGroupManager.shared.allGroups) { grp in
                            Label(grp.name, systemImage: grp.iconName).tag(grp.name)
                        }
                    }
                    .frame(width: 220)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main Content Area
            if importedItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.6))

                    Text("No Servers Loaded Yet")
                        .font(.headline)

                    Text("Click 'Load ~/.ssh/config' to automatically discover your SSH hosts, or select an exported configuration file from FileZilla (XML), Transmit (JSON/Plist), or ForkLift (JSON/Plist).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    HStack(spacing: 12) {
                        Button {
                            loadFromDefaultSSHConfig()
                        } label: {
                            Label("Load ~/.ssh/config", systemImage: "terminal.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            chooseFileToImport()
                        } label: {
                            Label("Choose File...", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                VStack(spacing: 0) {
                    // Filter and select bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search imported servers...", text: $searchText)
                            .textFieldStyle(.plain)

                        Spacer()

                        Button("Select All") {
                            selectAll(true)
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Button("Deselect All") {
                            selectAll(false)
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)

                        Text("(\(selectedCount) of \(importedItems.count) selected)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    // Server Table List
                    List {
                        ForEach($importedItems) { $item in
                            if matchesFilter(item) {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: $item.isSelected)
                                        .labelsHidden()

                                    Circle()
                                        .fill(item.colorTag.color)
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.body.weight(.medium))

                                        HStack(spacing: 6) {
                                            if !item.username.isEmpty {
                                                Text("\(item.username)@\(item.host)")
                                            } else {
                                                Text(item.host)
                                            }
                                            Text(":\(item.port)")
                                                .foregroundStyle(.secondary)

                                            if item.remotePath != "/" {
                                                Text("•")
                                                    .foregroundStyle(.secondary)
                                                Text(item.remotePath)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    // Auth badge
                                    HStack(spacing: 4) {
                                        Image(systemName: item.authType == .keyFile ? "key.fill" : "lock.fill")
                                        Text(item.authType.rawValue)
                                    }
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                    .foregroundStyle(.secondary)

                                    if !item.sourceDescription.isEmpty {
                                        Text(item.sourceDescription)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .frame(maxWidth: 120, alignment: .trailing)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }

            Divider()

            // Footer / Import Action
            HStack {
                if !sourceLabel.isEmpty {
                    Text("Source: \(sourceLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    performImport()
                } label: {
                    Text("Import \(selectedCount) Server\(selectedCount == 1 ? "" : "s")")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 700, height: 500)
        .onAppear {
            targetGroupName = initialGroupName
            checkDefaultSSHConfig()
        }
    }

    private func matchesFilter(_ item: ImportedConnection) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return item.name.lowercased().contains(q) ||
               item.host.lowercased().contains(q) ||
               item.username.lowercased().contains(q)
    }

    private func selectAll(_ select: Bool) {
        for idx in importedItems.indices {
            importedItems[idx].isSelected = select
        }
    }

    private func checkDefaultSSHConfig() {
        let path = ("~/.ssh/config" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            let found = ConnectionImporter.parseSSHConfig(content: content)
            defaultSSHCount = found.count
        }
    }

    private func loadFromDefaultSSHConfig() {
        let items = ConnectionImporter.loadDefaultSSHConfig()
        if items.isEmpty {
            errorMessage = "No host entries found in ~/.ssh/config"
        } else {
            importedItems = items
            sourceLabel = "~/.ssh/config (\(items.count) hosts)"
            errorMessage = nil
        }
    }

    private func chooseFileToImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType.xml,
            UTType.json,
            UTType.propertyList,
            UTType.plainText,
            UTType.data
        ]
        panel.prompt = "Import"
        panel.message = "Select FileZilla (.xml), Transmit (.json/.plist), ForkLift (.json/.plist), or SSH config file"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let items = try ConnectionImporter.parseFile(at: url)
                if items.isEmpty {
                    errorMessage = "No recognizable server connections found in '\(url.lastPathComponent)'"
                } else {
                    importedItems = items
                    sourceLabel = "\(url.lastPathComponent) (\(items.count) items)"
                    errorMessage = nil
                }
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        }
    }

    private func performImport() {
        let selected = importedItems.filter { $0.isSelected }
        let connections = selected.map { item -> SSHConnection in
            let conn = item.toSSHConnection()
            conn.groupRaw = targetGroupName
            return conn
        }
        onImport(connections)
        dismiss()
    }
}
