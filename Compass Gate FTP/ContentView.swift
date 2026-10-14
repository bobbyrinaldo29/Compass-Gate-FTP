//
//  ContentView.swift
//  Compass Gate FTP
//
//  Created by Bobby Rinaldo Sukma Dewa on 10/10/26.
//

import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case tab(UUID)
    case quickConnect
    case activityTransfers
    case allBookmarks
    case group(String)
    case localFolder(LocalFolder)
}

enum FileViewMode: String, CaseIterable {
    case icons = "Icons"
    case list = "List"
    case columns = "Columns"
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var connections: [SSHConnection]

    @State private var selection: SidebarItem? = .allBookmarks
    @State private var showingAddSheet: Bool = false
    @State private var targetGroupForAdd: String = "Production Servers"
    @State private var showingNewGroupSheet: Bool = false
    @State private var showingImportSheet: Bool = false
    @State private var targetGroupForImport: String = "Production Servers"
    @State private var groupToDelete: BookmarkGroup? = nil
    @State private var showingDeleteGroupAlert: Bool = false
    @State private var connectionToEdit: SSHConnection?

    // Toolbar states matching ForkLift macOS native toolbar
    @State private var viewMode: FileViewMode = .list
    @State private var searchText: String = ""
    @State private var groupBy: FileGrouping = .none
    @State private var showDualPane: Bool = true
    @State private var localFileManager = LocalFileManager()

    @AppStorage("remoteCol_size") private var showRemoteColSize = true
    @AppStorage("remoteCol_kind") private var showRemoteColKind = true
    @AppStorage("remoteCol_dateModified") private var showRemoteColDateModified = true
    @AppStorage("remoteCol_permissions") private var showRemoteColPermissions = true
    @AppStorage("remoteCol_owner") private var showRemoteColOwner = true

    @AppStorage("localCol_size") private var showLocalColSize = true
    @AppStorage("localCol_kind") private var showLocalColKind = true
    @AppStorage("localCol_dateModified") private var showLocalColDateModified = true

    // SFTP State Manager
    @State private var sftpService = SFTPService()
    @State private var sessionTabs: [SessionTab] = []
    @State private var activeTabID: UUID? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var connectionNeedingPassword: SSHConnection? = nil

    private var activeTab: SessionTab? {
        if let id = activeTabID {
            return sessionTabs.first { $0.id == id }
        }
        return sessionTabs.first
    }

    private var activeSFTPService: SFTPService {
        activeTab?.service ?? sftpService
    }

    private var activeLocalManager: LocalFileManager {
        activeTab?.localManager ?? localFileManager
    }



    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                // Open Sessions / Tabs (Multi-Server Tabs)
                if !sessionTabs.isEmpty {
                    Section("Open Sessions") {
                        ForEach(sessionTabs) { tab in
                            NavigationLink(value: SidebarItem.tab(tab.id)) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(tab.connection.tagColor)
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tab.connection.name)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text("\(tab.connection.username)@\(tab.connection.host)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button {
                                        closeTab(tab)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Close Session Tab")
                                }
                            }
                        }
                    }
                }

                // Section 1: Connection
                Section("Connection") {
                    NavigationLink(value: SidebarItem.quickConnect) {
                        Label {
                            Text("Quick Connect")
                        } icon: {
                            Image(systemName: "bolt.horizontal.fill")
                                .foregroundStyle(.cyan)
                        }
                    }

                    NavigationLink(value: SidebarItem.activityTransfers) {
                        HStack {
                            Label {
                                Text("Activity & Transfers")
                            } icon: {
                                Image(systemName: "arrow.triangle.swap")
                                    .foregroundStyle(.blue)
                            }

                            Spacer()

                            if activeSFTPService.hasActiveTransfers {
                                ProgressView()
                                    .controlSize(.mini)
                            } else if !activeSFTPService.transfers.isEmpty {
                                Text("\(activeSFTPService.transfers.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }

                // Section 2: Bookmarks & Groups (Only Groups in Sidebar)
                Section {
                    NavigationLink(value: SidebarItem.allBookmarks) {
                        HStack {
                            Label("All Bookmarks", systemImage: "bookmark.fill")
                            Spacer()
                            Text("\(connections.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(BookmarkGroupManager.shared.allGroups) { grp in
                        let count = connections.filter { $0.groupRaw == grp.name }.count
                        NavigationLink(value: SidebarItem.group(grp.name)) {
                            HStack {
                                Label(grp.name, systemImage: grp.iconName)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                if BookmarkGroupManager.shared.allGroups.count > 1 {
                                    Button(role: .destructive) {
                                        promptDeleteGroup(grp, count: count)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .contextMenu {
                            if BookmarkGroupManager.shared.allGroups.count > 1 {
                                Button(role: .destructive) {
                                    promptDeleteGroup(grp, count: count)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Bookmarks & Groups")
                        Spacer()
                        Button {
                            showingNewGroupSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Create New Group")
                    }
                }

                // Section 3: Local Files (Finder Favorites)
                Section("Favorites") {
                    ForEach(LocalFolder.allCases.filter { $0.isAvailable }) { folder in
                        NavigationLink(value: SidebarItem.localFolder(folder)) {
                            Label(folder.displayName, systemImage: folder.iconName)
                        }
                    }
                }


            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            detailView()
                .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
                .toolbar {
                    mainToolbarItems()
                }
        }
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: $showingNewGroupSheet) {
            NewGroupView { newGroup in
                selection = .group(newGroup.name)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ConnectionEditorView(defaultGroupName: targetGroupForAdd)
        }
        .sheet(item: $connectionToEdit) { connection in
            ConnectionEditorView(connectionToEdit: connection)
        }
        .sheet(item: $connectionNeedingPassword) { connection in
            PasswordPromptView(
                connection: connection,
                onConnect: { password, remember in
                    if remember {
                        connection.password = password
                        try? modelContext.save()
                    }
                    connectionNeedingPassword = nil
                    if let tab = sessionTabs.first(where: { $0.connection.id == connection.id }) {
                        Task {
                            await tab.service.connect(to: connection, sessionPassword: password)
                        }
                    } else {
                        connectToBookmark(connection, sessionPassword: password)
                    }
                },
                onCancel: {
                    connectionNeedingPassword = nil
                }
            )
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportConnectionsView(initialGroupName: targetGroupForImport) { imported in
                for conn in imported {
                    modelContext.insert(conn)
                }
                try? modelContext.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowImportConnections"))) { _ in
            showingImportSheet = true
        }
        .alert("Delete Group \"\(groupToDelete?.name ?? "")\"?", isPresented: $showingDeleteGroupAlert) {
            Button("Cancel", role: .cancel) {
                groupToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let grp = groupToDelete {
                    deleteGroup(grp)
                }
                groupToDelete = nil
            }
        } message: {
            let count = connections.filter { $0.groupRaw == groupToDelete?.name }.count
            Text("This group contains \(count) server\(count == 1 ? "" : "s"). They will be safely moved to another group.")
        }

        .background {
            // Hidden buttons registering standard macOS Finder shortcuts
            Group {
                Button("Icons View") { viewMode = .icons }.keyboardShortcut("1", modifiers: .command)
                Button("List View") { viewMode = .list }.keyboardShortcut("2", modifiers: .command)
                Button("Columns View") { viewMode = .columns }.keyboardShortcut("3", modifiers: .command)
                Button("Go to Folder") {
                    sftpService.goToFolderPath = sftpService.currentPath
                    sftpService.showingGoToFolder = true
                }.keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Get Info") {
                    sftpService.promptGetInfoSelected()
                }.keyboardShortcut("i", modifiers: .command)
                Button("Open Item") {
                    sftpService.openSelectedFileOrFolder()
                }.keyboardShortcut("o", modifiers: .command)
                Button("Back Folder") {
                    activeSFTPService.navigateUp()
                }.keyboardShortcut("[", modifiers: .command)
                Button("New Tab") { openNewConnectionTab() }.keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") {
                    if let active = activeTab { closeTab(active) }
                }.keyboardShortcut("w", modifiers: .command)
                Button("Next Tab") { selectNextTab() }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { selectPreviousTab() }.keyboardShortcut("[", modifiers: [.command, .shift])
            }
            .opacity(0)
        }
        .overlay(alignment: .bottomTrailing) {
            if let toast = sftpService.currentToast {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: toast.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(toast.isSuccess ? .green : .red)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(toast.title)
                            .font(.headline)
                        Text(toast.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Button {
                        withAnimation {
                            sftpService.currentToast = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: 380)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(toast.isSuccess ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                .padding(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sftpService.currentToast)
        .onAppear {
            seedSampleDataIfNeeded()
        }
        .background(WindowBlurAccessor())
    }

    @ToolbarContentBuilder
    private func mainToolbarItems() -> some ToolbarContent {
        // 1. Activity / Transfers Circular Toggle Button
        ToolbarItem(placement: .navigation) {
            Button {
                selection = .activityTransfers
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.triangle.swap")
                    if activeSFTPService.hasActiveTransfers {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .help("Activity & Transfers")
        }

        // Dual Pane Toggle Button (Local & Remote)
        ToolbarItem(placement: .principal) {
            Button {
                showDualPane.toggle()
            } label: {
                Image(systemName: showDualPane ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }
            .help(showDualPane ? "Hide Local Browser (Remote Only)" : "Show Dual Pane (Local & Remote)")
        }

        // 2. View Mode (Icons, List, Columns) Native macOS Segmented Control
        ToolbarItem(placement: .principal) {
            Picker("View Mode", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(FileViewMode.icons)
                Image(systemName: "list.bullet").tag(FileViewMode.list)
                Image(systemName: "rectangle.split.3x1").tag(FileViewMode.columns)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Change View Mode")
        }

        // 3. Grouping / Arrange Menu Button
        ToolbarItem(placement: .principal) {
            Menu {
                Picker("Group By", selection: $groupBy) {
                    Label("None", systemImage: "circle.slash").tag(FileGrouping.none)
                    Divider()
                    Label("Name", systemImage: "textformat").tag(FileGrouping.name)
                    Label("Kind", systemImage: "square.2.layers.3d").tag(FileGrouping.kind)
                    Label("Date Modified", systemImage: "calendar").tag(FileGrouping.dateModified)
                    Label("Size", systemImage: "scalemass").tag(FileGrouping.size)
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: groupBy == .none ? "square.grid.3x2" : "square.grid.3x2.fill")
            }
            .help(groupBy == .none ? "Group By" : "Grouped by: \(groupBy.rawValue)")
        }

        // 4. Columns Filter Menu
        ToolbarItem(placement: .principal) {
            Menu {
                Section("Remote Columns") {
                    Toggle("Size", isOn: $showRemoteColSize)
                    Toggle("Kind", isOn: $showRemoteColKind)
                    Toggle("Date Modified", isOn: $showRemoteColDateModified)
                    Toggle("Permissions", isOn: $showRemoteColPermissions)
                    Toggle("Owner", isOn: $showRemoteColOwner)
                }

                Section("Local Columns") {
                    Toggle("Size", isOn: $showLocalColSize)
                    Toggle("Kind", isOn: $showLocalColKind)
                    Toggle("Date Modified", isOn: $showLocalColDateModified)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Show / Hide Table Columns")
        }

        // 5. Disconnect Group
        ToolbarItemGroup(placement: .principal) {
            Button {
                if let active = activeTab {
                    closeTab(active)
                } else {
                    activeSFTPService.disconnect()
                }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help("Disconnect Current Session (⌘W)")
            .disabled(activeSFTPService.state != .connected)
        }

        // 5. File Operations Group (Refresh, Duplicate, New Folder, Trash)
        ToolbarItemGroup(placement: .principal) {
            Button {
                activeSFTPService.refreshCurrentDirectory()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Directory (⌘R)")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(activeSFTPService.state != .connected)

            Button {
                activeSFTPService.duplicateSelectedFile()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Duplicate Selected Item (⌘D)")
            .keyboardShortcut("d", modifiers: .command)
            .disabled(activeSFTPService.selectedFile == nil || activeSFTPService.state != .connected)

            Button {
                activeSFTPService.newFolderName = ""
                activeSFTPService.showingNewFolderDialog = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New Remote Folder (⇧⌘N)")
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(activeSFTPService.state != .connected)

            Button {
                openTerminalForActiveRemote()
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal in Current Remote Folder")
            .disabled(activeSFTPService.state != .connected)

            Button {
                activeSFTPService.promptDeleteSelectedFile()
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete Selected Item (⌘⌫)")
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(activeSFTPService.selectedFile == nil || activeSFTPService.state != .connected)
        }

        // 6. New Tab Toolbar Button
        ToolbarItem(placement: .primaryAction) {
            Button {
                openNewConnectionTab()
            } label: {
                Image(systemName: "plus")
            }
            .help("New Connection Tab (⌘T)")
        }
    }

    @ViewBuilder
    private func tabBrowserContainer(tab: SessionTab) -> some View {
        VStack(spacing: 0) {
            SessionTabBarView(
                tabs: sessionTabs,
                activeTabID: activeTabID,
                onSelectTab: { selected in
                    activeTabID = selected.id
                    selection = .tab(selected.id)
                },
                onCloseTab: closeTab,
                onNewTab: openNewConnectionTab
            )

            connectedBrowserView(tab: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func connectedBrowserView(tab: SessionTab) -> some View {
        if showDualPane {
            HSplitView {
                LocalFileBrowserView(
                    localManager: tab.localManager,
                    sftpService: tab.service,
                    viewMode: viewMode,
                    isActive: tab.activePane == .local,
                    onActivate: { tab.activePane = .local }
                )
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

                RemoteFileBrowserView(
                    connection: tab.connection,
                    sftpService: tab.service,
                    viewMode: viewMode,
                    searchText: searchText,
                    groupBy: groupBy,
                    localManager: tab.localManager,
                    isActive: tab.activePane == .remote,
                    onActivate: { tab.activePane = .remote },
                    onPromptPassword: { conn in
                        connectionNeedingPassword = conn
                    },
                    onEditConnection: { conn in
                        connectionToEdit = conn
                    }
                )
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onKeyPress(.tab) {
                tab.activePane = (tab.activePane == .local) ? .remote : .local
                return .handled
            }
        } else {
            RemoteFileBrowserView(
                connection: tab.connection,
                sftpService: tab.service,
                viewMode: viewMode,
                searchText: searchText,
                groupBy: groupBy,
                localManager: tab.localManager,
                isActive: true,
                onActivate: nil,
                onPromptPassword: { conn in
                    connectionNeedingPassword = conn
                },
                onEditConnection: { conn in
                    connectionToEdit = conn
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func detailView() -> some View {
        switch selection {
        case .tab(let tabID):
            if let tab = sessionTabs.first(where: { $0.id == tabID }) {
                tabBrowserContainer(tab: tab)
            } else if let fallback = sessionTabs.first {
                tabBrowserContainer(tab: fallback)
            } else {
                bookmarkListView(title: "All Bookmarks", iconName: "bookmark.fill", group: nil)
            }
        case .quickConnect:
            VStack(spacing: 0) {
                if !sessionTabs.isEmpty {
                    SessionTabBarView(
                        tabs: sessionTabs,
                        activeTabID: activeTabID,
                        onSelectTab: { selected in
                            activeTabID = selected.id
                            selection = .tab(selected.id)
                        },
                        onCloseTab: closeTab,
                        onNewTab: openNewConnectionTab
                    )
                }
                QuickConnectView(
                    sftpService: activeSFTPService,
                    savedConnections: connections,
                    onConnect: { conn in
                        connectToBookmark(conn)
                    }
                )
            }
        case .activityTransfers:
            TransfersActivityView(sftpService: activeSFTPService)
        case .allBookmarks:
            VStack(spacing: 0) {
                if !sessionTabs.isEmpty {
                    SessionTabBarView(
                        tabs: sessionTabs,
                        activeTabID: activeTabID,
                        onSelectTab: { selected in
                            activeTabID = selected.id
                            selection = .tab(selected.id)
                        },
                        onCloseTab: closeTab,
                        onNewTab: openNewConnectionTab
                    )
                }
                bookmarkListView(title: "All Bookmarks", iconName: "bookmark.fill", group: nil)
            }
        case .group(let groupName):
            let grp = BookmarkGroupManager.shared.group(named: groupName)
            let icon = grp?.iconName ?? "folder.fill"
            VStack(spacing: 0) {
                if !sessionTabs.isEmpty {
                    SessionTabBarView(
                        tabs: sessionTabs,
                        activeTabID: activeTabID,
                        onSelectTab: { selected in
                            activeTabID = selected.id
                            selection = .tab(selected.id)
                        },
                        onCloseTab: closeTab,
                        onNewTab: openNewConnectionTab
                    )
                }
                bookmarkListView(title: groupName, iconName: icon, group: groupName)
            }
        case .localFolder(let folder):
            LocalFileBrowserView(
                localManager: activeLocalManager,
                sftpService: activeSFTPService,
                viewMode: viewMode
            )
            .onAppear {
                if let dir = folder.systemDirectory {
                    activeLocalManager.currentURL = dir
                    activeLocalManager.loadCurrentDirectory()
                }
            }
            .onChange(of: folder) { _, newFolder in
                if let dir = newFolder.systemDirectory {
                    activeLocalManager.currentURL = dir
                    activeLocalManager.loadCurrentDirectory()
                }
            }
        case .none:
            bookmarkListView(title: "All Bookmarks", iconName: "bookmark.fill", group: nil)
        }
    }

    private func bookmarkListView(title: String, iconName: String, group: String?) -> some View {
        BookmarkGroupListView(
            title: title,
            iconName: iconName,
            group: group,
            connections: connections,
            searchText: searchText,
            sftpService: activeSFTPService,
            sessionTabs: sessionTabs,
            onConnect: { conn in
                connectToBookmark(conn)
            },
            onEdit: { conn in
                connectionToEdit = conn
            },
            onDuplicate: { conn in
                duplicateConnection(conn)
            },
            onDelete: { conn in
                deleteConnection(conn)
            },
            onAdd: { grp in
                targetGroupForAdd = grp ?? "Production Servers"
                showingAddSheet = true
            },
            onImport: {
                targetGroupForImport = group ?? "Production Servers"
                showingImportSheet = true
            },
            onMoveGroup: { conn, targetGroup in
                moveConnection(conn, to: targetGroup)
            },
            onBrowseFiles: {
                if let active = activeTab {
                    selection = .tab(active.id)
                }
            },
            onSwitchToTab: { tab in
                activeTabID = tab.id
                selection = .tab(tab.id)
            }
        )
    }

    private func connectToBookmark(_ conn: SSHConnection, sessionPassword: String? = nil) {
        let effectivePassword = sessionPassword ?? conn.password
        if conn.authType == .password && effectivePassword.isEmpty {
            connectionNeedingPassword = conn
            return
        }

        // If connection is already open in a tab, switch directly to that tab!
        if let existing = sessionTabs.first(where: { $0.connection.id == conn.id }) {
            activeTabID = existing.id
            selection = .tab(existing.id)
            if existing.service.state != .connected {
                Task {
                    await existing.service.connect(to: conn, sessionPassword: effectivePassword)
                }
            }
            return
        }

        // Connecting to another server -> Create a brand new tab!
        let newTab = SessionTab(connection: conn)
        sessionTabs.append(newTab)
        activeTabID = newTab.id
        selection = .tab(newTab.id)

        Task {
            await newTab.service.connect(to: conn, sessionPassword: effectivePassword)
        }
    }

    private func closeTab(_ tab: SessionTab) {
        tab.service.disconnect()
        if let idx = sessionTabs.firstIndex(where: { $0.id == tab.id }) {
            sessionTabs.remove(at: idx)
            if activeTabID == tab.id {
                if let nextTab = sessionTabs.indices.contains(idx) ? sessionTabs[idx] : sessionTabs.last {
                    activeTabID = nextTab.id
                    selection = .tab(nextTab.id)
                } else {
                    activeTabID = nil
                    selection = .allBookmarks
                }
            }
        }
    }

    private func openTerminalForActiveRemote() {
        guard let tab = activeTab ?? sessionTabs.first(where: { $0.service.state == .connected }) else { return }
        TerminalLauncher.openRemoteTerminal(connection: tab.connection, remotePath: tab.service.currentPath)
    }

    private func openNewConnectionTab() {
        selection = .quickConnect
    }

    private func selectNextTab() {
        guard sessionTabs.count > 1, let currentID = activeTabID,
              let idx = sessionTabs.firstIndex(where: { $0.id == currentID }) else { return }
        let nextIdx = (idx + 1) % sessionTabs.count
        let nextTab = sessionTabs[nextIdx]
        activeTabID = nextTab.id
        selection = .tab(nextTab.id)
    }

    private func selectPreviousTab() {
        guard sessionTabs.count > 1, let currentID = activeTabID,
              let idx = sessionTabs.firstIndex(where: { $0.id == currentID }) else { return }
        let prevIdx = (idx - 1 + sessionTabs.count) % sessionTabs.count
        let prevTab = sessionTabs[prevIdx]
        activeTabID = prevTab.id
        selection = .tab(prevTab.id)
    }

    private func duplicateConnection(_ conn: SSHConnection) {
        let copy = SSHConnection(
            name: "\(conn.name) Copy",
            host: conn.host,
            port: conn.port,
            username: conn.username,
            password: conn.password,
            keyFilePath: conn.keyFilePath,
            authType: conn.authType,
            group: conn.group,
            colorTag: conn.colorTag,
            remotePath: conn.remotePath
        )
        modelContext.insert(copy)
    }

    private func moveConnection(_ connection: SSHConnection, to targetGroup: String) {
        connection.groupRaw = targetGroup
        try? modelContext.save()
    }

    private func promptDeleteGroup(_ grp: BookmarkGroup, count: Int) {
        if count > 0 {
            groupToDelete = grp
            showingDeleteGroupAlert = true
        } else {
            deleteGroup(grp)
        }
    }

    private func deleteGroup(_ grp: BookmarkGroup) {
        let remainingGroups = BookmarkGroupManager.shared.allGroups.filter { $0.name != grp.name }
        guard let fallback = remainingGroups.first else { return }

        let affected = connections.filter { $0.groupRaw == grp.name }
        for conn in affected {
            conn.groupRaw = fallback.name
        }
        try? modelContext.save()

        BookmarkGroupManager.shared.deleteGroup(named: grp.name)

        if selection == .group(grp.name) {
            selection = .group(fallback.name)
        }
    }

    private func deleteConnection(_ connection: SSHConnection) {
        // If an open tab exists for this connection, close it
        if let tab = sessionTabs.first(where: { $0.connection.id == connection.id }) {
            closeTab(tab)
        }
        modelContext.delete(connection)
    }

    private func seedSampleDataIfNeeded() {
        if connections.isEmpty {
            let prod = SSHConnection(
                name: "Production Server",
                host: "ssh.example.com",
                port: 22,
                username: "admin",
                authType: .password,
                group: .production,
                remotePath: "/"
            )

            let staging = SSHConnection(
                name: "Staging Server",
                host: "staging.example.com",
                port: 2222,
                username: "developer",
                authType: .password,
                group: .staging,
                remotePath: "/"
            )

            modelContext.insert(prod)
            modelContext.insert(staging)
        }
    }
}
