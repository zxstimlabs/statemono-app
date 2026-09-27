#if os(macOS)
import AppKit
import SwiftUI

/// Hands the window's events of `events` types to `handler` before AppKit dispatches them, for as long as this view is
/// in the window. The handler also gets this view, which has the frame of the view it's the background of, to convert
/// the event's location with. Returning true swallows the event.
struct WindowEventMonitor: NSViewRepresentable {
    var events: NSEvent.EventTypeMask
    var handler: (NSEvent, NSView) -> Bool
    /// Called when the window stops being key, for example when the user switches to another app.
    var onResignKey: () -> Void = {}

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(events: events)
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.handler = handler
        view.onResignKey = onResignKey
    }

    final class MonitorView: NSView {
        let events: NSEvent.EventTypeMask
        var handler: ((NSEvent, NSView) -> Bool)?
        var onResignKey: (() -> Void)?
        private var monitor: Any?
        private var resignObserver: NSObjectProtocol?

        init(events: NSEvent.EventTypeMask) {
            self.events = events
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// Top-left origin, like SwiftUI.
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                let swallowed = MainActor.assumeIsolated {
                    guard let self, event.window === self.window, let handler = self.handler else { return false }
                    return handler(event, self)
                }
                return swallowed ? nil : event
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onResignKey?() }
            }
        }

        private func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            monitor = nil
            resignObserver = nil
        }
    }
}
#endif
