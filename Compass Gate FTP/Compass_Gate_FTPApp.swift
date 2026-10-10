//
//  Compass_Gate_FTPApp.swift
//  Compass Gate FTP
//
//  Created by Bobby Rinaldo Sukma Dewa on 10/10/26.
//

import SwiftUI
import SwiftData

@main
struct Compass_Gate_FTPApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
