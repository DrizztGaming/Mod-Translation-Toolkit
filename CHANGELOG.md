# Changelog

## v0.10.20
- Dodano centralny overlay podczas skanowania moda, aby aplikacja nie wyglądała na zawieszoną.
- Overlay pokazuje aktualny etap pracy i indeterminate progress bar.
- Wymuszane jest renderowanie overlayu przed wejściem w synchroniczny etap skanowania.
- Zachowano logikę skanera i dopasowania tłumaczeń z v0.10.19.
- Zaktualizowano numer wersji w interfejsie i generowanym modVersion.

## 0.10.19 Experimental - 2026-08-26

### Fixed
- Removed the premature startup call to `Apply-CentralUiLanguage`, eliminating the non-fatal red PowerShell `CommandNotFoundException` shown during startup. Central UI localization is still applied from `Apply-UiLanguage` after the function has been defined.
- Updated all visible/runtime version markers to `v0.10.19`, including `$AppVersion`, window title, version badge, and generated `modVersion`.

### UI
- Made long RimWorld mod scan status messages actually render before synchronous work begins. The status bar now updates its layout and pumps the WPF dispatcher at `ContextIdle` between scan stages.
- Added a wait cursor while scan stages are running and restores the normal cursor when the final `Gotowe` status is set.
- No changes to the v0.10.18 extraction logic; Glitter Tech should remain at the same 544 entries while retaining the improved 530 automatic matches.

## 0.10.18 Experimental - 2026-08-26

### Fixed
- Fixed RimWorld `DefType` detection when a Def has an XML `Name` attribute. PowerShell's XML adapter could expose the attribute value through `.Name`, causing types such as `OCDKatana_GT`, `HeavyPowerConduit` or `StabBase` to be used as fake Def types. The scanner now uses the XML node's `LocalName`.
- Applied the same safe node-name detection to RimWorld Game scanning and KeyBindingDef diagnostics.
- Version number is now updated in the application title, version badge, `$AppVersion`, and generated mod metadata.

### UI
- Added visible work-status messages during longer RimWorld mod scans: reading mod info, scanning localizations, scanning Defs/nested fields, analyzing KeyBindingDef, and matching existing translations.
- The UI dispatcher is refreshed between stages so the status text is visible instead of making the application look frozen.

## 0.10.17 Experimental - 2026-08-25

### RimWorld extraction and translation migration
- Added cross-file matching for existing `DefInjected` translations using `DefType + key`, so translations survive XML file reorganization.
- Added key-only cross-file matching for `Keyed` entries.
- Added conflict detection when duplicate historical keys contain different translations.
- Added recursive extraction of nested localizable fields such as `tools.0.label` and `comps.0.tools.0.label`.
- Expanded the RimWorld localizable-field whitelist with fields identified during the RimTrans/Glitter Tech audit.
- Added generated `PawnKindDef.labelPlural` fallback support.
- Fixed obsolete-entry counting so moved XML entries are not falsely reported as removed.
- Blueprint/Frame implied Def generation remains intentionally deferred until it can follow current RimWorld rules safely.

## 0.10.16 Experimental - 2026-08-07

### Existing translation update detection fix
- Fixed `Aktualizuj istniejące tłumaczenie` rejecting valid custom-named translation mods.
- The update workflow now validates the translation directly against the source-mod folder explicitly selected by the user.
- `modDependencies`, `loadAfter`, `loadBefore`, and packageId-derived references can confirm the selected original even when it is not present in the previously scanned installed-mod list.
- A real language payload is still required, so the stronger detection does not turn arbitrary dependency mods into translation mods.
- Added support for language-prefix packageIds such as `pl.Aoba.Exosuit.Framework -> Aoba.Exosuit.Framework`.
- Improved rejection diagnostics now include the classification score/signals.
- Verified specifically against the structure used by `Exosuit Framework [PL]`.

## 0.10.15 Experimental - 2026-08-07

### Quiet glossary learning
- Learning mode now defaults to **Silent** instead of showing a popup after every manual correction.
- Added three persistent modes: **Silent / Ask / Off**.
- Clicking the learning-mode button cycles between the modes.
- Silent mode queues manual corrections without interrupting translation work.
- Added **Suggestions: N / Propozycje: N** buttons to RimWorld Game and RimWorld Mod.
- Added a batch review window for queued suggestions.
- Review actions: accept selected, accept all, reject selected, reject all.
- Repeated identical corrections are merged and counted.
- Accepting a suggestion transfers its occurrence count into glossary confidence.
- Confidence 3+ activates the learned contextual rule automatically.
- Core/DLC and mod suggestions remain context-aware by Module, DefType, Field and PackageId.
- Ask mode preserves the previous immediate confirmation workflow.
- Off mode disables learning while leaving the glossary itself active.

## 0.10.14 Experimental - 2026-08-06

- Rebuilt the startup hotfix from clean v0.10.12.
- Fixed only the two invalid `$score:` interpolations using `${score}:`.
- Removed the over-broad v0.10.13 replacement that corrupted valid `$script:` scoped variables.
- Preserves smarter translation detection, glossary and learning features.

## 0.10.12 Experimental - 2026-08-06

### Smarter existing RimWorld translation detection
- Existing translation mods no longer need `Translation`, `Tłumaczenie` or similar wording in `About.xml` name.
- Added weighted structural classification using multiple independent signals.
- Signals include actual language payload, translation-only content shape, Toolkit metadata/attribution, translation-like packageId/name/description, packageId-derived original, `modDependencies`, and `loadAfter`.
- Dependencies and loadAfter only count when they resolve to an installed non-framework mod.
- A real language payload is mandatory, reducing false positives from normal compatibility/patch mods.
- Custom-named language-only mods with an explicit dependency on their original mod are now recognized automatically.
- Classification score/signals are shown in the status text when an existing translation is opened.
- Source-mod resolution still uses packageId, normalized name, dependencies and loadAfter/loadBefore after classification.

## 0.10.11 Experimental - 2026-08-06

### Learning glossary / translation memory
- RimWorld Game and RimWorld Mod now remember the result of automatic translation as a learning baseline.
- When the user manually changes that automatic result, Toolkit can propose saving the correction to the contextual glossary.
- Learned rules are scoped to the current context: Game/Mod, Module/DLC, DefType, Field and mod PackageId.
- Learned rules start with confidence 1 and remain inactive.
- Repeating the same correction raises confidence automatically.
- At confidence 3 the learned rule activates automatically.
- This avoids turning one accidental edit into a global rule.
- The glossary editor now shows **Confidence** and whether a rule was **Learned**.
- Manual glossary rules still work immediately as before.
- Learning uses complete source entries, not guessed fragments from long sentences. This is especially reliable for labels such as `Counter -> lada`.

## 0.10.10 Experimental - 2026-08-06

### RimWorld contextual glossary
- Added a shared contextual glossary for **RimWorld Game (Core/DLC)** and **RimWorld Mod**.
- Rules support: Source, Target, Scope (All/Game/Mod), Module/DLC, DefType, Field and PackageId.
- Glossary terms are protected before Google/DeepL/LibreTranslate and restored as the chosen target term after translation.
- Whole-word matching prevents terms such as `counter` from affecting words such as `counterattack`.
- Exact full-entry glossary matches bypass the translation provider entirely.
- Added a conservative default example: `counter -> lada` only for `ThingDef.label`.
- Added **Glosariusz...** editor to both RimWorld Game and RimWorld Mod.
- Added **Tłumacz brakujące** to RimWorld Game, so Core/DLC automatic translation uses the same contextual glossary.
- Added **Zastosuj do istniejących etykiet** for correcting already translated exact labels.
- Glossary is stored persistently as `rimworld-glossary.csv` in Toolkit settings.
- Existing placeholder protection remains active independently of glossary protection.

## 0.10.9 Experimental - 2026-08-06

### Custom Workshop description for RimWorld Mod
- Added **Workshop description...** to the RimWorld Mod workflow.
- Added the same multiline BBCode editor available in RimWorld Game.
- Custom descriptions are saved per original mod/packageId, so different translation projects can keep different Workshop text.
- Added **Load default**, **Delete saved custom**, **Cancel**, and **Save description** actions.
- `Build-SteamWorkshopDescription` now uses the saved custom text when present.
- Default generation remains available at any time.
- Includes the RimWorld Game Workshop editor from v0.10.8.

## 0.10.8 Experimental - 2026-08-06

### Custom Steam Workshop description for RimWorld Game
- Added **Workshop description...** next to the RimWorld Game translation-mod builder.
- Added a multiline BBCode editor for the Workshop description.
- Custom description is saved persistently in Toolkit settings and reused on future builds.
- Added **Load default** to regenerate the current default description.
- Added **Delete saved custom** to return permanently to automatic defaults.
- `SteamWorkshopDescription.txt` now uses the saved custom description when present.
- The default description automatically lists currently selected/scanned Core/DLC modules.
- Includes the Windows PowerShell 5.1 startup parser hotfix from v0.10.7.

## 0.10.7 Experimental - 2026-08-06

### Windows PowerShell 5.1 startup parser hotfix
- Fixed a startup `ParseException` in `Get-RimWorldGameInheritanceSummary`.
- Replaced unsafe `"$name: ..."` interpolation with `"${name}: ..."`.
- This restores startup on Windows PowerShell 5.1.
- Includes the RimWorld Game translation mod builder from v0.10.6.

## 0.10.6 Experimental - 2026-08-06

### RimWorld Game translation mod builder
- Added **Build translation mod** to RimWorld Game.
- Core + selected DLC can now be packaged as a normal RimWorld mod instead of CSV-only output.
- Uses all scanned entries, independent of the active grid filter.
- Writes translated Keyed and DefInjected entries to `Languages/<TargetLanguage>`.
- Detects duplicate Core/DLC keys with conflicting translations and stops the build instead of silently overwriting data.
- Equal duplicate keys are safely deduplicated.
- Adds About.xml, packageId, modVersion, supported RimWorld version, DLC dependencies/loadAfter, Preview.png, SteamWorkshopDescription.txt and TranslationBuildReport.txt.
- Output defaults to the game's `Mods` folder when available.
- Includes ParentName inheritance for both RimWorld Mod and Core/DLC workflows from v0.10.4/v0.10.5.

## 0.10.5 Experimental - 2026-08-05

### RimWorld Core/DLC ParentName inheritance
- Applied the v0.10.4 ParentName inheritance logic to the RimWorld Game workflow.
- Core and DLC Def scanning now uses the same two-pass model as RimWorld Mod.
- Abstract/template Defs with `Name` are indexed even without `defName`.
- Concrete Core/DLC Defs inherit supported localizable fields recursively through `ParentName`.
- Direct child fields override inherited fields.
- Cycle protection is preserved.
- Generated source entries use the concrete child key, e.g. `SomeChildDef.description`.
- Inherited entry counts are tracked per module/DLC.
- Includes all fixes from v0.10.1 through v0.10.4.

## 0.10.4 Experimental - 2026-08-05

### RimWorld ParentName inheritance fix
- Reworked `Scan-Defs` into a two-pass scanner.
- Abstract/template Defs with a `Name` attribute are now indexed even when they have no `defName`.
- Concrete Defs now inherit supported localizable fields through `ParentName`.
- Inheritance is recursive, so multi-level parent chains are supported.
- Direct child values always override inherited values.
- Cycle protection prevents broken ParentName chains from hanging the scanner.
- Inherited fields are emitted under the concrete child key, e.g. `Tav_1x1Table.description`.
- TranslationBuildReport now records inherited field counts and Tavern-specific inheritance diagnostics.
- Includes v0.10.1 placeholder, v0.10.2 builder verification, and v0.10.3 grid reconciliation fixes.

## 0.10.3 Experimental - 2026-08-05

### RimWorld grid-to-builder reconciliation fix
- Fixed a pipeline case where a DefInjected row could be visible/editable in the Toolkit grid but absent from `$script:Entries` at build time.
- Pending DataGrid edits are now committed before building.
- Visible grid rows are reconciled back into the canonical entry list.
- Missing DefInjected metadata is recovered from the row key/path when possible.
- Entry identity now uses canonical DefInjected output paths.
- Added a pre-write invariant that stops the build if a canonical DefInjected row disappears before XML generation.
- TranslationBuildReport now records reconciliation statistics.
- Added explicit diagnostics for `Tav_1x1Table*` and `Tav_1x2Table*`.
- Includes v0.10.1 placeholder fixes and v0.10.2 post-write XML verification.

## 0.10.2 Experimental - 2026-08-05

### RimWorld DefInjected builder fix
- Fixed translated DefInjected rows being visible in the Toolkit but missing from the generated XML.
- DefInjected output paths are now canonicalized from `DefType`.
- Duplicate file/key rows now prefer the entry containing an explicit translation instead of blindly keeping the first row.
- Added post-write XML verification for every generated language file.
- A build now fails visibly if any selected translation key is missing from the generated XML.
- TranslationBuildReport now includes the number of XML files/entries written and verification result.
- Includes the v0.10.1 placeholder integrity fixes.

### Regression testcase
- Verified the builder logic against the reported `Tav_1x1Table.description` / `Tav_1x2Table.description` case.

## 0.10.1 Experimental - 2026-08-05

### RimWorld placeholder hotfix
- Fixed internal `__MTTPH0__`, `__MTTPH1__`, and similar tokens leaking into translations.
- Replaced legacy underscore tokens with provider-resistant alphanumeric tokens.
- Placeholder restoration now tolerates provider-added spaces and letter-case changes.
- Added strict placeholder count and order validation after every API translation.
- Literal `\n` sequences are preserved exactly as structural text.
- Damaged provider responses are rejected instead of saved as valid translations.
- Placeholder validation automatically repairs recoverable legacy token leaks.
- Build validation detects unresolved internal tokens and changed placeholder order.

## 0.10.0 public-package documentation update - 2026-08-05

- Added Microsoft Defender false-positive guidance.
- Added source-verification and SHA-256 instructions.
- Added a ready-to-copy Microsoft sample-submission template.
- Application code and version remain v0.10.0 Experimental.

## 0.10.0 Experimental - 2026-08-05

### Project Zomboid B42 workflow
- First Workshop publication now uses empty `id=`.
- Stored translation Workshop ID can be reused for later updates.
- `poster.png` is a dedicated Polish-flag image for the in-game mod list.
- `preview.png` remains a separate Workshop preview with a Polish badge.
- B42 Workshop staging validation and root/versioned `mod.info` fixes remain enabled.
- Generated PZ translations remain reopenable and editable.

### RimWorld Game filters
- Added All, Missing translation, Translated, Identical source/target and Suspicious filters.
- Filtered count is shown against the full scan result.

### Packaging
- Updated README, changelog and release notes.
- Prepared normal and GitHub-ready packages.

## 0.9.8 Experimental - 2026-08-05

### Project Zomboid Workshop uploader hotfix
- Fixed Workshop upload failing with Steam/PZ `result=9` when the staging package had no root `mod.info`.
- Workshop packages now always contain `Contents\mods\<ModName>\mod.info` in addition to versioned B42 metadata.
- Ensures a root `poster.png` beside the root `mod.info`.
- Added a Workshop staging validator for `Contents`, `Contents\mods`, `preview.png`, `workshop.txt`, root `mod.info`, and versioned `mod.info`.

## 0.9.7 Experimental - 2026-08-04

### Project Zomboid Workshop staging package
- Fixed the in-game Workshop uploader error: `Contents/ in the selected folder does not exist`.
- Toolkit now creates a separate Workshop-ready staging package for every PZ translation build.
- Workshop staging path defaults to `%USERPROFILE%\Zomboid\Workshop\<Translation Name>`.
- Generated Workshop structure:
  - `Contents\mods\<Translation Mod>\...`
  - `preview.png`
  - `workshop.txt`
- The playable local mod remains in `%USERPROFILE%\Zomboid\mods`.
- Added `Open Workshop package` button.
- Workshop preview is generated as a 256x256 PNG from the translation poster.
- `workshop.txt` contains title, description, Translation tag and initial public visibility.

### Important workflow split
- `Zomboid\mods` = local testing / playable mod.
- `Zomboid\Workshop\<item>` = folder selected in Project Zomboid's Create/Update Workshop Item screen.

## 0.9.6 Experimental - 2026-08-04

### Reopen and update Project Zomboid translation mods
- Fixed Toolkit-generated PZ translation mods not being readable after creation.
- Translation packages are recognized through `ModTranslationToolkit.json`.
- Source strings are loaded from the original mod.
- Target strings are loaded from the Toolkit-generated translation mod.
- Existing translations are matched back into the editor.
- Original mod path can be resolved from stored path, Workshop ID, or mod ID.
- Rebuilding an opened translation updates the same folder instead of creating another package.
- Existing B42 structure, dependency, poster and description fixes are preserved.

## 0.9.5 Experimental - 2026-08-04

### Project Zomboid poster / preview fix
- Fixed translation mods being detected by Project Zomboid while showing a blank preview.
- `poster.png` is now placed beside every generated/mirrored `mod.info`, not only in the outer mod folder.
- The root poster is retained for packaging and Workshop use.

### Project Zomboid description cleanup
- Generated `mod.info` descriptions are now normalized to exactly one description line.
- Source description lines are removed before writing the translation description.
- Prevents repeated `translation. Created with Mod Translation Toolkit.` text in the in-game mod browser.

## 0.9.4 Experimental - 2026-08-04

### Project Zomboid B42 translation builder structure fix
- Reworked the Project Zomboid translation builder to mirror the selected source mod's real B42 container structure.
- Detects actual `mod.info` locations instead of assuming one layout.
- Supports root `mod.info`, `common\mod.info`, and numeric B42 roots such as `42\mod.info` or `42.21\mod.info`.
- Prefers the newest numeric B42 `mod.info` when several versions exist.
- Mirrors detected version/common roots into the generated translation mod.
- Updates every mirrored `mod.info` with the translation name, unique ID and dependency on the original mod.
- Localization output is written to the exact relative source content root instead of a reconstructed guessed root.
- Original subscribed Workshop files are never modified.

### Local installation
- The build folder dialog now defaults to `%USERPROFILE%\Zomboid\mods`.
- The local mods directory is created automatically when possible.
- This avoids treating `steamapps\workshop\content\108600` as a manual-install destination.

## 0.9.3 Experimental - 2026-08-04

### Project Zomboid Game automatic translation progress
- Added live 0-100% progress for `Translate missing`.
- Shows processed / total, successful translations and errors.
- UI is refreshed throughout long translation runs so the window no longer appears frozen.
- Translation button is disabled while the job is running and restored in `finally`.
- Autosave checkpoints every 25 processed entries are preserved.
- Grid/filter refresh happens periodically during long jobs.
- Individual translation errors are counted and skipped instead of silently making the whole job appear stuck.

## 0.9.2 Experimental - 2026-08-04

### Translation provider readiness hotfix
- Fixed LibreTranslate being reported as `none` even when it was correctly saved and working in API settings.
- The readiness check now uses `Get-TranslationProviderSettings`, the exact same persisted settings source used by `Translate-Configured`.
- Removed dependency on transient API dialog controls and the stale `$script:TranslationSettings` assumption.
- Self-hosted LibreTranslate is considered ready when its saved endpoint exists; an API key remains optional.
- Diagnostic messages can show the saved LibreTranslate endpoint without exposing API secrets.

## 0.9.1 Experimental - 2026-08-04

### Project Zomboid translation mod builder
- Added `Build translation mod` to the Project Zomboid Mod profile.
- Generates a separate translation mod instead of modifying the original Workshop item.
- Preserves Project Zomboid B42/common translation-root structure.
- Builds only the selected target-language localization folder.
- JSON output preserves the original source JSON structure and case-sensitive keys.
- Legacy TXT localization output is also supported.
- Generates `mod.info` with a unique translation mod ID.
- Adds `require=<original mod id>` when the original `mod.info` provides an ID.
- Stores original mod/workshop metadata in `ModTranslationToolkit.json`.
- Generates `SteamWorkshopDescription.txt`.
- Added `Copy Workshop description`.
- Generates `poster.png` by copying the original poster and overlaying a Polish flag.
- Creates a fallback MTT translation poster when the source mod has no poster.

### Safety
- Original Workshop mod files are never modified by the builder.
- Existing autosave, provider validation, PZ markup validation and atomic CSV export remain enabled.

## 0.9.0 Experimental - 2026-08-04

### Project Zomboid Game scan progress
- Added a visible 0-100% progress bar to Project Zomboid Game scanning.
- Added live stage text for source scan, target scan, indexing, matching and coverage.
- Source and target file scanning updates progress while files are being processed.
- The Scan button is disabled while scanning to prevent duplicate scans.
- UI events are pumped during progress updates so the window remains responsive.
- Progress reaches 100% only after matching and coverage calculation complete.

### Scan stages
- 0-5% preparation
- 5-40% source language files
- 40-75% target language files
- 75-85% indexing
- 85-95% matching
- 95-100% coverage/finalization

## 0.8.9 Experimental - 2026-08-04

### Translation provider detection
- Fixed a false "no provider configured" result when a provider was visibly selected in the API settings.
- Provider detection now reads the actual selected ComboBox item and falls back to persisted settings.
- Provider display labels are normalized to internal names.
- LibreTranslate is considered configured when a valid endpoint exists, even without an API key.
- Missing-provider messages now include the provider Toolkit thinks is selected.

### Project Zomboid Game scan performance
- Coverage no longer rescans English and target localization files a second time.
- Source/target maps are cached during the main scan and reused for coverage.
- Target-only count is computed from the same cached scan.
- This removes a large amount of duplicate work on 40k+ entry Project Zomboid installations.

## 0.8.8 Experimental - 2026-08-04

### Translation provider handling
- Automatic translation now stops immediately when no provider is configured.
- Added a clear PL/EN message directing the user to API / Translation.
- Prevents entering long translation loops when API/provider configuration is missing.

### Project Zomboid markup safety
- Added dedicated protection for Project Zomboid angle-bracket markup such as `<H1>`, `<LEFT>`, `<ORANGE>`, `<SIZE:...>`, `<IMAGE:...>` and `<SETX:...>`.
- Markup is restored 1:1 after translation.
- Added post-translation integrity validation.
- Translations containing unrecovered `__MTTPH...` or `__PZTAG...` tokens are rejected instead of silently accepted.

### Project Zomboid mod discovery
- The detected-mod list now includes all detected local/Workshop mods, not only mods with localization roots.
- Mods are marked `[LOC OK]` or `[NO LOC]`.
- Workshop ID and `mod.info` names are preserved.

### Project Zomboid Game coverage
- Added coverage counters for missing target, identical source/target, translated and target-only entries.
- Added filters for all, missing target, identical source/target and suspicious/untranslated entries.
- Makes it possible to detect formally present target entries that still contain unchanged English text.

## 0.8.7 Experimental - 2026-08-03

### Project Zomboid Mod selection
- Fixed Workshop detection treating the entire `content\108600` tree as one combined mod.
- `Detect mods` now enumerates individual Project Zomboid mods.
- Added a detected-mod selector to the Project Zomboid Mod profile.
- Selecting a mod updates the active mod path automatically.
- `Scan mod` now scans only the selected mod instead of combining translations from every subscribed Workshop item.
- Reads `mod.info` where available to show a human-friendly mod name and mod ID.
- Workshop items retain their PublishedFileId in the selector.
- Local `%USERPROFILE%\Zomboid\mods` entries appear in the same selector.
- Only mods containing a detectable translation root are listed.

## 0.8.6 Experimental - 2026-08-03

### Project Zomboid Game JSON fix
- Replaced PowerShell 5.1 `ConvertFrom-Json` in the Project Zomboid reader with .NET `JavaScriptSerializer`.
- Fixes valid localization files containing keys that differ only by capitalization, such as `Farming_Lemongrass` and `Farming_LemonGrass`.

### Project Zomboid Mod detection
- Added `Wykryj mody` / `Detect mods`.
- Detects `%USERPROFILE%\Zomboid\mods`.
- Detects `steamapps\workshop\content\108600` in all Steam libraries.
- Understands Workshop item layout `<PublishedFileId>\mods\<mod>\...`.
- Understands B42 versioned folders such as `42`, `42.15`, etc.
- The scanner can now accept a root containing many mods, not only one exact mod folder.

## 0.8.5 Experimental - 2026-08-03

### Startup hotfix 2
- Fixed the exact Windows PowerShell 5.1 parse error reported by `STARTUP_ERROR.log`.
- The autosave metadata counter had a misplaced parenthesis around `Where-Object` / `.Count`.
- The corrected expression now parses before the UI starts.
- Project Zomboid TXT + JSON support, Steam detection, autosave and crash-safe CSV export are preserved.
- `START_DEBUG.ps1` remains included for future startup diagnostics.

## 0.8.4 Experimental - 2026-08-03

### Startup hotfix
- Fixed a Windows PowerShell 5.1 startup regression introduced in v0.8.3.
- The new Project Zomboid JSON reader used constructor syntax that could break parsing before the UI opened.
- Restored the parser-safe `New-Object -TypeName ... -ArgumentList ...` form.
- Project Zomboid TXT + JSON support is preserved.
- Added `START_DEBUG.ps1` to capture startup failures into `STARTUP_ERROR.log`.

## 0.8.3 Experimental - 2026-08-03

### Project Zomboid B42.15+ JSON localization
- Added recursive JSON translation parsing for Project Zomboid Game and Project Zomboid Mod.
- Keeps backward compatibility with legacy TXT localization files.
- JSON objects and arrays are flattened into stable translation keys for matching source and target files.
- Only string leaf values are treated as translatable text.
- CSV exports now preserve a `Format` field (`TXT` or `JSON`) for Project Zomboid entries.
- Existing target JSON translations are matched against English/source JSON keys.
- UTF-8 JSON is read explicitly and invalid JSON now produces a readable file-specific error.
- Build 42 versioned mod-folder support from v0.8.2 is preserved.
- Autosave every 25 translated entries is preserved.

### Recorded media
- Legacy `Recorded_Media_*.txt` remains excluded from the generic TXT parser because it is a generated/special format.
- JSON localization is no longer excluded and is now the preferred current B42 path.

## 0.8.2 Experimental - 2026-08-03

### Project Zomboid Game
- Added automatic Steam-library detection for Project Zomboid.
- Added a dedicated Project Zomboid Game profile.
- Scans base-game `media/lua/shared/Translate/<LANG>` files.
- Added source/target language selection.
- Loads existing target-language entries and matches them against the source.
- Added manual editing, automatic translation and CSV import/export.
- Project Zomboid Game CSV export uses the crash-safe atomic writer.
- Project Zomboid Game automatic translation creates autosave checkpoints.

### Translation autosave
- RimWorld Mod automatic translation now saves a checkpoint every 25 completed entries.
- Project Zomboid Game automatic translation saves every 25 entries and again when translation completes.
- Project Zomboid Mod automatic translation now also keeps an autosave CSV during long translation runs.

### Current limitation
- `Recorded_Media_*` and other structured Project Zomboid localization formats are still intentionally excluded from the generic key/value parser.

## 0.8.1 Experimental - 2026-08-03

### Crash-safe translation saving
- Added an automatic translation checkpoint before RimWorld Mod CSV export.
- Added an automatic translation checkpoint before building or updating a RimWorld translation mod.
- Checkpoints are stored in `%APPDATA%\ModTranslationToolkit\autosave`.
- `latest.csv` and `latest.json` always point to the newest checkpoint.
- Up to 20 timestamped checkpoints are retained automatically.
- RimWorld Mod CSV export now uses an atomic temporary-file workflow and verifies that the completed CSV is not empty before replacing the destination.
- RimWorld Game and Project Zomboid CSV exports use the same atomic writer.
- Failed RimWorld Mod export/build dialogs now point to the preserved checkpoint.
- CSV filenames now include the selected source and target language pair.

## 0.8.0 - 2026-08-03

### Project Zomboid experimental foundation
- Added a new `Project Zomboid Mod` profile.
- Detects standard `media/lua/shared/Translate/<LANG>` translation folders.
- Supports common Build 41 layouts and Build 42 versioned mod folders such as `42/` and `42.x/`.
- Can scan a direct mod folder or a Workshop item containing `mods/<mod-name>/...`.
- Added multilingual source/target selectors for common Project Zomboid language codes.
- Loads existing target translations and shows matched entries in the translation grid.
- Added manual editing, automatic translation, CSV export and CSV import.
- CSV matching uses root + file + key.
- v0.8.0 intentionally handles only standard `key = "value"` translation tables.
- Structured formats such as `Recorded_Media_*` are intentionally skipped until a dedicated parser is added.
- Translation-mod packaging for Project Zomboid is not enabled yet.

## 0.7.8 - 2026-08-03

### LibreTranslate UTF-8 fix
- Reworked LibreTranslate HTTP handling for Windows PowerShell 5.1.
- The Toolkit now reads LibreTranslate responses as raw bytes and decodes them explicitly as UTF-8 before JSON parsing.
- This avoids legacy-codepage corruption such as `MoÅ¼na`, `biaÅ‚e`, `dostÄ™pnych`, etc.
- Existing mojibake repair remains as a guarded fallback only.
- LibreTranslate error responses are also decoded as UTF-8 when possible.

## 0.7.7 - 2026-08-03

### Startup regression fix
- Fixed a Windows PowerShell 5.1 startup/parser regression introduced by the v0.7.6 LibreTranslate mojibake helper.
- Replaced the risky UTF8Encoding constructor syntax with PowerShell 5.1-safe `New-Object -ArgumentList`.
- Reworked mojibake detection so the PowerShell source stays ASCII-only and does not contain embedded C1 control characters.
- LibreTranslate encoding repair remains guarded and only accepts a conversion when the suspicion score improves.

## 0.7.6 - 2026-08-03

### Stable candidate
- Added guarded mojibake repair for LibreTranslate responses.
- Repairs common UTF-8-as-Windows-1252 corruption such as `PokaÅ¼` → `Pokaż`, `UÅ¼yj` → `Użyj`, and `bÄ™dzie` → `będzie`.
- Repair is heuristic and only applied when suspicious mojibake markers are detected and the converted text scores better than the original.
- Correctly decoded LibreTranslate text is left untouched.
- Placeholder restoration still runs after encoding repair.
- Prepared GitHub-ready stable package and release notes for v0.7.6.

## 0.7.5 - 2026-08-03

### RimWorld Game CSV workflow
- Added CSV export for scanned RimWorld Core and DLC entries.
- CSV includes Module, Type, File, Key, Source, Translation, SourceLanguage and TargetLanguage.
- Added CSV import back into the RimWorld Game scan.
- Import matches rows by Module + Type + Key, so translations are restored to the correct Core/DLC entries.
- Added source/target language metadata mismatch warning.
- Import requires a current RimWorld Game scan, preventing a CSV from silently replacing unrelated game data.
- Export/import buttons follow the PL/EN interface language.

## 0.7.4 - 2026-08-02

### Windows smoke-test fixes
- Fixed RimWorld Mod CSV export/import crash caused by helper names colliding with PowerShell built-in cmdlets.
- Creator name is restored from the saved Workshop profile on startup and copied into the translation author field.
- Fixed a broken creator-profile reference to a non-existent `txtTranslator` control.
- Fresh translation builds now consistently use the selected target language in the folder and `About.xml` display name.
- RimWorld Game copies official `.tar` language archives to an ASCII-only temporary filename before `tar.exe` extraction, improving accented, Cyrillic and CJK archive handling.
- Failed RimWorld Game scans clear stale rows/counts/tooltips from the previous language.

## 0.7.3 - 2026-08-02

### UI language fixes
- Fixed Game Profiles becoming empty after switching to English.
- Tab localization now changes `TabItem.Header` instead of overwriting `TabItem.Content`.
- Connected remaining RimWorld Game labels/buttons/status text to the central PL/EN localization layer.
- RimWorld Game static grid headers now localize while source/target language columns keep the selected language names.

### Translation API language check
- Reworked **Check languages / Sprawdź języki** to avoid testing every registered source/target pair individually.
- Google now uses one language-capabilities request.
- DeepL uses one source-list and one target-list request.
- LibreTranslate uses one `/languages` request.
- Added visible `Checking... / Sprawdzanie...` state.
- Reduced provider capability timeout to 8 seconds.
- Button is always restored after success or failure.

## 0.7.2 - 2026-08-02

### Critical startup fix
- Fixed a WPF XAML layout error introduced with the Creator ID row.
- A `Border` accidentally contained two direct child controls; WPF `Border` supports only one child.
- Wrapped the coverage row and Creator ID row in a parent `StackPanel`.
- This fixes the application failing to open in v0.7.0/v0.7.1.

### Validation
- Added a semantic WPF layout check for single-child controls such as `Border`.

## 0.7.1 - 2026-08-02

### Stability / regression fixes
- Removed a duplicate `Get-SelectedTargetLanguageCode` definition left during the multilingual migration.
- RimWorld Mod CSV exports now reliably include `SourceLanguage` and `TargetLanguage` while preserving Def metadata and semicolon delimiters.
- CSV import remains backward compatible with older files that do not contain language metadata.
- When language metadata is present and differs from the current selection, Toolkit shows a warning but still allows import.
- Clarified that Kenshi automatic translation is intentionally still English → Polish pending its separate multilingual migration.

### Validation
- Re-ran static package, XAML, registry, packageId, provider and synthetic RimWorld localization tests after the fixes.

## 0.7.0 - 2026-08-02

### Multilingual milestone
- Completed the first full multilingual architecture migration.
- Translation-mod naming and metadata follow the selected target language.
- Workshop descriptions include target language information and generated packageId.
- Preview flag selection follows the selected target language preset.
- Build reports include source/target language, Creator ID and generated packageId.

### PackageId / creator identity
- Added persistent Creator ID.
- Generated package IDs use `<original.packageId>.<creatorId>.<language>`.
- Creator and language components are normalized to safe lowercase alphanumeric values.

### CSV
- RimWorld Mod CSV exports include `SourceLanguage` and `TargetLanguage`.
- Kenshi CSV exports include explicit source/target metadata.

### Validation
- Added an internal multilingual configuration self-test.
- Checks registry completeness, duplicate RimWorld folders and generated packageId format.

## 0.6.4 - 2026-08-02

### Automatic translation language validation
- Added provider-aware source/target language validation before automatic translation.
- Unsupported language pairs are blocked before translation begins.
- Added localized error messages explaining why a pair cannot be used.

### Google Cloud Translation
- Uses the central language registry mappings for source and target codes.

### DeepL
- Queries `/v2/languages` for current source and target language capabilities.
- Caches capability results for the current Toolkit session.
- Added role-aware handling for language variants such as English, Portuguese/Brazilian Portuguese and Chinese.
- Resolves provider-returned regional/script variants when API naming differs from the Toolkit registry.

### LibreTranslate
- Queries `/languages` on the configured LibreTranslate server.
- Validates the actual source → target pair exposed by that server.
- Works with different self-hosted servers whose installed language models may differ.

### API settings
- Added **Check languages / Sprawdź języki**.
- Provider capability cache is cleared when API settings are changed.

## 0.6.3 - 2026-08-02

### RimWorld Game multilingual migration
- Added independent source and target language selectors to RimWorld Game.
- Core and DLC scanning now uses the central language registry.
- Official language folders and `.tar` archives are resolved for arbitrary registered languages.
- Keyed and DefInjected matching is now source/target-role based rather than hardcoded English/Polish.
- Result-grid language column headers update to the selected languages.
- Scan counters and status messages report the selected target language dynamically.
- Source and target cannot be the same language.

### Language detection
- Reworked RimWorld language aliases to use code, English name, native name and RimWorld folder name.
- Preserved strict token matching for short language codes to prevent false matches such as the old `pl` / `ChineseSimplified` issue.
- Added common aliases for Brazilian Portuguese, Simplified/Traditional Chinese and Czech.

### Source behavior
- English Core/DLC source still generates DefInjected entries from game `Defs`.
- Non-English source uses only the selected official localization and does not mix English Defs.

## 0.6.2 - 2026-08-02

### RimWorld Mod multilingual migration
- RimWorld Mod now resolves the selected source localization dynamically.
- Existing localizations are scanned for every registered language.
- Changing the source language rescans the loaded mod.
- Changing the target language refreshes coverage and loads an existing target localization when available.
- Generated translation files use the selected target RimWorld folder.
- Translation-mod naming, Workshop suffix and About.xml description follow the target language.
- PackageId language suffixes are normalized for codes such as `pt-br`.

### Source handling
- English source continues to combine localization files with Def-derived source entries.
- Non-English source uses the selected localization without silently mixing English Def text.

### Coverage
- Coverage storage is no longer limited to Polish and English.
- Existing coverage slots show the selected source and target languages.

### Scope
- RimWorld Game/Core/DLC multilingual migration remains the next step.

## 0.6.1 - 2026-08-02

### Language architecture
- Added a central language registry.
- Each language now defines:
  - Toolkit language code
  - English/native display name
  - RimWorld language folder name
  - Google translation code
  - DeepL translation code
  - LibreTranslate code
  - flag preset
- Source/target ComboBoxes are now populated dynamically from the registry.
- Removed the hardcoded English/Polish ComboBox entries.
- `Get-LanguageFolderName` now resolves through the registry.
- Translation providers now resolve their language codes through the registry.

### Languages included in the first registry
- English
- Polish
- German
- French
- Spanish
- Italian
- Portuguese
- Brazilian Portuguese
- Czech
- Ukrainian
- Russian
- Japanese
- Korean
- Simplified Chinese
- Traditional Chinese
- Dutch
- Swedish

### Scope
- This release only introduces the language layer.
- RimWorld Mod and RimWorld Game still need the next migration stages before every workflow can fully save/load arbitrary target languages.

## 0.6.0 - 2026-08-02

### Folder picker / UX
- Added centralized `Show-ModernFolderPicker`.
- Enabled the upgraded Windows shell folder-selection experience where supported by the installed .NET/Windows version.
- Modernized folder selection for:
  - RimWorld Game
  - RimWorld Mod
  - Kenshi Game
  - translation-mod output folder
  - existing-translation update workflow
- Existing-translation path dialogs now include **Browse...** / **Przeglądaj...** in addition to paste and drag-and-drop.
- Folder pickers open from the currently entered/selected path when possible.

### Compatibility
- Uses the built-in Windows/.NET folder dialog and falls back gracefully when the upgraded shell mode is unavailable.
- No external UI library is required.

## 0.5.9 - 2026-08-02

### UI localization
- Added a central Polish/English UI text dictionary.
- Central localization is now applied across:
  - Game Profiles
  - RimWorld Game
  - RimWorld Mod
  - Translation
  - Installed Mods
  - Workshop
  - Kenshi Game
  - Translation API controls
- Newly added controls no longer need ad-hoc English text assignments to be usable in English mode.

### UI readability
- Reworked `ComboBoxItem` styling with an explicit control template.
- Improved contrast for normal, highlighted and selected dropdown rows.
- Fixed the long-standing issue where opened ComboBox items could become difficult to read on some Windows themes.

### Architecture
- Added `T()` helper and centralized UI text lookup as groundwork for future multi-language interface support.

## 0.5.8 - 2026-08-02

### Added
- Added selectable automatic translation providers:
  - Google Cloud Translation
  - DeepL API
  - LibreTranslate
- Added DeepL API Free / API Pro endpoint selection.
- Added configurable LibreTranslate endpoint and optional API key.
- Self-hosted LibreTranslate can be used without an API key when the server allows it.
- Added provider-specific setup instructions in Polish and English.
- Added migration of the previous Google-only API key into the new provider settings.

### Security
- Google requests now send the API key through the `X-goog-api-key` header instead of placing it in the URL.
- Google, DeepL and LibreTranslate credentials remain encrypted locally with Windows DPAPI.
- No shared Toolkit translation API key is bundled.

### Changed
- Automatic translation now routes through the provider selected in **API / Translation** settings.
- Provider-specific cost/quota warnings replace the previous Google-only warning.

## 0.5.7 - 2026-08-02

### Changed
- Automatic translation now requires the user's own Google Cloud Translation API key.
- Removed the unofficial public Google Translate endpoint.
- RimWorld Mod and Kenshi automatic translation use the official Google Cloud Translation API v2 endpoint.

### Added
- Added **API Settings** to the main Toolkit header.
- Added local API-key storage encrypted with Windows DPAPI for the current Windows user.
- Added **How to get an API key** instructions in Polish and English.
- Added clear billing/quota warning: Google Cloud usage is billed to the owner of the configured key.
- Automatic translation opens API Settings when no key is configured.

### Security
- The API key is not stored as plain text.
- The Toolkit does not bundle or provide a shared translation API key.
- The key is sent only to Google's Translation API when automatic translation is used.

## 0.5.6 - 2026-08-02

### Fixed
- Fixed RimWorld Game scans exposing almost exclusively `Keyed` entries.
- Core/DLC `DefInjected` source is now generated directly from the module's `Defs` instead of assuming a complete English `Languages/English/DefInjected` mirror exists.
- Generated DefInjected keys use the standard `defName.field` format and are matched against the official target-language DefInjected data.
- Explicit English DefInjected files are still merged in when present.
- Source entries are deduplicated by module + type + key.

### Diagnostics
- RimWorld Game counters now show separate totals for `Keyed`, `DefInjected`, and matched target-language entries.
- Per-module status tooltip now reports Keyed and DefInjected counts separately.

### Scope
- This release intentionally focuses only on the RimWorld Game DefInjected issue. UI localization, additional target languages and folder-picker modernization are reserved for later steps.

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

