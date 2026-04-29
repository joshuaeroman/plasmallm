# Makefile for PlasmaLLM

WIDGET_ID := com.joshuaroman.plasmallm
PACKAGE_DIR := package
LOCALE_DIR := $(PACKAGE_DIR)/contents/locale
DOMAIN := plasma_applet_$(WIDGET_ID)

GET_VERSION = grep '"Version"' $(PACKAGE_DIR)/metadata.json | cut -d'"' -f4

PO_FILES := $(wildcard $(LOCALE_DIR)/*.po)
MO_FILES := $(patsubst $(LOCALE_DIR)/%.po,$(LOCALE_DIR)/%/LC_MESSAGES/$(DOMAIN).mo,$(PO_FILES))
SRC_FILES := $(shell find $(PACKAGE_DIR)/contents/ui $(PACKAGE_DIR)/contents/config -type f -name '*.qml' -o -name '*.js')

.PHONY: all package translations install install-dev remove clean check-translations

all: package

# Translations
translations: $(MO_FILES)

$(LOCALE_DIR)/$(DOMAIN).pot: $(SRC_FILES)
	@echo "Extracting translation strings..."
	xgettext --from-code=UTF-8 --language=JavaScript \
		--keyword=i18n --keyword=i18n:1,2 \
		--package-name="PlasmaLLM" \
		-o $@ $^

$(LOCALE_DIR)/%.po: $(LOCALE_DIR)/$(DOMAIN).pot
	@echo "Updating translation file for $*..."
	msgmerge --update --no-fuzzy-matching --backup=none $@ $<

check-translations: $(PO_FILES)
	@echo "Checking translations..."
	@errors=0; \
	for po in $^; do \
		untranslated=$$(msgattrib --untranslated --no-fuzzy $$po | grep -c '^msgid ' || true); \
		untranslated=$$((untranslated > 0 ? untranslated - 1 : 0)); \
		fuzzy=$$(msgattrib --only-fuzzy $$po | grep -c '^msgid ' || true); \
		if [ "$$untranslated" -gt 0 ] || [ "$$fuzzy" -gt 0 ]; then \
			echo "Error: $$po has $$untranslated untranslated and $$fuzzy fuzzy string(s)"; \
			if [ "$$untranslated" -gt 0 ]; then \
				msgattrib --untranslated --no-fuzzy --no-wrap $$po | grep '^msgid ' | grep -v '^msgid ""$$' | sed 's/^msgid "//;s/"$$//' | while read -r msg; do \
					escaped=$$(printf '%s' "$$msg" | sed 's/[[\.*^$$()+?{|\\]/\\&/g'); \
					line=$$(grep -n "^msgid \"$$escaped" "$$po" | head -1 | cut -d: -f1); \
					echo "    Line $$line: \"$${msg:0:77}...\""; \
				done; \
			fi; \
			if [ "$$fuzzy" -gt 0 ]; then \
				msgattrib --only-fuzzy --no-wrap $$po | grep '^msgid ' | grep -v '^msgid ""$$' | sed 's/^msgid "//;s/"$$//' | while read -r msg; do \
					escaped=$$(printf '%s' "$$msg" | sed 's/[[\.*^$$()+?{|\\]/\\&/g'); \
					line=$$(grep -n "^msgid \"$$escaped" "$$po" | head -1 | cut -d: -f1); \
					echo "    Line $$line (fuzzy): \"$${msg:0:77}...\""; \
				done; \
			fi; \
			errors=$$((errors + 1)); \
		fi; \
	done; \
	if [ "$$errors" -gt 0 ]; then \
		echo "Aborting: $$errors translation file(s) have errors." >&2; \
		exit 1; \
	fi

$(LOCALE_DIR)/%/LC_MESSAGES/$(DOMAIN).mo: $(LOCALE_DIR)/%.po | check-translations
	@echo "Compiling translation for $*..."
	@mkdir -p $(dir $@)
	msgfmt -o $@ $<

# Package
package: translations
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
	@rm -f PlasmaLLM-*.plasmoid
	@rm -rf $(LOCALE_DIR)/*/LC_MESSAGES/$(DOMAIN).mo
