#!/bin/sh
# Runs the headless test suite. Works around a Command Line Tools 6.3.1 bug where
# SwiftPM passes the bundled Testing.framework directory with the Linux-style -I/-L
# instead of -F and omits the runpath. With full Xcode installed, plain `swift test`
# works and these flags are harmless.
set -e
CLT=$(xcode-select -p)
if [ -d "$CLT/Library/Developer/Frameworks/Testing.framework" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib" \
    "$@"
fi
exec swift test "$@"
