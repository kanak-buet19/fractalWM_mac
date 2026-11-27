// Run inside the VM with: osascript -l JavaScript - < scripts/vm-windows.js
// Prints fractalWM's on-screen window frames (top-left origin), the main screen and lock state.
// Needs no permissions.
ObjC.import("CoreGraphics");
ObjC.import("AppKit");

const list = ObjC.deepUnwrap(
  ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0))
);
const mine = list
  .filter((w) => w.kCGWindowOwnerName === "fractalWM" && w.kCGWindowLayer === 0)
  .map((w) => {
    const b = w.kCGWindowBounds;
    return `x=${b.X} y=${b.Y} w=${b.Width} h=${b.Height}`;
  })
  .sort();

const screen = $.NSScreen.mainScreen;
const f = screen.frame;
const v = screen.visibleFrame;
const locked = list.some((w) => w.kCGWindowOwnerName === "loginwindow" && w.kCGWindowLayer >= 2000);

[
  `fractalWM windows: ${mine.length}`,
  ...mine.map((s) => "  " + s),
  `screen:  ${f.size.width}x${f.size.height}`,
  `visible: x=${v.origin.x} y=${v.origin.y} w=${v.size.width} h=${v.size.height} (AppKit, bottom-left)`,
  `locked:  ${locked}`,
].join("\n");
