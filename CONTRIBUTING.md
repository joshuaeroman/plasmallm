# Contributing to PlasmaLLM

Thanks for your interest in contributing to PlasmaLLM! This document covers guidelines for submitting changes.

## Getting Started

1. Fork the repository and clone your fork
2. Install for development: `./install.sh --dev`
3. Restart Plasma to see changes: `plasmashell --replace &`
4. View logs: `journalctl -u plasmashell --follow`

There is no build step, test suite, or linter for dev mode. QML is interpreted at runtime.

> **Note:** Run `./install.sh --remove` before switching back to a release version from [GitHub](https://github.com/joshuaeroman/plasmallm/releases) or the [KDE Store](https://store.kde.org/p/2348409/) to remove the development symlink.

## Submitting Changes

- Create a feature branch from `master` (`feature/<description>` or `fix/<description>`)
- Keep commits focused — one logical change per PR
- Include SPDX headers on new files: `SPDX-FileCopyrightText: 2026 Joshua Roman`
- Test your changes by restarting Plasma and verifying the feature works

## Code Style

- Use `var` for variable declarations and the `function` keyword (not arrows) — QML JS standard
- Use theme colors from `Kirigami.Theme`, not hardcoded values
- Import order: Qt, KDE Plasma, P5Support, Kirigami, local JS
- Avoid external dependencies

## Translations

Translations are welcome but **not required** in code contributions. If your change adds or modifies user-facing strings (anything wrapped in `i18n()`), you do not need to update the `.po` translation files. The maintainer will review and add missing translations using LLM-assisted tooling when packaging releases.

If you do want to contribute translations — especially native speaker corrections to existing ones — those PRs are appreciated along with an explanation of why the translation is more correct. Translation files are in `package/contents/locale/`.

## Reporting Issues

Open an issue on GitHub with steps to reproduce. Include your Plasma version, distribution, and any relevant log output from `journalctl`.
