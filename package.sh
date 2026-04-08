#!/bin/bash
# SPDX-FileCopyrightText: 2024 Joshua Roman
# SPDX-License-Identifier: GPL-2.0-or-later
set -e

PACKAGE_DIR="package"
LOCALE_DIR="$PACKAGE_DIR/contents/locale"
DOMAIN="plasma_applet_com.joshuaroman.plasmallm"

VERSION=$(python3 -c "import json,sys; print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
OUTPUT="PlasmaLLM-${VERSION}.plasmoid"

# Validate and compile .po translation files to binary .mo files
echo "Compiling translations..."
errors=0
for po_file in "$LOCALE_DIR"/*.po; do
    [ -e "$po_file" ] || continue
    lang=$(basename "$po_file" .po)

    # Check for untranslated or fuzzy strings
    untranslated=$(msgattrib --untranslated --no-fuzzy "$po_file" | grep -c '^msgid ' || true)
    fuzzy=$(msgattrib --only-fuzzy "$po_file" | grep -c '^msgid ' || true)

    if [ "$untranslated" -gt 0 ] || [ "$fuzzy" -gt 0 ]; then
        echo "  Error: $lang has $untranslated untranslated and $fuzzy fuzzy string(s)" >&2
        errors=$((errors + 1))
        continue
    fi

    # Check for strings in .pot missing from .po
    missing=$(msgcmp "$po_file" "$LOCALE_DIR/$DOMAIN.pot" 2>&1 | grep -c 'missing' || true)
    if [ "$missing" -gt 0 ]; then
        echo "  Error: $lang is missing $missing string(s) present in the template" >&2
        errors=$((errors + 1))
        continue
    fi

    mo_dir="$LOCALE_DIR/$lang/LC_MESSAGES"
    mkdir -p "$mo_dir"
    msgfmt "$po_file" -o "$mo_dir/$DOMAIN.mo"
    echo "  Compiled $lang"
done

if [ "$errors" -gt 0 ]; then
    echo "Aborting: $errors translation file(s) have errors." >&2
    exit 1
fi

# Build the plasmoid package
rm -f "$OUTPUT"
(cd "$PACKAGE_DIR" && zip -r "../$OUTPUT" .)
echo "Created $OUTPUT"

