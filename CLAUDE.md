# fractalWM_mac

A personal, native macOS window manager. It docks real app windows into a nested ("fractal") layout tree and lets
the user zoom into any part of that tree. It is for personal use only.

## Hard rules

- **Claude may compile, run and test without asking in this project.** This overrides the user's global "never
  run or compile" rule, but only within these limits:
  - **On the host:** compiling only (`swift build`, `swift test` for pure-logic tests, `scripts/bundle.sh`).
    These produce files and never launch the app.
  - **In the VM (`ssh fractalvm`):** launching and testing (`scripts/run-in-vm.sh`), taking screenshots,
    reading window positions, sending input, and using passwordless `sudo` there.
  - Never launch the app or send synthetic input on the host.

- **Never run the app on the host Mac.** It moves real windows. Building on the host is fine, because that only
  produces the `.app` file. Launching and testing happen only inside the UTM macOS VM (see Dev loop).
- **`reference/` is read-only and gitignored.** `reference/trellis/` is a clone of DanFessler/trellis, a web layout
  engine with a source-available, non-commercial license. Read it for ideas only. Never copy its code into this
  repo, and never reuse the "Trellis" name or branding.
- Inspiration: trelliswm.app (a commercial Mac window manager). Copy concepts only, never its name, UI or assets.
- Use MIT-licensed projects such as Rectangle, Amethyst and yabai for Accessibility API techniques, with
  attribution if code is adapted.

## Stack

- Swift with AppKit. A menu-bar app (`LSUIElement = YES`) with no Dock icon.
- Build with Swift Package Manager and the Command Line Tools only. Xcode is not used. `scripts/bundle.sh` wraps
  the built binary into `fractalWM.app` with an `Info.plist` and signs it.
- Targets macOS 14+ on Apple silicon.
- App Sandbox is **off**, because the Accessibility API requires that.
- Global hotkeys use Carbon's `RegisterEventHotKey` (`Sources/FractalWM/HotKey.swift`), so there are no
  dependencies. Add a dependency only when it is clearly justified.
- The kill switch is ⌃⌥⌘F.

## Features

This is the full target feature set, modeled on what trelliswm.app offers. There are no paid tiers: every
feature is included and there is no window limit.

- **Docking.** Drag a window to a screen edge to dock it. Docked windows tile, and spaces nest inside spaces to
  any depth.
- **Pinch zoom.** ⌥ + trackpad pinch anywhere zooms the real desktop in and out of the layout tree. This needs a
  `CGEventTap` that catches magnify gesture events.
- **Show everything.** ⌃⌥Space zooms out to the whole tree.
- **Live previews.** While zoomed out or zooming, windows show live thumbnails via ScreenCaptureKit.
- **Tab groups.** Stack several windows under one tab strip, drawn as an overlay panel above the active window.
- **Resize at the seams.** Dragging the gap between two windows resizes both.
- **Keyboard navigation.** Move focus between neighbors, zoom in and out, and move windows between nodes, all
  from hotkeys.
- **Menu-bar navigation.** The menu-bar item offers back/forward through the zoom history, jumps to saved views,
  and shows a mini map of the tree.
- **Saved views.** ⌃⌥⇧ + a number saves the current viewport. ⌃⌥ + the same number returns to it.
- **Per-display arrangements.** Each display keeps its own tree, and every tree is restored after a restart.
- **All displays.** Works across multiple monitors and handles displays being plugged in or unplugged.
- **URL commands.** A `fractalwm://` URL scheme, e.g. `fractalwm://view?n=1`, `fractalwm://zoom?dir=out` or
  `fractalwm://float-all`. These let Raycast, Alfred, Shortcuts, Stream Deck and the shell drive the app.
- **Float all windows.** One command undocks every window and returns to a normal Mac. This is also the kill
  switch.

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
4. Tab groups, zoom/viewport navigation, keyboard navigation and show-everything.
5. `AXBackend`: permission prompt, listing windows, tiling real windows (in the VM only), and an allowlist of
   bundle IDs to manage.
6. AX observers, persistence, and per-display arrangements across all displays.
7. Saved views, menu-bar navigation (back/forward) and URL commands.
8. Pinch zoom, plus live previews and animated zoom with ScreenCaptureKit.

## Dev loop

Build on the host Mac, run in the VM:

```
host:  swift build -c release && scripts/bundle.sh     # produces build/fractalWM.app; nothing is launched
host:  scripts/run-in-vm.sh                            # copies the app into the VM and launches it there
```

- **The VM** is a stock macOS 26.5.1 install with no developer tools. It's reachable over passwordless SSH as
  `fractalvm`, an alias in `~/.ssh/config` set up by `scripts/vm-ssh-setup.sh`.
- **VM limits:** the disk is small (about 5 GB free), so never install anything into it, and keep automatic
  updates off. The VM's macOS must never be newer than the host's.
- **Signing:** `scripts/bundle.sh` signs with a fixed self-signed certificate from the host's Keychain (one-time
  setup). That keeps the VM's Accessibility grant valid across rebuilds. Ad-hoc signing would reset it every
  time.
- **VM test tools**, all run from the host:
  - `scripts/vm-windows.sh` prints fractalWM's window frames and the screen size. It needs no permissions.
  - `scripts/vm-screenshot.sh` saves a screenshot to `build/vm-shot.png`.
  - `scripts/vm-input.sh key f control,option,command` presses keys.
  - `scripts/vm-input.sh menu "Retile"` clicks a fractalWM menu item.
  - The screenshot and input tools need Screen Recording and Accessibility for `sshd-keygen-wrapper` in the VM.
    `scripts/vm-grant-permissions.sh` walks through granting them.
  - Verify behavior by comparing frames from `vm-windows.sh` with the expected layout, and use screenshots for
    visual checks.
- **The VM screen** is fixed at 1920×1200 (dynamic resolution off).
- **Pure logic** (`LayoutTree`, the layout engine) has no AppKit, so its unit tests can run on the host. They
  never touch windows.
- Keep a clean duplicate of the VM's `.utm` bundle as a restore point.
