#!/bin/bash
# The Xcode named by XCODE in ci/app.env (or the newest, when unset). Never a beta: TestFlight
# rejects beta builds, and the runner's plain Xcode_27.2.app can be a symlink to one.
set -euo pipefail
source ci/app.env
release() { for x in "$@"; do [ -e "$x" ] || continue; r=$(readlink -f "$x"); case "$r" in *[Bb]eta*) ;; *) echo "$r" ;; esac; done; }
if [ -n "${XCODE:-}" ]; then
  X=$(release /Applications/Xcode_"$XCODE".app | head -1)
  [ -n "$X" ] || { echo "::error::Xcode $XCODE (release) isn't on this runner:"; ls -d /Applications/Xcode_*.app; exit 1; }
else
  X=$(release /Applications/Xcode_*.app | sort -uV | tail -1)
fi
sudo xcode-select -s "$X/Contents/Developer"
xcodebuild -version
