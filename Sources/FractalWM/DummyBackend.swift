import AppKit
import FractalCore

/// Drives colored test windows that this app creates itself.
/// Needs no permissions and never touches other apps' windows.
@MainActor
final class DummyBackend: WindowBackend {
    private var windowsByID: [WindowID: NSWindow] = [:]
    private var order: [WindowID] = []
    private var nextID = 1
    private var observers: [WindowID: [NSObjectProtocol]] = [:]
    /// True while this backend is moving windows itself, so those moves aren't reported as the user's.
    private var applyingFrames = false

    /// Called when the user moves or resizes a window (not when the app does).
    var onUserChange: ((WindowID) -> Void)?

    private static let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple,
        .systemPink, .systemTeal, .systemIndigo, .systemBrown,
    ]

    /// Called after the user closes a dummy window.
    var onClose: ((WindowID) -> Void)?

    /// Creates `count` new dummy windows, cascaded so they visibly overlap until tiled.
    @discardableResult
    func spawn(count: Int) -> [WindowID] {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        var created: [WindowID] = []
        for _ in 0..<count {
            let id = WindowID(nextID)
            nextID += 1

            let offset = CGFloat(order.count) * 28
            let frame = CGRect(
                x: screen.minX + 60 + offset, y: screen.maxY - 360 - offset, width: 420, height: 300
            )
            let window = makeWindow(id: id, frame: frame)
            windowsByID[id] = window
            order.append(id)

            // queue: nil runs the blocks synchronously on the posting thread, which for AppKit window
            // notifications is the main thread. That keeps `applyingFrames` accurate.
            let center = NotificationCenter.default
            var tokens = [
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.forget(id) }
                },
            ]
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                tokens.append(center.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, !self.applyingFrames else { return }
                        self.onUserChange?(id)
                    }
                })
            }
            observers[id] = tokens
            window.orderFront(nil)
            created.append(id)
        }
        return created
    }

    /// Frames for an overlapping cascade of every window (used by "Float All").
    func cascadeFrames() -> [WindowID: CGRect] {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        var frames: [WindowID: CGRect] = [:]
        for (index, id) in order.enumerated() {
            let offset = CGFloat(index) * 28
            frames[id] = CGRect(
                x: screen.minX + 60 + offset, y: screen.maxY - 360 - offset, width: 420, height: 300
            )
        }
        return frames
    }

    // MARK: WindowBackend

    func windows() -> [ManagedWindow] {
        order.compactMap { id in
            guard let window = windowsByID[id] else { return nil }
            return ManagedWindow(id: id, title: window.title, frame: window.frame)
        }
    }

    func setFrame(_ id: WindowID, _ frame: CGRect) {
        applyingFrames = true
        defer { applyingFrames = false }
        windowsByID[id]?.setFrame(frame, display: true, animate: false)
    }

    func focus(_ id: WindowID) {
        NSApp.activate()
        windowsByID[id]?.makeKeyAndOrderFront(nil)
    }

    func appearance(of id: WindowID) -> WindowAppearance? {
        guard let window = windowsByID[id] else { return nil }
        let titleBarHeight = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        return WindowAppearance(
            color: Self.color(for: id).cgColor,
            label: "\(id.raw)",
            snapshot: Self.snapshot(of: window),
            titleBarHeight: titleBarHeight,
            scale: window.backingScaleFactor
        )
    }

    /// Renders the whole window, title bar included, by drawing its frame view (the content view's
    /// superview). This only works for the app's own windows; real apps' windows will need ScreenCaptureKit.
    private static func snapshot(of window: NSWindow) -> CGImage? {
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    func setHidden(_ id: WindowID, _ hidden: Bool) {
        windowsByID[id]?.alphaValue = hidden ? 0 : 1
    }

    private static func color(for id: WindowID) -> NSColor {
        colors[(id.raw - 1) % colors.count]
    }

    // MARK: Private

    private func forget(_ id: WindowID) {
        windowsByID[id] = nil
        order.removeAll { $0 == id }
        for token in observers.removeValue(forKey: id) ?? [] {
            NotificationCenter.default.removeObserver(token)
        }
        onClose?(id)
    }

    private func makeWindow(id: WindowID, frame: CGRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Dummy \(id.raw)"

        let color = Self.color(for: id)
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor

        let label = NSTextField(labelWithString: "\(id.raw)")
        label.font = .systemFont(ofSize: 96, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        window.contentView = content
        return window
    }
}
