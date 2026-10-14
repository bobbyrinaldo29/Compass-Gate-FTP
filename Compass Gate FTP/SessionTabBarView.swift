//
//  SessionTabBarView.swift
//  Compass Gate FTP
//

import SwiftUI
import AppKit

struct SessionTabBarView: View {
    let tabs: [SessionTab]
    let activeTabID: UUID?
    var onSelectTab: (SessionTab) -> Void
    var onCloseTab: (SessionTab) -> Void
    var onNewTab: () -> Void

    @State private var hoveredTabID: UUID? = nil
    @State private var isHoveringCloseID: UUID? = nil
    @State private var isHoveringPlus: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Finder-style Pill Capsule Container
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let isActive = (tab.id == activeTabID)

                    tabSegment(for: tab, isActive: isActive)

                    // Vertical hairline separator between adjacent inactive tabs
                    if index < tabs.count - 1 && !isActive && (tabs[index + 1].id != activeTabID) {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(width: 1, height: 16)
                    }
                }
            }
            .padding(2)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.8)
                    )
            }

            // Finder-style Circular "+" New Tab Button
            Button {
                onNewTab()
            } label: {
                ZStack {
                    Circle()
                        .fill(isHoveringPlus ? Color(nsColor: .controlColor).opacity(0.6) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.8)
                        )

                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHoveringPlus ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
            .onHover { isHoveringPlus = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func tabSegment(for tab: SessionTab, isActive: Bool) -> some View {
        let isHovered = (hoveredTabID == tab.id)

        ZStack {
            // Background capsule for active or hovered segment
            if isActive {
                Capsule()
                    .fill(tab.connection.tagColor.opacity(0.18))
                    .overlay(
                        Capsule()
                            .strokeBorder(tab.connection.tagColor.opacity(0.4), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 1, y: 0.5)
            } else if isHovered {
                Capsule()
                    .fill(Color(nsColor: .controlColor).opacity(0.3))
            }

            // Left-aligned Close (✕) button (macOS Finder style)
            HStack {
                Button {
                    onCloseTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            isHoveringCloseID == tab.id
                            ? Color(nsColor: .labelColor)
                            : (isActive ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .tertiaryLabelColor))
                        )
                        .frame(width: 16, height: 16)
                        .background(
                            isHoveringCloseID == tab.id ? Color(nsColor: .controlColor).opacity(0.5) : Color.clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .help("Close Tab (⌘W)")
                .onHover { isHoveringCloseID = $0 ? tab.id : nil }
                .padding(.leading, 6)

                Spacer()
            }

            // Centered content: Status dot, Server icon, and Server title
            HStack(spacing: 6) {
                if tab.service.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    switch tab.service.state {
                    case .connected:
                        Circle()
                            .fill(tab.connection.tagColor)
                            .frame(width: 7, height: 7)
                    case .connecting:
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                    case .error:
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    case .disconnected:
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }

                Image(systemName: tab.connection.group.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(isActive ? tab.connection.tagColor : Color(nsColor: .secondaryLabelColor))

                Text(tab.connection.name)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isActive ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
            }
            .padding(.horizontal, 28) // Keeps centered without colliding with close button
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Capsule())
        .onTapGesture {
            onSelectTab(tab)
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
        .contextMenu {
            Button("Switch to Tab") {
                onSelectTab(tab)
            }
            Divider()
            if tab.service.state == .connected {
                Button("Disconnect Session") {
                    tab.service.disconnect()
                }
            } else {
                Button("Reconnect") {
                    Task {
                        await tab.service.connect(to: tab.connection)
                    }
                }
            }
            Divider()
            Button("Close Tab") {
                onCloseTab(tab)
            }
        }
    }
}
