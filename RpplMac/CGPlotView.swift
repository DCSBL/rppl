import AppKit

/// Core Graphics plot host — no SwiftUI / Charts (Intel RenderBox Metal is broken).
final class PlotNSView: NSView {
    var drawHandler: ((CGContext, CGSize) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = false
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.controlBackgroundColor.setFill()
        context.fill(bounds)
        drawHandler?(context, bounds.size)
    }
}
