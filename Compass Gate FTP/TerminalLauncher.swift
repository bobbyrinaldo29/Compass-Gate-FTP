//
//  TerminalLauncher.swift
//  Compass Gate FTP
//

import AppKit
import Foundation

@MainActor
enum TerminalLauncher {
    /// Generates the self-deleting expect script that handles:
    /// - automated password entry (decoded securely from Base64)
    /// - SIGWINCH window resize forwarding
    /// - automatic cd to remote directory after login
    static func buildExpectScript(connection: SSHConnection, remotePath: String) -> String {
        let path = remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : remotePath

        var sshArgs: [String] = [
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        if connection.port != 22 && connection.port > 0 {
            sshArgs.append("-p \(connection.port)")
        }

        if connection.authType == .keyFile && !connection.keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let keyPath = (connection.keyFilePath as NSString).expandingTildeInPath
            let escapedKey = keyPath.replacingOccurrences(of: "'", with: "'\\''")
            sshArgs.append("-i '\(escapedKey)'")
        }

        let user = connection.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = user.isEmpty ? host : "\(user)@\(host)"
        sshArgs.append(target)

        let spawnCmd = "ssh " + sshArgs.joined(separator: " ")

        let pathData = Data(path.utf8)
        let b64Path = pathData.base64EncodedString()

        let passData = Data(connection.password.utf8)
        let b64Pass = passData.base64EncodedString()
        let hasPassword = connection.authType == .password && !connection.password.isEmpty

        let passwordBlock = hasPassword ? """
        set pass [exec echo "\(b64Pass)" | base64 --decode]
        """ : """
        set pass ""
        """

        let passwordPromptHandler = hasPassword ? """
            -re {(?i)(password|passphrase).*:\\s*$} {
                send -- "$pass\\r"
            }
        """ : ""

        return """
        #!/usr/bin/expect -f
        catch { file delete [info script] }
        set timeout 20

        trap {
            set rows [stty rows]
            set cols [stty columns]
            stty rows $rows columns $cols < $spawn_out(slave,name)
        } SIGWINCH

        set remotePath [exec echo "\(b64Path)" | base64 --decode]
        \(passwordBlock)

        spawn \(spawnCmd)

        expect {
            -re {(?i)are you sure you want to continue} {
                send "yes\\r"
                exp_continue
            }
        \(passwordPromptHandler)
            timeout {}
        }

        expect {
            -re {[#$%>~]\\s*$} {
                send "cd \\"$remotePath\\"\\r"
            }
            timeout {
                send "cd \\"$remotePath\\"\\r"
            }
        }

        interact
        """
    }

    /// Launches the terminal application (iTerm2 if running/available, or macOS Terminal.app)
    /// connects to the SSH server, automatically enters the password if needed,
    /// and navigates directly into the target remote folder without triggering macOS security prompts.
    static func openRemoteTerminal(connection: SSHConnection, remotePath: String) {
        // Also keep clipboard ready as fallback
        if connection.authType == .password && !connection.password.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(connection.password, forType: .string)
        }

        let scriptContent = buildExpectScript(connection: connection, remotePath: remotePath)
        let tempScript = FileManager.default.temporaryDirectory
            .appendingPathComponent("compass_gate_ssh_\(UUID().uuidString.prefix(8)).exp")

        do {
            try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempScript.path)

            launchTerminal(withScriptPath: tempScript.path)
        } catch {
            print("Failed to write expect script: \(error)")
        }
    }

    /// Executes the script inside a new tab or window of iTerm2 or macOS Terminal
    /// using /usr/bin/osascript. Since this sends `exec <path>` to the terminal session,
    /// it does NOT trigger any LaunchServices Gatekeeper security warnings.
    static func launchTerminal(withScriptPath scriptPath: String) {
        let pref = UserDefaults.standard.string(forKey: "settings_terminalApp") ?? "auto"
        let isITermRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty
        let useITerm: Bool
        switch pref {
        case "iterm":
            useITerm = true
        case "terminal":
            useITerm = false
        default:
            useITerm = isITermRunning
        }
        let escapedPath = scriptPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScriptText: String
        if useITerm {
            appleScriptText = """
            tell application "iTerm"
                activate
                try
                    tell current window
                        create tab with default profile
                        tell current session
                            write text "exec \\"\(escapedPath)\\""
                        end tell
                    end tell
                on error
                    create window with default profile
                    tell current session of current window
                        write text "exec \\"\(escapedPath)\\""
                    end tell
                end try
            end tell
            """
        } else {
            appleScriptText = """
            tell application "Terminal"
                activate
                do script "exec \\"\(escapedPath)\\""
            end tell
            """
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        do {
            try process.run()
            stdinPipe.fileHandleForWriting.write(Data(appleScriptText.utf8))
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            print("Failed to run osascript process: \(error)")
        }
    }
}
