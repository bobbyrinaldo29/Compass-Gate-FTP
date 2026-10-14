//
//  QuickLookCoordinator.swift
//  Compass Gate FTP
//

import SwiftUI
import AppKit
import QuickLookUI

struct ScreenRectReader: NSViewRepresentable {
    var onChange: (NSRect) -> Void

    func makeNSView(context: Context) -> ScreenRectReaderView {
        let view = ScreenRectReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenRectReaderView, context: Context) {
        nsView.onChange = onChange
        nsView.reportFrame()
    }
}

final class ScreenRectReaderView: NSView {
    var onChange: ((NSRect) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrame()
    }

    override func layout() {
        super.layout()
        reportFrame()
    }

    func reportFrame() {
        guard let window = self.window, !self.bounds.isEmpty else { return }
        let rectInWindow = self.convert(self.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        onChange?(screenRect)
    }
}

@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private(set) var currentURL: URL?
    var currentSourceFrame: NSRect?

    var isVisible: Bool {
        QLPreviewPanel.shared()?.isVisible ?? false
    }

    func toggle(url: URL?) {
        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible {
            if let newURL = url, newURL != currentURL {
                currentURL = newURL
                panel.reloadData()
            } else {
                panel.orderOut(nil)
                currentURL = nil
            }
        } else if let newURL = url {
            currentURL = newURL
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func updatePreview(url: URL?) {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        if let newURL = url {
            currentURL = newURL
            panel.reloadData()
        } else {
            panel.orderOut(nil)
            currentURL = nil
        }
    }

    func close() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
        currentURL = nil
    }

    // MARK: - QLPreviewPanelDataSource
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            return currentURL != nil ? 1 : 0
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard let url = currentURL else { return nil }
            return url as NSURL
        }
    }

    // MARK: - QLPreviewPanelDelegate (Smooth Native Icon Zoom)
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        MainActor.assumeIsolated {
            if let frame = currentSourceFrame, frame.width > 0, frame.height > 0 {
                return frame
            }
            return .zero
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        MainActor.assumeIsolated {
            guard let url = currentURL else { return nil }
            var isDir: ObjCBool = false
            let icon: NSImage
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                icon = NSWorkspace.shared.icon(for: .folder)
            } else {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            }
            let size = NSSize(width: 32, height: 32)
            icon.size = size
            if let contentRect = contentRect {
                contentRect.pointee = NSRect(origin: .zero, size: size)
            }
            return icon
        }
    }
}
