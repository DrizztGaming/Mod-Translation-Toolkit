# Mod Translation Toolkit v0.8.8 Experimental

## Project Zomboid validation and coverage update

### Fixed
- Missing API/provider no longer leaves the UI appearing frozen.
- Project Zomboid formatting tags are protected and restored 1:1.
- Broken placeholder tokens are rejected after translation.

### Mod discovery
All detected Project Zomboid mods are now listed:
- `[LOC OK]` means supported localization files were found.
- `[NO LOC]` means the mod was detected, but no supported localization files were found.

### Project Zomboid Game coverage
The Game profile now reports:
- Missing target
- Identical source/target
- Translated
- Target-only

A new filter can show suspicious/untranslated entries, including target strings identical to their source text.
