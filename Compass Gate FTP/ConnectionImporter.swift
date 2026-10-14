//
//  ConnectionImporter.swift
//  Compass Gate FTP
//

import Foundation
import SwiftUI

struct ImportedConnection: Identifiable, Hashable {
    var id = UUID()
    var isSelected: Bool = true
    var name: String
    var host: String
    var port: Int = 22
    var username: String = ""
    var password: String = ""
    var keyFilePath: String = ""
    var authType: AuthenticationType = .password
    var remotePath: String = "/"
    var sourceDescription: String = ""
    var group: ConnectionGroup = .production
    var colorTag: ServerColorTag = .blue

    func toSSHConnection(overrideGroup: ConnectionGroup? = nil) -> SSHConnection {
        SSHConnection(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : name,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port > 0 ? port : 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            keyFilePath: keyFilePath,
            authType: authType,
            group: overrideGroup ?? group,
            colorTag: colorTag,
            remotePath: remotePath.isEmpty ? "/" : remotePath
        )
    }
}

enum ConnectionImporter {

    /// Loads and parses the user's default OpenSSH config from ~/.ssh/config if available.
    static func loadDefaultSSHConfig() -> [ImportedConnection] {
        let path = ("~/.ssh/config" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        return parseSSHConfig(content: content, source: "~/.ssh/config")
    }

    /// Parses OpenSSH config syntax.
    static func parseSSHConfig(content: String, source: String = "SSH Config") -> [ImportedConnection] {
        var results: [ImportedConnection] = []
        let lines = content.components(separatedBy: .newlines)
        var current: [String: Any]? = nil

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace || $0 == "=" })
            guard !parts.isEmpty else { continue }
            let key = parts[0].lowercased()
            let val = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            if key == "host" {
                if let cur = current, let h = cur["host"] as? String, !h.isEmpty {
                    if let item = makeFromDict(cur, source: source) {
                        results.append(item)
                    }
                }
                // Skip wildcards
                if val.contains("*") || val.contains("?") {
                    current = nil
                    continue
                }
                current = [
                    "name": val,
                    "host": "",
                    "port": 22,
                    "user": "",
                    "key": "",
                    "path": "/"
                ]
            } else if var cur = current {
                if key == "hostname" {
                    cur["host"] = val
                } else if key == "port", let p = Int(val) {
                    cur["port"] = p
                } else if key == "user" {
                    cur["user"] = val
                } else if key == "identityfile" {
                    cur["key"] = val
                } else if key == "remotecommand" {
                    if let range = val.range(of: "cd\\s+([^;&]+)", options: .regularExpression) {
                        let match = String(val[range])
                        let dir = match.replacingOccurrences(of: "cd", with: "").trimmingCharacters(in: .whitespaces)
                        cur["path"] = dir
                    }
                }
                current = cur
            }
        }

        if let cur = current, let h = cur["host"] as? String, !h.isEmpty {
            if let item = makeFromDict(cur, source: source) {
                results.append(item)
            }
        }

        return results
    }

    private static func makeFromDict(_ dict: [String: Any], source: String) -> ImportedConnection? {
        let name = dict["name"] as? String ?? ""
        var host = dict["host"] as? String ?? ""
        if host.isEmpty { host = name }
        guard !host.isEmpty else { return nil }

        let port = dict["port"] as? Int ?? 22
        let user = dict["user"] as? String ?? ""
        let key = dict["key"] as? String ?? ""
        let path = dict["path"] as? String ?? "/"
        let auth: AuthenticationType = !key.isEmpty ? .keyFile : .password

        return ImportedConnection(
            name: name,
            host: host,
            port: port,
            username: user,
            keyFilePath: key,
            authType: auth,
            remotePath: path,
            sourceDescription: source
        )
    }

    /// Parses FileZilla site manager XML export.
    static func parseFileZilla(content: String, source: String = "FileZilla") -> [ImportedConnection] {
        var results: [ImportedConnection] = []
        guard let serverRegex = try? NSRegularExpression(pattern: "<Server>([\\s\\S]*?)</Server>", options: .caseInsensitive) else {
            return results
        }
        let nsContent = content as NSString
        let matches = serverRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for m in matches {
            let block = nsContent.substring(with: m.range(at: 1))
            func extract(_ tag: String) -> String {
                if let r = block.range(of: "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>", options: .regularExpression) {
                    let match = String(block[r])
                    let clean = match.replacingOccurrences(of: "<\(tag)[^>]*>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "</\(tag)>", with: "", options: .regularExpression)
                    return clean.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return ""
            }

            let host = extract("Host")
            guard !host.isEmpty else { continue }

            let nameRaw = extract("Name")
            let name = nameRaw.isEmpty ? host : nameRaw
            let port = Int(extract("Port")) ?? 22
            let user = extract("User")
            var pass = extract("Pass")
            if block.contains("Pass encoding=\"base64\"") {
                if let d = Data(base64Encoded: pass), let decoded = String(data: d, encoding: .utf8) {
                    pass = decoded
                }
            }
            let key = extract("Keyfile")
            var path = extract("RemoteDir")
            if path.hasPrefix("1 0") {
                let tokens = path.components(separatedBy: " ")
                let parts = tokens.enumerated().filter { $0.offset % 2 == 1 && $0.offset >= 3 }.map { $0.element }
                path = "/" + parts.joined(separator: "/")
            }
            if path.isEmpty { path = "/" }

            let auth: AuthenticationType = !key.isEmpty ? .keyFile : .password

            results.append(
                ImportedConnection(
                    name: name,
                    host: host,
                    port: port,
                    username: user,
                    password: pass,
                    keyFilePath: key,
                    authType: auth,
                    remotePath: path,
                    sourceDescription: source
                )
            )
        }
        return results
    }

    /// Recursively extracts dictionary representations from JSON or Plist structures.
    static func extractDictionaries(from object: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if let dict = object as? [String: Any] {
            let hasHost = dict["host"] != nil || dict["Host"] != nil ||
                          dict["address"] != nil || dict["Address"] != nil ||
                          dict["server"] != nil || dict["Server"] != nil ||
                          dict["hostname"] != nil
            if hasHost {
                result.append(dict)
            }
            for (_, value) in dict {
                result.append(contentsOf: extractDictionaries(from: value))
            }
        } else if let array = object as? [Any] {
            for element in array {
                result.append(contentsOf: extractDictionaries(from: element))
            }
        }
        return result
    }

    /// Parses a generic dictionary from Transmit, ForkLift, or standard JSON/Plist.
    static func parseServerDictionary(_ dict: [String: Any], source: String = "Imported") -> ImportedConnection? {
        let name = (dict["name"] as? String)
            ?? (dict["nickname"] as? String)
            ?? (dict["Nickname"] as? String)
            ?? (dict["Name"] as? String)
            ?? (dict["title"] as? String)
            ?? ""

        let host = (dict["host"] as? String)
            ?? (dict["Host"] as? String)
            ?? (dict["address"] as? String)
            ?? (dict["Address"] as? String)
            ?? (dict["server"] as? String)
            ?? (dict["Server"] as? String)
            ?? (dict["hostname"] as? String)
            ?? ""

        guard !host.isEmpty else { return nil }

        let port: Int
        if let p = dict["port"] as? Int ?? (dict["Port"] as? Int) {
            port = p
        } else if let s = dict["port"] as? String ?? (dict["Port"] as? String), let p = Int(s) {
            port = p
        } else {
            port = 22
        }

        let username = (dict["username"] as? String)
            ?? (dict["userName"] as? String)
            ?? (dict["UserName"] as? String)
            ?? (dict["User"] as? String)
            ?? (dict["user"] as? String)
            ?? ""

        let password = (dict["password"] as? String)
            ?? (dict["Password"] as? String)
            ?? ""

        let keyFilePath = (dict["keyFilePath"] as? String)
            ?? (dict["keyPath"] as? String)
            ?? (dict["KeyPath"] as? String)
            ?? (dict["privateKey"] as? String)
            ?? (dict["identityFile"] as? String)
            ?? ""

        let remotePath = (dict["remotePath"] as? String)
            ?? (dict["initialPath"] as? String)
            ?? (dict["InitialPath"] as? String)
            ?? (dict["path"] as? String)
            ?? (dict["Path"] as? String)
            ?? "/"

        let authType: AuthenticationType = !keyFilePath.isEmpty ? .keyFile : .password

        return ImportedConnection(
            name: name.isEmpty ? host : name,
            host: host,
            port: port,
            username: username,
            password: password,
            keyFilePath: keyFilePath,
            authType: authType,
            remotePath: remotePath.isEmpty ? "/" : remotePath,
            sourceDescription: source
        )
    }

    /// Auto-detects the format and parses connections from any supported file.
    static func parseFile(at url: URL) throws -> [ImportedConnection] {
        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent.lowercased()

        // 1. Check for OpenSSH config
        if filename == "config" || filename.hasSuffix(".ssh/config") ||
           (String(data: data, encoding: .utf8)?.contains("Host ") == true && !filename.hasSuffix(".xml")) {
            if let str = String(data: data, encoding: .utf8) {
                let items = parseSSHConfig(content: str, source: url.lastPathComponent)
                if !items.isEmpty { return items }
            }
        }

        // 2. Check for FileZilla XML
        if let str = String(data: data, encoding: .utf8),
           str.contains("<FileZilla") || str.contains("<Servers>") || str.contains("<Server>") {
            let items = parseFileZilla(content: str, source: "FileZilla (\(url.lastPathComponent))")
            if !items.isEmpty { return items }
        }

        // 3. Try JSON (Transmit / ForkLift)
        if let json = try? JSONSerialization.jsonObject(with: data) {
            let dicts = extractDictionaries(from: json)
            let items = dicts.compactMap { parseServerDictionary($0, source: url.lastPathComponent) }
            if !items.isEmpty { return items }
        }

        // 4. Try Plist (Transmit / ForkLift)
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            let dicts = extractDictionaries(from: plist)
            let items = dicts.compactMap { parseServerDictionary($0, source: url.lastPathComponent) }
            if !items.isEmpty { return items }
        }

        // 5. Fallback: try parsing as SSH config
        if let str = String(data: data, encoding: .utf8) {
            let items = parseSSHConfig(content: str, source: url.lastPathComponent)
            if !items.isEmpty { return items }
        }

        return []
    }
}
