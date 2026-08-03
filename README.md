# Mod Translation Toolkit

A Windows desktop helper for translating game mods.

> **Current stable release:** v0.8.0  
> **Supported profiles:** RimWorld Game, RimWorld Mod, Kenshi Game, Project Zomboid Mod (experimental)

The project started as a small RimWorld translation helper and is being prepared as a multi-game toolkit with separate game profiles.

## Features

- **DLL/UI diagnostics** heuristically scans RimWorld mod assemblies for UI/keybind-related references and strings such as Hotkey, KeyBindingDef, Tooltip, Gizmo, Command, Widgets and Translate.
- Bilingual manuals (`MANUAL_PL.md`, `MANUAL_EN.md`) are shipped next to the launcher.

- **Keybind/UI diagnostics for RimWorld**: scans `KeyBindingDef`, translates exposed `label`/`description` through the normal DefInjected workflow, and flags keybindings with no localizable label/description as likely UI/code-generated text.

- **Workshop Dashboard**: save a creator profile, automatically reuse the creator name as translation author, track Workshop items by URL/PublishedFileID, refresh public item details, and aggregate subscriptions, favorites and views. No Steam password or publisher API key is stored.

- Translation-table search can filter by source text, translated text or both. Bulk replace can fix a phrase everywhere in translations, or assign one translation to every matching source phrase.

- Mod/game paths can be pasted directly or loaded by dragging a folder onto the path field; pressing Enter loads the path immediately.

- **Update existing translation**: compare an updated source mod with an existing translation mod, keep matching translated strings, expose only new/missing content, and save back into the same translation mod while preserving `packageId` and `About.xml`.

- **Kenshi base-game profile**: detects Steam installation, scans UI gettext `main.pot` / `main.po`, scans FCS-exported `gamedata.pot` and dialogue POT files, loads existing `pl_PL` work, supports manual/automatic translation and CSV, writes `main.po` + `main.mo`, and prepares `__translations\pl_PL` for FCS Build.
- Kenshi mod translation is intentionally not enabled yet; v0.3.0 focuses only on the base game.

- Existing translation editing can resolve the original mod through `modDependencies`, `loadAfter/loadBefore`, common translation packageId suffixes, or the cleaned base mod name.

- Existing translation mods can be reopened from Installed Mods. The Toolkit resolves the original dependency, loads source strings from the original mod, overlays the existing translation, and saves changes back into the same translation mod without deleting Workshop metadata.

- Source/original strings are selectable and copyable directly from the translation table.

- Existing localization for the selected target language is loaded automatically into the translation table.
- Automatic translation only processes entries that are still missing, preserving detected human/localized text.
- Switching the target language automatically loads the detected localization for that language when available.

- Detects existing localization for registered languages in root and versioned language folders.
- Shows translation coverage against the currently scanned source entries.
- Classifies existing localization as missing, partial or complete.
- Existing source or target localization can be loaded directly into the translation table for editing or completion.

- Version-aware localization scanning: detects `Languages/English` both at mod root and inside version folders such as `1.6/Languages/English`.
- Follows `LoadFolders.xml` when locating active language folders.
- Reads both `Keyed` and existing `DefInjected` localization files instead of relying only on rebuilding DefInjected from `Defs`.
- Existing English `DefInjected` entries take priority over fallback extraction from `Defs`.

- Automatically generates a ready-to-paste Steam Workshop description in BBCode.
- Workshop description includes Requirements, Original Mod, Credits, Mod Translation Toolkit attribution, GitHub link and Ko-fi support section.
- After building a translation mod, the generated Workshop description can be copied directly to the clipboard.

- Generated translation mods include a permanent attribution to Mod Translation Toolkit and a link to the project repository: `https://github.com/DrizztGaming/Mod-Translation-Toolkit`.

- Can copy the original RimWorld mod `About/Preview.png` into the generated translation mod.
- Can overlay a language flag on the copied preview (Polish, UK/English, German, French, Spanish, Italian, Czech, Ukrainian, Japanese, Korean, Chinese, Portuguese).

- Startup interface-language selector: Polish or English.
- Automatic translation source and target languages can be selected independently through the multilingual language registry.
- `Open mod folder` is available directly from the translation workspace.

- Dark UI with a purple Mrokar-inspired accent theme.
- No Python installation required.
- Starts without a visible CMD/PowerShell console.
- Detects Steam and additional Steam libraries.
- Detects RimWorld Workshop mods and local mods.
- Searches installed mods by name, author or `packageId`.
- Reads `Languages/English`.
- Also scans RimWorld `Defs` at the same time, including versioned content selected through `LoadFolders.xml`.
- Falls back to common translatable fields from `Defs` when possible.
- Manual translation in a table.
- CSV import/export.
- Optional automatic English → Polish translation.
- Placeholder validation and repair (`{0}`, `{1}`, `%s`, `\n`).
- Builds a separate RimWorld translation mod for the selected target language with `About.xml`, `supportedVersions`, dependency metadata and source links.

## Run

On Windows, double-click:

`Mod Translation Toolkit.vbs`

Only the GUI should appear. The launcher starts the PowerShell backend hidden.

## Current limitations

RimWorld mods can store text in many different places. Custom XML formats, `RulesStrings`, some quest structures, strings generated by C# code, DLL-embedded strings and mods with custom localization loaders may require manual handling.

Automatic translation requires a configured provider: Google Cloud Translation, DeepL API, or LibreTranslate. Machine-translated text should always be reviewed.

## Roadmap

Planned profile architecture:

- RimWorld
- Paradox games
- Project Zomboid
- Minecraft
- Generic XML / JSON / CSV

## Repository layout

- `src/RimWorld/` - current RimWorld profile and GUI
- `launcher/` - hidden Windows launcher
- `docs/` - project notes
- `releases/` - release packaging notes

## License

MIT. See `LICENSE`.


### Placeholder repair

When placeholder problems are detected, the user can:
- repair manually with problematic rows highlighted,
- repair all detected issues automatically,
- review every proposed repair one by one with Yes / No confirmation.


## UI structure (v0.5.0)
- **Profile gier**
  - **RimWorld Game** — base game / DLC localization workspace.
  - **RimWorld Mod**
    - **Tłumaczenie**
    - **Zainstalowane mody**
  - **Kenshi Game**
- **Workshop** remains a separate top-level section.

The RimWorld Game workspace detects the game installation, lists Core and detected DLC/data modules, allows selecting Core only, DLC only or any combination, and scans the selected source/target languages for the selected modules.

- RimWorld Game supports official RimWorld `.tar` language archives as well as loose language folders.

- RimWorld Game now derives DefInjected source entries from the game's/DLC's `Defs` and matches them against the target-language DefInjected files.

## Automatic translation API
Automatic translation now requires the user's own Google Cloud Translation API key. The Toolkit no longer uses the unofficial public Google Translate endpoint. The API key is stored locally using Windows DPAPI encryption for the current Windows user.

## Translation providers
Automatic translation can use:
- Google Cloud Translation
- DeepL API
- LibreTranslate, including self-hosted instances

LibreTranslate self-hosting can work without an API key. Google and DeepL credentials are stored locally using Windows DPAPI encryption.

## UI localization
v0.5.9 introduces a central Polish/English UI text dictionary and applies it across Game Profiles, RimWorld Game, RimWorld Mod, Installed Mods, Workshop, Kenshi Game and Translation API controls. ComboBox dropdown contrast was also reworked for reliable readability.

## Folder selection
v0.6.0 centralizes folder selection through the modernized Windows shell picker. RimWorld Game, RimWorld Mod, Kenshi Game, translation output and existing-translation update workflows now support easier Explorer-style browsing while preserving paste and drag-and-drop paths.

## Language architecture
v0.6.1 introduces a central language registry. Source/target language selectors are now populated dynamically from language metadata rather than hardcoded English/Polish entries. The registry stores RimWorld folder names and provider-specific codes for Google, DeepL and LibreTranslate.

## RimWorld Mod multilingual workflow
v0.6.2 migrates the RimWorld Mod workflow to the central language registry. Source and target localization folders are resolved dynamically, existing target translations are detected and loaded for the selected language, and generated translation mods use the correct `Languages/<Language>` folder and language-specific metadata.

## RimWorld Game multilingual workflow
v0.6.3 adds independent source/target language selectors to RimWorld Game. Core and DLC localization scanning now resolves official loose language folders and `.tar` archives using the central language registry. English source keeps Def-derived DefInjected generation; non-English source remains strictly based on the selected official localization.

## Translation-provider language validation
v0.6.4 validates the selected language pair before automatic translation. Google uses Toolkit mappings, DeepL queries the API language list and resolves source/target variants, and LibreTranslate reads the `/languages` capabilities of the configured server. Unsupported pairs are blocked before translation starts.

## Multilingual milestone
v0.7.0 completes the first full multilingual migration. Translation-mod naming, package IDs, Workshop metadata, Preview flag presets, CSV metadata and build reports now follow the selected target language. A persistent Creator ID is used in generated package IDs to reduce collisions between translation authors.


## RimWorld Game CSV workflow
v0.7.5 adds CSV export/import for scanned RimWorld Core and DLC entries. CSV metadata includes the source and target language pair, and imports match entries by module, type and key.

## LibreTranslate encoding repair
v0.7.6 adds guarded repair for common mojibake in LibreTranslate responses, such as UTF-8 text accidentally decoded as Windows-1252. The repair is heuristic and leaves correctly decoded text unchanged.


## LibreTranslate UTF-8 handling
v0.7.8 reads LibreTranslate HTTP responses as raw bytes and decodes them explicitly as UTF-8 before JSON parsing. This avoids Windows PowerShell 5.1 legacy-codepage corruption of translated text.


## Project Zomboid Mod
v0.8.0 introduces an experimental Project Zomboid mod profile. It scans standard `media/lua/shared/Translate/<LANG>` tables, recognizes common B41 layouts and B42 versioned mod folders, matches existing target translations, and supports manual editing, automatic translation and CSV workflows.

The first implementation intentionally skips structured translation formats such as `Recorded_Media_*` and does not build a Project Zomboid translation package yet.
