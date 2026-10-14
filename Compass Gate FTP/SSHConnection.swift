//
//  SSHConnection.swift
//  Compass Gate FTP
//

import Foundation
import SwiftData
import SwiftUI

enum AuthenticationType: String, Codable, CaseIterable {
    case password = "Password"
    case keyFile = "Key File"
}

enum ConnectionGroup: String, Codable, CaseIterable, Identifiable {
    case production = "Production Servers"
    case staging = "Staging & Testing"
    case general = "General"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .production:
            return "lock.shield.fill"
        case .staging:
            return "hammer.fill"
        case .general:
            return "server.rack"
        }
    }
}

enum ServerColorTag: String, Codable, CaseIterable, Identifiable {
    case blue = "Blue"
    case green = "Green"
    case orange = "Orange"
    case red = "Red"
    case purple = "Purple"
    case pink = "Pink"
    case yellow = "Yellow"
    case teal = "Teal"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        case .yellow: return .yellow
        case .teal: return .teal
        }
    }
}

@Model
final class SSHConnection {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var keyFilePath: String
    var authTypeRaw: String
    var groupRaw: String
    var colorTagRaw: String = ServerColorTag.blue.rawValue
    var remotePath: String
    var createdAt: Date

    var authType: AuthenticationType {
        get {
            AuthenticationType(rawValue: authTypeRaw) ?? .password
        }
        set {
            authTypeRaw = newValue.rawValue
        }
    }

    var group: ConnectionGroup {
        get {
            ConnectionGroup(rawValue: groupRaw) ?? .production
        }
        set {
            groupRaw = newValue.rawValue
        }
    }

    var colorTag: ServerColorTag {
        get {
            ServerColorTag(rawValue: colorTagRaw) ?? .blue
        }
        set {
            colorTagRaw = newValue.rawValue
        }
    }

    var tagColor: Color {
        colorTag.color
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        password: String = "",
        keyFilePath: String = "",
        authType: AuthenticationType = .password,
        group: ConnectionGroup = .production,
        groupRaw: String? = nil,
        colorTag: ServerColorTag = .blue,
        remotePath: String = "/",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.keyFilePath = keyFilePath
        self.authTypeRaw = authType.rawValue
        self.groupRaw = groupRaw ?? group.rawValue
        self.colorTagRaw = colorTag.rawValue
        self.remotePath = remotePath
        self.createdAt = createdAt
    }

    var groupIconName: String {
        BookmarkGroupManager.shared.group(named: groupRaw)?.iconName ?? group.iconName
    }
}
