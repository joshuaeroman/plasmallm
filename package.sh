#!/bin/bash
# SPDX-FileCopyrightText: 2026 Joshua Roman
# SPDX-License-Identifier: GPL-2.0-or-later
set -e

PACKAGE_DIR="package"

VERSION=$(python3 -c "import json,sys; print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
OUTPUT="PlasmaLLM-${VERSION}.plasmoid"

# Extract, merge, validate, and compile translations
./translations.sh

# Build the plasmoid package
rm -f "$OUTPUT"
(cd "$PACKAGE_DIR" && zip -r "../$OUTPUT" . --exclude "contents/locale/*.po" --exclude "contents/locale/*.pot")
echo "Created $OUTPUT"
