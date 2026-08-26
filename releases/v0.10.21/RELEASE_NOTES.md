# Mod Translation Toolkit v0.10.21

This release focuses on translation-state clarity and manual editing ergonomics for RimWorld mods.

## Changes

- Translation coverage now distinguishes actually translated entries from values that are identical to the source text.
- Source-language status explicitly explains when no `Languages/English` folder exists and the Toolkit is using text directly from `Defs`.
- The target status now reports translated, identical-to-source, and missing entries separately.
- Renamed the target reload action to make its purpose clearer.
- Added **Load from folder...** for importing an existing translation from a separate translation mod or directly from a target-language folder. This is useful when updating old RimTrans/community translations that are not bundled with the source mod.
- Added a **multiline editor**. Literal RimWorld `\n` / `\r\n` markers are displayed as normal line breaks while editing and converted back when saved.
- Automatic translation already protects RimWorld line-break markers together with placeholders, so paragraph structure survives provider round-trips.
- UI localization/version metadata updated to v0.10.21.

## Glitter Tech test context

The v0.10.20 scanner remains unchanged. The new coverage display is intended to reveal cases where a `Languages/Polish` folder exists but many values are still copies of the English source rather than completed Polish translations.
