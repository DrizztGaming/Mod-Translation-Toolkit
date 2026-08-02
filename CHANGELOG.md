# Changelog

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

