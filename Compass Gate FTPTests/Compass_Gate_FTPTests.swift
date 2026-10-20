//
//  Compass_Gate_FTPTests.swift
//  Compass Gate FTPTests
//
//  Created by Bobby Rinaldo Sukma Dewa on 10/10/26.
//

import Testing
import Foundation
import SwiftUI
@testable import Compass_Gate_FTP

@MainActor
struct Compass_Gate_FTPTests {

    @Test func testTerminalLauncherExpectScriptWithPassword() {
        let conn = SSHConnection(
            name: "Demo Server",
            host: "ssh.example.com",
            port: 22,
            username: "testuser",
            password: "SampleSecretPass123!",
            authType: .password
        )

        let script = TerminalLauncher.buildExpectScript(connection: conn, remotePath: "/home")
        #expect(script.contains("#!/usr/bin/expect -f"))
        #expect(script.contains("catch { file delete [info script] }"))
        #expect(script.contains("spawn ssh -o StrictHostKeyChecking=accept-new"))
        #expect(script.contains("-o HostKeyAlgorithms=+ssh-rsa"))
        #expect(script.contains("-o PubkeyAcceptedAlgorithms=+ssh-rsa"))
        #expect(script.contains("testuser@ssh.example.com"))
        #expect(script.contains("eof"))
        #expect(script.contains("password|passphrase"))
        #expect(script.contains("cd \\\"$remotePath\\\""))
        #expect(script.contains("interact"))

        // Check base64 encoding of password & path
        let b64Pass = Data("SampleSecretPass123!".utf8).base64EncodedString()
        let b64Path = Data("/home".utf8).base64EncodedString()
        #expect(script.contains(b64Pass))
        #expect(script.contains(b64Path))
    }

    @Test func testTerminalLauncherExpectScriptWithKey() {
        let conn = SSHConnection(
            name: "Key Server",
            host: "deploy.example.com",
            port: 2222,
            username: "deploy",
            keyFilePath: "~/.ssh/id_ed25519",
            authType: .keyFile
        )

        let script = TerminalLauncher.buildExpectScript(connection: conn, remotePath: "/var/www/my site")
        #expect(script.contains("#!/usr/bin/expect -f"))
        #expect(script.contains("-p 2222"))
        #expect(script.contains("-i '"))
        #expect(script.contains("deploy@deploy.example.com"))
        #expect(!script.contains("SampleSecretPass123!"))
        #expect(script.contains("cd \\\"$remotePath\\\""))
    }

    @Test func testRemoteFileItemIsHidden() {
        let hidden1 = RemoteFileItem(
            id: "1", name: ".bashrc", path: "/home/.bashrc", type: .file,
            size: 100, permissions: "-rw-r--r--", owner: "root", group: "root", modifiedDate: Date()
        )
        let hidden2 = RemoteFileItem(
            id: "2", name: ".git", path: "/var/www/.git", type: .directory,
            size: 0, permissions: "drwxr-xr-x", owner: "root", group: "root", modifiedDate: Date()
        )
        let normal = RemoteFileItem(
            id: "3", name: "index.html", path: "/var/www/index.html", type: .file,
            size: 500, permissions: "-rw-r--r--", owner: "root", group: "root", modifiedDate: Date()
        )

        #expect(hidden1.isHidden == true)
        #expect(hidden2.isHidden == true)
        #expect(normal.isHidden == false)

        let allFiles = [hidden1, hidden2, normal]
        let visibleFiles = allFiles.filter { !$0.isHidden }
        #expect(visibleFiles.count == 1)
        #expect(visibleFiles.first?.name == "index.html")
    }

    @Test func testImportSSHConfig() {
        let configSample = """
        # Sample Documentation SSH Configuration
        Host webapp
            HostName web.example.org
            Port 22
            User webmaster
            RemoteCommand cd /srv/www;bash

        Host demoserver
            HostName demo.example.org
            Port 11184
            User demo_user
            RemoteCommand cd /srv/demo;bash

        Host keyhost
            HostName secure.example.com
            User admin
            Port 2222
            IdentityFile ~/.ssh/id_ed25519

        Host *
            ServerAliveInterval 60
        """

        let results = ConnectionImporter.parseSSHConfig(content: configSample)
        #expect(results.count == 3)

        #expect(results[0].name == "webapp")
        #expect(results[0].host == "web.example.org")
        #expect(results[0].port == 22)
        #expect(results[0].username == "webmaster")
        #expect(results[0].remotePath == "/srv/www")
        #expect(results[0].authType == .password)

        #expect(results[1].name == "demoserver")
        #expect(results[1].host == "demo.example.org")
        #expect(results[1].port == 11184)
        #expect(results[1].username == "demo_user")
        #expect(results[1].remotePath == "/srv/demo")

        #expect(results[2].name == "keyhost")
        #expect(results[2].host == "secure.example.com")
        #expect(results[2].port == 2222)
        #expect(results[2].keyFilePath == "~/.ssh/id_ed25519")
        #expect(results[2].authType == .keyFile)
    }

    @Test func testImportFileZillaXML() {
        let fzSample = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FileZilla3>
            <Servers>
                <Server>
                    <Host>ftp.example.com</Host>
                    <Port>21</Port>
                    <Protocol>0</Protocol>
                    <User>ftpuser</User>
                    <Pass>secret123</Pass>
                    <Name>My FTP Server</Name>
                    <RemoteDir>/public_html</RemoteDir>
                </Server>
                <Server>
                    <Host>sftp.example.org</Host>
                    <Port>22</Port>
                    <Protocol>1</Protocol>
                    <User>sftp_admin</User>
                    <Pass encoding="base64">YWRtaW4xMjM=</Pass>
                    <Keyfile>~/.ssh/id_rsa</Keyfile>
                    <Name>Production SFTP</Name>
                </Server>
            </Servers>
        </FileZilla3>
        """

        let results = ConnectionImporter.parseFileZilla(content: fzSample)
        #expect(results.count == 2)

        #expect(results[0].name == "My FTP Server")
        #expect(results[0].host == "ftp.example.com")
        #expect(results[0].port == 21)
        #expect(results[0].username == "ftpuser")
        #expect(results[0].password == "secret123")
        #expect(results[0].remotePath == "/public_html")

        #expect(results[1].name == "Production SFTP")
        #expect(results[1].host == "sftp.example.org")
        #expect(results[1].port == 22)
        #expect(results[1].username == "sftp_admin")
        #expect(results[1].password == "admin123")
        #expect(results[1].keyFilePath == "~/.ssh/id_rsa")
        #expect(results[1].authType == .keyFile)
    }

    @Test func testImportTransmitAndForkLiftJSON() {
        let transmitJSON = """
        [
            {
                "nickname": "Transmit Web",
                "address": "web.transmit.com",
                "port": 22,
                "userName": "webuser",
                "initialPath": "/var/www/html"
            },
            {
                "name": "ForkLift App",
                "host": "app.forklift.com",
                "port": 8022,
                "username": "forkuser",
                "path": "/srv/app",
                "keyPath": "~/.ssh/id_ed25519"
            }
        ]
        """.data(using: .utf8)!

        let json = try! JSONSerialization.jsonObject(with: transmitJSON)
        let dicts = ConnectionImporter.extractDictionaries(from: json)
        let results = dicts.compactMap { ConnectionImporter.parseServerDictionary($0) }

        #expect(results.count == 2)
        #expect(results[0].name == "Transmit Web")
        #expect(results[0].host == "web.transmit.com")
        #expect(results[0].port == 22)
        #expect(results[0].username == "webuser")
        #expect(results[0].remotePath == "/var/www/html")

        #expect(results[1].name == "ForkLift App")
        #expect(results[1].host == "app.forklift.com")
        #expect(results[1].port == 8022)
        #expect(results[1].username == "forkuser")
        #expect(results[1].remotePath == "/srv/app")
        #expect(results[1].keyFilePath == "~/.ssh/id_ed25519")
        #expect(results[1].authType == .keyFile)
    }

    @Test func testConnectionGroupChange() {
        let conn = SSHConnection(
            name: "Server",
            host: "example.com",
            port: 22,
            username: "root",
            group: .production
        )
        #expect(conn.group == .production)
        conn.group = .staging
        #expect(conn.group == .staging)
        #expect(conn.groupRaw == ConnectionGroup.staging.rawValue)
        conn.group = .general
        #expect(conn.group == .general)
        #expect(conn.groupRaw == ConnectionGroup.general.rawValue)
    }

    @Test func testCustomGroupCreationAndAssignment() {
        let manager = BookmarkGroupManager.shared
        let customName = "Database Nodes Test"

        // Clean up if already exists
        manager.deleteGroup(named: customName)

        let created = manager.addGroup(name: customName, iconName: "cpu", color: .purple)
        #expect(created != nil)
        #expect(manager.allGroups.contains(where: { $0.name == customName }))

        let conn = SSHConnection(
            name: "DB-Master",
            host: "db.example.org",
            port: 22,
            username: "dbadmin",
            groupRaw: customName
        )

        #expect(conn.groupRaw == customName)
        #expect(conn.groupIconName == "cpu")

        // Cannot add duplicate
        let dup = manager.addGroup(name: customName, iconName: "server.rack", color: .blue)
        #expect(dup == nil)

        // Clean up custom group
        manager.deleteGroup(named: customName)
        #expect(!manager.allGroups.contains(where: { $0.name == customName }))
    }

    @Test func testMoveConnectionToCustomGroup() {
        let manager = BookmarkGroupManager.shared
        let customGroup = "My Server Test"
        manager.deleteGroup(named: customGroup)

        let created = manager.addGroup(name: customGroup, iconName: "folder.fill")
        #expect(created != nil)

        let conn = SSHConnection(
            name: "Server To Move",
            host: "server.example.com",
            port: 22,
            username: "root",
            groupRaw: "Production Servers"
        )
        #expect(conn.groupRaw == "Production Servers")

        // Simulate move to custom group
        conn.groupRaw = customGroup
        #expect(conn.groupRaw == "My Server Test")
        #expect(conn.groupIconName == "folder.fill")

        // Simulate move back to system group
        conn.groupRaw = "Staging & Testing"
        #expect(conn.groupRaw == "Staging & Testing")
        #expect(conn.group.rawValue == "Staging & Testing")

        manager.deleteGroup(named: customGroup)
    }

    @Test func testParseServerStats() {
        let service = SFTPService()

        // 1. Full Linux stats output
        let linuxOutput = "STATS|14%|42% (1.7/4.0 GB)|38G"
        let parsedLinux = service.parseServerStats(linuxOutput)
        #expect(parsedLinux != nil)
        #expect(parsedLinux?.cpuUsage == "14%")
        #expect(parsedLinux?.ramUsage == "42% (1.7/4.0 GB)")
        #expect(parsedLinux?.diskFree == "38G")

        // 2. macOS / BSD Load stats output
        let macOutput = "STATS|Load 1.45|16.0 GB|120Gi"
        let parsedMac = service.parseServerStats(macOutput)
        #expect(parsedMac != nil)
        #expect(parsedMac?.cpuUsage == "Load 1.45")
        #expect(parsedMac?.ramUsage == "16.0 GB")
        #expect(parsedMac?.diskFree == "120Gi")

        // 3. Fallback dashed output
        let dashOutput = "STATS|--|--|--"
        let parsedDash = service.parseServerStats(dashOutput)
        #expect(parsedDash != nil)
        #expect(parsedDash?.cpuUsage == nil)
        #expect(parsedDash?.ramUsage == nil)
        #expect(parsedDash?.diskFree == nil)

        // 4. New section-delimited Linux output with stat calculation
        let delimitedLinux = """
===CPU===
150 1000
165 1050
0.25 0.15 0.08 1/140 1234
===MEM===
              total        used        free      shared  buff/cache   available
Mem:           3919        1423         812         120        1683        2142
===DISK===
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        40G   12G   26G  32% /
"""
        let parsedDelimited = service.parseServerStats(delimitedLinux)
        #expect(parsedDelimited != nil)
        #expect(parsedDelimited?.cpuUsage == "30%")
        #expect(parsedDelimited?.ramUsage?.contains("GB") == true)
        #expect(parsedDelimited?.diskFree == "26G")

        // 5. Invalid output
        let invalid = "Command not found"
        #expect(service.parseServerStats(invalid) == nil)
    }

    @Test func testFriendlyErrorMessage() {
        let service = SFTPService()

        // 1. NIOCore.ChannelError 5
        let nioErr = "The operation couldn’t be completed. (NIOCore.ChannelError error 5.)"
        let resNio = service.friendlyErrorMessage(for: nioErr, action: "read the remote directory")
        #expect(resNio.title == "Connection Lost")
        #expect(!resNio.message.contains("NIOCore"))
        #expect(resNio.message.contains("connection to the server was closed unexpectedly"))
        #expect(resNio.message.contains("Reconnect"))

        // 2. Authentication failure
        let authErr = "Permission denied (publickey,password)"
        let resAuth = service.friendlyErrorMessage(for: authErr)
        #expect(resAuth.title == "Authentication Failed")
        #expect(resAuth.message.contains("username, password, or SSH private key"))

        // 3. Permission denied
        let permErr = "permissionDenied"
        let resPerm = service.friendlyErrorMessage(for: permErr, action: "delete item")
        #expect(resPerm.title == "Permission Denied")
        #expect(resPerm.message.contains("insufficient permissions"))

        // 4. Connection refused
        let connRefused = "Connection refused (ECONNREFUSED)"
        let resRefused = service.friendlyErrorMessage(for: connRefused)
        #expect(resRefused.title == "Connection Refused")
        #expect(resRefused.message.contains("port number"))
    }

    @Test func testDualPaneSplitViewClampAndPersistence() {
        var width: Double = 420.0
        let binding = Binding<Double>(
            get: { width },
            set: { width = $0 }
        )
        let split = DualPaneSplitView(
            leftWidth: binding,
            minLeftWidth: 280,
            minRightWidth: 300,
            left: { Text("Left") },
            right: { Text("Right") }
        )
        #expect(split.minLeftWidth == 280)
        #expect(split.minRightWidth == 300)
        binding.wrappedValue = 520.0
        #expect(width == 520.0)
    }

    @Test func testEmptyPasswordValidationAndSessionPassword() async {
        let service = SFTPService()
        let connWithoutPass = SSHConnection(
            name: "Server Without Pass",
            host: "192.168.1.100",
            port: 22,
            username: "root",
            password: "",
            authType: .password
        )

        // Attempting to connect without password must set error state
        await service.connect(to: connWithoutPass)
        if case .error(let msg) = service.state {
            #expect(msg.contains("Password is required"))
            #expect(service.showErrorAlert == true)
        } else {
            Issue.record("Expected state to be .error when password is missing")
        }

        // Connecting with sessionPassword sets currentSessionPassword
        await service.connect(to: connWithoutPass, sessionPassword: "TempPassword123!")
        #expect(service.currentSessionPassword == "TempPassword123!")

        // Disconnecting must clear session password
        service.disconnect()
        #expect(service.currentSessionPassword == nil)
        #expect(service.state == .disconnected)
    }
}

