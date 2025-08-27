---
mode: agent
---
# Design Guide for DaliMaster
# Collaboration Notice
To facilitate collaboration, the prompt file must be written in English.

# Issue check
- Use `flutter analyze` to get the list of files with issues. Then, for each file, use the problems tool to check for specific problems.

# Test
- Use `flutter test` to run the test suite.
- Aim for high test coverage, especially for critical components.

# API Deprecation Guide
File path: `.github/prompts/deprecated_api_guide.prompt.md`
This file is used for guidance on deprecated APIs. When correcting errors related to deprecated APIs, always check the latest documentation online first. Then, document the API changes and important notes in this file for future reference.


## Repository layout

Use this repository structure when navigating, building automation, or proposing changes. Keep this section in sync when directories are added/removed.

- Root
	- `lib/` — Flutter app source code
		- `auth/` — Casdoor integration, auth services and config
		- `connection/` — device connection logic (USB/Cloud etc.)
		- `dali/` — DALI protocol handling and related models
		- `pages/` — UI pages (e.g., settings, home, login, short address manager)
		- `widgets/` — UI components
        - `utils/` — shared helpers
	- `assets/` — app assets
		- `icon/` — app icons
		- `translations/` — i18n JSONs (e.g., `en.json`, `zh-CN.json`)
	- `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/` — platform targets
	- `test/` — Flutter tests
	- `server/` — Backend service as a Git submodule (independent Go project)
		- `README.md`, `TODO.md` — backend blueprint and notes
	- Config files — `pubspec.yaml`, `analysis_options.yaml`, `firebase.json`, `flutter_launcher_icons.yaml`
	- Tooling — `.github/` (prompts & guides), `.dart_tool/`, `.idea/`, `.gitmodules`

Conventions:
- Keep platform-specific changes scoped to their platform folders.
- Place new shared Dart utilities in `lib/utils/` and reusable UI in `lib/widgets/`.
- Update `assets/translations/` for user-facing text and run localization tooling if applicable.
- Backend changes live in the `server/` submodule; bump the submodule pointer in the parent repo when updating it.

