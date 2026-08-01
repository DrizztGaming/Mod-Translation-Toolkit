# Changelog

## 0.2.8 - 2026-08-01

### Fixed
- Removed the remaining structure-based translation-mod fallback that could still misclassify normal mods such as Missile Girl - Performance Mod.
- A mod is now treated as a translation mod only when its name/packageId explicitly indicates a translation, or when its About.xml contains Mod Translation Toolkit attribution.
- `Languages`, `modDependencies`, `loadAfter`, and a lightweight folder structure are no longer sufficient by themselves to enter translation-edit mode.

## 0.2.7 - 2026-08-01

### Fixed
- Normal mods with a `Languages` folder and `loadAfter` are no longer misclassified as translation mods.
- Fixes cases such as Missile Girl - Performance Mod being incorrectly opened as a translation of Combat Extended.
- Translation-mod detection now requires an explicit translation signal in name/packageId, or a language-only mod structure with a dependency.
- Removed the unsafe final fallback that could select an arbitrary dependency such as Combat Extended or Harmony as the original mod.

## 0.2.6 - 2026-08-01

### Fixed
- Existing translation editing no longer selects Harmony simply because it is the first dependency.
- Original-mod resolution now prioritizes translation packageId suffixes and normalized mod names.
- Common framework/runtime dependencies such as Harmony, HugsLib, Vanilla Expanded Framework and XML Extensions are skipped during normal source detection.
- Framework dependencies are only considered as a final fallback for unusual cases.

## 0.2.5 - 2026-08-01

### Fixed
- Fixed `Cannot overwrite variable PID because it is read-only or constant` when opening an existing translation mod.
- Translation-source resolver no longer uses `$pid`, which conflicts with PowerShell's built-in read-only `$PID` variable.
- Renamed packageId resolver variables to explicit, collision-safe names.

## 0.2.4 - 2026-08-01

### Fixed
- Existing translation mods no longer rely only on `modDependencies` to find their original mod.
- Added fallback resolution through `loadAfter`, `loadBefore`, common translation packageId suffixes and normalized mod names.
- Error messages now include the base name/packageId candidates used during source-mod resolution.
- Editing status shows how the original mod was resolved.

## 0.2.3 - 2026-08-01

### Added
- Existing translation mods can be opened directly from the Installed Mods list.
- The original mod is resolved from `About.xml` dependencies.
- Source entries are scanned from the original mod and the existing translation is overlaid for editing.
- Saving in edit mode updates the same translation mod instead of creating a duplicate.
- Workshop metadata and unrelated files are preserved during in-place updates.

### Fixed
- Generated language output now follows the selected target language folder instead of always writing to `Languages/Polish`.

## 0.2.2 - 2026-08-01

### Fixed
- Fixed the WPF `.Text` error when using **Translate selected mod** after the existing-language UI was added.
- Registered the Polish/English coverage controls correctly.

### Changed
- Source text is now displayed in a selectable read-only text field.
- Original/source strings can be selected and copied with `Ctrl+C` or the standard right-click copy action.
- When the grid itself has focus, `Ctrl+C` copies the source string from the selected row.
- Existing translation auto-fill from v0.2.1 is preserved.

## 0.2.1 - 2026-08-01

### Changed
- Existing localization for the selected target language is now loaded automatically after scanning a mod.
- Switching the target language automatically loads the matching existing localization when available.
- Existing localized strings are preserved, so automatic translation only fills missing entries.
- Manual language-load buttons remain available as reload actions.

## 0.2.0 - 2026-08-01

### Added
- Existing-language detection for both supported languages: Polish and English.
- Detects localization in root folders, versioned folders and paths selected through `LoadFolders.xml`.
- Displays coverage as matched entries / total entries and percentage.
- Classifies localization as missing, partial or complete.
- Existing Polish or English localization can be loaded into the translation table and edited instead of starting from scratch.

## 0.1.9 - 2026-08-01

### Fixed
- RimWorld localization scanning now searches versioned language folders such as `1.6/Languages/English`.
- `LoadFolders.xml` is used when locating active language roots.
- Existing `Keyed` and `DefInjected` XML files are both imported.
- Official English `DefInjected` entries are preferred over fallback extraction from raw `Defs`.
- Fixes incomplete translations in mods such as Hospitality where most localization lives under a versioned `Languages` folder.

## 0.1.8 - 2026-08-01

### Added
- Automatic Steam Workshop description generation in BBCode.
- Generated description includes Description, Requirements, Original Mod, Credits, Mod Translation Toolkit attribution and Support sections.
- GitHub project link is included automatically.
- Ko-fi support link is included automatically.
- Added a `Copy Workshop description` button after generating a translation mod.
- Workshop description is saved as `SteamWorkshopDescription.txt` inside the generated translation mod.

## 0.1.7 - 2026-08-01

### Added
- Generated translation mods now contain permanent attribution in `About/About.xml`.
- The description explicitly states that the translation was created with Mod Translation Toolkit.
- The generated description links to: https://github.com/DrizztGaming/Mod-Translation-Toolkit
- Attribution is intentionally always enabled.

## 0.1.6 - 2026-08-01

### Added
- Optional reuse of the original mod `About/Preview.png`.
- Optional language-flag overlay for generated translation mods.
- Included flag presets: Polish, UK/English, German, French, Spanish, Italian, Czech, Ukrainian, Japanese, Korean, Chinese and Portuguese.
- Preview is generated directly by the toolkit without external flag-image files.

## 0.1.5 - 2026-08-01

### Added
- Placeholder repair workflow.
- Manual mode highlights problematic rows only.
- Automatic mode can repair all detected placeholder issues at once.
- Review mode presents each proposed fix one by one with Yes / No confirmation.
- Build workflow offers placeholder repair before generating a translation mod.

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
