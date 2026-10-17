#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Local development artifact only. No uploads, distribution or Developer ID use.
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
TASK_DERIVED_DATA="$TASK_ROOT/build/Universal2/DerivedData"
mkdir -p "$TASK_ROOT/build/Universal2"
rm -f "$TASK_ROOT/build/Universal2/verification.json"
xcodebuild -project Aura/Aura.xcodeproj -scheme Aura -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$TASK_DERIVED_DATA" \
  ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
python3 Scripts/verify-universal.py "$TASK_DERIVED_DATA/Build/Products/Release/AURA.app" \
  > "$TASK_ROOT/build/Universal2/verification.json"
cat "$TASK_ROOT/build/Universal2/verification.json"
