//
//  AboutCompassGateView.swift
//  Compass Gate FTP
//

import SwiftUI

struct AboutCompassGateView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            VStack(spacing: 6) {
                Text("Compass Gate FTP")
                    .font(.title2)
                    .bold()

                Text("Version \(appVersion) (Build \(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("A modern, fast, and secure SSH, SFTP, and FTP client for macOS.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 10) {
                Label("SwiftUI & SwiftData powered", systemImage: "swift")
                Label("Secure SSH & SFTP transfer", systemImage: "lock.shield")
                Label("Dual-pane & Sidebar workspace", systemImage: "sidebar.left")
            }
            .font(.body)
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutCompassGateView()
}
