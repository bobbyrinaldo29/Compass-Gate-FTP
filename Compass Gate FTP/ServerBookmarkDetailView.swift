//
//  ServerBookmarkDetailView.swift
//  Compass Gate FTP
//

import SwiftUI
import SwiftData

struct ServerBookmarkDetailView: View {
    @Bindable var connection: SSHConnection
    @Bindable var sftpService: SFTPService
    var onEdit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: connection.group.iconName)
                .font(.largeTitle)
                .foregroundStyle(connection.tagColor)

            VStack(spacing: 4) {
                Text(connection.name)
                    .font(.title2)
                    .bold()
                Text("\(connection.group.rawValue) • \(connection.authType.rawValue) Authentication")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let err = sftpService.errorMessage, case .error = sftpService.state {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
                .frame(maxWidth: 500)
            }

            Form {
                Section {
                    LabeledContent("Group") {
                        Text(connection.group.rawValue)
                    }

                    LabeledContent("Color Tag") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(connection.tagColor)
                                .frame(width: 10, height: 10)
                            Text(connection.colorTag.rawValue)
                        }
                    }

                    LabeledContent("Server Host / IP") {
                        Text(connection.host)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }

                    LabeledContent("Port") {
                        Text("\(connection.port)")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }

                    LabeledContent("Username") {
                        Text(connection.username)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }

                    LabeledContent("Auth Method") {
                        Text(connection.authType.rawValue)
                    }

                    if connection.authType == .keyFile && !connection.keyFilePath.isEmpty {
                        LabeledContent("Key File") {
                            Text(connection.keyFilePath)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    LabeledContent("Initial Directory") {
                        Text(connection.remotePath)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 500, maxHeight: 290)

            HStack(spacing: 12) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Connection", systemImage: "pencil")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }

                Button {
                    Task {
                        await sftpService.connect(to: connection)
                    }
                } label: {
                    if sftpService.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    } else {
                        Label("Connect SFTP", systemImage: "arrow.right.circle.fill")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sftpService.isBusy)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
