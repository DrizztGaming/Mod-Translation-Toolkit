# Mod Translation Toolkit v0.5.6

## Fixed
- RimWorld Game now exposes DefInjected entries for Core and DLC.
- English DefInjected source is derived from `Defs`.
- Official translated DefInjected data is matched using `defName.field`.
- Keyed and DefInjected counts are shown separately.

## Why this changed
RimWorld does not require a complete English DefInjected localization mirror because English text lives in the game's Def XML. The old RimWorld Game scanner therefore found the English Keyed files but could miss nearly all DefInjected content.

## Scope
This is step 1 of the current feedback pass. No multi-language/UI/folder-picker redesign is included yet.
