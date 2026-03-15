import AppKit
import SwiftUI

struct ActionWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}
