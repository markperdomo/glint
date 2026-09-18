#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Release}"
xcodebuild -project Glint.xcodeproj -scheme Glint -configuration "$configuration" \
    -derivedDataPath build CODE_SIGN_IDENTITY=- build
echo "App: $(pwd)/build/Build/Products/$configuration/Glint.app"
