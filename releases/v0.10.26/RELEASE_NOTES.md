# Mod Translation Toolkit v0.10.26

Test release adding a persistent offline English-to-Polish dictionary helper to the RimWorld Mod workflow.

## New

- Bundled 138-entry local EN→PL starter lexicon; no API or network connection is used.
- Preferred and alternative equivalents are displayed as separate selectable results.
- Double-click inserts the selected result into the current Polish translation; single-click never changes text.
- Insert-at-caret and replace-selection behavior for an actively edited Polish cell.
- Safe fallback that fills an empty translation or appends to existing text without overwriting it.
- **Add to Glossary** creates a contextual Mod-layer rule for the current package.
- Added **Export for sharing** and **Import from translator** in the Glossary editor for portable contributor files.

## Compatibility and safety

- Existing v0.10.25 general, RimWorld and Mod glossary files remain readable.
- Priority is preserved as `Mod > RimWorld > General > bundled local lexicon`.
- Glossary, Expert/AI context, terminology checks and other game/language workflows are unchanged.
- Application UI and generated metadata report v0.10.26.
- Imports never silently replace an existing preferred term; conflicts are merged as alternatives.
