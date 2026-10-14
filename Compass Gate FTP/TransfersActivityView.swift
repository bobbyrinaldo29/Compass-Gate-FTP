//
//  TransfersActivityView.swift
//  Compass Gate FTP
//

import SwiftUI
import AppKit

enum TransferFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case uploads = "Uploads"
    case downloads = "Downloads"
    case completed = "Completed"
    case failed = "Failed"

    var id: String { rawValue }
}

struct TransfersActivityView: View {
    @Bindable var sftpService: SFTPService

    @State private var filter: TransferFilter = .all
    @State private var searchText: String = ""
    @State private var selectedTransferID: UUID? = nil

    private var filteredTransfers: [TransferItem] {
        var list = sftpService.transfers

        switch filter {
        case .all:
            break
        case .uploads:
            list = list.filter { $0.direction == .upload }
        case .downloads:
            list = list.filter { $0.direction == .download }
        case .completed:
            list = list.filter { $0.status == .completed }
        case .failed:
            list = list.filter {
                if case .failed = $0.status { return true }
                return false
            }
        }

        if !searchText.isEmpty {
            list = list.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.serverName.localizedCaseInsensitiveContains(searchText) ||
                $0.destinationPath.localizedCaseInsensitiveContains(searchText)
            }
        }

        return list
    }

    private var inProgressCount: Int {
        sftpService.transfers.filter { $0.status == .inProgress }.count
    }

    private var completedCount: Int {
        sftpService.transfers.filter { $0.status == .completed }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity & Transfers")
                        .font(.headline.weight(.semibold))

                    HStack(spacing: 6) {
                        Text("\(sftpService.transfers.count) Total")
                        Text("•")
                        Text("\(completedCount) Completed")
                            .foregroundStyle(.green)
                        if inProgressCount > 0 {
                            Text("•")
                            Text("\(inProgressCount) Active")
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                // Filter Picker
                Picker("Filter", selection: $filter) {
                    ForEach(TransferFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                // Clear Button
                Button {
                    sftpService.clearTransfers(completedOnly: true)
                } label: {
                    Label("Clear Finished", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(sftpService.transfers.allSatisfy { $0.status == .inProgress } || sftpService.transfers.isEmpty)
                .help("Clear completed and failed transfers")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main Content
            if filteredTransfers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(sftpService.transfers.isEmpty ? "No Transfer History" : "No Matching Transfers")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(sftpService.transfers.isEmpty ? "Uploads and downloads will automatically appear here." : "Try adjusting your filter or search keywords.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                List(filteredTransfers, selection: $selectedTransferID) { item in
                    transferRow(for: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Copy File Name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.fileName, forType: .string)
                            }
                            Button("Copy Destination Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.destinationPath, forType: .string)
                            }
                            if item.direction == .download {
                                Button("Show in Finder") {
                                    let url = URL(fileURLWithPath: item.destinationPath)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            } else {
                                Button("Show Source in Finder") {
                                    let url = URL(fileURLWithPath: item.sourcePath)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            Divider()
                            Button("Remove from History", role: .destructive) {
                                sftpService.removeTransfer(id: item.id)
                            }
                        }
                }
                .listStyle(.inset)
                .background(Color(nsColor: .textBackgroundColor))
            }

            Divider()

            // Status Bar Footer
            HStack {
                Text("\(filteredTransfers.count) items displayed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !sftpService.transfers.isEmpty {
                    Button("Clear All History") {
                        sftpService.clearTransfers(completedOnly: false)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func transferRow(for item: TransferItem) -> some View {
        HStack(spacing: 12) {
            // Direction Badge Icon
            Image(systemName: item.direction.iconName)
                .font(.title2)
                .foregroundStyle(item.direction.color)
                .frame(width: 28, height: 28)

            // File Icon
            Image(systemName: item.fileExtensionIcon)
                .font(.title3)
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 24)

            // File & Path Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.fileName)
                        .font(.body.weight(.medium))

                    Text(item.formattedSize)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(item.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    Text(item.serverName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(item.destinationPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Status Section
            statusView(for: item)
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusView(for item: TransferItem) -> some View {
        switch item.status {
        case .inProgress:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Transferring...")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        case .completed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Completed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    Text(item.formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let errorMsg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Failed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .help(errorMsg)
            }
        case .cancelled:
            HStack(spacing: 6) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
                Text("Cancelled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
