# Mod Translation Toolkit v0.7.6

## Stable multilingual release

v0.7.6 is the stable candidate following the multilingual migration and Windows smoke testing.

### Highlights
- RimWorld Game: multilingual Core/DLC scanning
- RimWorld Game: CSV export/import workflow
- RimWorld Mod: multilingual source/target workflow
- Translation mod packaging with language-aware names and package IDs
- Preview flag selection follows target language
- Existing translation update workflow
- Workshop description generation
- Creator ID and Creator name persistence
- Google Cloud, DeepL API and LibreTranslate support
- Provider language capability checks
- Kenshi base-game translation workflow
- PL/EN interface
- Modern folder selection
- DLL/UI and keybinding diagnostics

### v0.7.6 fix
LibreTranslate responses now receive a guarded encoding repair pass for common UTF-8/Windows-1252 mojibake. Correct text is preserved; repair only applies when the result is measurably cleaner.

### Validation
This release follows manual Windows smoke testing of the major RimWorld, Kenshi, CSV, Workshop, language-selection, build and provider-check workflows.
