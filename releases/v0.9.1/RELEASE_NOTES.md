# Mod Translation Toolkit v0.9.1 Experimental

## Project Zomboid translation mod builder

The Project Zomboid Mod profile can now build a separate translation mod.

Included:
- generated `mod.info`
- unique translation mod ID
- dependency on the original PZ mod when its mod ID is available
- B42/common localization layout
- JSON and legacy TXT output
- original JSON structure preservation
- generated `poster.png` with a target-language flag
- `SteamWorkshopDescription.txt`
- copied Workshop description button
- `ModTranslationToolkit.json` metadata for future update workflows

The builder never modifies the subscribed original Workshop mod.
