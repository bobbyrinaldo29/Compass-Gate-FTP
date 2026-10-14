//
//  SettingsView.swift
//  Compass Gate FTP
//

import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general
        case terminal
        case columns
    }

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tabs.general)

            TerminalSettingsView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
                .tag(Tabs.terminal)

            ColumnsSettingsView()
                .tabItem {
                    Label("Columns", systemImage: "tablecells")
                }
                .tag(Tabs.columns)
        }
        .frame(width: 480, height: 240)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("settings_confirmDelete") private var confirmDelete = true
    @AppStorage("settings_showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("settings_autoRefresh") private var autoRefresh = true

    var body: some View {
        Form {
            Section {
                Toggle("Confirm before deleting files and folders", isOn: $confirmDelete)
                Toggle("Show hidden files by default (dotfiles)", isOn: $showHiddenFiles)
                Toggle("Automatically refresh remote folder on reconnect", isOn: $autoRefresh)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

struct TerminalSettingsView: View {
    @AppStorage("settings_terminalApp") private var terminalApp = "auto"

    var body: some View {
        Form {
            Section(header: Text("Terminal Application")) {
                Picker("Open In:", selection: $terminalApp) {
                    Text("Auto (iTerm2 if running, else Terminal)").tag("auto")
                    Text("macOS Terminal.app").tag("terminal")
                    Text("iTerm2").tag("iterm")
                }
                .pickerStyle(.radioGroup)

                Text("When connecting to SSH, Compass Gate FTP will launch the selected terminal app directly into the active remote directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

struct ColumnsSettingsView: View {
    @AppStorage("remoteCol_size") private var showSize = true
    @AppStorage("remoteCol_kind") private var showKind = true
    @AppStorage("remoteCol_dateModified") private var showDateModified = true
    @AppStorage("remoteCol_permissions") private var showPermissions = true
    @AppStorage("remoteCol_owner") private var showOwner = true

    var body: some View {
        Form {
            Section(header: Text("Remote Browser Columns")) {
                Toggle("File Size", isOn: $showSize)
                Toggle("Kind / Type", isOn: $showKind)
                Toggle("Date Modified", isOn: $showDateModified)
                Toggle("Permissions", isOn: $showPermissions)
                Toggle("Owner / Group", isOn: $showOwner)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}
