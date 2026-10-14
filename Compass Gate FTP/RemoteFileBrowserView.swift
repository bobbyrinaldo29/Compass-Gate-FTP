//
//  RemoteFileBrowserView.swift
//  Compass Gate FTP
//

import SwiftUI
import AppKit
import QuickLook

struct RemoteFileBrowserView: View {
    let connection: SSHConnection
    @Bindable var sftpService: SFTPService
    var viewMode: FileViewMode
    var searchText: String
    var groupBy: FileGrouping = .none
    var localManager: LocalFileManager? = nil
    var isActive: Bool = true
    var onActivate: (() -> Void)? = nil
    var onPromptPassword: ((SSHConnection) -> Void)? = nil
    var onEditConnection: ((SSHConnection) -> Void)? = nil

    private var groupSections: [FileGroupSection] {
        groupFiles(filteredFiles, by: groupBy)
    }

    @State private var isEditingPath = false
    @State private var editedPathText = ""
    @FocusState private var isRenameFocused: Bool
    @FocusState private var isTableFocused: Bool

    @AppStorage("localCol_size") private var showSize: Bool = false
    @AppStorage("localCol_kind") private var showKind: Bool = false
    @AppStorage("localCol_dateModified") private var showDateModified: Bool = false
    @AppStorage("remoteCol_permissions") private var showPermissions: Bool = false
    @AppStorage("remoteCol_owner") private var showOwner: Bool = false
    @AppStorage("settings_showHiddenFiles") private var showHiddenFiles: Bool = false

    private struct MillerColumn: Identifiable {
        let id: String
        let path: String
        var items: [RemoteFileItem]
        var selectedFileID: String?
        var isLoading: Bool
    }

    @State private var millerColumns: [MillerColumn] = []
    @State private var quickLookLoadingItem: RemoteFileItem? = nil
    @State private var previewItem: RemoteFileItem? = nil

    private let gridColumns = [GridItem(.adaptive(minimum: 90, maximum: 120))]

    private struct PathBreadcrumbSegment: Identifiable {
        let id: String
        let name: String
        let fullPath: String
        let isLast: Bool
    }

    private var pathSegments: [PathBreadcrumbSegment] {
        let path = sftpService.currentPath
        var segments: [PathBreadcrumbSegment] = []

        let isRoot = path == "/" || path.isEmpty
        segments.append(PathBreadcrumbSegment(id: "root", name: "/", fullPath: "/", isLast: isRoot))

        if !isRoot {
            let parts = path.split(separator: "/").map(String.init)
            var cumulative = ""
            for (index, part) in parts.enumerated() {
                cumulative += "/" + part
                let isLast = index == parts.count - 1
                segments.append(PathBreadcrumbSegment(
                    id: cumulative,
                    name: part,
                    fullPath: cumulative,
                    isLast: isLast
                ))
            }
        }
        return segments
    }

    private var filteredFiles: [RemoteFileItem] {
        var result = sftpService.files
        if !showHiddenFiles {
            result = result.filter { !$0.isHidden }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    private func toggleQuickLook() {
        if QuickLookCoordinator.shared.isVisible {
            QuickLookCoordinator.shared.close()
            quickLookLoadingItem = nil
        } else if let selected = sftpService.selectedFile {
            loadQuickLook(for: selected)
        }
    }

    private func loadQuickLook(for item: RemoteFileItem) {
        quickLookLoadingItem = item
        Task {
            let url: URL?
            if item.isDirectory {
                url = await sftpService.fetchQuickLookFolderURL(for: item)
            } else {
                url = await sftpService.fetchQuickLookURL(for: item)
            }
            await MainActor.run {
                if quickLookLoadingItem?.id == item.id {
                    quickLookLoadingItem = nil
                    if let url = url {
                        QuickLookCoordinator.shared.toggle(url: url)
                    }
                }
            }
        }
    }

    private func updateQuickLook(for item: RemoteFileItem) {
        guard QuickLookCoordinator.shared.isVisible else { return }
        Task {
            let url: URL?
            if item.isDirectory {
                url = await sftpService.fetchQuickLookFolderURL(for: item)
            } else {
                url = await sftpService.fetchQuickLookURL(for: item)
            }
            await MainActor.run {
                QuickLookCoordinator.shared.updatePreview(url: url)
            }
        }
    }

    private var deleteAlertTitle: String {
        if let file = sftpService.fileToDelete {
            return "Delete “\(file.name)”?"
        }
        return "Delete Item?"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pane Header
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? connection.tagColor : Color.secondary)

                Text("Remote (\(connection.name))")
                    .font(.system(size: 13, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))

                Circle()
                    .fill(isActive ? connection.tagColor : connection.tagColor.opacity(0.35))
                    .frame(width: 8, height: 8)

                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(connection.tagColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(connection.tagColor.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(connection.tagColor.opacity(0.35), lineWidth: 1))
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                if let local = localManager, let selected = sftpService.selectedFile {
                    Button {
                        sftpService.download(remoteItem: selected, toLocalDir: local.currentURL)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Download selected item to local folder")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isActive ? connection.tagColor.opacity(0.06) : Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isActive ? connection.tagColor : Color.clear)
                    .frame(height: 2.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onActivate?()
                isTableFocused = true
            }

            Divider()

            // Path breadcrumb bar
            HStack(spacing: 6) {
                Button {
                    sftpService.navigateUp()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sftpService.currentPath == "/" ? Color.secondary.opacity(0.4) : Color(nsColor: .secondaryLabelColor))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sftpService.currentPath == "/")
                .help("Enclosing Folder (⌘↑)")

                if isEditingPath {
                    HStack(spacing: 6) {
                        TextField("Remote path", text: $editedPathText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12).monospaced())
                            .onSubmit {
                                sftpService.navigateToPath(editedPathText)
                                isEditingPath = false
                            }

                        Button("Go") {
                            sftpService.navigateToPath(editedPathText)
                            isEditingPath = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            isEditingPath = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(pathSegments) { segment in
                                if segment.id != "root" {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                }

                                Button {
                                    if !segment.isLast {
                                        sftpService.navigateToPath(segment.fullPath)
                                    } else {
                                        sftpService.refreshCurrentDirectory()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if segment.id == "root" {
                                            Image(systemName: "server.rack")
                                                .font(.system(size: 11))
                                                .foregroundStyle(connection.tagColor)
                                        } else {
                                            Image(systemName: segment.isLast ? "folder.fill" : "folder")
                                                .font(.system(size: 11))
                                                .foregroundStyle(segment.isLast ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                                        }
                                        Text(segment.name)
                                            .font(.system(size: 12, weight: segment.isLast ? .medium : .regular))
                                            .foregroundStyle(segment.isLast ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(segment.isLast ? Color(nsColor: .controlColor).opacity(0.4) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help(segment.fullPath)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editedPathText = sftpService.currentPath
                        isEditingPath = true
                    }

                    Spacer()

                    Button {
                        editedPathText = sftpService.currentPath
                        isEditingPath = true
                    } label: {
                        Label("Edit Path", systemImage: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .help("Edit path directly")

                    Menu {
                        Section("Columns") {
                            Toggle("Size", isOn: $showSize)
                            Toggle("Kind", isOn: $showKind)
                            Toggle("Date Modified", isOn: $showDateModified)
                            Toggle("Permissions", isOn: $showPermissions)
                            Toggle("Owner", isOn: $showOwner)
                        }
                    } label: {
                        Label("Columns", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .help("Show or hide table columns")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // File Listing area
            if sftpService.isBusy {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Fetching remote directory...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .error(let msg) = sftpService.state {
                let isPasswordRequired = connection.authType == .password && (connection.password.isEmpty || msg.lowercased().contains("password"))
                ContentUnavailableView {
                    Label(
                        isPasswordRequired ? "Password Required" : "Connection Failed",
                        systemImage: isPasswordRequired ? "lock.shield" : "exclamationmark.triangle"
                    )
                } description: {
                    Text(msg)
                } actions: {
                    HStack(spacing: 12) {
                        if isPasswordRequired || connection.authType == .password {
                            Button("Enter Password") {
                                onPromptPassword?(connection)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Retry") {
                            sftpService.retryConnection()
                        }
                        .buttonStyle(.bordered)

                        Button("Edit Connection") {
                            onEditConnection?(connection)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFiles.isEmpty {
                ContentUnavailableView {
                    Label("Folder is Empty", systemImage: "folder")
                } description: {
                    Text("No files or directories found in \(sftpService.currentPath)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewMode {
                case .list:
                    listView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .icons:
                    iconsView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .columns:
                    columnsView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            remoteStatusBar
        }
        .defaultFocus($isTableFocused, true)
        .onAppear {
            if isActive {
                isTableFocused = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                isTableFocused = true
            } else {
                isTableFocused = false
            }
        }
        .onChange(of: sftpService.currentPath) {
            if isActive {
                isTableFocused = true
            }
        }
        .onChange(of: sftpService.isBusy) { oldValue, newValue in
            if !newValue && isActive {
                isTableFocused = true
            }
        }
        .onKeyPress(.return) {
            if sftpService.renamingFileID == nil, let selected = sftpService.selectedFile {
                sftpService.startRenaming(file: selected)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if QuickLookCoordinator.shared.isVisible {
                QuickLookCoordinator.shared.close()
                return .handled
            }
            if sftpService.renamingFileID != nil {
                sftpService.cancelRenaming()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.downArrow], phases: .down) { press in
            if press.modifiers.contains(.command) && sftpService.renamingFileID == nil {
                sftpService.openSelectedFileOrFolder()
                return .handled
            }
            if sftpService.renamingFileID == nil {
                selectNextFile()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.upArrow], phases: .down) { press in
            if press.modifiers.contains(.command) && sftpService.renamingFileID == nil && sftpService.currentPath != "/" {
                sftpService.navigateUp()
                return .handled
            }
            if sftpService.renamingFileID == nil {
                selectPreviousFile()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.delete, KeyEquivalent("\u{7f}"), KeyEquivalent("\u{08}"), .deleteForward], phases: .down) { press in
            if press.modifiers.contains(.command) {
                if sftpService.renamingFileID == nil && !isEditingPath, let file = sftpService.selectedFile {
                    sftpService.promptDelete(file: file)
                    return .handled
                }
            } else if press.modifiers.isEmpty {
                if sftpService.renamingFileID == nil && !isEditingPath && sftpService.currentPath != "/" {
                    sftpService.navigateUp()
                    return .handled
                }
            }
            return .ignored
        }
        .onKeyPress(keys: [KeyEquivalent("[")], phases: .down) { press in
            if press.modifiers.contains(.command) && sftpService.renamingFileID == nil && !isEditingPath && sftpService.currentPath != "/" {
                sftpService.navigateUp()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            if sftpService.renamingFileID == nil && !isEditingPath && sftpService.selectedFile != nil {
                toggleQuickLook()
                return .handled
            }
            return .ignored
        }
        .simultaneousGesture(TapGesture().onEnded {
            onActivate?()
            isTableFocused = true
        })
        .onChange(of: sftpService.selectedFileID) { oldValue, newValue in
            if newValue != nil {
                onActivate?()
                isTableFocused = true
            }
            if let renamingID = sftpService.renamingFileID, renamingID != newValue {
                sftpService.commitOrCancelRename()
            }
            if let newID = newValue, let newFile = sftpService.files.first(where: { $0.id == newID }) {
                updateQuickLook(for: newFile)
            }
        }
        .onChange(of: isRenameFocused) { oldValue, newValue in
            if oldValue == true && newValue == false {
                sftpService.commitOrCancelRename()
                isTableFocused = true
            }
        }
        .alert(
            deleteAlertTitle,
            isPresented: $sftpService.showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                sftpService.fileToDelete = nil
                sftpService.showingDeleteConfirmation = false
            }
            Button("Delete", role: .destructive) {
                sftpService.confirmDelete()
            }
        } message: {
            if let file = sftpService.fileToDelete {
                Text("Are you sure you want to permanently delete \(file.isDirectory ? "the folder" : "the file") “\(file.name)”? This action cannot be undone.")
            } else {
                Text("Are you sure you want to permanently delete this item? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $sftpService.showingNewFolderDialog) {
            VStack(spacing: 16) {
                Text("New Remote Folder")
                    .font(.headline)

                TextField("Folder Name", text: $sftpService.newFolderName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        sftpService.showingNewFolderDialog = false
                    }
                    Button("Create") {
                        sftpService.createFolder(name: sftpService.newFolderName)
                        sftpService.showingNewFolderDialog = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sftpService.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        .alert(sftpService.errorAlertTitle, isPresented: $sftpService.showErrorAlert) {
            if sftpService.canReconnect {
                Button("Reconnect") {
                    sftpService.showErrorAlert = false
                    Task {
                        await sftpService.reconnect()
                    }
                }
            }
            Button("OK", role: .cancel) {
                sftpService.showErrorAlert = false
            }
        } message: {
            Text(sftpService.errorMessage ?? "Unable to connect to the remote server. Please check your network connection and server status.")
        }
        .sheet(isPresented: $sftpService.showingGoToFolder) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Go to Folder")
                    .font(.headline)

                Text("Enter a remote path:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("/path/to/folder", text: $sftpService.goToFolderPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit {
                        let path = sftpService.goToFolderPath
                        sftpService.showingGoToFolder = false
                        sftpService.navigateToPath(path)
                    }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        sftpService.showingGoToFolder = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Go") {
                        let path = sftpService.goToFolderPath
                        sftpService.showingGoToFolder = false
                        sftpService.navigateToPath(path)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sftpService.goToFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 380)
            .onAppear {
                sftpService.goToFolderPath = sftpService.currentPath
            }
        }
        .sheet(isPresented: $sftpService.showingGetInfo) {
            if let item = sftpService.infoItem {
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        Image(systemName: item.type.iconName)
                            .font(.system(size: 44))
                            .foregroundStyle(item.isDirectory ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(item.isDirectory ? "Folder" : "File")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.formattedSize)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Where", value: item.path)
                        LabeledContent("Modified", value: item.formattedDate)
                        LabeledContent("Permissions", value: item.permissions)
                        LabeledContent("Owner", value: "\(item.owner):\(item.group)")
                    }
                    .font(.callout)

                    Divider()

                    HStack {
                        Spacer()
                        Button("Done") {
                            sftpService.showingGetInfo = false
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(22)
                .frame(width: 380)
            }
        }
        .overlay {
            if let loading = quickLookLoadingItem {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Preparing Quick Look for \(loading.name)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 10)
            }
        }
        .task {
            if sftpService.state == .connected {
                await sftpService.fetchServerResourceStats()
            }
        }
        .onChange(of: sftpService.state) { _, newState in
            if newState == .connected {
                Task {
                    await sftpService.fetchServerResourceStats()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var remoteStatusBar: some View {
        HStack(spacing: 12) {
            // Left: Count and selection
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .foregroundStyle(connection.tagColor)
                    .font(.caption2)
                Text("\(filteredFiles.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let selected = sftpService.selectedFile {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("1 selected (\(selected.formattedSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right: Remote Server System Stats (RAM, CPU, Free Disk)
            if sftpService.state == .connected {
                HStack(spacing: 12) {
                    // CPU
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                        Text(sftpService.serverStats.cpuUsage != nil ? "CPU: \(sftpService.serverStats.cpuUsage!)" : "CPU: --")
                            .font(.caption.monospacedDigit())
                    }
                    .help("Remote CPU Usage / Load Average")

                    // RAM
                    HStack(spacing: 4) {
                        Image(systemName: "memorychip")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(sftpService.serverStats.ramUsage != nil ? "RAM: \(sftpService.serverStats.ramUsage!)" : "RAM: --")
                            .font(.caption.monospacedDigit())
                    }
                    .help("Remote RAM Memory Usage")

                    // Free Disk
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(sftpService.serverStats.diskFree != nil ? "\(sftpService.serverStats.diskFree!) free" : "-- free")
                            .font(.caption.monospacedDigit())
                    }
                    .help("Remote Free Disk Space")

                    // Refresh button
                    Button {
                        Task {
                            await sftpService.fetchServerResourceStats(force: true)
                        }
                    } label: {
                        if sftpService.serverStats.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Server Stats")
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var listView: some View {
        Table(of: RemoteFileItem.self, selection: $sftpService.selectedFileID) {
            TableColumn("Name") { file in
                HStack(spacing: 8) {
                    Image(systemName: file.type.iconName)
                        .foregroundStyle(file.isDirectory ? .blue : .secondary)
                        .background(
                            ScreenRectReader { rect in
                                if sftpService.selectedFileID == file.id {
                                    QuickLookCoordinator.shared.currentSourceFrame = rect
                                }
                            }
                        )

                    if sftpService.renamingFileID == file.id {
                        TextField("Name", text: $sftpService.renameText)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .focused($isRenameFocused)
                            .padding(.horizontal, 4)
                            .frame(height: 18)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1))
                            .onSubmit {
                                sftpService.submitRename(for: file)
                                isTableFocused = true
                            }
                            .onExitCommand {
                                sftpService.cancelRenaming()
                                isTableFocused = true
                            }
                            .onAppear {
                                isRenameFocused = true
                            }
                    } else {
                        Text(file.name)
                            .font(.body)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 20)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    if file.isDirectory {
                        sftpService.navigate(to: file)
                    }
                })
            }
            .width(min: 200, ideal: 280)

            if showSize {
                TableColumn("Size") { file in
                    HStack {
                        Text(file.formattedSize)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if file.isDirectory {
                            sftpService.navigate(to: file)
                        }
                    })
                }
                .width(min: 80, ideal: 100, max: 120)
            }

            if showKind {
                TableColumn("Kind") { file in
                    HStack {
                        Text(file.kindDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if file.isDirectory {
                            sftpService.navigate(to: file)
                        }
                    })
                }
                .width(min: 80, ideal: 100, max: 130)
            }

            if showDateModified {
                TableColumn("Date Modified") { file in
                    HStack {
                        Text(file.formattedDate)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if file.isDirectory {
                            sftpService.navigate(to: file)
                        }
                    })
                }
                .width(min: 140, ideal: 170)
            }

            if showPermissions {
                TableColumn("Permissions") { file in
                    HStack {
                        Text(file.permissions)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if file.isDirectory {
                            sftpService.navigate(to: file)
                        }
                    })
                }
                .width(min: 90, ideal: 110, max: 130)
            }

            if showOwner {
                TableColumn("Owner") { file in
                    HStack {
                        Text("\(file.owner):\(file.group)")
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if file.isDirectory {
                            sftpService.navigate(to: file)
                        }
                    })
                }
                .width(min: 90, ideal: 120, max: 140)
            }
        } rows: {
            if groupBy == .none {
                ForEach(filteredFiles) { file in
                    TableRow(file)
                }
            } else {
                ForEach(groupSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { file in
                            TableRow(file)
                        }
                    }
                }
            }
        }
        .focused($isTableFocused)
        .background(Color(nsColor: .textBackgroundColor))
        .contextMenu(forSelectionType: String.self) { selectedIDs in
            if let firstID = selectedIDs.first, let file = sftpService.files.first(where: { $0.id == firstID }) {
                contextMenu(for: file)
            }
        }
    }

    private var iconsView: some View {
        ScrollView {
            if groupBy == .none {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(filteredFiles) { file in
                        iconGridItem(for: file)
                    }
                }
                .padding(16)
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groupSections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(section.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(section.items.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            Divider()
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(section.items) { file in
                                    iconGridItem(for: file)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func iconGridItem(for file: RemoteFileItem) -> some View {
        let isSelected = sftpService.selectedFileID == file.id
        VStack(spacing: 6) {
            Image(systemName: file.type.iconName)
                .font(.system(size: 38))
                .foregroundStyle(file.isDirectory ? .blue : .secondary)
                .background(
                    ScreenRectReader { rect in
                        if sftpService.selectedFileID == file.id {
                            QuickLookCoordinator.shared.currentSourceFrame = rect
                        }
                    }
                )

            if sftpService.renamingFileID == file.id {
                TextField("Name", text: $sftpService.renameText)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($isRenameFocused)
                    .padding(.horizontal, 4)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1))
                    .onSubmit {
                        sftpService.submitRename(for: file)
                        isTableFocused = true
                    }
                    .onExitCommand {
                        sftpService.cancelRenaming()
                        isTableFocused = true
                    }
                    .onAppear {
                        isRenameFocused = true
                    }
            } else {
                Text(file.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.accentColor : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: 88, height: 80)
        .contentShape(Rectangle())
        .onTapGesture {
            sftpService.selectedFileID = file.id
            isTableFocused = true
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if file.isDirectory {
                sftpService.navigate(to: file)
            }
        })
        .contextMenu {
            contextMenu(for: file)
        }
    }

    private var columnsView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(millerColumns.enumerated()), id: \.element.id) { index, column in
                        millerColumnView(column: column, columnIndex: index)
                            .id("col-\(index)")

                        Divider()
                    }

                    if let preview = previewItem {
                        columnPreviewPane(for: preview)
                            .id("preview-pane")

                        Divider()
                    }

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id("scroll-anchor")
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: millerColumns.count) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo("scroll-anchor", anchor: .trailing)
                }
            }
            .onChange(of: previewItem?.id) { _, _ in
                if previewItem != nil {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("scroll-anchor", anchor: .trailing)
                    }
                }
            }
        }
        .onAppear {
            resetMillerColumns()
        }
        .onChange(of: sftpService.currentPath) { _, _ in
            resetMillerColumns()
        }
        .onChange(of: showHiddenFiles) { _, _ in
            if viewMode == .columns {
                resetMillerColumns()
            }
        }
        .onChange(of: filteredFiles) { _, newFiles in
            if !millerColumns.isEmpty && millerColumns[0].path == sftpService.currentPath {
                millerColumns[0].items = newFiles
            }
        }
    }

    private func resetMillerColumns() {
        millerColumns = [
            MillerColumn(
                id: sftpService.currentPath,
                path: sftpService.currentPath,
                items: filteredFiles,
                selectedFileID: sftpService.selectedFileID,
                isLoading: false
            )
        ]
        previewItem = nil
    }

    private func didSelect(item: RemoteFileItem, inColumn colIndex: Int) {
        if millerColumns.count > colIndex + 1 {
            millerColumns.removeSubrange((colIndex + 1)...)
        }
        millerColumns[colIndex].selectedFileID = item.id
        sftpService.selectedFileID = item.id
        isTableFocused = true

        if item.isDirectory {
            previewItem = nil
            let newColumn = MillerColumn(
                id: item.path,
                path: item.path,
                items: [],
                selectedFileID: nil,
                isLoading: true
            )
            millerColumns.append(newColumn)

            Task {
                if let items = try? await sftpService.fetchDirectory(atPath: item.path) {
                    let displayItems = showHiddenFiles ? items : items.filter { !$0.isHidden }
                    await MainActor.run {
                        if let idx = millerColumns.firstIndex(where: { $0.id == item.path }) {
                            millerColumns[idx].items = displayItems
                            millerColumns[idx].isLoading = false
                        }
                    }
                } else {
                    await MainActor.run {
                        if let idx = millerColumns.firstIndex(where: { $0.id == item.path }) {
                            millerColumns[idx].isLoading = false
                        }
                    }
                }
            }
        } else {
            previewItem = item
        }
    }

    @ViewBuilder
    private func millerColumnView(column: MillerColumn, columnIndex: Int) -> some View {
        VStack(spacing: 0) {
            if column.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Spacer()
            } else if column.items.isEmpty {
                Spacer()
                Text("Zero Items")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 1) {
                        if groupBy == .none {
                            ForEach(column.items) { item in
                                millerRowItem(item: item, inColumn: columnIndex)
                            }
                        } else {
                            ForEach(groupFiles(column.items, by: groupBy)) { section in
                                HStack {
                                    Text(section.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 2)

                                ForEach(section.items) { item in
                                    millerRowItem(item: item, inColumn: columnIndex)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func millerRowItem(item: RemoteFileItem, inColumn colIndex: Int) -> some View {
        let isSelected = millerColumns[colIndex].selectedFileID == item.id

        HStack(spacing: 6) {
            Image(systemName: item.type.iconName)
                .font(.system(size: 13))
                .foregroundStyle(item.isDirectory ? (isSelected ? .white : .blue) : (isSelected ? .white : .secondary))
                .background(
                    ScreenRectReader { rect in
                        if sftpService.selectedFileID == item.id {
                            QuickLookCoordinator.shared.currentSourceFrame = rect
                        }
                    }
                )

            if sftpService.renamingFileID == item.id {
                TextField("Name", text: $sftpService.renameText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isRenameFocused)
                    .padding(.horizontal, 4)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1))
                    .onSubmit {
                        sftpService.submitRename(for: item)
                        isTableFocused = true
                    }
                    .onExitCommand {
                        sftpService.cancelRenaming()
                        isTableFocused = true
                    }
            } else {
                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? .white : .primary)
            }

            Spacer()

            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            didSelect(item: item, inColumn: colIndex)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if item.isDirectory {
                sftpService.navigate(to: item)
            }
        })
        .contextMenu {
            contextMenu(for: item)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func columnPreviewPane(for item: RemoteFileItem) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(item.isDirectory ? .blue : .secondary)
                    .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Text(item.isDirectory ? "Folder" : "Document")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(item.formattedSize)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)

                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Kind", value: item.isDirectory ? "Folder" : "File")
                    LabeledContent("Size", value: item.formattedSize)
                    LabeledContent("Modified", value: item.formattedDate)
                    LabeledContent("Permissions", value: item.permissions)
                    LabeledContent("Owner", value: "\(item.owner):\(item.group)")
                    LabeledContent("Where", value: item.path)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 16)

                Divider()
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    Button {
                        sftpService.promptGetInfo(for: item)
                    } label: {
                        Label("Get Info", systemImage: "info.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        sftpService.duplicateFile(item: item)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        sftpService.promptDelete(file: item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func contextMenu(for file: RemoteFileItem) -> some View {
        Button {
            sftpService.selectedFileID = file.id
            loadQuickLook(for: file)
        } label: {
            Label("Quick Look “\(file.name)”", systemImage: "eye")
        }
        Divider()

        if let local = localManager {
            Button {
                sftpService.download(remoteItem: file, toLocalDir: local.currentURL)
            } label: {
                Label("Download to '\(local.currentURL.lastPathComponent)'", systemImage: "arrow.down.circle")
            }
            Divider()
        }

        if file.isDirectory {
            Button("Open Folder") {
                sftpService.navigate(to: file)
            }
            Button {
                TerminalLauncher.openRemoteTerminal(connection: connection, remotePath: file.path)
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
        }

        Button("Get Info") {
            sftpService.promptGetInfo(for: file)
        }

        Button("Rename") {
            sftpService.startRenaming(file: file)
        }

        Button("Duplicate") {
            sftpService.duplicateFile(item: file)
        }

        Divider()

        Button("Delete", role: .destructive) {
            sftpService.selectedFileID = file.id
            sftpService.promptDelete(file: file)
        }

        Divider()

        Menu("Columns") {
            Toggle("Size", isOn: $showSize)
            Toggle("Kind", isOn: $showKind)
            Toggle("Date Modified", isOn: $showDateModified)
            Toggle("Permissions", isOn: $showPermissions)
            Toggle("Owner", isOn: $showOwner)
        }
    }

    private func selectNextFile() {
        guard !filteredFiles.isEmpty else { return }
        guard let currentID = sftpService.selectedFileID,
              let currentIndex = filteredFiles.firstIndex(where: { $0.id == currentID }) else {
            sftpService.selectedFileID = filteredFiles.first?.id
            return
        }
        let nextIndex = min(currentIndex + 1, filteredFiles.count - 1)
        sftpService.selectedFileID = filteredFiles[nextIndex].id
    }

    private func selectPreviousFile() {
        guard !filteredFiles.isEmpty else { return }
        guard let currentID = sftpService.selectedFileID,
              let currentIndex = filteredFiles.firstIndex(where: { $0.id == currentID }) else {
            sftpService.selectedFileID = filteredFiles.first?.id
            return
        }
        let prevIndex = max(currentIndex - 1, 0)
        sftpService.selectedFileID = filteredFiles[prevIndex].id
    }
}
