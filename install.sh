#!/bin/bash
set -e

WIDGET_ID="com.joshuaroman.plasmallm"
PACKAGE_DIR="$(cd "$(dirname "$0")/package" && pwd)"

if [ ! -d "$PACKAGE_DIR" ]; then
    echo "Error: package directory not found at $PACKAGE_DIR" >&2
    exit 1
fi

case "$1" in
    --dev)
        echo "Installing PlasmaLLM in dev mode (symlink)..."
        TARGET_DIR="$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"
        mkdir -p "$(dirname "$TARGET_DIR")"
        rm -rf "$TARGET_DIR"
        ln -sfv "$PACKAGE_DIR" "$TARGET_DIR"
        echo "Dev install complete. Restart Plasma to load: plasmashell --replace &"
        ;;
    --remove)
        echo "Removing PlasmaLLM..."
        rm -rf "$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"
        echo "Removed. Restart Plasma to take effect."
        ;;
    *)
        echo "Installing PlasmaLLM..."
        TARGET_DIR="$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"
        mkdir -p "$(dirname "$TARGET_DIR")"
        rm -rf "$TARGET_DIR"
        cp -rv "$PACKAGE_DIR" "$TARGET_DIR"
        echo "Install complete. Restart Plasma to load: plasmashell --replace &"
        ;;
esac
