//
//  SFTPService.swift
//  Compass Gate FTP
//

import Foundation
import AppKit
import SwiftUI
import UserNotifications
#if canImport(Citadel)
import Citadel
import NIO
import NIOSSH
import Crypto
#endif

enum SFTPConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

struct TransferToast: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isSuccess: Bool
}

enum TransferDirection: String, Sendable, CaseIterable {
    case upload = "Upload"
    case download = "Download"

    var iconName: String {
        switch self {
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .upload: return .blue
        case .download: return .orange
        }
    }
}

enum TransferStatus: Sendable, Equatable {
    case inProgress
    case completed
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .inProgress:
            return false
        }
    }

    var title: String {
        switch self {
        case .inProgress: return "Transferring"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct TransferItem: Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let direction: TransferDirection
    let isDirectory: Bool
    let sourcePath: String
    let destinationPath: String
    let serverName: String
    var fileSize: Int64
    var status: TransferStatus
    let startDate: Date
    var endDate: Date?

    var formattedSize: String {
        if isDirectory { return "Folder" }
        if fileSize <= 0 { return "--" }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: fileSize)
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: startDate)
    }

    var formattedDuration: String {
        guard let end = endDate else { return "In progress" }
        let duration = max(0.1, end.timeIntervalSince(startDate))
        if duration < 1.0 {
            return String(format: "%.1fs", duration)
        } else if duration < 60.0 {
            return String(format: "%.0fs", duration)
        } else {
            let mins = Int(duration) / 60
            let secs = Int(duration) % 60
            return "\(mins)m \(secs)s"
        }
    }

    var fileExtensionIcon: String {
        if isDirectory { return "folder.fill" }
        let ext = (fileName as NSString).pathExtension.lowercased()
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
}

struct ServerResourceStats: Equatable, Sendable {
    var cpuUsage: String? = nil
    var ramUsage: String? = nil
    var diskFree: String? = nil
    var isLoading: Bool = false
    var lastUpdated: Date? = nil
}

@Observable
final class SFTPService {
    var state: SFTPConnectionState = .disconnected
    var currentPath: String = "/"
    var files: [RemoteFileItem] = []
    var isBusy: Bool = false
    var statusMessage: String = ""
    var errorMessage: String? = nil
    var errorAlertTitle: String = "Connection Failed"
    var showErrorAlert: Bool = false
    var canReconnect: Bool { activeConnection != nil }
    var showingNewFolderDialog: Bool = false
    var newFolderName: String = ""
    var selectedFileID: String? = nil
    var transfers: [TransferItem] = []
    var currentToast: TransferToast? = nil
    var serverStats = ServerResourceStats()
    private var statsTimer: Timer? = nil
    private var toastDismissTask: Task<Void, Never>? = nil

    func showToast(title: String, message: String, isSuccess: Bool) {
        toastDismissTask?.cancel()
        currentToast = TransferToast(title: title, message: message, isSuccess: isSuccess)
        sendSystemNotification(title: title, body: message, isSuccess: isSuccess)
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                withAnimation {
                    self.currentToast = nil
                }
            }
        }
    }

    private func sendSystemNotification(title: String, body: String, isSuccess: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isSuccess ? .default : .defaultCritical

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }


    var hasActiveTransfers: Bool {
        transfers.contains { $0.status == .inProgress }
    }

    func clearTransfers(completedOnly: Bool = false) {
        if completedOnly {
            transfers.removeAll { $0.status.isFinished }
        } else {
            transfers.removeAll()
        }
    }

    func removeTransfer(id: UUID) {
        transfers.removeAll { $0.id == id }
    }

    var fileToDelete: RemoteFileItem? = nil
    var showingDeleteConfirmation: Bool = false

    // Inactivity & Auto-Reconnect
    var inactivityTimeout: TimeInterval = 300 // 5 minutes of idle
    var showingInactivityAlert: Bool = false
    var lastActivityDate: Date = Date()
    private var eventMonitor: Any?
    private var inactivityTimer: Timer?

    var selectedFile: RemoteFileItem? {
        guard let id = selectedFileID else { return nil }
        return files.first { $0.id == id }
    }

    func promptDeleteSelectedFile() {
        guard let file = selectedFile else { return }
        fileToDelete = file
        showingDeleteConfirmation = true
    }

    func promptDelete(file: RemoteFileItem) {
        fileToDelete = file
        showingDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let file = fileToDelete else { return }
        deleteFile(item: file)
        fileToDelete = nil
        if selectedFileID == file.id {
            selectedFileID = nil
        }
    }

    var renamingFileID: String? = nil
    var renameText: String = ""

    var showingGoToFolder: Bool = false
    var goToFolderPath: String = ""

    var showingGetInfo: Bool = false
    var infoItem: RemoteFileItem? = nil

    func promptGetInfo(for item: RemoteFileItem) {
        infoItem = item
        showingGetInfo = true
    }

    func promptGetInfoSelected() {
        guard let item = selectedFile else { return }
        promptGetInfo(for: item)
    }

    func openSelectedFileOrFolder() {
        guard let item = selectedFile else { return }
        if item.isDirectory {
            navigate(to: item)
        }
    }

    func generateDuplicateName(for originalName: String, isDirectory: Bool) -> String {
        let name: String
        let ext: String

        if isDirectory {
            name = originalName
            ext = ""
        } else {
            let nsName = originalName as NSString
            ext = nsName.pathExtension
            name = nsName.deletingPathExtension
        }

        func makeCandidate(copyCount: Int) -> String {
            let suffix = copyCount == 1 ? " copy" : " copy \(copyCount)"
            if ext.isEmpty {
                return "\(name)\(suffix)"
            } else {
                return "\(name)\(suffix).\(ext)"
            }
        }

        let existingNames = Set(files.map { $0.name.lowercased() })
        var counter = 1
        var candidate = makeCandidate(copyCount: counter)
        while existingNames.contains(candidate.lowercased()) {
            counter += 1
            candidate = makeCandidate(copyCount: counter)
        }
        return candidate
    }

    func duplicateSelectedFile() {
        guard let item = selectedFile else { return }
        duplicateFile(item: item)
    }

    func duplicateFile(item: RemoteFileItem) {
        let newName = generateDuplicateName(for: item.name, isDirectory: item.isDirectory)
        let parentDir: String
        if let lastSlash = item.path.range(of: "/", options: .backwards) {
            let prefix = String(item.path[..<lastSlash.lowerBound])
            parentDir = prefix.isEmpty ? "/" : prefix
        } else {
            parentDir = currentPath
        }
        let newFullPath = (parentDir == "/" ? "" : parentDir) + "/" + newName

        #if canImport(Citadel)
        if let sftp = sftpClient {
            isBusy = true
            Task {
                do {
                    if item.isDirectory {
                        try await self.copyDirectoryRecursively(sftp: sftp, from: item.path, to: newFullPath)
                    } else {
                        try await self.copySingleFile(sftp: sftp, from: item.path, to: newFullPath)
                    }
                    await MainActor.run {
                        self.loadDirectory(path: self.currentPath)
                    }
                } catch {
                    await MainActor.run {
                        let err = "Failed to duplicate: \(error.localizedDescription)"
                        self.statusMessage = err
                        self.errorMessage = err
                        self.showErrorAlert = true
                        self.isBusy = false
                    }
                }
            }
            return
        }
        #endif

        if let conn = activeConnection {
            isBusy = true
            Task {
                let res = await runSSHCommand(connection: conn, command: "cp -R -p '\(item.path)' '\(newFullPath)'")
                await MainActor.run {
                    if res.success {
                        self.loadDirectory(path: self.currentPath)
                    } else {
                        let err = "Failed to duplicate: \(res.error)"
                        self.statusMessage = err
                        self.errorMessage = err
                        self.showErrorAlert = true
                    }
                    self.isBusy = false
                }
            }
        }
    }

    #if canImport(Citadel)
    private func copySingleFile(sftp: SFTPClient, from sourcePath: String, to destPath: String) async throws {
        let sourceFile = try await sftp.openFile(filePath: sourcePath, flags: [.read])
        let data = try await sourceFile.readAll()
        try await sourceFile.close()

        let destFile = try await sftp.openFile(filePath: destPath, flags: [.write, .create, .truncate])
        try await destFile.write(data, at: 0)
        try await destFile.close()
    }

    private func copyDirectoryRecursively(sftp: SFTPClient, from sourceDir: String, to destDir: String) async throws {
        try await sftp.createDirectory(atPath: destDir)
        let entries = try await sftp.listDirectory(atPath: sourceDir)
        for entry in entries {
            for comp in entry.components {
                guard comp.filename != "." && comp.filename != ".." else { continue }
                let isDir = comp.longname.hasPrefix("d") || (comp.attributes.permissions.map { ($0 & 0o170000) == 0o040000 } ?? false)
                let childSrc = (sourceDir == "/" ? "" : sourceDir) + "/" + comp.filename
                let childDst = (destDir == "/" ? "" : destDir) + "/" + comp.filename
                if isDir {
                    try await copyDirectoryRecursively(sftp: sftp, from: childSrc, to: childDst)
                } else {
                    try await copySingleFile(sftp: sftp, from: childSrc, to: childDst)
                }
            }
        }
    }

    private func uploadSingleFile(sftp: SFTPClient, localFile: URL, remotePath: String) async throws {
        let localData = try Data(contentsOf: localFile)
        var buffer = ByteBufferAllocator().buffer(capacity: localData.count)
        buffer.writeBytes(localData)
        let destFile = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
        try await destFile.write(buffer, at: 0)
        try await destFile.close()
    }

    private func uploadDirectoryRecursively(sftp: SFTPClient, localDir: URL, remoteDir: String) async throws {
        try await sftp.createDirectory(atPath: remoteDir)
        let fileURLs = try FileManager.default.contentsOfDirectory(at: localDir, includingPropertiesForKeys: [.isDirectoryKey])
        for fileURL in fileURLs {
            let childRemote = (remoteDir == "/" ? "" : remoteDir) + "/" + fileURL.lastPathComponent
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                try await uploadDirectoryRecursively(sftp: sftp, localDir: fileURL, remoteDir: childRemote)
            } else {
                try await uploadSingleFile(sftp: sftp, localFile: fileURL, remotePath: childRemote)
            }
        }
    }

    private func downloadSingleFile(sftp: SFTPClient, remotePath: String, localFile: URL) async throws {
        let sourceFile = try await sftp.openFile(filePath: remotePath, flags: [.read])
        var buffer = try await sourceFile.readAll()
        try await sourceFile.close()
        let data = Data(buffer.readableBytesView)
        try data.write(to: localFile)
    }

    private func downloadDirectoryRecursively(sftp: SFTPClient, remoteDir: String, localDir: URL) async throws {
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        let entries = try await sftp.listDirectory(atPath: remoteDir)
        for entry in entries {
            for comp in entry.components {
                guard comp.filename != "." && comp.filename != ".." else { continue }
                let isDir = comp.longname.hasPrefix("d") || (comp.attributes.permissions.map { ($0 & 0o170000) == 0o040000 } ?? false)
                let childRemote = (remoteDir == "/" ? "" : remoteDir) + "/" + comp.filename
                let childLocal = localDir.appendingPathComponent(comp.filename)
                if isDir {
                    try await downloadDirectoryRecursively(sftp: sftp, remoteDir: childRemote, localDir: childLocal)
                } else {
                    try await downloadSingleFile(sftp: sftp, remotePath: childRemote, localFile: childLocal)
                }
            }
        }
    }
    #endif

    func upload(localURL: URL, toRemotePath remoteDir: String) {
        let fileName = localURL.lastPathComponent
        let targetRemotePath = (remoteDir == "/" ? "" : remoteDir) + "/" + fileName
        let serverName = activeConnection?.name ?? "SFTP Server"

        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir)
        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0

        let transferID = UUID()
        let newItem = TransferItem(
            id: transferID,
            fileName: fileName,
            direction: .upload,
            isDirectory: isDir.boolValue,
            sourcePath: localURL.path,
            destinationPath: targetRemotePath,
            serverName: serverName,
            fileSize: fileSize,
            status: .inProgress,
            startDate: Date(),
            endDate: nil
        )
        self.transfers.insert(newItem, at: 0)

        #if canImport(Citadel)
        if let sftp = sftpClient {
            isBusy = true
            statusMessage = "Uploading \(fileName)..."
            Task {
                do {
                    if isDir.boolValue {
                        try await self.uploadDirectoryRecursively(sftp: sftp, localDir: localURL, remoteDir: targetRemotePath)
                    } else {
                        try await self.uploadSingleFile(sftp: sftp, localFile: localURL, remotePath: targetRemotePath)
                    }
                    await MainActor.run {
                        if let idx = self.transfers.firstIndex(where: { $0.id == transferID }) {
                            self.transfers[idx].status = .completed
                            self.transfers[idx].endDate = Date()
                        }
                        self.loadDirectory(path: self.currentPath)
                        self.statusMessage = "Uploaded \(fileName) successfully"
                        self.showToast(title: "Upload Completed", message: "\(fileName) uploaded to server successfully", isSuccess: true)
                        self.isBusy = false
                    }
                } catch {
                    await MainActor.run {
                        let err = "Failed to upload \(fileName): \(error.localizedDescription)"
                        if let idx = self.transfers.firstIndex(where: { $0.id == transferID }) {
                            self.transfers[idx].status = .failed(error.localizedDescription)
                            self.transfers[idx].endDate = Date()
                        }
                        self.statusMessage = err
                        self.errorMessage = err
                        self.showToast(title: "Upload Failed", message: "Failed to upload \(fileName): \(error.localizedDescription)", isSuccess: false)
                        self.showErrorAlert = true
                        self.isBusy = false
                    }
                }
            }
            return
        }
        #endif
    }

    func download(remoteItem: RemoteFileItem, toLocalDir localDir: URL) {
        let localDestURL = localDir.appendingPathComponent(remoteItem.name)
        let serverName = activeConnection?.name ?? "SFTP Server"

        let transferID = UUID()
        let newItem = TransferItem(
            id: transferID,
            fileName: remoteItem.name,
            direction: .download,
            isDirectory: remoteItem.isDirectory,
            sourcePath: remoteItem.path,
            destinationPath: localDestURL.path,
            serverName: serverName,
            fileSize: remoteItem.size,
            status: .inProgress,
            startDate: Date(),
            endDate: nil
        )
        self.transfers.insert(newItem, at: 0)

        #if canImport(Citadel)
        if let sftp = sftpClient {
            isBusy = true
            statusMessage = "Downloading \(remoteItem.name)..."
            Task {
                do {
                    if remoteItem.isDirectory {
                        try await self.downloadDirectoryRecursively(sftp: sftp, remoteDir: remoteItem.path, localDir: localDestURL)
                    } else {
                        try await self.downloadSingleFile(sftp: sftp, remotePath: remoteItem.path, localFile: localDestURL)
                    }
                    await MainActor.run {
                        if let idx = self.transfers.firstIndex(where: { $0.id == transferID }) {
                            self.transfers[idx].status = .completed
                            self.transfers[idx].endDate = Date()
                        }
                        self.statusMessage = "Downloaded \(remoteItem.name) successfully"
                        self.showToast(title: "Download Completed", message: "\(remoteItem.name) downloaded to Mac successfully", isSuccess: true)
                        self.isBusy = false
                    }
                } catch {
                    await MainActor.run {
                        let err = "Failed to download \(remoteItem.name): \(error.localizedDescription)"
                        if let idx = self.transfers.firstIndex(where: { $0.id == transferID }) {
                            self.transfers[idx].status = .failed(error.localizedDescription)
                            self.transfers[idx].endDate = Date()
                        }
                        self.statusMessage = err
                        self.errorMessage = err
                        self.showToast(title: "Download Failed", message: "Failed to download \(remoteItem.name): \(error.localizedDescription)", isSuccess: false)
                        self.showErrorAlert = true
                        self.isBusy = false
                    }
                }
            }
            return
        }
        #endif
    }

    func fetchQuickLookURL(for item: RemoteFileItem) async -> URL? {
        guard !item.isDirectory else { return nil }

        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compass_preview_cache", isDirectory: true)
            .appendingPathComponent(String(abs(item.path.hashValue)), isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let localFileURL = cacheDir.appendingPathComponent(item.name)

        if FileManager.default.fileExists(atPath: localFileURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: localFileURL.path),
           let size = attrs[.size] as? Int64,
           size == item.size && size > 0 {
            return localFileURL
        }

        #if canImport(Citadel)
        if let sftp = sftpClient {
            do {
                try await downloadSingleFile(sftp: sftp, remotePath: item.path, localFile: localFileURL)
                return localFileURL
            } catch {
                return nil
            }
        }
        #endif

        if let conn = activeConnection {
            let res = await runSSHCommand(connection: conn, command: "cat '\(item.path)'")
            if res.success, let data = res.output.data(using: .utf8) {
                try? data.write(to: localFileURL)
                return localFileURL
            }
        }

        return nil
    }

    func fetchQuickLookFolderURL(for item: RemoteFileItem) async -> URL? {
        guard item.isDirectory else { return nil }

        let baseCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compass_preview_folders", isDirectory: true)
            .appendingPathComponent(String(abs(item.path.hashValue)), isDirectory: true)

        let folderURL = baseCacheDir.appendingPathComponent(item.name, isDirectory: true)

        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        #if canImport(Citadel)
        if let sftp = sftpClient {
            if let entries = try? await sftp.listDirectory(atPath: item.path) {
                let existingFiles = (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) ?? []
                for f in existingFiles {
                    try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(f))
                }

                for entry in entries {
                    for comp in entry.components {
                        if comp.filename == "." || comp.filename == ".." { continue }
                        let childURL = folderURL.appendingPathComponent(comp.filename)
                        let isDir = comp.longname.hasPrefix("d") || (comp.attributes.permissions.map { ($0 & 0o170000) == 0o040000 } ?? false)
                        if isDir {
                            try? FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
                        } else {
                            FileManager.default.createFile(atPath: childURL.path, contents: nil)
                            if let sz = comp.attributes.size, sz > 0 {
                                if let fh = try? FileHandle(forWritingTo: childURL) {
                                    try? fh.truncate(atOffset: sz)
                                    try? fh.close()
                                }
                            }
                        }
                    }
                }
            }
        }
        #endif

        try? FileManager.default.setAttributes([.modificationDate: item.modifiedDate], ofItemAtPath: folderURL.path)

        return folderURL
    }

    func fetchFolderQuickLookInfo(for path: String) async -> FolderQuickLookInfo {
        #if canImport(Citadel)
        if let sftp = sftpClient {
            do {
                let entries = try await sftp.listDirectory(atPath: path)
                var count = 0
                var size: Int64 = 0
                for entry in entries {
                    for comp in entry.components {
                        if comp.filename == "." || comp.filename == ".." { continue }
                        count += 1
                        size += comp.attributes.size.map { Int64($0) } ?? 0
                    }
                }
                return FolderQuickLookInfo(itemCount: count, totalSize: size, isLoading: false)
            } catch {
                return FolderQuickLookInfo(itemCount: 0, totalSize: 0, isLoading: false)
            }
        }
        #endif

        if let conn = activeConnection {
            let res = await runSSHCommand(connection: conn, command: "ls -1A '\(path)' | wc -l")
            let count = Int(res.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return FolderQuickLookInfo(itemCount: count, totalSize: 0, isLoading: false)
        }

        return FolderQuickLookInfo(itemCount: 0, totalSize: 0, isLoading: false)
    }

    func startRenaming(file: RemoteFileItem) {
        selectedFileID = file.id
        renamingFileID = file.id
        renameText = file.name
    }

    func commitOrCancelRename() {
        guard let renamingID = renamingFileID else { return }
        if let item = files.first(where: { $0.id == renamingID }) {
            let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != item.name {
                submitRename(for: item)
            } else {
                cancelRenaming()
            }
        } else {
            cancelRenaming()
        }
    }

    func startRenamingSelectedFile() {
        guard let file = selectedFile else { return }
        startRenaming(file: file)
    }

    func cancelRenaming() {
        renamingFileID = nil
        renameText = ""
        showingGoToFolder = false
        goToFolderPath = ""
        showingGetInfo = false
        infoItem = nil
    }

    func submitRename(for item: RemoteFileItem) {
        let trimmedNewName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty, trimmedNewName != item.name else {
            cancelRenaming()
            return
        }

        let parentDir: String
        if let lastSlash = item.path.range(of: "/", options: .backwards) {
            let prefix = String(item.path[..<lastSlash.lowerBound])
            parentDir = prefix.isEmpty ? "/" : prefix
        } else {
            parentDir = currentPath
        }

        let newFullPath = (parentDir == "/" ? "" : parentDir) + "/" + trimmedNewName
        renamingFileID = nil
        renameText = ""

        #if canImport(Citadel)
        if let sftp = sftpClient {
            Task {
                do {
                    try await sftp.rename(at: item.path, to: newFullPath)
                    await MainActor.run {
                        self.loadDirectory(path: self.currentPath)
                    }
                } catch {
                    await MainActor.run {
                        let friendly = self.friendlyErrorMessage(for: error, action: "rename item")
                        self.errorAlertTitle = friendly.title
                        self.statusMessage = friendly.message
                        self.errorMessage = friendly.message
                        self.showErrorAlert = true
                    }
                }
            }
            return
        }
        #endif

        if let conn = activeConnection {
            Task {
                let res = await runSSHCommand(connection: conn, command: "mv '\(item.path)' '\(newFullPath)'")
                await MainActor.run {
                    if res.success {
                        self.loadDirectory(path: self.currentPath)
                    } else {
                        let err = "Error renaming: \(res.error)"
                        self.statusMessage = err
                        self.errorMessage = err
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }


    func registerActivity() {
        lastActivityDate = Date()
    }

    func startInactivityMonitoring() {
        stopInactivityMonitoring()
        lastActivityDate = Date()
        showingInactivityAlert = false

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            self?.registerActivity()
            return event
        }

        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInactivity()
            }
        }
    }

    func stopInactivityMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        showingInactivityAlert = false
    }

    func checkInactivity() {
        guard state == .connected, !showingInactivityAlert, !isBusy else { return }
        let idleTime = Date().timeIntervalSince(lastActivityDate)
        if idleTime >= inactivityTimeout {
            showingInactivityAlert = true
        }
    }

    static let serverStatsShellCommand: String = "exec 2>&1; echo '===CPU==='; (awk '/cpu /{print $2+$4,$2+$4+$5}' /proc/stat 2>/dev/null; sleep 0.1; awk '/cpu /{print $2+$4,$2+$4+$5}' /proc/stat 2>/dev/null; cat /proc/loadavg 2>/dev/null || uptime); echo '===MEM==='; (free -m 2>/dev/null || cat /proc/meminfo 2>/dev/null || sysctl -n hw.memsize); echo '===DISK==='; (df -h . 2>/dev/null || df -h /)"

    func parseServerStats(_ output: String) -> ServerResourceStats? {
        // Handle legacy STATS|... format if present
        if let range = output.range(of: "STATS|") {
            let raw = String(output[range.upperBound...])
            let parts = raw.components(separatedBy: "|")
            if parts.count >= 3 {
                let cpu = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let ram = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let disk = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                return ServerResourceStats(
                    cpuUsage: (cpu.isEmpty || cpu == "--") ? nil : cpu,
                    ramUsage: (ram.isEmpty || ram == "--") ? nil : ram,
                    diskFree: (disk.isEmpty || disk == "--") ? nil : disk,
                    isLoading: false,
                    lastUpdated: Date()
                )
            }
        }

        func extractSection(startTag: String, endTag: String?) -> String? {
            guard let startRange = output.range(of: startTag) else { return nil }
            let remainder = output[startRange.upperBound...]
            if let endTag = endTag, let endRange = remainder.range(of: endTag) {
                return String(remainder[..<endRange.lowerBound])
            }
            return String(remainder)
        }

        let cpuPart = extractSection(startTag: "===CPU===", endTag: "===MEM===")
        let memPart = extractSection(startTag: "===MEM===", endTag: "===DISK===")
        let diskPart = extractSection(startTag: "===DISK===", endTag: nil)

        guard cpuPart != nil || memPart != nil || diskPart != nil else { return nil }

        var cpu: String? = nil
        var ram: String? = nil
        var disk: String? = nil

        // 1. Parse CPU
        if let cpuRaw = cpuPart?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let lines = cpuRaw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if lines.count >= 2 {
                let p1 = lines[0].split(separator: " ").compactMap { Double($0) }
                let p2 = lines[1].split(separator: " ").compactMap { Double($0) }
                if p1.count == 2 && p2.count == 2 {
                    let dTot = p2[1] - p1[1]
                    let dAct = p2[0] - p1[0]
                    if dTot > 0 {
                        let pct = max(0, min(100, Int(round((dAct * 100.0) / dTot))))
                        cpu = "\(pct)%"
                    }
                }
            }

            if cpu == nil {
                for line in lines {
                    let tokens = line.split(separator: " ").map(String.init)
                    if let first = tokens.first, Double(first) != nil {
                        cpu = "Load \(first)"
                        break
                    } else if let range = line.range(of: "load average") {
                        let after = String(line[range.upperBound...])
                            .trimmingCharacters(in: CharacterSet(charactersIn: "s: "))
                        let loadTokens = after.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        if let firstLoad = loadTokens.first, !firstLoad.isEmpty {
                            let subTokens = firstLoad.split(separator: " ").map(String.init)
                            cpu = "Load \(subTokens.first ?? firstLoad)"
                            break
                        }
                    }
                }
            }
        }

        // 2. Parse RAM
        if let memRaw = memPart?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let lines = memRaw.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("Mem:") {
                    let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    if parts.count >= 3, let totalMB = Double(parts[1]), let usedMB = Double(parts[2]), totalMB > 0 {
                        let pct = Int(round((usedMB / totalMB) * 100))
                        let usedGB = usedMB / 1024.0
                        let totalGB = totalMB / 1024.0
                        ram = String(format: "%d%% (%.1f/%.1f GB)", pct, usedGB, totalGB)
                        break
                    }
                } else if trimmed.hasPrefix("MemTotal:") {
                    var totalKB: Double? = nil
                    var availKB: Double? = nil
                    for l in lines {
                        let sub = l.trimmingCharacters(in: .whitespaces)
                        if sub.hasPrefix("MemTotal:"), let val = sub.split(whereSeparator: { $0.isWhitespace }).dropFirst().first.flatMap({ Double($0) }) {
                            totalKB = val
                        } else if (sub.hasPrefix("MemAvailable:") || sub.hasPrefix("MemFree:")), availKB == nil, let val = sub.split(whereSeparator: { $0.isWhitespace }).dropFirst().first.flatMap({ Double($0) }) {
                            availKB = val
                        }
                    }
                    if let t = totalKB, t > 0 {
                        let a = availKB ?? 0
                        let used = max(0, t - a)
                        let pct = Int(round((used / t) * 100))
                        let usedGB = used / 1048576.0
                        let totalGB = t / 1048576.0
                        ram = String(format: "%d%% (%.1f/%.1f GB)", pct, usedGB, totalGB)
                        break
                    }
                } else if let bytes = Double(trimmed), bytes > 1024 * 1024 * 100 {
                    let gb = bytes / 1073741824.0
                    ram = String(format: "%.1f GB", gb)
                    break
                }
            }
        }

        // 3. Parse Free Disk
        if let diskRaw = diskPart?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let lines = diskRaw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let lastLine = lines.last {
                let cols = lastLine.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if cols.count >= 4 {
                    disk = cols[3]
                }
            }
        }

        return ServerResourceStats(
            cpuUsage: cpu,
            ramUsage: ram,
            diskFree: disk,
            isLoading: false,
            lastUpdated: Date()
        )
    }

    func startStatsMonitoring() {
        stopStatsMonitoring()
        Task {
            await fetchServerResourceStats()
        }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchServerResourceStats()
            }
        }
    }

    func stopStatsMonitoring() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    func fetchServerResourceStats(force: Bool = false) async {
        guard state == .connected, let conn = activeConnection else { return }

        await MainActor.run {
            self.serverStats.isLoading = true
        }

        #if canImport(Citadel)
        if let client = self.sshClient {
            do {
                var buffer = try await client.executeCommand(Self.serverStatsShellCommand)
                if let str = buffer.readString(length: buffer.readableBytes),
                   let parsed = parseServerStats(str) {
                    await MainActor.run {
                        self.serverStats = parsed
                    }
                    return
                }
            } catch let err as TTYSTDError {
                var buf = err.message
                if let str = buf.readString(length: buf.readableBytes),
                   let parsed = parseServerStats(str) {
                    await MainActor.run {
                        self.serverStats = parsed
                    }
                    return
                }
            } catch {
                print("[SFTPService] Citadel stats query error: \(error)")
            }
        }
        #endif

        let result = await runSSHCommand(connection: conn, command: Self.serverStatsShellCommand)
        if result.success, let parsed = parseServerStats(result.output) {
            await MainActor.run {
                self.serverStats = parsed
            }
        } else {
            await MainActor.run {
                self.serverStats.isLoading = false
            }
        }
    }

    func reconnect() async {
        guard let conn = activeConnection else {
            disconnect()
            return
        }
        let pathToRestore = currentPath
        showingInactivityAlert = false
        stopInactivityMonitoring()

        #if canImport(Citadel)
        try? await sftpClient?.close()
        try? await sshClient?.close()
        sftpClient = nil
        sshClient = nil
        #endif

        await MainActor.run {
            self.state = .connecting
            self.statusMessage = "Reconnecting to \(conn.name)..."
            self.isBusy = true
        }

        await connect(to: conn, initialPath: pathToRestore)
    }

    var activeConnection: SSHConnection?

    #if canImport(Citadel)
    private var sshClient: SSHClient?
    private var sftpClient: SFTPClient?
    #endif

    func connect(to connection: SSHConnection, initialPath: String? = nil) async {
        self.activeConnection = connection
        await MainActor.run {
            self.state = .connecting
            self.statusMessage = "Connecting to \(connection.host):\(connection.port)..."
            self.errorMessage = nil
            self.showErrorAlert = false
            self.isBusy = true
            self.files = []
        }

        // Validate credentials before attempting network connection
        if connection.authType == .password && connection.password.isEmpty {
            let msg = "Password is required for \(connection.username)@\(connection.host). Please enter your password in Quick Connect or Edit Connection."
            await MainActor.run {
                self.state = .error(msg)
                self.statusMessage = msg
                self.errorMessage = msg
                self.showErrorAlert = true
                self.isBusy = false
            }
            return
        }

        let targetInitialPath = initialPath ?? (connection.remotePath.isEmpty ? "/" : connection.remotePath)
        let initialPath = targetInitialPath

        #if canImport(Citadel)
        do {
            let auth: SSHAuthenticationMethod
            if connection.authType == .password {
                auth = .passwordBased(username: connection.username, password: connection.password)
            } else {
                let rawKey = connection.keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "~/.ssh/id_rsa"
                    : connection.keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
                let expandedKey = (rawKey as NSString).expandingTildeInPath
                let keyUrl = URL(fileURLWithPath: expandedKey)
                guard FileManager.default.fileExists(atPath: expandedKey) else {
                    throw NSError(domain: "SFTPService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Private key file not found at \(rawKey)"])
                }
                let keyContent = try String(contentsOf: keyUrl, encoding: .utf8)
                if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: keyContent) {
                    auth = .rsa(username: connection.username, privateKey: rsaKey)
                } else if let edKey = try? Curve25519.Signing.PrivateKey(sshEd25519: keyContent) {
                    auth = .ed25519(username: connection.username, privateKey: edKey)
                } else {
                    throw NSError(domain: "SFTPService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported private key format in \(rawKey). Please provide an OpenSSH RSA or Ed25519 key."])
                }
            }

            let client = try await SSHClient.connect(
                host: connection.host,
                port: connection.port,
                authenticationMethod: auth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all
            )
            self.sshClient = client
            let sftp = try await client.openSFTP()
            self.sftpClient = sftp

            let remoteEntries = try await sftp.listDirectory(atPath: initialPath)
            var mappedFiles: [RemoteFileItem] = []

            for entry in remoteEntries {
                for comp in entry.components {
                    guard comp.filename != "." && comp.filename != ".." else { continue }
                    let isDir = comp.longname.hasPrefix("d") || (comp.attributes.permissions.map { ($0 & 0o170000) == 0o040000 } ?? false)
                    let isSym = comp.longname.hasPrefix("l")
                    let type: RemoteFileType = isDir ? .directory : (isSym ? .symlink : .file)
                    let fullPath = (initialPath == "/" ? "" : initialPath) + "/" + comp.filename

                    mappedFiles.append(
                        RemoteFileItem(
                            id: UUID().uuidString,
                            name: comp.filename,
                            path: fullPath,
                            type: type,
                            size: Int64(comp.attributes.size ?? 0),
                            permissions: comp.longname.isEmpty ? (isDir ? "drwxr-xr-x" : "-rw-r--r--") : String(comp.longname.prefix(10)),
                            owner: connection.username,
                            group: connection.username,
                            modifiedDate: comp.attributes.accessModificationTime?.modificationTime ?? Date()
                        )
                    )
                }
            }

            await MainActor.run {
                self.currentPath = initialPath
                self.files = mappedFiles.sorted {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory && !$1.isDirectory
                    }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                self.state = .connected
                self.statusMessage = "Connected to \(connection.host) via SFTP"
                self.isBusy = false
                self.startInactivityMonitoring()
                self.startStatsMonitoring()
            }
            return
        } catch {
            await MainActor.run {
                let friendly = self.friendlyErrorMessage(for: error, action: "connect to \(connection.host):\(connection.port)")
                self.errorAlertTitle = friendly.title
                self.state = .error(friendly.message)
                self.statusMessage = friendly.message
                self.errorMessage = friendly.message
                self.showErrorAlert = true
                self.files = []
                self.isBusy = false
            }
            return
        }
        #endif

        // Direct Native SSH Execution (Supports legacy RSA, id_rsa, and standard ciphers)
        let result = await runSSHCommand(connection: connection, command: "ls -la '\(initialPath)'")
        if result.success, let parsed = parseLsOutput(result.output, basePath: initialPath) {
            await MainActor.run {
                self.currentPath = initialPath
                self.files = parsed.sorted {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory && !$1.isDirectory
                    }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                self.state = .connected
                self.statusMessage = "Connected to \(connection.host)"
                self.isBusy = false
                self.startInactivityMonitoring()
                self.startStatsMonitoring()
            }
        } else {
            let errorDetail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            let friendly = self.friendlyErrorMessage(for: errorDetail.isEmpty ? "Connection to \(connection.host):\(connection.port) failed" : errorDetail, action: "connect to \(connection.host):\(connection.port)")
            await MainActor.run {
                self.errorAlertTitle = friendly.title
                self.state = .error(friendly.message)
                self.statusMessage = friendly.message
                self.errorMessage = friendly.message
                self.showErrorAlert = true
                self.files = []
                self.isBusy = false
            }
        }
    }

    func disconnect() {
        stopInactivityMonitoring()
        stopStatsMonitoring()
        serverStats = ServerResourceStats()
        #if canImport(Citadel)
        Task {
            try? await sftpClient?.close()
            try? await sshClient?.close()
            self.sftpClient = nil
            self.sshClient = nil
        }
        #endif

        state = .disconnected
        files = []
        currentPath = "/"
        statusMessage = "Disconnected"
        errorMessage = nil
        errorAlertTitle = "Connection Failed"
        showErrorAlert = false
        activeConnection = nil
        selectedFileID = nil
        fileToDelete = nil
        showingDeleteConfirmation = false
        renamingFileID = nil
        renameText = ""
    }

    func navigate(to item: RemoteFileItem) {
        guard item.isDirectory else { return }
        let newPath: String
        if currentPath == "/" {
            newPath = "/\(item.name)"
        } else {
            newPath = "\(currentPath)/\(item.name)"
        }
        currentPath = newPath
        loadDirectory(path: newPath)
    }

    func navigateUp() {
        guard currentPath != "/" else { return }
        let components = currentPath.split(separator: "/").map(String.init)
        if components.count <= 1 {
            currentPath = "/"
        } else {
            currentPath = "/" + components.dropLast().joined(separator: "/")
        }
        loadDirectory(path: currentPath)
    }

    func refreshCurrentDirectory() {
        loadDirectory(path: currentPath)
    }

    func navigateToPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPath = trimmed.isEmpty ? "/" : (trimmed.hasPrefix("/") ? trimmed : "/" + trimmed)
        guard cleanPath != currentPath else {
            refreshCurrentDirectory()
            return
        }
        currentPath = cleanPath
        loadDirectory(path: cleanPath)
    }

    func createFolder(name: String) {
        guard !name.isEmpty else { return }
        let targetPath = (currentPath == "/" ? "" : currentPath) + "/" + name

        #if canImport(Citadel)
        if let sftp = sftpClient {
            Task {
                do {
                    try await sftp.createDirectory(atPath: targetPath)
                    await MainActor.run {
                        self.loadDirectory(path: self.currentPath)
                    }
                } catch {
                    await MainActor.run {
                        let friendly = self.friendlyErrorMessage(for: error, action: "create folder")
                        self.errorAlertTitle = friendly.title
                        self.statusMessage = friendly.message
                        self.errorMessage = friendly.message
                        self.showErrorAlert = true
                    }
                }
            }
            return
        }
        #endif

        if let conn = activeConnection {
            Task {
                let res = await runSSHCommand(connection: conn, command: "mkdir -p '\(targetPath)'")
                await MainActor.run {
                    if res.success {
                        self.loadDirectory(path: self.currentPath)
                    } else {
                        let err = "Error creating folder: \(res.error)"
                        self.statusMessage = err
                        self.errorMessage = err
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }

    func deleteFile(item: RemoteFileItem) {
        #if canImport(Citadel)
        if let sftp = sftpClient {
            Task {
                do {
                    if item.isDirectory {
                        try await sftp.rmdir(at: item.path)
                    } else {
                        try await sftp.remove(at: item.path)
                    }
                    await MainActor.run {
                        self.files.removeAll { $0.id == item.id }
                    }
                } catch {
                    await MainActor.run {
                        let friendly = self.friendlyErrorMessage(for: error, action: "delete item")
                        self.errorAlertTitle = friendly.title
                        self.statusMessage = friendly.message
                        self.errorMessage = friendly.message
                        self.showErrorAlert = true
                    }
                }
            }
            return
        }
        #endif

        if let conn = activeConnection {
            Task {
                let flag = item.isDirectory ? "-rf" : "-f"
                let res = await runSSHCommand(connection: conn, command: "rm \(flag) '\(item.path)'")
                await MainActor.run {
                    if res.success {
                        self.files.removeAll { $0.id == item.id }
                    } else {
                        let err = "Error deleting: \(res.error)"
                        self.statusMessage = err
                        self.errorMessage = err
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }

    func fetchDirectory(atPath path: String) async throws -> [RemoteFileItem] {
        #if canImport(Citadel)
        if let sftp = sftpClient, let conn = activeConnection {
            let remoteEntries = try await sftp.listDirectory(atPath: path)
            var mappedFiles: [RemoteFileItem] = []
            for entry in remoteEntries {
                for comp in entry.components {
                    guard comp.filename != "." && comp.filename != ".." else { continue }
                    let isDir = comp.longname.hasPrefix("d") || (comp.attributes.permissions.map { ($0 & 0o170000) == 0o040000 } ?? false)
                    let isSym = comp.longname.hasPrefix("l")
                    let type: RemoteFileType = isDir ? .directory : (isSym ? .symlink : .file)
                    let fullPath = (path == "/" ? "" : path) + "/" + comp.filename

                    mappedFiles.append(
                        RemoteFileItem(
                            id: UUID().uuidString,
                            name: comp.filename,
                            path: fullPath,
                            type: type,
                            size: Int64(comp.attributes.size ?? 0),
                            permissions: comp.longname.isEmpty ? (isDir ? "drwxr-xr-x" : "-rw-r--r--") : String(comp.longname.prefix(10)),
                            owner: conn.username,
                            group: conn.username,
                            modifiedDate: comp.attributes.accessModificationTime?.modificationTime ?? Date()
                        )
                    )
                }
            }
            return mappedFiles.sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        #endif

        if let conn = activeConnection {
            let result = await runSSHCommand(connection: conn, command: "ls -la '\(path)'")
            if result.success, let parsed = parseLsOutput(result.output, basePath: path) {
                return parsed.sorted {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory && !$1.isDirectory
                    }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
        }
        return []
    }

    func friendlyErrorMessage(for error: Error, action: String? = nil) -> (title: String, message: String) {
        return friendlyErrorMessage(for: "\(error) \(error.localizedDescription)", action: action)
    }

    func friendlyErrorMessage(for rawText: String, action: String? = nil) -> (title: String, message: String) {
        let lower = rawText.lowercased()

        // 1. Channel closed / NIOCore.ChannelError 5 / broken pipe
        if lower.contains("channelerror") || lower.contains("error 5") || lower.contains("ioonclosedchannel") || lower.contains("broken pipe") || lower.contains("closed channel") {
            let title = "Connection Lost"
            let msg: String
            if let act = action {
                msg = "Unable to \(act) because the connection to the server was closed unexpectedly. Please check your internet connection or click Reconnect to restore the session."
            } else {
                msg = "The connection to the server was closed unexpectedly. Please check your network connection or click Reconnect to continue."
            }
            return (title, msg)
        }

        // 2. Authentication failure
        if lower.contains("authenticationfailed") || lower.contains("authentication failed") || lower.contains("permission denied (publickey") || lower.contains("password incorrect") {
            let title = "Authentication Failed"
            let msg = "Could not log in to the server. Please verify your username, password, or SSH private key."
            return (title, msg)
        }

        // 3. Permission denied on file/folder
        if lower.contains("permission denied") || lower.contains("permissiondenied") || lower.contains("eacces") || lower.contains("eperm") {
            let title = "Permission Denied"
            let msg = action != nil 
                ? "Unable to \(action!) due to insufficient permissions on the remote server."
                : "You do not have permission to access or modify this item on the remote server."
            return (title, msg)
        }

        // 4. File / folder not found
        if lower.contains("nosuchfile") || lower.contains("no such file") || lower.contains("not found") {
            let title = "Item Not Found"
            let msg = action != nil 
                ? "Unable to \(action!) because the specified folder or file could not be found on the server."
                : "The requested folder or file does not exist on the remote server."
            return (title, msg)
        }

        // 5. Connection refused
        if lower.contains("connection refused") || lower.contains("econnrefused") {
            let title = "Connection Refused"
            let msg = "The server refused the connection. Please verify that the SSH/SFTP service is running and that the port number is correct."
            return (title, msg)
        }

        // 6. Timeout
        if lower.contains("timed out") || lower.contains("timeout") || lower.contains("etimedout") {
            let title = "Connection Timed Out"
            let msg = "The server took too long to respond. Please check your internet connection and verify that the server is online."
            return (title, msg)
        }

        // 7. Host / Network unreachable or DNS resolution failure
        if lower.contains("no route to host") || lower.contains("ehostunreach") || lower.contains("enetunreach") || lower.contains("nodename nor servname") {
            let title = "Server Unreachable"
            let msg = "Could not find or reach the server address. Please check the hostname or IP address and your network connection."
            return (title, msg)
        }

        // 8. Disk full
        if lower.contains("no space left") || lower.contains("disk quota") {
            let title = "Server Storage Full"
            let msg = "The server disk is full or storage quota has been reached. Please free up space on the server."
            return (title, msg)
        }

        // Fallback: clean up ugly Cocoa / NIO prefixes
        let title = "Connection Error"
        var clean = rawText
        if clean.contains("The operation couldn’t be completed. ") {
            clean = clean.replacingOccurrences(of: "The operation couldn’t be completed. ", with: "")
        }
        let msg = action != nil ? "Unable to \(action!): \(clean)" : clean
        return (title, msg)
    }

    private func loadDirectory(path: String) {
        isBusy = true
        Task {
            do {
                let items = try await fetchDirectory(atPath: path)
                await MainActor.run {
                    self.files = items
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    let friendly = self.friendlyErrorMessage(for: error, action: "read the remote directory")
                    self.errorAlertTitle = friendly.title
                    self.statusMessage = friendly.message
                    self.errorMessage = friendly.message
                    self.showErrorAlert = true
                    self.isBusy = false
                    if friendly.title == "Connection Lost" {
                        self.state = .error(friendly.message)
                    }
                }
            }
        }
    }

    // MARK: - Direct SSH Command Execution
    private struct SSHCommandResult {
        let success: Bool
        let output: String
        let error: String
    }

    private func runSSHCommand(connection: SSHConnection, command: String) async -> SSHCommandResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                let sshpassPaths = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass", "/usr/bin/sshpass"]
                let foundSshpass = sshpassPaths.first { FileManager.default.fileExists(atPath: $0) }

                var tempAskpassURL: URL? = nil

                // Common RSA & legacy host key / cipher options
                let rsaCompatibilityOptions = [
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    "-o", "ConnectTimeout=10",
                    "-o", "HostKeyAlgorithms=+ssh-rsa,rsa-sha2-512,rsa-sha2-256",
                    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa,rsa-sha2-512,rsa-sha2-256",
                    "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa,rsa-sha2-512,rsa-sha2-256",
                    "-o", "KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1,diffie-hellman-group-exchange-sha1,diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha256"
                ]

                if connection.authType == .password && !connection.password.isEmpty, let sshpass = foundSshpass {
                    process.executableURL = URL(fileURLWithPath: sshpass)
                    var args = [
                        "-p", connection.password,
                        "ssh",
                        "-p", "\(connection.port)"
                    ]
                    args.append(contentsOf: rsaCompatibilityOptions)
                    args.append("\(connection.username)@\(connection.host)")
                    args.append(command)
                    process.arguments = args
                } else if connection.authType == .password && !connection.password.isEmpty {
                    // Create temporary executable askpass helper script using EOF heredoc
                    let askpassURL = FileManager.default.temporaryDirectory.appendingPathComponent("compass_askpass_\(UUID().uuidString).sh")
                    tempAskpassURL = askpassURL

                    let script = """
                    #!/bin/sh
                    cat << 'COMPASS_ASKPASS_EOF'
                    \(connection.password)
                    COMPASS_ASKPASS_EOF
                    """
                    
                    try? script.write(to: askpassURL, atomically: true, encoding: .utf8)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassURL.path)

                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    var args = ["-p", "\(connection.port)"]
                    args.append(contentsOf: rsaCompatibilityOptions)
                    args.append("\(connection.username)@\(connection.host)")
                    args.append(command)
                    process.arguments = args

                    var env = ProcessInfo.processInfo.environment
                    env["SSH_ASKPASS"] = askpassURL.path
                    env["SSH_ASKPASS_REQUIRE"] = "force"
                    env["DISPLAY"] = ":0"
                    process.environment = env
                } else {
                    // Key File authentication (id_rsa or custom private key)
                    let rawKey = connection.keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "~/.ssh/id_rsa"
                        : connection.keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
                    let expandedKey = (rawKey as NSString).expandingTildeInPath

                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    var args = ["-p", "\(connection.port)"]
                    args.append(contentsOf: rsaCompatibilityOptions)
                    args.append(contentsOf: ["-o", "BatchMode=yes"])

                    if FileManager.default.fileExists(atPath: expandedKey) {
                        args.append(contentsOf: ["-i", expandedKey])
                    }

                    args.append("\(connection.username)@\(connection.host)")
                    args.append(command)
                    process.arguments = args
                }

                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if let url = tempAskpassURL {
                        try? FileManager.default.removeItem(at: url)
                    }

                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = String(data: errData, encoding: .utf8) ?? ""

                    continuation.resume(returning: SSHCommandResult(
                        success: process.terminationStatus == 0,
                        output: outStr,
                        error: errStr
                    ))
                } catch {
                    if let url = tempAskpassURL {
                        try? FileManager.default.removeItem(at: url)
                    }

                    continuation.resume(returning: SSHCommandResult(
                        success: false,
                        output: "",
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }

    private func parseLsOutput(_ output: String, basePath: String) -> [RemoteFileItem]? {
        guard !output.isEmpty else { return nil }

        var results: [RemoteFileItem] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("total") { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            let perms = String(parts[0])
            let owner = String(parts[2])
            let group = String(parts[3])
            let size = Int64(parts[4]) ?? 0

            let nameParts = parts[8...]
            let rawName = nameParts.joined(separator: " ")

            if rawName == "." || rawName == ".." { continue }

            let cleanName: String
            let isSymlink = perms.hasPrefix("l")
            if isSymlink, let arrowIndex = rawName.range(of: " -> ") {
                cleanName = String(rawName[..<arrowIndex.lowerBound])
            } else {
                cleanName = rawName
            }

            let type: RemoteFileType
            if perms.hasPrefix("d") {
                type = .directory
            } else if isSymlink {
                type = .symlink
            } else {
                type = .file
            }

            let fullPath = (basePath == "/" ? "" : basePath) + "/" + cleanName

            let item = RemoteFileItem(
                id: UUID().uuidString,
                name: cleanName,
                path: fullPath,
                type: type,
                size: size,
                permissions: perms,
                owner: owner,
                group: group,
                modifiedDate: Date()
            )
            results.append(item)
        }

        return results
    }
}
