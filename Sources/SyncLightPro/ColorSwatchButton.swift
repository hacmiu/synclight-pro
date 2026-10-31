import SwiftUI
import AppKit

/// A clickable color swatch that opens the shared `NSColorPanel` when clicked,
/// reporting the chosen color back via `onChange`. This gives the "click the
/// square → palette opens" behaviour without an extra step.
struct ColorSwatchButton<Label: View>: NSViewRepresentable {
    let color: NSColor
    let onChange: (NSColor) -> Void
    @ViewBuilder let label: () -> Label

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> SwatchHostingView<Label> {
        let v = SwatchHostingView(rootView: label())
        v.onClick = {
            let panel = NSColorPanel.shared
            panel.showsAlpha = false
            panel.color = color
            panel.setTarget(context.coordinator)
            panel.setAction(#selector(Coordinator.colorChanged(_:)))
            panel.orderFront(nil)
        }
        return v
    }

    func updateNSView(_ nsView: SwatchHostingView<Label>, context: Context) {
        nsView.rootView = label()
        context.coordinator.onChange = onChange
    }

    final class Coordinator: NSObject {
        var onChange: (NSColor) -> Void
        init(onChange: @escaping (NSColor) -> Void) { self.onChange = onChange }
        @objc func colorChanged(_ sender: NSColorPanel) {
            onChange(sender.color)
        }
    }
}

/// NSHostingView that turns clicks into a callback.
final class SwatchHostingView<Content: View>: NSHostingView<Content> {
    var onClick: (() -> Void)? {
        didSet { installGestureIfNeeded() }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    /// A click recognizer makes the whole view reliably clickable even when the
    /// hosted SwiftUI content would otherwise swallow the mouse-down.
    private func installGestureIfNeeded() {
        guard gestureRecognizers.isEmpty else { return }
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    @objc private func handleClick() {
        onClick?()
    }
}
