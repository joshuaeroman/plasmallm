# Makefile for PlasmaLLM

WIDGET_ID := com.joshuaroman.plasmallm
PACKAGE_DIR := package
LOCALE_DIR := $(PACKAGE_DIR)/contents/locale
DOMAIN := plasma_applet_$(WIDGET_ID)

GET_VERSION = grep '"Version"' $(PACKAGE_DIR)/metadata.json | cut -d'"' -f4

PO_FILES := $(wildcard $(LOCALE_DIR)/*.po)
MO_FILES := $(patsubst $(LOCALE_DIR)/%.po,$(LOCALE_DIR)/%/LC_MESSAGES/$(DOMAIN).mo,$(PO_FILES))
SRC_FILES := $(shell find $(PACKAGE_DIR)/contents/ui $(PACKAGE_DIR)/contents/config -type f -name '*.qml' -o -name '*.js')

STANDALONE_DIR := build/standalone
STANDALONE_DATA := $(STANDALONE_DIR)/share/plasmallm
PREFIX ?= $(HOME)/.local
FLATPAK_DIR := build/flatpak
FLATPAK_MANIFEST := flatpak/$(WIDGET_ID).yml
FLATPAK_BUILDER ?= flatpak-builder

.PHONY: all package package-no-i18n do-package translations install install-dev remove clean check-translations test \
	standalone standalone-no-i18n do-standalone install-standalone remove-standalone run-standalone \
	flatpak install-flatpak

all: package

test:
	node tests/wallet_core.mjs
	node tests/gemini_thinking.mjs
	node tests/skills.mjs
	node tests/command_validation.mjs
	node tests/decisions_adapter.mjs
	node tests/memory.mjs
	node tests/path_sandbox.mjs
	node tests/opencode_route.mjs
	node tests/openrouter_attribution.mjs
	node tests/cfg_props.mjs
	node tests/utils.mjs
	node tests/tts.mjs

# Translations
translations: check-translations $(MO_FILES)

$(LOCALE_DIR)/$(DOMAIN).pot: $(SRC_FILES)
	@echo "Extracting translation strings..."
	xgettext --from-code=UTF-8 --language=JavaScript \
		--keyword=i18n \
		--package-name="PlasmaLLM" \
		--no-location \
		-o $@ $^

$(LOCALE_DIR)/%.po: $(LOCALE_DIR)/$(DOMAIN).pot
	@echo "Updating translation file for $*..."
	msgmerge --update --no-fuzzy-matching --backup=none --no-location $@ $<

check-translations: $(PO_FILES)
	@echo "Checking translations..."
	@errors=0; \
	for po in $^; do \
		untranslated=$$(msgattrib --untranslated --no-fuzzy $$po | grep -c '^msgid ' || true); \
		untranslated=$$((untranslated > 0 ? untranslated - 1 : 0)); \
		fuzzy=$$(msgattrib --only-fuzzy $$po | grep -c '^msgid ' || true); \
		fuzzy=$$((fuzzy > 0 ? fuzzy - 1 : 0)); \
		if [ "$$untranslated" -gt 0 ] || [ "$$fuzzy" -gt 0 ]; then \
			echo "Error: $$po has $$untranslated untranslated and $$fuzzy fuzzy string(s)"; \
			if [ "$$untranslated" -gt 0 ]; then \
				msgattrib --untranslated --no-fuzzy --no-wrap $$po | grep '^msgid ' | grep -v '^msgid ""$$' | sed 's/^msgid "//;s/"$$//' | while read -r msg; do \
					escaped=$$(printf '%s' "$$msg" | sed 's/[[\.*^$$()+?{|\\]/\\&/g'); \
					line=$$(grep -n "^msgid \"$$escaped" "$$po" | head -1 | cut -d: -f1); \
					echo "    Line $$line: \"$${msg}\""; \
				done; \
			fi; \
			if [ "$$fuzzy" -gt 0 ]; then \
				msgattrib --only-fuzzy --no-wrap $$po | grep '^msgid ' | grep -v '^msgid ""$$' | sed 's/^msgid "//;s/"$$//' | while read -r msg; do \
					escaped=$$(printf '%s' "$$msg" | sed 's/[[\.*^$$()+?{|\\]/\\&/g'); \
					line=$$(grep -n "^msgid \"$$escaped" "$$po" | head -1 | cut -d: -f1); \
					echo "    Line $$line (fuzzy): \"$${msg}\""; \
				done; \
			fi; \
			errors=$$((errors + 1)); \
		fi; \
	done; \
	if [ "$$errors" -gt 0 ]; then \
		echo "Aborting: $$errors translation file(s) have errors." >&2; \
		exit 1; \
	fi

$(LOCALE_DIR)/%/LC_MESSAGES/$(DOMAIN).mo: $(LOCALE_DIR)/%.po
	@echo "Compiling translation for $*..."
	@mkdir -p $(dir $@)
	msgfmt -o $@ $<

# Package
package: translations do-package

package-no-i18n: do-package

do-package:
	@CURRENT_VERSION=$$($(GET_VERSION)); \
	read -p "Enter new version number (current: $$CURRENT_VERSION) [Press Enter to keep current]: " NEW_VERSION; \
	if [ -n "$$NEW_VERSION" ] && [ "$$NEW_VERSION" != "$$CURRENT_VERSION" ]; then \
		sed -i 's/"Version": "'$$CURRENT_VERSION'"/"Version": "'$$NEW_VERSION'"/' $(PACKAGE_DIR)/metadata.json; \
		echo "Updated metadata.json to version $$NEW_VERSION"; \
		FINAL_VERSION=$$NEW_VERSION; \
	else \
		FINAL_VERSION=$$CURRENT_VERSION; \
	fi; \
	OUTPUT="PlasmaLLM-$${FINAL_VERSION}.plasmoid"; \
	echo "Building package $$OUTPUT..."; \
	rm -f "$$OUTPUT"; \
	cd $(PACKAGE_DIR) && zip -r "../$$OUTPUT" . --exclude "contents/locale/*.po" --exclude "contents/locale/*.pot"; \
	echo "Created $$OUTPUT"

# Standalone app: the plasmoid in its own window (needs KDE Plasma 6 libraries
# and the distro's python3-pyside6). Builds an install tree in $(STANDALONE_DIR)
# plus a relocatable PlasmaLLM-standalone-<version>.tar.gz of it.
standalone: translations do-standalone

standalone-no-i18n: do-standalone

do-standalone:
	@VERSION=$$($(GET_VERSION)); \
	echo "Building standalone PlasmaLLM $$VERSION in $(STANDALONE_DIR)..."; \
	rm -rf $(STANDALONE_DIR); \
	mkdir -p $(STANDALONE_DIR)/bin $(STANDALONE_DATA) $(STANDALONE_DIR)/share/applications $(STANDALONE_DIR)/share/metainfo; \
	install -m 755 standalone/plasmallm.py $(STANDALONE_DIR)/bin/plasmallm; \
	cp -r standalone/qml $(STANDALONE_DATA)/qml; \
	cp -r $(PACKAGE_DIR) $(STANDALONE_DATA)/package; \
	rm -rf $(STANDALONE_DATA)/package/contents/locale; \
	for mo in $(LOCALE_DIR)/*/LC_MESSAGES/$(DOMAIN).mo; do \
		[ -f "$$mo" ] || continue; \
		lang=$$(basename $$(dirname $$(dirname $$mo))); \
		mkdir -p $(STANDALONE_DIR)/share/locale/$$lang/LC_MESSAGES; \
		cp $$mo $(STANDALONE_DIR)/share/locale/$$lang/LC_MESSAGES/; \
	done; \
	install -m 644 standalone/$(WIDGET_ID).desktop $(STANDALONE_DIR)/share/applications/; \
	install -m 644 standalone/$(WIDGET_ID).metainfo.xml $(STANDALONE_DIR)/share/metainfo/; \
	find $(STANDALONE_DIR) -name __pycache__ -prune -exec rm -rf {} +; \
	/usr/bin/python3 -s -m py_compile standalone/plasmallm.py; \
	OUTPUT="PlasmaLLM-standalone-$${VERSION}.tar.gz"; \
	tar -czf "$$OUTPUT" -C $(STANDALONE_DIR) --transform "s,^\.,plasmallm-$${VERSION}," .; \
	echo "Created $$OUTPUT (run $(STANDALONE_DIR)/bin/plasmallm, or: make install-standalone)"

install-standalone:
	@[ -x $(STANDALONE_DIR)/bin/plasmallm ] || { echo "Run 'make standalone' first." >&2; exit 1; }
	@echo "Installing standalone PlasmaLLM into $(PREFIX)..."
	@rm -rf $(PREFIX)/share/plasmallm
	@mkdir -p $(PREFIX)/bin $(PREFIX)/share/applications
	@cp -r $(STANDALONE_DIR)/share/. $(PREFIX)/share/
	@install -m 755 $(STANDALONE_DIR)/bin/plasmallm $(PREFIX)/bin/plasmallm
	@sed -i 's|^Exec=plasmallm|Exec=$(PREFIX)/bin/plasmallm|' $(PREFIX)/share/applications/$(WIDGET_ID).desktop
	@echo "Installed. Launch PlasmaLLM from the app menu or run $(PREFIX)/bin/plasmallm"

remove-standalone:
	@echo "Removing standalone PlasmaLLM from $(PREFIX)..."
	@rm -rf $(PREFIX)/share/plasmallm
	@rm -f $(PREFIX)/bin/plasmallm $(PREFIX)/share/applications/$(WIDGET_ID).desktop
	@rm -f $(PREFIX)/share/metainfo/$(WIDGET_ID).metainfo.xml
	@rm -f $(PREFIX)/share/locale/*/LC_MESSAGES/$(DOMAIN).mo

run-standalone: standalone-no-i18n
	$(STANDALONE_DIR)/bin/plasmallm

# Flatpak of the standalone app, as a single-file PlasmaLLM-<version>.flatpak
# bundle. Needs flatpak-builder and the flathub remote (dependencies such as
# org.kde.Sdk//6.11 and io.qt.PySide.BaseApp//6.11 are installed per-user).
flatpak:
	@VERSION=$$($(GET_VERSION)); \
	$(FLATPAK_BUILDER) --user --install-deps-from=flathub --force-clean --ccache \
		--state-dir=$(FLATPAK_DIR)/state --repo=$(FLATPAK_DIR)/repo \
		$(FLATPAK_DIR)/app $(FLATPAK_MANIFEST) && \
	flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
		$(FLATPAK_DIR)/repo "PlasmaLLM-$${VERSION}.flatpak" $(WIDGET_ID) && \
	echo "Created PlasmaLLM-$${VERSION}.flatpak (install with: make install-flatpak)"

install-flatpak:
	@VERSION=$$($(GET_VERSION)); \
	flatpak install --user -y "PlasmaLLM-$${VERSION}.flatpak"

# Install
install:
	@echo "Installing PlasmaLLM..."
	@mkdir -p $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
	@rm -rf $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
	@cp -rv $(PACKAGE_DIR) $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
	@echo "Install complete. Restart Plasma to load: plasmashell --replace &"

install-dev:
	@echo "Installing PlasmaLLM in dev mode (symlink)..."
	@mkdir -p $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
	@rm -rf $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
	@ln -sfv $$(pwd)/$(PACKAGE_DIR) $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
	@echo "Dev install complete. Restart Plasma to load: plasmashell --replace &"

remove:
	@echo "Removing PlasmaLLM..."
	@rm -rf $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
	@echo "Removed. Restart Plasma to take effect."

clean:
	@echo "Cleaning up..."
	@rm -f PlasmaLLM-*.plasmoid PlasmaLLM-standalone-*.tar.gz PlasmaLLM-*.flatpak
	@rm -rf $(STANDALONE_DIR) $(FLATPAK_DIR)
	@rm -rf $(LOCALE_DIR)/*/LC_MESSAGES/$(DOMAIN).mo
