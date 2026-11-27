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
}
