//
//  AboutCompassGateView.swift
//  Compass Gate FTP
//

import SwiftUI

struct AboutCompassGateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "safari.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Compass Gate FTP")
                    .font(.title2)
                    .bold()

                Text("Version 1.0 (Build 1)")
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
