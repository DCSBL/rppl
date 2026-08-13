import AppKit
import SwiftUI

/// Core Graphics plot host — avoids Swift Charts / RenderBox Metal (broken on Intel: no metallib slice).
struct CGPlotView: NSViewRepresentable {
    var draw: (CGContext, CGSize) -> Void

    func makeNSView(context: Context) -> PlotNSView {
        let view = PlotNSView()
        view.drawHandler = draw
        return view
    }

    func updateNSView(_ nsView: PlotNSView, context: Context) {
        nsView.drawHandler = draw
        nsView.needsDisplay = true
    }
}

final class PlotNSView: NSView {
    var drawHandler: ((CGContext, CGSize) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        NSColor.controlBackgroundColor.setFill()
        context.fill(bounds)
        drawHandler?(context, bounds.size)
    }
}
