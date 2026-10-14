//
//  PasswordPromptView.swift
//  Compass Gate FTP
//

import SwiftUI

struct PasswordPromptView: View {
    let connection: SSHConnection
    var onConnect: (String, Bool) -> Void
    var onCancel: () -> Void

    @State private var password: String = ""
    @State private var rememberPassword: Bool = true
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(connection.tagColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(connection.tagColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Password Required")
                        .font(.headline)
                    Text("Enter password for **\(connection.username)** on **\(connection.host)**:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isPasswordFocused)
                    .onSubmit {
                        if !password.isEmpty {
                            onConnect(password, rememberPassword)
                        }
                    }

                Toggle("Remember password in bookmark", isOn: $rememberPassword)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    onConnect(password, rememberPassword)
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            isPasswordFocused = true
        }
    }
}
