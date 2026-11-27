import CoreGraphics

/// Stable identifier for a window the app manages.
public struct WindowID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public var description: String { "w\(raw)" }
}

/// A snapshot of one managed window.
public struct ManagedWindow: Equatable, Sendable {
    public let id: WindowID
    public let title: String
    public let frame: CGRect

    public init(id: WindowID, title: String, frame: CGRect) {
        self.id = id
        self.title = title
        self.frame = frame
    }
}

/// What a window's stand-in looks like while it moves.
public struct WindowAppearance {
    /// Placeholder fill: the app's color.
    public var color: CGColor
    /// Placeholder label (an app name or number) when there is no icon or snapshot.
    public var label: String
    /// A picture of the whole window, title bar included. When present, the stand-in is built from it
    /// instead of the placeholder.
    public var snapshot: CGImage?
    /// Height of the title bar in points (0 if none). The stand-in keeps it at this height.
    public var titleBarHeight: CGFloat
    /// Pixels per point in `snapshot` (2 on Retina).
    public var scale: CGFloat

    public init(
        color: CGColor, label: String, snapshot: CGImage? = nil, titleBarHeight: CGFloat = 0, scale: CGFloat = 1
    ) {
        self.color = color
        self.label = label
        self.snapshot = snapshot
        self.titleBarHeight = titleBarHeight
        self.scale = scale
    }
}

/// The only way the window manager touches windows. The rest of the app never knows whether
/// it is driving its own dummy windows or real app windows.
///
/// All frames are in AppKit global coordinates: origin at the bottom-left of the primary
/// display, y grows upward. Backends that use other coordinate spaces (Accessibility uses
/// top-left) convert internally.
@MainActor
public protocol WindowBackend: AnyObject {
    func windows() -> [ManagedWindow]
    func setFrame(_ id: WindowID, _ frame: CGRect)
    func focus(_ id: WindowID)
    /// How to draw this window's stand-in during motion. Nil if the window is gone.
    func appearance(of id: WindowID) -> WindowAppearance?
    /// Hides or shows the real window while its stand-in moves.
    func setHidden(_ id: WindowID, _ hidden: Bool)
}
