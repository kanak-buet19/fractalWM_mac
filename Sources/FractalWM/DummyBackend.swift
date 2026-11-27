import AppKit
import FractalCore

/// Drives colored test windows that this app creates itself.
/// Needs no permissions and never touches other apps' windows.
@MainActor
final class DummyBackend: WindowBackend {
    private var windowsByID: [WindowID: NSWindow] = [:]
    private var order: [WindowID] = []
    private var nextID = 1
    private var closeObservers: [WindowID: NSObjectProtocol] = [:]

    private static let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple,
        .systemPink, .systemTeal, .systemIndigo, .systemBrown,
    ]

    /// Creates `count` new dummy windows, cascaded so they visibly overlap until tiled.
    func spawn(count: Int) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
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

            closeObservers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.forget(id) }
            }
            window.orderFront(nil)
        }
    }

    /// Puts every window back into an overlapping cascade (used by "Float All").
    func cascade() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        for (index, id) in order.enumerated() {
            let offset = CGFloat(index) * 28
            setFrame(id, CGRect(
                x: screen.minX + 60 + offset, y: screen.maxY - 360 - offset, width: 420, height: 300
            ))
        }
    }

    // MARK: WindowBackend

    func windows() -> [ManagedWindow] {
        order.compactMap { id in
            guard let window = windowsByID[id] else { return nil }
            return ManagedWindow(id: id, title: window.title, frame: window.frame)
        }
    }

    func setFrame(_ id: WindowID, _ frame: CGRect) {
        windowsByID[id]?.setFrame(frame, display: true, animate: false)
    }

    func focus(_ id: WindowID) {
        NSApp.activate()
        windowsByID[id]?.makeKeyAndOrderFront(nil)
    }

    // MARK: Private

    private func forget(_ id: WindowID) {
        windowsByID[id] = nil
        order.removeAll { $0 == id }
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
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

        let color = DummyBackend.colors[(id.raw - 1) % DummyBackend.colors.count]
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
