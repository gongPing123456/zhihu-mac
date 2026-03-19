import SwiftUI
import AppKit

struct HideEnclosingScrollView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            hideScrollView(from: view, retry: 4)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            hideScrollView(from: nsView, retry: 4)
        }
    }

    private func hideScrollView(from view: NSView, retry: Int) {
        var current: NSView? = view
        while let node = current {
            if let scroll = node as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
                scroll.autohidesScrollers = true
                scroll.scrollerStyle = .overlay
                return
            }
            current = node.superview
        }
        if retry > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                hideScrollView(from: view, retry: retry - 1)
            }
        }
    }
}
