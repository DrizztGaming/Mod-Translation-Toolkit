# Mod Translation Toolkit v0.10.22

This release expands RimWorld Def extraction for RulePack-based mods.

## Changes

- Added context-aware extraction of bare `<li>` strings inside `rulesStrings` collections.
- Generated keys follow the expected indexed form, e.g. `CM_Callouts_Common.rulePack.rulesStrings.0`.
- Added `name` to the translatable Def field set, including custom DLL-defined Def types.
- The scanner intentionally does **not** translate arbitrary `<li>` nodes. Only explicitly known localizable list containers are enabled, preventing Def references and configuration lists from being mistaken for text.
- Updated visible/runtime version metadata to v0.10.22.

## Callouts regression case

Callouts (`2362736503`) is now used as a regression test. The supplied source contains 323 `rulesStrings` entries, 2 localizable custom-Def `name` entries, and 28 English Keyed entries. The historical Polish translation contains 350 matching entries; the current source adds 3 RulePack strings that were not present in that translation.
