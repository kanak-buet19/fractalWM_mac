import AppKit
import FractalCore

/// Animates layout changes the way real windows will be animated.
///
/// Each moving window is hidden and replaced by a borderless stand-in (a placeholder now, a snapshot
/// once Screen Recording is used) that glides to the new frame. The real window is placed once, at the
/// end. This avoids stepping real windows through the Accessibility API, which is jerky.
@MainActor
final class Animator {
    /// One shared motion for every split, dock, close and snap-back. For testing or tuning, override it
    /// with `defaults write local.fractalwm AnimationDuration -float 3` (relaunch to apply).
    static let duration: TimeInterval = {
        let custom = UserDefaults.standard.double(forKey: "AnimationDuration")
        return custom > 0 ? custom : 0.46
    }()
    /// Fast start, long gentle settle.
    static let timing = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)

    /// When false, layout changes apply instantly.
    var enabled = true

    private struct Move {
        let id: WindowID
        let from: CGRect
        let to: CGRect
    }

    private var pending: [Move] = []
    private var standIns: [NSWindow] = []
    private var generation = 0
    private weak var backend: (any WindowBackend)?

    /// Moves windows to `targets`, animating the ones whose frame changes.
    func animate(to targets: [WindowID: CGRect], with backend: any WindowBackend) {
        finishNow()
        self.backend = backend

        let current = Dictionary(uniqueKeysWithValues: backend.windows().map { ($0.id, $0.frame) })
        let moves = targets.compactMap { id, to in current[id].map { Move(id: id, from: $0, to: to) } }
        let moving = moves.filter { $0.from != $0.to }

        guard enabled, !moving.isEmpty else {
            for move in moves { backend.setFrame(move.id, move.to) }
            return
        }

        pending = moves
        generation += 1
        let thisGeneration = generation

        var flights: [(standIn: NSWindow, to: CGRect)] = []
        for move in moving {
            guard let look = backend.appearance(of: move.id) else { continue }
            let standIn = Self.makeStandIn(look, frame: move.from)
            standIn.orderFront(nil)
            backend.setHidden(move.id, true)
            standIns.append(standIn)
            flights.append((standIn, move.to))
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = Self.timing
            for flight in flights {
                flight.standIn.animator().setFrame(flight.to, display: true)
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == thisGeneration else { return }
                self.finishNow()
            }
        }
    }

    /// Jumps a running motion to its end: real windows at their final frames, stand-ins removed.
    func finishNow() {
        if let backend {
            for move in pending {
                backend.setFrame(move.id, move.to)
                backend.setHidden(move.id, false)
            }
        }
        pending = []
        for standIn in standIns {
            standIn.orderOut(nil)
            standIn.close()
        }
        standIns = []
    }

    private static func makeStandIn(_ look: WindowAppearance, frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = look.color

        if let snapshot = look.snapshot {
            view.layer?.backgroundColor = nil
            buildFromSnapshot(snapshot, look: look, in: view)
        } else {
            let label = NSTextField(labelWithString: look.label)
            label.font = .systemFont(ofSize: 64, weight: .bold)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }

        window.contentView = view
        return window
    }

    /// Builds a stand-in from a snapshot without ever scaling it, so text keeps its size as the window
    /// changes shape:
    /// - Title bar: kept at its real height. The left part (traffic lights) is pinned left, the middle
    ///   (title) stays centered, and the bar's background is a 1-pixel slice of the real bar, stretched.
    /// - Content: drawn at actual size and centered, cropped or surrounded by its own edge color.
    private static func buildFromSnapshot(_ image: CGImage, look: WindowAppearance, in view: NSView) {
        let s = look.scale
        let width = view.bounds.width, height = view.bounds.height
        let pxWidth = CGFloat(image.width), pxHeight = CGFloat(image.height)
        let bar = min(look.titleBarHeight, height)
        let barPx = bar * s
        let side: CGFloat = 80 // points kept pinned at each end of the title bar

        // Image-space crops (origin top-left, in pixels).
        func crop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGImage? {
            guard w >= 1, h >= 1 else { return nil }
            return image.cropping(to: CGRect(x: x, y: y, width: w, height: h).integral)
        }

        func layerView(
            _ image: CGImage?, _ gravity: CALayerContentsGravity, _ frame: CGRect, _ mask: NSView.AutoresizingMask
        ) -> NSView {
            let child = NSView(frame: frame)
            child.wantsLayer = true
            child.autoresizingMask = mask
            child.layer?.contents = image
            child.layer?.contentsGravity = gravity
            child.layer?.contentsScale = s
            child.layer?.masksToBounds = true
            view.addSubview(child)
            return child
        }

        // Content: background = its own edge color (a 1-pixel slice), image centered at actual size.
        let contentFrame = CGRect(x: 0, y: 0, width: width, height: height - bar)
        let edge = crop(4 * s, barPx + 4 * s, 1, 1)
        _ = layerView(edge, .resize, contentFrame, [.width, .height])
        _ = layerView(crop(0, barPx, pxWidth, pxHeight - barPx), .center, contentFrame, [.width, .height])

        guard bar > 0 else { return }
        let barFrame = CGRect(x: 0, y: height - bar, width: width, height: bar)
        let sidePx = min(side * s, pxWidth / 2)
        _ = layerView(crop(pxWidth - sidePx / 2, 0, 1, barPx), .resize, barFrame, [.width, .minYMargin])
        _ = layerView(
            crop(0, 0, sidePx, barPx), .topLeft,
            CGRect(x: 0, y: height - bar, width: sidePx / s, height: bar), [.maxXMargin, .minYMargin]
        )
        _ = layerView(
            crop(sidePx, 0, pxWidth - 2 * sidePx, barPx), .center,
            CGRect(x: sidePx / s, y: height - bar, width: max(0, width - 2 * sidePx / s), height: bar),
            [.width, .minYMargin]
        )
    }
}
