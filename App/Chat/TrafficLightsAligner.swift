#if os(macOS)
import AppKit
import SwiftUI

/// Moves the window's traffic lights down so they sit level with the floating header, and reports how far
/// they reach from the leading edge (0 in full screen, where they're hidden).
///
/// There's no API for this. It grows the titlebar container and re-centers the buttons, the same way Tauri
/// and Electron do. AppKit resets both on resize and full-screen changes, so it reapplies after each one.
struct TrafficLightsAligner: NSViewRepresentable {
    var centerY: CGFloat
    @Binding var width: CGFloat

    func makeNSView(context: Context) -> AlignerView {
        AlignerView()
    }

    func updateNSView(_ view: AlignerView, context: Context) {
        view.onWidthChange = { width = $0 }
        view.centerY = centerY
    }

    final class AlignerView: NSView {
        var centerY: CGFloat = 0 {
            didSet { if centerY != oldValue { realign() } }
        }
        var onWidthChange: ((CGFloat) -> Void)?
        private var reportedWidth: CGFloat?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.realign() }
                }
            }
            realign()
        }

        override func layout() {
            super.layout()
            realign()
        }

        private func realign() {
            guard let window,
                  let close = window.standardWindowButton(.closeButton),
                  let zoom = window.standardWindowButton(.zoomButton),
                  let titlebar = close.superview,
                  let container = titlebar.superview
            else { return }

            guard !window.styleMask.contains(.fullScreen) else {
                report(0)
                return
            }

            let height = centerY * 2
            let frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
            if container.frame != frame {
                container.frame = frame
            }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(kind) else { continue }
                let y = (titlebar.bounds.height - button.frame.height) / 2
                if button.frame.origin.y != y {
                    button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y))
                }
            }
            report(zoom.frame.maxX)
        }

        /// Deferred because this can run inside a SwiftUI layout pass, where writing state isn't allowed.
        private func report(_ width: CGFloat) {
            guard width != reportedWidth else { return }
            reportedWidth = width
            Task { @MainActor [weak self] in self?.onWidthChange?(width) }
        }
    }
}
#endif
