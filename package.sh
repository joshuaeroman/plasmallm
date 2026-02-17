#!/bin/bash
# SPDX-FileCopyrightText: 2024 Joshua Roman
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
VERSION=$(python3 -c "import json,sys; print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
OUTPUT="PlasmaLLM-${VERSION}.plasmoid"
rm -f "$OUTPUT"
(cd package && zip -r "../$OUTPUT" .)
echo "Created $OUTPUT"
