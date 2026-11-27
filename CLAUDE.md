# fractalWM_mac

A personal, native macOS window manager. It docks real app windows into a nested ("fractal") layout tree and lets
the user zoom into any part of that tree. It is for personal use only.

## Hard rules

- **Never run the app on the host Mac.** It moves real windows. All running and testing happens inside a UTM
  macOS VM. Write code, then tell the user what to build and run there.
- **`reference/` is read-only and gitignored.** `reference/trellis/` is a clone of DanFessler/trellis, a web layout
  engine with a source-available, non-commercial license. Read it for ideas only. Never copy its code into this
  repo, and never reuse the "Trellis" name or branding.
- Inspiration: trelliswm.app (a commercial Mac window manager). Copy concepts only, never its name, UI or assets.
- Use MIT-licensed projects such as Rectangle, Amethyst and yabai for Accessibility API techniques, with
  attribution if code is adapted.

## Stack

- Swift with AppKit. A menu-bar app (`LSUIElement = YES`) with no Dock icon.
- Targets macOS 14+ on Apple silicon.
- App Sandbox is **off**, because the Accessibility API requires that.
- Global hotkeys come from the `KeyboardShortcuts` Swift package.
- No other dependencies unless clearly justified.

## Architecture

Keep these layers separate. The model and the layout engine never import AppKit.

1. **Model (`LayoutTree`).** Pure value types.
   - `Split { axis: .horizontal/.vertical, weights: [Double], children: [Node] }`
   - `Stack { windows: [WindowID], active: Int }`, a tab group. A plain docked window is a one-item stack.
   - Operations: insert, dock(at: edge of node), remove, move, resizeSeam, normalize. Normalize collapses a
     single-child split and drops an empty stack.
   - Each display has its own tree.
   - Unit-test every operation.
2. **Layout engine.** A pure function `(tree, rect, gap) -> [WindowID: CGRect]`.
3. **Window backend.** Behind a protocol, so the logic never knows whether windows are real:
   ```swift
   protocol WindowBackend {
       func windows() -> [ManagedWindow]
       func setFrame(_ id: WindowID, _ frame: CGRect)
       func focus(_ id: WindowID)
   }
   ```
   - `DummyBackend` uses colored `NSWindow`s the app creates itself. It needs no permissions and is the default
     during development.
   - `AXBackend` drives real app windows via `AXUIElement`. Observe changes with `AXObserver` (created, moved,
     resized, destroyed, focused).
4. **Coordinates.** The Accessibility API uses a top-left origin, while AppKit and `NSScreen` use bottom-left.
   Convert in exactly one place, inside `AXBackend`.
5. **Interaction.**
   - Drag-to-dock: a global mouse monitor tracks window drags. Near a screen or node edge, a translucent
     overlay `NSPanel` shows the drop zone. On release, call `dock`.
   - Seam resize: invisible handle windows sit over the gaps between siblings. Dragging one updates `weights`.
   - Hotkeys: focus neighbor, zoom in/out, show all, save/recall view.
6. **Navigation / zoom.**
   - The viewport is a path to a subtree. Zooming in lays that subtree out to fill the display.
   - Windows outside the viewport are parked (moved off-screen or minimized) and restored on zoom out.
   - Later milestone: animated zoom using ScreenCaptureKit snapshots (needs Screen Recording permission).
7. **Persistence.** Store each display's tree as JSON in `~/Library/Application Support/fractalWM_mac/`. Match
   windows on restore by bundle ID, then title, then order.
8. **Kill switch.** A hotkey plus a menu item that stops managing windows and "floats all". Build it in the first
   milestone.

## Milestones

1. Menu-bar app with the kill switch, and `DummyBackend` spawning 6 colored windows.
2. `LayoutTree` with unit tests, and the layout engine tiling the dummy windows.
3. Seam resize and drag-to-dock on dummy windows.
4. Stacks (tab groups) and zoom/viewport navigation.
5. `AXBackend`: permission prompt, listing windows, tiling real windows (in the VM only), and an allowlist of
   bundle IDs to manage.
6. AX observers, persistence and multiple displays.
7. Animated zoom with ScreenCaptureKit.

## Dev loop

- Develop in Xcode inside the UTM macOS VM.
- Sign with a fixed development team, so the Accessibility grant survives rebuilds.
- Keep a clean duplicate of the VM's `.utm` bundle as a restore point.
