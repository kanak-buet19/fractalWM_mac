import AppKit
import Carbon.HIToolbox
import FractalCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let backend = DummyBackend()
    private var statusItem: NSStatusItem!
    private var managingItem: NSMenuItem!
    private var floatAllHotKey: HotKey?

    /// When false, the app leaves every window alone. The kill switch sets this to false.
    private var managing = true {
        didSet { managingItem.state = managing ? .on : .off }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.split.2x2", accessibilityDescription: "fractalWM"
        )
        statusItem.menu = buildMenu()

        // Kill switch: ⌃⌥⌘F floats all windows and stops managing.
        floatAllHotKey = HotKey(
            keyCode: kVK_ANSI_F, modifiers: controlKey | optionKey | cmdKey
        ) { [weak self] in
            MainActor.assumeIsolated { self?.floatAll() }
        }

        // Retile when displays change (resolution, Dock size or position, monitor plugged in or out).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.retile() }
        }

        backend.spawn(count: 6)
        retile()
    }

    // MARK: Actions

    @objc private func toggleManaging() {
        managing.toggle()
        if managing { retile() } else { backend.cascade() }
    }

    @objc private func floatAll() {
        managing = false
        backend.cascade()
    }

    @objc private func spawnDummies() {
        backend.spawn(count: 6)
        retile()
    }

    @objc private func retile() {
        guard managing else { return }
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let windows = backend.windows()
        let frames = SimpleGrid.frames(count: windows.count, in: area)
        NSLog("fractalWM: retile \(windows.count) windows in \(area)")
        for (window, frame) in zip(windows, frames) {
            backend.setFrame(window.id, frame)
        }
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "fractalWM", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        managingItem = item("Manage Windows", #selector(toggleManaging))
        managingItem.state = .on
        menu.addItem(managingItem)

        let floatItem = item("Float All Windows", #selector(floatAll), key: "f")
        floatItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(floatItem)

        menu.addItem(item("Retile", #selector(retile)))
        menu.addItem(.separator())
        menu.addItem(item("Spawn 6 Dummy Windows", #selector(spawnDummies)))
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit fractalWM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
