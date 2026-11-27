#!/usr/bin/env bash
# Runs the FractalCore unit tests on the host. They are pure logic and never touch windows.
# Command Line Tools ship Swift Testing outside the default search path (Xcode adds it
# automatically), so point the compiler and linker at it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FRAMEWORKS="$DEV/Library/Developer/Frameworks"
LIBS="$DEV/Library/Developer/usr/lib"

swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$LIBS" \
  "$@"
