#!/usr/bin/env bash
# Patches DankMaterialShell to fix the 1px gap between the left bar and screen edge
# at 1.5x fractional scale. Re-run after quickshell/dms package updates.

TARGET="/usr/share/quickshell/dms/Modules/DankBar/DankBarWindow.qml"
OLD='axis.edge === "left" ? spacingPx : 0'
NEW='axis.edge === "left" ? spacingPx - 1 : 0'
APPLIED='axis.edge === "left" ? spacingPx - 1'

if ! grep -qF "$OLD" "$TARGET"; then
    if grep -qF "$APPLIED" "$TARGET"; then
        echo "Already patched: $TARGET"
    else
        echo "ERROR: Expected pattern not found — file may have changed upstream." >&2
        exit 1
    fi
    exit 0
fi

sudo sed -i 's/axis\.edge === "left" ? spacingPx : 0/axis.edge === "left" ? spacingPx - 1 : 0/' "$TARGET"
echo "Patched: $TARGET"
