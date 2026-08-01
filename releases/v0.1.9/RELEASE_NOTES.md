# Mod Translation Toolkit v0.1.9

RimWorld versioned-localization fix.

- scans root and versioned `Languages/English`
- follows `LoadFolders.xml`
- imports both `Keyed` and `DefInjected`
- prefers existing localization data over reconstructing it from raw Defs
- fixes incomplete scans for mods such as Hospitality
