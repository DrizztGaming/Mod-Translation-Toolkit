# Mod Translation Toolkit v0.5.5

## Highlights
- Added the first functional **RimWorld Game** workflow.
- Reorganized navigation around **Game Profiles** and **Workshop**.
- RimWorld Game can detect Core and installed DLC/data modules.
- Added per-module scanning for official RimWorld localization data.
- Added support for official RimWorld language `.tar` archives.
- Added separate `Keyed` and `DefInjected` scanning.
- Fixed incorrect language matching where `pl` could match names such as `ChineseSimplified`.
- Workshop description copy no longer requires building the translation mod first.
- Kenshi tab renamed to **Kenshi Game**.
- DLL/UI diagnostics are lazy and run only when requested.

## Current navigation
- Game Profiles
  - RimWorld Game
  - RimWorld Mod
    - Translation
    - Installed Mods
  - Kenshi Game
- Workshop

## RimWorld Game
The current stage:
- detects the RimWorld installation,
- lists Core and detected DLC/data modules,
- supports selecting all, Core only, DLC only, or custom selection,
- reads official localization from loose folders and `.tar` archives,
- scans `Keyed` and `DefInjected`,
- shows English and Polish entries side by side.

## Known / planned
- progress bar for longer scans,
- improved scan stage reporting,
- further RimWorld Game comparison/diff tooling,
- more complete official-translation maintenance workflow.

## Safety
- Original RimWorld files are not modified.
- Official language archives are extracted only to a temporary cache for reading.
