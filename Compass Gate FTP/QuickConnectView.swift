//
//  QuickConnectView.swift
//  Compass Gate FTP
//

import SwiftUI
import SwiftData

struct QuickConnectView: View {
    @Bindable var sftpService: SFTPService
    var savedConnections: [SSHConnection] = []
    var onConnect: ((SSHConnection) -> Void)? = nil

    @State private var selectedSavedConnectionID: PersistentIdentifier?
    @State private var serverAddress: String = ""
    @State private var username: String = ""
    @State private var passwordOrKey: String = ""
    @State private var keyFilePath: String = "~/.ssh/id_rsa"
    @State private var authType: AuthenticationType = .password
    @State private var port: String = "22"
    @State private var protocolType: String = "SFTP"

    private var currentConnectionObject: SSHConnection {
        if let selectedSavedConnectionID,
           let match = savedConnections.first(where: { $0.persistentModelID == selectedSavedConnectionID }) {
            return match
        }
        return SSHConnection(
            name: serverAddress.isEmpty ? "Quick Connect" : serverAddress,
            host: serverAddress,
            port: Int(port) ?? 22,
            username: username,
            password: authType == .password ? passwordOrKey : "",
            keyFilePath: authType == .keyFile ? (keyFilePath.isEmpty ? "~/.ssh/id_rsa" : keyFilePath) : "",
            authType: authType,
            group: .production,
            remotePath: "/"
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("Quick Connect")
                    .font(.title2)
                    .bold()
                Text("Connect directly to an SFTP/SSH server or pick a saved bookmark.")
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
                .frame(maxWidth: 480)
            }

            Form {
                if !savedConnections.isEmpty {
                    Picker("Saved Bookmark", selection: $selectedSavedConnectionID) {
                        Text("Custom / Direct").tag(nil as PersistentIdentifier?)
                        Divider()
                        ForEach(savedConnections) { conn in
                            Text("\(conn.name) (\(conn.username)@\(conn.host))")
                                .tag(conn.persistentModelID as PersistentIdentifier?)
                        }
                    }
                }

                Picker("Protocol", selection: $protocolType) {
                    Text("SFTP - SSH File Transfer Protocol").tag("SFTP")
                }

                TextField("Server Address (Host / IP)", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)

                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)

                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)

                Picker("Authentication", selection: $authType) {
                    Text("Password").tag(AuthenticationType.password)
                    Text("Key File").tag(AuthenticationType.keyFile)
                }
                .pickerStyle(.segmented)

                if authType == .password {
                    SecureField("Password", text: $passwordOrKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    HStack {
                        TextField("Private Key Path", text: $keyFilePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            if panel.runModal() == .OK, let url = panel.url {
                                keyFilePath = url.path
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 480, maxHeight: 320)
            .onChange(of: selectedSavedConnectionID) { _, newID in
                if let newID, let conn = savedConnections.first(where: { $0.persistentModelID == newID }) {
                    serverAddress = conn.host
                    port = "\(conn.port)"
                    username = conn.username
                    authType = conn.authType
                    passwordOrKey = conn.password
                    keyFilePath = conn.keyFilePath.isEmpty ? "~/.ssh/id_rsa" : conn.keyFilePath
                }
            }

            Button {
                let conn = currentConnectionObject
                if let onConnect = onConnect {
                    onConnect(conn)
                } else {
                    Task {
                        await sftpService.connect(to: conn)
                    }
                }
            } label: {
                if sftpService.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                } else {
                    Label("Connect Now", systemImage: "arrow.right.circle.fill")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverAddress.isEmpty || username.isEmpty || sftpService.isBusy)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
