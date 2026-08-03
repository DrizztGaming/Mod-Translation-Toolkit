# Changelog

## 0.8.0 - 2026-08-03

### Project Zomboid experimental foundation
- Added a new `Project Zomboid Mod` profile.
- Detects standard `media/lua/shared/Translate/<LANG>` translation folders.
- Supports common Build 41 layouts and Build 42 versioned mod folders such as `42/` and `42.x/`.
- Can scan a direct mod folder or a Workshop item containing `mods/<mod-name>/...`.
- Added multilingual source/target selectors for common Project Zomboid language codes.
- Loads existing target translations and shows matched entries in the translation grid.
- Added manual editing, automatic translation, CSV export and CSV import.
- CSV matching uses root + file + key.
- v0.8.0 intentionally handles only standard `key = "value"` translation tables.
- Structured formats such as `Recorded_Media_*` are intentionally skipped until a dedicated parser is added.
- Translation-mod packaging for Project Zomboid is not enabled yet.

## 0.7.8 - 2026-08-03

### LibreTranslate UTF-8 fix
- Reworked LibreTranslate HTTP handling for Windows PowerShell 5.1.
- The Toolkit now reads LibreTranslate responses as raw bytes and decodes them explicitly as UTF-8 before JSON parsing.
- This avoids legacy-codepage corruption such as `MoÅ¼na`, `biaÅ‚e`, `dostÄ™pnych`, etc.
- Existing mojibake repair remains as a guarded fallback only.
- LibreTranslate error responses are also decoded as UTF-8 when possible.

## 0.7.7 - 2026-08-03

### Startup regression fix
- Fixed a Windows PowerShell 5.1 startup/parser regression introduced by the v0.7.6 LibreTranslate mojibake helper.
- Replaced the risky UTF8Encoding constructor syntax with PowerShell 5.1-safe `New-Object -ArgumentList`.
- Reworked mojibake detection so the PowerShell source stays ASCII-only and does not contain embedded C1 control characters.
- LibreTranslate encoding repair remains guarded and only accepts a conversion when the suspicion score improves.

## 0.7.6 - 2026-08-03

### Stable candidate
- Added guarded mojibake repair for LibreTranslate responses.
- Repairs common UTF-8-as-Windows-1252 corruption such as `PokaÅ¼` → `Pokaż`, `UÅ¼yj` → `Użyj`, and `bÄ™dzie` → `będzie`.
- Repair is heuristic and only applied when suspicious mojibake markers are detected and the converted text scores better than the original.
- Correctly decoded LibreTranslate text is left untouched.
- Placeholder restoration still runs after encoding repair.
- Prepared GitHub-ready stable package and release notes for v0.7.6.

## 0.7.5 - 2026-08-03

### RimWorld Game CSV workflow
- Added CSV export for scanned RimWorld Core and DLC entries.
- CSV includes Module, Type, File, Key, Source, Translation, SourceLanguage and TargetLanguage.
- Added CSV import back into the RimWorld Game scan.
- Import matches rows by Module + Type + Key, so translations are restored to the correct Core/DLC entries.
- Added source/target language metadata mismatch warning.
- Import requires a current RimWorld Game scan, preventing a CSV from silently replacing unrelated game data.
- Export/import buttons follow the PL/EN interface language.

## 0.7.4 - 2026-08-02

### Windows smoke-test fixes
- Fixed RimWorld Mod CSV export/import crash caused by helper names colliding with PowerShell built-in cmdlets.
- Creator name is restored from the saved Workshop profile on startup and copied into the translation author field.
- Fixed a broken creator-profile reference to a non-existent `txtTranslator` control.
- Fresh translation builds now consistently use the selected target language in the folder and `About.xml` display name.
- RimWorld Game copies official `.tar` language archives to an ASCII-only temporary filename before `tar.exe` extraction, improving accented, Cyrillic and CJK archive handling.
- Failed RimWorld Game scans clear stale rows/counts/tooltips from the previous language.

## 0.7.3 - 2026-08-02

### UI language fixes
- Fixed Game Profiles becoming empty after switching to English.
- Tab localization now changes `TabItem.Header` instead of overwriting `TabItem.Content`.
- Connected remaining RimWorld Game labels/buttons/status text to the central PL/EN localization layer.
- RimWorld Game static grid headers now localize while source/target language columns keep the selected language names.

### Translation API language check
- Reworked **Check languages / Sprawdź języki** to avoid testing every registered source/target pair individually.
- Google now uses one language-capabilities request.
- DeepL uses one source-list and one target-list request.
- LibreTranslate uses one `/languages` request.
- Added visible `Checking... / Sprawdzanie...` state.
- Reduced provider capability timeout to 8 seconds.
- Button is always restored after success or failure.

## 0.7.2 - 2026-08-02

### Critical startup fix
- Fixed a WPF XAML layout error introduced with the Creator ID row.
- A `Border` accidentally contained two direct child controls; WPF `Border` supports only one child.
- Wrapped the coverage row and Creator ID row in a parent `StackPanel`.
- This fixes the application failing to open in v0.7.0/v0.7.1.

### Validation
- Added a semantic WPF layout check for single-child controls such as `Border`.

## 0.7.1 - 2026-08-02

### Stability / regression fixes
- Removed a duplicate `Get-SelectedTargetLanguageCode` definition left during the multilingual migration.
- RimWorld Mod CSV exports now reliably include `SourceLanguage` and `TargetLanguage` while preserving Def metadata and semicolon delimiters.
- CSV import remains backward compatible with older files that do not contain language metadata.
- When language metadata is present and differs from the current selection, Toolkit shows a warning but still allows import.
- Clarified that Kenshi automatic translation is intentionally still English → Polish pending its separate multilingual migration.

### Validation
- Re-ran static package, XAML, registry, packageId, provider and synthetic RimWorld localization tests after the fixes.

## 0.7.0 - 2026-08-02

### Multilingual milestone
- Completed the first full multilingual architecture migration.
- Translation-mod naming and metadata follow the selected target language.
- Workshop descriptions include target language information and generated packageId.
- Preview flag selection follows the selected target language preset.
- Build reports include source/target language, Creator ID and generated packageId.

### PackageId / creator identity
- Added persistent Creator ID.
- Generated package IDs use `<original.packageId>.<creatorId>.<language>`.
- Creator and language components are normalized to safe lowercase alphanumeric values.

### CSV
- RimWorld Mod CSV exports include `SourceLanguage` and `TargetLanguage`.
- Kenshi CSV exports include explicit source/target metadata.

### Validation
- Added an internal multilingual configuration self-test.
- Checks registry completeness, duplicate RimWorld folders and generated packageId format.

## 0.6.4 - 2026-08-02

### Automatic translation language validation
- Added provider-aware source/target language validation before automatic translation.
- Unsupported language pairs are blocked before translation begins.
- Added localized error messages explaining why a pair cannot be used.

### Google Cloud Translation
- Uses the central language registry mappings for source and target codes.

### DeepL
- Queries `/v2/languages` for current source and target language capabilities.
- Caches capability results for the current Toolkit session.
- Added role-aware handling for language variants such as English, Portuguese/Brazilian Portuguese and Chinese.
- Resolves provider-returned regional/script variants when API naming differs from the Toolkit registry.

### LibreTranslate
- Queries `/languages` on the configured LibreTranslate server.
- Validates the actual source → target pair exposed by that server.
- Works with different self-hosted servers whose installed language models may differ.

### API settings
- Added **Check languages / Sprawdź języki**.
- Provider capability cache is cleared when API settings are changed.

## 0.6.3 - 2026-08-02

### RimWorld Game multilingual migration
- Added independent source and target language selectors to RimWorld Game.
- Core and DLC scanning now uses the central language registry.
- Official language folders and `.tar` archives are resolved for arbitrary registered languages.
- Keyed and DefInjected matching is now source/target-role based rather than hardcoded English/Polish.
- Result-grid language column headers update to the selected languages.
- Scan counters and status messages report the selected target language dynamically.
- Source and target cannot be the same language.

### Language detection
- Reworked RimWorld language aliases to use code, English name, native name and RimWorld folder name.
- Preserved strict token matching for short language codes to prevent false matches such as the old `pl` / `ChineseSimplified` issue.
- Added common aliases for Brazilian Portuguese, Simplified/Traditional Chinese and Czech.

### Source behavior
- English Core/DLC source still generates DefInjected entries from game `Defs`.
- Non-English source uses only the selected official localization and does not mix English Defs.

## 0.6.2 - 2026-08-02

### RimWorld Mod multilingual migration
- RimWorld Mod now resolves the selected source localization dynamically.
- Existing localizations are scanned for every registered language.
- Changing the source language rescans the loaded mod.
- Changing the target language refreshes coverage and loads an existing target localization when available.
- Generated translation files use the selected target RimWorld folder.
- Translation-mod naming, Workshop suffix and About.xml description follow the target language.
- PackageId language suffixes are normalized for codes such as `pt-br`.

### Source handling
- English source continues to combine localization files with Def-derived source entries.
- Non-English source uses the selected localization without silently mixing English Def text.

### Coverage
- Coverage storage is no longer limited to Polish and English.
- Existing coverage slots show the selected source and target languages.

### Scope
- RimWorld Game/Core/DLC multilingual migration remains the next step.

## 0.6.1 - 2026-08-02

### Language architecture
- Added a central language registry.
- Each language now defines:
  - Toolkit language code
  - English/native display name
  - RimWorld language folder name
  - Google translation code
  - DeepL translation code
  - LibreTranslate code
  - flag preset
- Source/target ComboBoxes are now populated dynamically from the registry.
- Removed the hardcoded English/Polish ComboBox entries.
- `Get-LanguageFolderName` now resolves through the registry.
- Translation providers now resolve their language codes through the registry.

### Languages included in the first registry
- English
- Polish
- German
- French
- Spanish
- Italian
- Portuguese
- Brazilian Portuguese
- Czech
- Ukrainian
- Russian
- Japanese
- Korean
- Simplified Chinese
- Traditional Chinese
- Dutch
- Swedish

### Scope
- This release only introduces the language layer.
- RimWorld Mod and RimWorld Game still need the next migration stages before every workflow can fully save/load arbitrary target languages.

## 0.6.0 - 2026-08-02

### Folder picker / UX
- Added centralized `Show-ModernFolderPicker`.
- Enabled the upgraded Windows shell folder-selection experience where supported by the installed .NET/Windows version.
- Modernized folder selection for:
  - RimWorld Game
  - RimWorld Mod
  - Kenshi Game
  - translation-mod output folder
  - existing-translation update workflow
- Existing-translation path dialogs now include **Browse...** / **Przeglądaj...** in addition to paste and drag-and-drop.
- Folder pickers open from the currently entered/selected path when possible.

### Compatibility
- Uses the built-in Windows/.NET folder dialog and falls back gracefully when the upgraded shell mode is unavailable.
- No external UI library is required.

## 0.5.9 - 2026-08-02

### UI localization
- Added a central Polish/English UI text dictionary.
- Central localization is now applied across:
  - Game Profiles
  - RimWorld Game
  - RimWorld Mod
  - Translation
  - Installed Mods
  - Workshop
  - Kenshi Game
  - Translation API controls
- Newly added controls no longer need ad-hoc English text assignments to be usable in English mode.

### UI readability
- Reworked `ComboBoxItem` styling with an explicit control template.
- Improved contrast for normal, highlighted and selected dropdown rows.
- Fixed the long-standing issue where opened ComboBox items could become difficult to read on some Windows themes.

### Architecture
- Added `T()` helper and centralized UI text lookup as groundwork for future multi-language interface support.

## 0.5.8 - 2026-08-02

### Added
- Added selectable automatic translation providers:
  - Google Cloud Translation
  - DeepL API
  - LibreTranslate
- Added DeepL API Free / API Pro endpoint selection.
- Added configurable LibreTranslate endpoint and optional API key.
- Self-hosted LibreTranslate can be used without an API key when the server allows it.
- Added provider-specific setup instructions in Polish and English.
- Added migration of the previous Google-only API key into the new provider settings.

### Security
- Google requests now send the API key through the `X-goog-api-key` header instead of placing it in the URL.
- Google, DeepL and LibreTranslate credentials remain encrypted locally with Windows DPAPI.
- No shared Toolkit translation API key is bundled.

### Changed
- Automatic translation now routes through the provider selected in **API / Translation** settings.
- Provider-specific cost/quota warnings replace the previous Google-only warning.

## 0.5.7 - 2026-08-02

### Changed
- Automatic translation now requires the user's own Google Cloud Translation API key.
- Removed the unofficial public Google Translate endpoint.
- RimWorld Mod and Kenshi automatic translation use the official Google Cloud Translation API v2 endpoint.

### Added
- Added **API Settings** to the main Toolkit header.
- Added local API-key storage encrypted with Windows DPAPI for the current Windows user.
- Added **How to get an API key** instructions in Polish and English.
- Added clear billing/quota warning: Google Cloud usage is billed to the owner of the configured key.
- Automatic translation opens API Settings when no key is configured.

### Security
- The API key is not stored as plain text.
- The Toolkit does not bundle or provide a shared translation API key.
- The key is sent only to Google's Translation API when automatic translation is used.

## 0.5.6 - 2026-08-02

### Fixed
- Fixed RimWorld Game scans exposing almost exclusively `Keyed` entries.
- Core/DLC `DefInjected` source is now generated directly from the module's `Defs` instead of assuming a complete English `Languages/English/DefInjected` mirror exists.
- Generated DefInjected keys use the standard `defName.field` format and are matched against the official target-language DefInjected data.
- Explicit English DefInjected files are still merged in when present.
- Source entries are deduplicated by module + type + key.

### Diagnostics
- RimWorld Game counters now show separate totals for `Keyed`, `DefInjected`, and matched target-language entries.
- Per-module status tooltip now reports Keyed and DefInjected counts separately.

### Scope
- This release intentionally focuses only on the RimWorld Game DefInjected issue. UI localization, additional target languages and folder-picker modernization are reserved for later steps.

## 0.5.5 - 2026-08-02

### Fixed
- Fixed RimWorld Game language matching where the Polish alias `pl` could incorrectly match filenames such as `ChineseSimplified`.
- Short language codes such as `pl` and `en` are now matched only as standalone tokens.
- Full language names still support formats such as `Polish (Polski)` and `English (English)`.

### Result
- RimWorld Game should now resolve the actual Polish archive instead of accidentally selecting unrelated language files.

## 0.5.4 - 2026-08-02

### Fixed
- RimWorld Game scan is now wrapped in a full safety handler. Scan errors show a dialog instead of closing the Toolkit.
- Reworked official `.tar` language extraction to use a simpler native `tar.exe` invocation.
- Removed the previous custom redirected-process implementation that could fail unpredictably on some Windows setups.
- Added validation of `tar.exe` exit code and clearer archive-specific error messages.
- Scan button is temporarily disabled while scanning and restored afterward.

## 0.5.3 - 2026-08-02

### Fixed
- RimWorld Game now detects official language archives such as `Polish (Polski).tar`.
- Official translations are no longer assumed to be loose directories.
- `.tar` archives are extracted read-only to a temporary Toolkit cache and scanned for `Keyed` and `DefInjected`.
- Loose language folders remain supported.
- Language archive cache is keyed by archive path + modification time, so unchanged archives are not repeatedly extracted.
- Per-module diagnostics now show the resolved Polish language source path.

### Safety
- RimWorld installation files and language `.tar` archives are never modified.

## 0.5.2 - 2026-08-02

### Fixed
- RimWorld Game no longer assumes that Polish localization must live in a folder named exactly `Languages/Polish`.
- Language folders are now detected from `LanguageInfo.xml` where possible, with folder-name aliases as fallback.
- Added aliases for Polish / Polski / PL and English / EN.

### Added
- RimWorld Game now scans `Keyed` and `DefInjected` separately.
- Entries are matched by module + type + key, reducing incorrect matches.
- Scan status now reports total English entries, Polish entries found and matched entries.
- Per-module scan details are available as a tooltip on the status line and explicitly report when Polish localization was not found.

## 0.5.1 - 2026-08-02

### Fixed
- **Copy Workshop description** no longer requires a translation mod to be built first.
- The button can now generate and copy the Workshop BBCode directly from the currently loaded RimWorld mod.
- If a generated `SteamWorkshopDescription.txt` already exists, Toolkit still uses that file.
- Added a clear message when the button is pressed without a RimWorld mod loaded.

## 0.5.0 - 2026-08-02

### UI
- Rebuilt top-level navigation around **Profile gier** and **Workshop**.
- **Profile gier** now contains **RimWorld Game**, **RimWorld Mod**, and **Kenshi Game**.
- **RimWorld Mod** contains the existing **Tłumaczenie** and **Zainstalowane mody** workspaces.
- Existing RimWorld mod, Workshop and Kenshi functionality is preserved in the new hierarchy.

### RimWorld Game
- Added automatic RimWorld installation detection.
- Added manual folder selection, paste/Enter and drag-and-drop path workflow.
- Detects Core and installed DLC/data modules.
- Added Select all / Core only / DLC only controls.
- Added first per-module localization scan for English and Polish Keyed XML.
- Added Module column so entries remain attributable when multiple DLC are scanned together.

### Notes
- RimWorld Game v0.5.0 is the first functional stage. DefInjected/Defs scanning, official-translation comparison and update-diff tooling are planned next.

