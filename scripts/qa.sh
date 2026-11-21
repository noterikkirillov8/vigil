#!/usr/bin/env bash
# Builds Debug and renders every panel, settings and intro frame to qa/ with fake data. Off-screen only: no window,
# no status item, no controller, so nothing can touch power settings.
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData/VigilDev"
(cd Vigil && xcodegen >/dev/null && xcodebuild -scheme Vigil -configuration Debug -derivedDataPath "$DERIVED" -quiet build)
APP="$DERIVED/Build/Products/Debug/Vigil.app/Contents/MacOS/Vigil"
rm -rf qa; mkdir qa
"$APP" -qa qa
"$APP" -intro-preview qa
echo "Rendered $(command ls qa | wc -l | tr -d ' ') PNGs in qa/"
