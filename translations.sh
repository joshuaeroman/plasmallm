#!/bin/bash
# SPDX-FileCopyrightText: 2026 Joshua Roman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Extract i18n() strings from source, merge into .po files, validate, and compile.
# Can be run standalone or called from package.sh.
set -e

PACKAGE_DIR="package"
LOCALE_DIR="$PACKAGE_DIR/contents/locale"
DOMAIN="plasma_applet_com.joshuaroman.plasmallm"

# Extract i18n() strings from source into .pot
echo "Extracting translation strings..."
xgettext --from-code=UTF-8 --language=JavaScript \
    --keyword=i18n --keyword=i18n:1,2 \
    --package-name="PlasmaLLM" \
    -o "$LOCALE_DIR/$DOMAIN.pot" \
    "$PACKAGE_DIR"/contents/ui/*.qml "$PACKAGE_DIR"/contents/ui/*.js "$PACKAGE_DIR"/contents/config/*.qml
echo "  Updated $DOMAIN.pot"

# Merge new strings into each .po file
echo "Updating translation files..."
for po_file in "$LOCALE_DIR"/*.po; do
    [ -e "$po_file" ] || continue
    lang=$(basename "$po_file" .po)
    msgmerge --update --no-fuzzy-matching --backup=none "$po_file" "$LOCALE_DIR/$DOMAIN.pot"
    echo "  Merged $lang"
done

# Validate and compile .po translation files to binary .mo files
echo "Compiling translations..."
errors=0
for po_file in "$LOCALE_DIR"/*.po; do
    [ -e "$po_file" ] || continue
    lang=$(basename "$po_file" .po)

    # Check for untranslated or fuzzy strings (subtract 1 for the header entry)
    untranslated_raw=$(msgattrib --untranslated --no-fuzzy "$po_file" | grep -c '^msgid ' || true)
    untranslated=$((untranslated_raw > 0 ? untranslated_raw - 1 : 0))
    fuzzy=$(msgattrib --only-fuzzy "$po_file" | grep -c '^msgid ' || true)

    if [ "$untranslated" -gt 0 ] || [ "$fuzzy" -gt 0 ]; then
        echo "  Error: $lang has $untranslated untranslated and $fuzzy fuzzy string(s)" >&2
        # Report untranslated strings with line numbers
        if [ "$untranslated" -gt 0 ]; then
            msgattrib --untranslated --no-fuzzy --no-wrap "$po_file" \
                | grep '^msgid ' | grep -v '^msgid ""$' | sed 's/^msgid "//;s/"$//' \
                | while IFS= read -r msgid_text; do
                    escaped=$(printf '%s' "$msgid_text" | sed 's/[[\.*^$()+?{|\\]/\\&/g')
                    po_line=$(grep -n "^msgid \"$escaped" "$po_file" | head -1 | cut -d: -f1)
                    display="$msgid_text"
                    [ ${#display} -gt 80 ] && display="${display:0:77}..."
                    echo "    Line $po_line: \"$display\"" >&2
                done
        fi
        # Report fuzzy strings with line numbers
        if [ "$fuzzy" -gt 0 ]; then
            msgattrib --only-fuzzy --no-wrap "$po_file" \
                | grep '^msgid ' | grep -v '^msgid ""$' | sed 's/^msgid "//;s/"$//' \
                | while IFS= read -r msgid_text; do
                    escaped=$(printf '%s' "$msgid_text" | sed 's/[[\.*^$()+?{|\\]/\\&/g')
                    po_line=$(grep -n "^msgid \"$escaped" "$po_file" | head -1 | cut -d: -f1)
                    display="$msgid_text"
                    [ ${#display} -gt 80 ] && display="${display:0:77}..."
                    echo "    Line $po_line (fuzzy): \"$display\"" >&2
                done
        fi
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
