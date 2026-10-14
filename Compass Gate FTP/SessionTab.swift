//
//  SessionTab.swift
//  Compass Gate FTP
//

import SwiftUI
import Foundation

enum ActiveFilePane: String, CaseIterable, Sendable {
    case local
    case remote
}

@Observable
final class SessionTab: Identifiable, Hashable {
    let id: UUID
    var connection: SSHConnection
    var service: SFTPService
    var localManager: LocalFileManager
    var activePane: ActiveFilePane = .remote
    var createdAt: Date

    init(connection: SSHConnection) {
        self.id = UUID()
        self.connection = connection
        self.service = SFTPService()
        self.localManager = LocalFileManager()
        self.activePane = .remote
        self.createdAt = Date()
    }

    static func == (lhs: SessionTab, rhs: SessionTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
