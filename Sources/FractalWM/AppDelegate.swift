import AppKit
import Carbon.HIToolbox
import FractalCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let backend = DummyBackend()
    private let animator = Animator()
    private var tree = LayoutTree()
    private let gap: CGFloat = 8

    private var statusItem: NSStatusItem!
    private var managingItem: NSMenuItem!
    private var floatAllHotKey: HotKey?
    private var snapTimer: Timer?

    /// When false, the app leaves every window alone. The kill switch sets this to false.
    /// The tree is kept, so turning management back on restores the arrangement.
    private var managing = true {
        didSet {
            managingItem.state = managing ? .on : .off
            writeState()
        }
    }

    /// Debug snapshot for the VM test tools (`scripts/vm-windows.sh`).
    private static let stateFile = URL(fileURLWithPath: "/tmp/fractalwm-state.txt")

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

        backend.onClose = { [weak self] id in
            self?.tree.remove(id)
            self?.retile()
        }
        backend.onUserChange = { [weak self] _ in
            self?.snapBackWhenMouseUp()
        }

        spawnDummies()
    }

    // MARK: Actions

    @objc private func toggleManaging() {
        managing.toggle()
        if managing { retile() } else { animator.animate(to: backend.cascadeFrames(), with: backend) }
    }

    @objc private func floatAll() {
        managing = false
        animator.animate(to: backend.cascadeFrames(), with: backend)
    }

    @objc private func toggleAnimation(_ sender: NSMenuItem) {
        animator.enabled.toggle()
        sender.state = animator.enabled ? .on : .off
    }

    @objc private func spawnDummies() {
        let area = displayArea()
        for id in backend.spawn(count: 6) {
            tree.insert(id, bounds: area)
        }
        retile()
    }

    /// The Retile menu item: an explicit request, so it also turns management back on.
    @objc private func retileFromMenu() {
        if !managing { managing = true }
        retile()
    }

    /// A user moved or resized a managed window: put it back in its tile once the drag ends.
    /// (Milestone 3 replaces this with drag-to-dock and seam resizing.)
    private func snapBackWhenMouseUp() {
        guard managing, snapTimer == nil else { return }
        snapTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons == 0 else { return }
                self.snapTimer?.invalidate()
                self.snapTimer = nil
                self.retile()
            }
        }
    }

    private func retile() {
        writeState()
        guard managing else { return }
        let layout = LayoutEngine.layout(tree, in: displayArea(), gap: gap)
        let targets = layout.frames.filter { layout.visible.contains($0.key) }
        animator.animate(to: targets, with: backend)
    }

    // MARK: Helpers

    private func displayArea() -> CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
    }

    private func writeState() {
        let text = """
        managing: \(managing)
        tree: \(tree.summary)

        """
        try? text.write(to: Self.stateFile, atomically: true, encoding: .utf8)
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

        menu.addItem(item("Retile", #selector(retileFromMenu)))
        let animationItem = item("Animate Layout Changes", #selector(toggleAnimation(_:)))
        animationItem.state = .on
        menu.addItem(animationItem)
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
