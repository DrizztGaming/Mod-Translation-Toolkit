# Changelog

## 0.1.4 - 2026-08-01

### Fixed
- Language-selection ComboBoxes now use explicit high-contrast colors so their values remain readable on Windows themes that override WPF dark backgrounds.
- Dropdown items now have explicit selected/highlight colors.
- Active tab text is now readable even when native Windows tab chrome overrides the requested purple background.
- Translation / Installed mods / Game profiles tab labels are explicitly localized.

## 0.1.3 - 2026-08-01

### Added
- Startup language selector for the application interface: Polish or English.
- Automatic translation source/target selectors with English and Polish.
- Automatic translation now supports both EN → PL and PL → EN.
- Added `Open mod folder` directly to the translation workspace.

### Preserved
- Dark Mrokar-inspired purple theme.
- Hidden launcher without a visible CMD/PowerShell window.
- Installed-mod browser and existing `Open mod folder` action.

## 0.1.2 - 2026-08-01

### Fixed
- RimWorld scan no longer treats `Languages/English` and `Defs` as mutually exclusive.
- Versioned mod content is discovered through `LoadFolders.xml`.
- The newest supported content version is selected by default, preventing duplicate DefInjected keys from 1.4/1.5/1.6 copies.
- Translation entries are deduplicated before XML generation.
- Generated XML trims trailing whitespace from translated/source values.
- Generated translation `About.xml` now copies `supportedVersions`.
- Generated dependency metadata now includes `steamWorkshopUrl` when the source mod is from Workshop, with a `downloadUrl` fallback.
- Added `TranslationBuildReport.txt` to generated translations for easier diagnostics.
- Existing hidden launcher, dark purple theme and “Otwórz folder moda” remain unchanged.

## 0.1.1 - 2026-08-01

### Fixed
- Duplicate Workshop/local mod rows caused by the same Steam library being discovered more than once.
- Mod deduplication now uses normalized full paths.
- `modVersion` is now read through XML node text, preventing `System.Xml.XmlElement` from appearing in the version column.

## 0.1.0 - 2026-08-01

First GitHub-oriented release.

### Added
- Dark graphite interface.
- Purple Mrokar-inspired accent theme.
- Hidden Windows launcher, no visible CMD/PowerShell console.
- RimWorld profile.
- Steam library and Workshop detection.
- Installed mod browser and search.
- `Languages/English` scanning.
- Basic fallback extraction from RimWorld `Defs`.
- CSV import/export.
- Optional automatic EN → PL translation.
- Placeholder validation.
- Separate Polish translation mod builder.
- GitHub-ready repository structure.
