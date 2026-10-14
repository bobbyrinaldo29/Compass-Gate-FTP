//
//  Compass_Gate_FTPApp.swift
//  Compass Gate FTP
//
//  Created by Bobby Rinaldo Sukma Dewa on 10/10/26.
//

import SwiftUI
import SwiftData
import UserNotifications


enum TableRowSelectionHelper {
    private static var isConfigured = false

    static func configureRoundedTableSelection() {
        guard !isConfigured else { return }
        isConfigured = true

        let targetClasses: [AnyClass] = [
            NSTableRowView.self,
            NSClassFromString("SwiftUI.SwiftUITableRowView")
        ].compactMap { $0 }

        for cls in targetClasses {
            swizzleDrawSelection(on: cls)
        }
    }

    private static func swizzleDrawSelection(on cls: AnyClass) {
        let sel = NSSelectorFromString("drawSelectionInRect:")
        guard let method = class_getInstanceMethod(cls, sel) else { return }

        let originalIMP = method_getImplementation(method)
        typealias DrawSelectionFn = @convention(c) (AnyObject, Selector, NSRect) -> Void
        let origDraw = unsafeBitCast(originalIMP, to: DrawSelectionFn.self)

        let customDraw: @convention(block) (AnyObject, NSRect) -> Void = { rowObj, dirtyRect in
            guard let row = rowObj as? NSTableRowView else {
                origDraw(rowObj, sel, dirtyRect)
                return
            }

            guard row.selectionHighlightStyle != .none, row.isSelected else {
                origDraw(rowObj, sel, dirtyRect)
                return
            }

            let visibleBounds = row.visibleRect
            let targetRect = (visibleBounds.isEmpty || visibleBounds.width > row.bounds.width) ? row.bounds : visibleBounds
            let selectionRect = NSInsetRect(targetRect, 6, 1)
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
            let color = row.isEmphasized
                ? NSColor.selectedContentBackgroundColor
                : NSColor.unemphasizedSelectedContentBackgroundColor
            color.setFill()
            path.fill()
        }

        let newIMP = imp_implementationWithBlock(customDraw)
        method_setImplementation(method, newIMP)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        TableRowSelectionHelper.configureRoundedTableSelection()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}


@main
struct Compass_Gate_FTPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        TableRowSelectionHelper.configureRoundedTableSelection()
    }
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SSHConnection.self,
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fallback gracefully during development if schema changes without migration plan
            if let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("default.store") {
                try? FileManager.default.removeItem(at: storeURL)
                let shm = storeURL.appendingPathExtension("shm")
                let wal = storeURL.appendingPathExtension("wal")
                try? FileManager.default.removeItem(at: shm)
                try? FileManager.default.removeItem(at: wal)
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Compass Gate FTP") {
                    showNativeAboutPanel()
                }
            }
            CommandGroup(after: .newItem) {
                Button("Import Connections...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowImportConnections"), object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                ShowHiddenFilesToggle()
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func showNativeAboutPanel() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4

        let credits = NSMutableAttributedString(
            string: """
A modern, fast, and secure SSH, SFTP, and FTP client for macOS.

• SwiftUI & SwiftData powered
• Secure SSH & SFTP transfer
• Dual-pane & Sidebar workspace
""",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Compass Gate FTP",
            .version: "1.0",
            .applicationVersion: "Build 1",
            .credits: credits
        ]

        if let icon = NSImage(named: NSImage.applicationIconName) {
            options[.applicationIcon] = icon
        }

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
}

struct ShowHiddenFilesToggle: View {
    @AppStorage("settings_showHiddenFiles") private var showHiddenFiles = false

    var body: some View {
        Toggle("Show Hidden Files", isOn: $showHiddenFiles)
            .keyboardShortcut(".", modifiers: [.command, .shift])
    }
}
