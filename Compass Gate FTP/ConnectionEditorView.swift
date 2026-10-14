//
//  ConnectionEditorView.swift
//  Compass Gate FTP
//

import SwiftUI
import SwiftData

struct ConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portText: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var keyFilePath: String = ""
    @State private var authType: AuthenticationType = .password
    @State private var groupName: String = "Production Servers"
    @State private var colorTag: ServerColorTag = .blue
    @State private var remotePath: String = "/"

    var connectionToEdit: SSHConnection?

    init(connectionToEdit: SSHConnection? = nil, defaultGroupName: String = "Production Servers") {
        self.connectionToEdit = connectionToEdit
        _name = State(initialValue: connectionToEdit?.name ?? "")
        _host = State(initialValue: connectionToEdit?.host ?? "")
        _portText = State(initialValue: String(connectionToEdit?.port ?? 22))
        _username = State(initialValue: connectionToEdit?.username ?? "")
        _password = State(initialValue: connectionToEdit?.password ?? "")
        _keyFilePath = State(initialValue: connectionToEdit?.keyFilePath ?? "")
        _authType = State(initialValue: connectionToEdit?.authType ?? .password)
        _groupName = State(initialValue: connectionToEdit?.groupRaw ?? defaultGroupName)
        _colorTag = State(initialValue: connectionToEdit?.colorTag ?? .blue)
        _remotePath = State(initialValue: connectionToEdit?.remotePath ?? "/")
    }

    init(defaultGroup: ConnectionGroup) {
        self.init(connectionToEdit: nil, defaultGroupName: defaultGroup.rawValue)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int(portText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group & Identification") {
                    Picker("Group", selection: $groupName) {
                        ForEach(BookmarkGroupManager.shared.allGroups) { grp in
                            Label(grp.name, systemImage: grp.iconName).tag(grp.name)
                        }
                    }

                    TextField("Connection Name", text: $name)

                    HStack {
                        Text("Color Tag")
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(ServerColorTag.allCases) { tag in
                                Button {
                                    colorTag = tag
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(tag.color)
                                            .frame(width: 20, height: 20)

                                        if colorTag == tag {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(tag.rawValue)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Server Details") {
                    TextField("Server Host / IP", text: $host)
                        .font(.body.monospaced())
                    TextField("Port", text: $portText)
                        .font(.body.monospaced())
                }

                Section("Authentication") {
                    TextField("Username", text: $username)
                        .font(.body.monospaced())

                    Picker("Auth Method", selection: $authType) {
                        ForEach(AuthenticationType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if authType == .password {
                        SecureField("Password", text: $password)
                    } else if authType == .keyFile {
                        TextField("Private Key Path (~/.ssh/id_rsa)", text: $keyFilePath)
                            .font(.body.monospaced())
                    }
                }

                Section("Initial Directory") {
                    TextField("Remote Path", text: $remotePath)
                        .font(.body.monospaced())
                }
            }
            .formStyle(.grouped)
            .navigationTitle(connectionToEdit == nil ? "New SSH Connection" : "Edit SSH Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConnection()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .frame(minWidth: 440, minHeight: 440)
        }
    }

    private func saveConnection() {
        let portNumber = Int(portText) ?? 22
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : remotePath

        if let connection = connectionToEdit {
            connection.name = trimmedName
            connection.host = trimmedHost
            connection.port = portNumber
            connection.username = trimmedUsername
            connection.password = password
            connection.keyFilePath = keyFilePath
            connection.authType = authType
            connection.groupRaw = groupName
            connection.colorTag = colorTag
            connection.remotePath = trimmedPath
        } else {
            let newConnection = SSHConnection(
                name: trimmedName,
                host: trimmedHost,
                port: portNumber,
                username: trimmedUsername,
                password: password,
                keyFilePath: keyFilePath,
                authType: authType,
                groupRaw: groupName,
                colorTag: colorTag,
                remotePath: trimmedPath
            )
            modelContext.insert(newConnection)
        }
    }
}
