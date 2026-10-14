//
//  FolderQuickLookView.swift
//  Compass Gate FTP
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FolderQuickLookInfo: Equatable, Sendable {
    var itemCount: Int
    var totalSize: Int64
    var isLoading: Bool

    var formattedSize: String {
        if isLoading {
            return "Calculating size..."
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: totalSize)
    }

    var itemsDescription: String {
        if isLoading {
            return "calculating items..."
        }
        return "\(itemCount) \(itemCount == 1 ? "item" : "items")"
    }
}

struct FolderQuickLookView: View {
    let name: String
    let modifiedDate: Date
    let info: FolderQuickLookInfo
    var onClose: () -> Void

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df.string(from: modifiedDate)
    }

    private var folderIcon: NSImage {
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = NSSize(width: 256, height: 256)
        return icon
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .buttonStyle(.plain)
                .help("Close (Space / Esc)")

                Image(systemName: "circle.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                Spacer()

                Button {
                    // Quick Look Share icon
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // Content: Folder icon + details
            HStack(spacing: 24) {
                Image(nsImage: folderIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 175, height: 175)
                    .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Text("\(info.formattedSize), \(info.itemsDescription)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                    Text("Last modified \(formattedDate)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 6)
        }
        .frame(width: 520)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 30, y: 15)
        }
    }
}
