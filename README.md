# fractalWM_mac

A fractal window manager for macOS. Dock your real app windows into a nested layout, then zoom in and out of any
part of it.

> **Status:** design phase. There is no runnable code yet. See [CLAUDE.md](CLAUDE.md) for the full design.

## Idea

Most tiling window managers give you one flat grid per screen. fractalWM arranges windows in a **tree** instead.
Splits contain splits, any branch can hold a group of tabs, and you can zoom into any branch so it fills the screen.
Zoom back out to see the whole workspace again.

## Planned features

- **Docking:** drag a window to a screen edge to dock it. Spaces nest inside spaces to any depth.
- **Pinch zoom:** ⌥ + trackpad pinch zooms in and out of the layout. ⌃⌥Space shows everything.
- **Live previews:** zoomed-out windows show live thumbnails.
- **Tab groups:** stack several windows under one tab strip.
- **Seam resizing:** drag the gap between two windows to resize both.
- **Keyboard navigation:** move focus, zoom, and move windows, all from hotkeys.
- **Menu-bar navigation:** back/forward through the zoom history, plus quick access to saved views.
- **Saved views:** ⌃⌥⇧ + a number saves a view. ⌃⌥ + the number jumps back to it.
- **Multiple displays:** each display keeps its own arrangement, restored after a restart.
- **URL commands:** `fractalwm://view?n=1` and similar URLs let Raycast, Alfred, Shortcuts, Stream Deck or a
  script drive it.
- **Float all:** one command undocks everything and gives you a normal Mac back.
- **Fluid motion:** every split, dock and close glides into place with one shared motion. Moving windows show a
  snapshot, or a color-and-icon placeholder when Screen Recording isn't granted.
- **Setup check:** detects macOS features that fight a window manager (edge tiling, click-wallpaper-to-reveal,
  Stage Manager) and offers to turn them off.

## Requirements

- An Apple silicon Mac (M1 or later)
- macOS 14 Sonoma or later
- Accessibility permission, to move and resize other apps' windows
- Screen Recording permission (optional), for live previews

## How it works

fractalWM is a native Swift/AppKit menu-bar app. It is built in four layers:

| Layer | Role |
| --- | --- |
| **Layout tree** | Pure Swift model of splits, tab groups and windows. Unit-tested with no UI. |
| **Layout engine** | Turns a tree and a screen rectangle into a frame for each window. |
| **Window backend** | `DummyBackend` drives the app's own test windows. `AXBackend` drives real windows through the macOS Accessibility API. |
| **Interaction** | Drag-to-dock overlays, seam handles, hotkeys, pinch gestures, URL commands and the menu bar. |

Because the logic sits behind the `WindowBackend` protocol, nearly everything can be built and tested against
dummy windows before it ever touches a real app.

## Development

The app moves real windows, so it is **built on the host Mac but only ever run inside a macOS virtual machine**.
Building just produces the `.app` file. Neither Xcode nor any developer tools are needed in the VM.

1. On the host, install the Command Line Tools: `xcode-select --install`
2. Install [UTM](https://mac.getutm.app) (`brew install --cask utm`) and create a VM: **Virtualize → macOS 12+**.
   Use a macOS version no newer than the host's.
3. In the VM, turn on **System Settings → General → Sharing → Remote Login**.
4. On the host, run `scripts/vm-ssh-setup.sh` to set up passwordless SSH under the alias `fractalvm`.
5. Build on the host, copy the app over, and run it in the VM:
   ```
   swift build -c release && scripts/bundle.sh
   scripts/run-in-vm.sh
   ```

The kill switch is **⌃⌥⌘F**. It floats all windows and stops managing them.

## Roadmap

- [x] Menu-bar app with a kill switch, and dummy test windows
- [x] Layout tree with unit tests, the layout engine, and placeholder motion
- [ ] Seam resizing and drag-to-dock
- [ ] Tab groups, zoom navigation and keyboard navigation
- [ ] Accessibility backend for real windows
- [ ] Window observers, persistence and multiple displays
- [ ] Saved views, menu-bar navigation and URL commands
- [ ] Pinch zoom, live previews and animated zoom

## Inspiration

- [trelliswm.app](https://trelliswm.app), a fractal window manager for Mac, inspired the concept.
- [Trellis](https://github.com/DanFessler/trellis), a web layout engine, inspired the nested-panel and zoom model.
- [Rectangle](https://github.com/rxhanson/Rectangle), [Amethyst](https://github.com/ianyh/Amethyst) and
  [yabai](https://github.com/koekeishiya/yabai) are references for working with the Accessibility API.

fractalWM is an independent personal project. It is not affiliated with any of the projects above and contains none
of their code.
