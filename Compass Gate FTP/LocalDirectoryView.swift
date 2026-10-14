//
//  LocalDirectoryView.swift
//  Compass Gate FTP
//

import SwiftUI
import AppKit
import QuickLook

enum LocalFolder: String, CaseIterable, Identifiable {
    case applications = "Applications"
    case desktop = "Desktop"
    case documents = "Documents"
    case downloads = "Downloads"
    case home = "Home"
    case iCloud = "iCloud Drive"
    case pictures = "Pictures"
    case movies = "Movies"
    case music = "Music"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home:
            let user = NSUserName()
            return user.isEmpty ? "Home" : user
        default:
            return rawValue
        }
    }

    var iconName: String {
        switch self {
        case .applications:
            return "app.badge"
        case .desktop:
            return "desktopcomputer"
        case .documents:
            return "doc.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .home:
            return "house.fill"
        case .iCloud:
            return "icloud.fill"
        case .pictures:
            return "photo.fill"
        case .movies:
            return "film.fill"
        case .music:
            return "music.note"
        }
    }

    var systemDirectory: URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        switch self {
        case .applications:
            let apps = URL(fileURLWithPath: "/Applications")
            return fm.fileExists(atPath: apps.path) ? apps : nil
        case .desktop:
            return home.appendingPathComponent("Desktop")
        case .documents:
            return home.appendingPathComponent("Documents")
        case .downloads:
            return home.appendingPathComponent("Downloads")
        case .home:
            return home
        case .iCloud:
            let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            return fm.fileExists(atPath: icloud.path) ? icloud : nil
        case .pictures:
            return home.appendingPathComponent("Pictures")
        case .movies:
            return home.appendingPathComponent("Movies")
        case .music:
            return home.appendingPathComponent("Music")
        }
    }

    var isAvailable: Bool {
        guard let url = systemDirectory else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

struct LocalFileItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date

    var formattedSize: String {
        if isDirectory { return "--" }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }

    var iconName: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico", "heic":
            return "photo"
        case "pdf", "doc", "docx", "txt", "md", "rtf":
            return "doc.richtext"
        case "zip", "tar", "gz", "tgz", "bz2", "7z", "rar":
            return "doc.zipper"
        case "swift", "py", "js", "ts", "html", "css", "json", "sh", "bash", "php", "c", "cpp":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }

    var kindDescription: String {
        if isDirectory { return "Folder" }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return "Document" }
        return "\(ext.uppercased()) File"
    }
}

@Observable
final class LocalFileManager {
    var currentURL: URL
    var files: [LocalFileItem] = []
    var selectedFileID: String? = nil
    var errorMessage: String? = nil

    init(initialURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let target = initialURL ?? home.appendingPathComponent("Downloads")
        self.currentURL = FileManager.default.fileExists(atPath: target.path) ? target : home
        loadCurrentDirectory()
    }

    var selectedFile: LocalFileItem? {
        guard let id = selectedFileID else { return nil }
        return files.first { $0.id == id }
    }

    func navigate(to item: LocalFileItem) {
        guard item.isDirectory else { return }
        currentURL = item.url
        selectedFileID = nil
        loadCurrentDirectory()
    }

    func navigateUp() {
        let parent = currentURL.deletingLastPathComponent()
        if parent.path != currentURL.path {
            currentURL = parent
            selectedFileID = nil
            loadCurrentDirectory()
        }
    }

    func navigateToPath(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            currentURL = url
            selectedFileID = nil
            loadCurrentDirectory()
        }
    }

    func refresh() {
        loadCurrentDirectory()
    }

    func loadCurrentDirectory() {
        let fm = FileManager.default
        let targetURL = currentURL.standardized
        do {
            let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            let showHidden = UserDefaults.standard.bool(forKey: "settings_showHiddenFiles")
            let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
            let contents = try fm.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: resourceKeys,
                options: options
            )

            var loaded: [LocalFileItem] = []
            for fileURL in contents {
                let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                var isObjCDir: ObjCBool = false
                _ = fm.fileExists(atPath: fileURL.path, isDirectory: &isObjCDir)
                let isDir = isObjCDir.boolValue || (values?.isDirectory ?? false)
                let size = Int64(values?.fileSize ?? 0)
                let date = values?.contentModificationDate ?? Date()

                loaded.append(LocalFileItem(
                    id: fileURL.path,
                    name: fileURL.lastPathComponent,
                    url: fileURL,
                    path: fileURL.path,
                    isDirectory: isDir,
                    size: size,
                    modifiedDate: date
                ))
            }

            self.files = loaded.sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            self.files = []
        }
    }
}

struct LocalFileBrowserView: View {
    @Bindable var localManager: LocalFileManager
    var sftpService: SFTPService?
    var viewMode: FileViewMode = .list
    var isActive: Bool = false
    var onActivate: (() -> Void)? = nil

    @State private var isEditingPath = false
    @State private var editedPathText = ""

    @AppStorage("localCol_size") private var showSize: Bool = true
    @AppStorage("localCol_kind") private var showKind: Bool = true
    @AppStorage("localCol_dateModified") private var showDateModified: Bool = true
    @AppStorage("settings_showHiddenFiles") private var showHiddenFiles: Bool = false

    @FocusState private var isTableFocused: Bool


    private func fetchLocalFolderInfo(url: URL) -> FolderQuickLookInfo {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        var size: Int64 = 0
        for u in items {
            if let s = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                size += Int64(s)
            }
        }
        return FolderQuickLookInfo(itemCount: items.count, totalSize: size, isLoading: false)
    }

    private struct PathSegment: Identifiable {
        let id: String
        let name: String
        let url: URL
        let isLast: Bool
    }

    private var pathSegments: [PathSegment] {
        var segments: [PathSegment] = []
        var cur = localManager.currentURL
        var stack: [URL] = []

        while cur.path != "/" && cur.pathComponents.count > 1 {
            stack.append(cur)
            cur = cur.deletingLastPathComponent()
        }
        stack.append(URL(fileURLWithPath: "/"))
        let ordered = stack.reversed()

        for (idx, u) in ordered.enumerated() {
            let name = (u.path == "/") ? "Macintosh HD" : u.lastPathComponent
            segments.append(PathSegment(
                id: u.path,
                name: name,
                url: u,
                isLast: idx == ordered.count - 1
            ))
        }
        return segments
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                Text("Local (Mac)")
                    .font(.system(size: 13, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))

                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                if let sftp = sftpService, sftp.state == .connected, let selected = localManager.selectedFile {
                    Button {
                        sftp.upload(localURL: selected.url, toRemotePath: sftp.currentPath)
                    } label: {
                        Label("Upload", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Upload selected item to current remote folder")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isActive ? Color.accentColor.opacity(0.06) : Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(height: 2.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onActivate?()
                isTableFocused = true
            }

            Divider()

            // Breadcrumb Navigation
            HStack(spacing: 6) {
                Button {
                    localManager.navigateUp()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(localManager.currentURL.path == "/" ? Color.secondary.opacity(0.4) : Color(nsColor: .secondaryLabelColor))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(localManager.currentURL.path == "/")
                .help("Parent Folder (⌘↑)")

                if isEditingPath {
                    HStack(spacing: 6) {
                        TextField("Local path", text: $editedPathText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12).monospaced())
                            .onSubmit {
                                localManager.navigateToPath(editedPathText)
                                isEditingPath = false
                            }

                        Button("Go") {
                            localManager.navigateToPath(editedPathText)
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
                            ForEach(pathSegments) { seg in
                                if seg.id != "/" {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                }

                                Button {
                                    if !seg.isLast {
                                        localManager.currentURL = seg.url
                                        localManager.loadCurrentDirectory()
                                    } else {
                                        localManager.refresh()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: seg.id == "/" ? "internaldrive" : (seg.isLast ? "folder.fill" : "folder"))
                                            .font(.system(size: 11))
                                            .foregroundStyle(seg.isLast ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                                        Text(seg.name)
                                            .font(.system(size: 12, weight: seg.isLast ? .medium : .regular))
                                            .foregroundStyle(seg.isLast ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(seg.isLast ? Color(nsColor: .controlColor).opacity(0.4) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Spacer()

                    Button {
                        editedPathText = localManager.currentURL.path
                        isEditingPath = true
                    } label: {
                        Label("Edit Path", systemImage: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .help("Edit local path directly")

                    Menu {
                        Section("Columns") {
                            Toggle("Size", isOn: $showSize)
                            Toggle("Kind", isOn: $showKind)
                            Toggle("Date Modified", isOn: $showDateModified)
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

            // File Listing Table
            if let err = localManager.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "lock.trianglebadge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Cannot access this folder")
                        .font(.headline)
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Go to Home Folder") {
                        localManager.navigateToPath("~")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else if localManager.files.isEmpty {
                ContentUnavailableView("Folder is Empty", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                Table(of: LocalFileItem.self, selection: $localManager.selectedFileID) {
                TableColumn("Name") { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.iconName)
                            .foregroundStyle(file.isDirectory ? .blue : .secondary)
                            .background(
                                ScreenRectReader { rect in
                                    if localManager.selectedFileID == file.id {
                                        QuickLookCoordinator.shared.currentSourceFrame = rect
                                    }
                                }
                            )

                        Text(file.name)
                            .font(.body)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if file.isDirectory {
                            localManager.navigate(to: file)
                        } else {
                            NSWorkspace.shared.open(file.url)
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
                    }
                    .width(min: 140, ideal: 170)
                }
            } rows: {
                ForEach(localManager.files) { file in
                    TableRow(file)
                }
            }
            .focused($isTableFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .contextMenu(forSelectionType: String.self) { selectedIDs in
                if let firstID = selectedIDs.first, let file = localManager.files.first(where: { $0.id == firstID }) {
                    Button {
                        QuickLookCoordinator.shared.toggle(url: file.url)
                    } label: {
                        Label("Quick Look “\(file.name)”", systemImage: "eye")
                    }
                    Divider()

                    if let sftp = sftpService, sftp.state == .connected {
                        Button {
                            sftp.upload(localURL: file.url, toRemotePath: sftp.currentPath)
                        } label: {
                            Label("Upload to Remote Server", systemImage: "arrow.up.circle")
                        }
                        Divider()
                    }

                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }

                    Button("Open with Default App") {
                        NSWorkspace.shared.open(file.url)
                    }

                    Divider()

                    Button("Move to Trash", role: .destructive) {
                        try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                        localManager.refresh()
                    }
                }
            }

            }

            Divider()

            localStatusBar
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
        .onChange(of: localManager.currentURL) {
            if isActive {
                isTableFocused = true
            }
        }
        .onChange(of: sftpService?.transfers.count) { _, _ in
            localManager.refresh()
        }
        .onKeyPress(keys: [.downArrow], phases: .down) { press in
            if press.modifiers.contains(.command) && !isEditingPath {
                openSelectedFileOrFolder()
                return .handled
            }
            if !isEditingPath {
                selectNextFile()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.upArrow], phases: .down) { press in
            if press.modifiers.contains(.command) && !isEditingPath && localManager.currentURL.path != "/" {
                localManager.navigateUp()
                return .handled
            }
            if !isEditingPath {
                selectPreviousFile()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            if !isEditingPath, localManager.selectedFile != nil {
                openSelectedFileOrFolder()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.delete, KeyEquivalent("\u{7f}"), KeyEquivalent("\u{08}"), .deleteForward], phases: .down) { press in
            if press.modifiers.isEmpty && !isEditingPath && localManager.currentURL.path != "/" {
                localManager.navigateUp()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [KeyEquivalent("[")], phases: .down) { press in
            if press.modifiers.contains(.command) && !isEditingPath && localManager.currentURL.path != "/" {
                localManager.navigateUp()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            if !isEditingPath {
                if QuickLookCoordinator.shared.isVisible {
                    QuickLookCoordinator.shared.close()
                } else if let selectedID = localManager.selectedFileID,
                          let file = localManager.files.first(where: { $0.id == selectedID }) {
                    QuickLookCoordinator.shared.toggle(url: file.url)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if QuickLookCoordinator.shared.isVisible {
                QuickLookCoordinator.shared.close()
                return .handled
            }
            return .ignored
        }
        .simultaneousGesture(TapGesture().onEnded {
            onActivate?()
            isTableFocused = true
        })
        .onChange(of: showHiddenFiles) { _, _ in
            localManager.refresh()
        }
        .onChange(of: localManager.selectedFileID) { oldValue, newValue in
            if newValue != nil {
                onActivate?()
                isTableFocused = true
            }
            if QuickLookCoordinator.shared.isVisible,
               let newID = newValue,
               let newFile = localManager.files.first(where: { $0.id == newID }) {
                QuickLookCoordinator.shared.updatePreview(url: newFile.url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var localStatusBar: some View {
        HStack {
            Text("\(localManager.files.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selected = localManager.selectedFile {
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("1 selected (\(selected.formattedSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func selectNextFile() {
        guard !localManager.files.isEmpty else { return }
        guard let currentID = localManager.selectedFileID,
              let currentIndex = localManager.files.firstIndex(where: { $0.id == currentID }) else {
            localManager.selectedFileID = localManager.files.first?.id
            return
        }
        let nextIndex = min(currentIndex + 1, localManager.files.count - 1)
        localManager.selectedFileID = localManager.files[nextIndex].id
    }

    private func selectPreviousFile() {
        guard !localManager.files.isEmpty else { return }
        guard let currentID = localManager.selectedFileID,
              let currentIndex = localManager.files.firstIndex(where: { $0.id == currentID }) else {
            localManager.selectedFileID = localManager.files.first?.id
            return
        }
        let prevIndex = max(currentIndex - 1, 0)
        localManager.selectedFileID = localManager.files[prevIndex].id
    }

    private func openSelectedFileOrFolder() {
        guard let selected = localManager.selectedFile else { return }
        if selected.isDirectory {
            localManager.navigate(to: selected)
        } else {
            NSWorkspace.shared.open(selected.url)
        }
    }
}

struct LocalDirectoryView: View {
    let folder: LocalFolder

    @State private var localManager: LocalFileManager

    init(folder: LocalFolder) {
        self.folder = folder
        _localManager = State(initialValue: LocalFileManager(initialURL: folder.systemDirectory))
    }

    var body: some View {
        LocalFileBrowserView(localManager: localManager)
            .onChange(of: folder) { _, newFolder in
                if let dir = newFolder.systemDirectory {
                    localManager.currentURL = dir
                    localManager.loadCurrentDirectory()
                }
            }
    }
}
