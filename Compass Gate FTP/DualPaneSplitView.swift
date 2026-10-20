//
//  DualPaneSplitView.swift
//  Compass Gate FTP
//

import AppKit
import SwiftUI

/// An NSViewRepresentable that sets the macOS horizontal resize cursor (NSCursor.resizeLeftRight)
/// natively over the divider bounds using resetCursorRects.
private final class ResizeCursorNSView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return self so mouse moves are tracked for cursor updates
        return super.hitTest(point)
    }
}

private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCursorNSView {
        let view = ResizeCursorNSView()
        return view
    }

    func updateNSView(_ nsView: ResizeCursorNSView, context: Context) {}
}

/// A macOS-native horizontal split view that maintains its split position
/// across tab changes, menu navigation, and app restarts via a persistent Double binding (e.g. @AppStorage).
struct DualPaneSplitView<Left: View, Right: View>: View {
    @Binding var leftWidth: Double
    var minLeftWidth: CGFloat = 300
    var minRightWidth: CGFloat = 320
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var dragStartWidth: CGFloat? = nil

    private let dividerHitWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let currentWidth = effectiveWidth(totalWidth: totalWidth)

            HStack(spacing: 0) {
                // Left Pane (Local)
                left()
                    .frame(width: currentWidth)
                    .frame(maxHeight: .infinity)

                // Custom Draggable Divider
                dividerBar(totalWidth: totalWidth, currentWidth: currentWidth)

                // Right Pane (Remote)
                right()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func dividerBar(totalWidth: CGFloat, currentWidth: CGFloat) -> some View {
        ZStack {
            // Invisible native cursor rect tracking
            ResizeCursorView()

            // 1pt subtle divider hairline
            Rectangle()
                .fill(
                    (isDragging || isHovering)
                        ? Color.accentColor.opacity(0.85)
                        : Color(nsColor: .separatorColor)
                )
                .frame(width: (isDragging || isHovering) ? 2 : 1)
                .animation(.easeInOut(duration: 0.12), value: isDragging || isHovering)
        }
        .frame(width: dividerHitWidth)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    let centered = totalWidth / 2
                    leftWidth = Double(clamp(centered, totalWidth: totalWidth))
                }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = currentWidth
                        isDragging = true
                    }
                    let base = dragStartWidth ?? currentWidth
                    let proposed = base + value.translation.width
                    let clamped = clamp(proposed, totalWidth: totalWidth)
                    leftWidth = Double(clamped)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    isDragging = false
                }
        )
        .help("Drag to resize panels (Double-click to center)")
    }

    private func effectiveWidth(totalWidth: CGFloat) -> CGFloat {
        if totalWidth <= 0 {
            return CGFloat(leftWidth)
        }
        if leftWidth <= 0 {
            return clamp(totalWidth / 2, totalWidth: totalWidth)
        }
        return clamp(CGFloat(leftWidth), totalWidth: totalWidth)
    }

    private func clamp(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        if totalWidth <= (minLeftWidth + minRightWidth) {
            return max(150, totalWidth / 2)
        }
        let maxLeft = totalWidth - minRightWidth
        return min(max(width, minLeftWidth), maxLeft)
    }
}
