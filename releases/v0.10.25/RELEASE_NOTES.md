# Mod Translation Toolkit v0.10.25

Test release introducing layered English-to-Polish terminology.

## New

- Separate general and RimWorld/mod-specific glossary data.
- Explicit `Mod > RimWorld > General` priority.
- Preferred Polish equivalents, allowed alternatives/synonyms, forbidden variants, context tags and notes.
- Expert/AI context for the selected RimWorld entry.
- Read-only terminology consistency and forbidden-variant reports.

## Compatibility and safety

- Existing v0.10.24 `rimworld-glossary.csv` files remain readable.
- Other language pairs retain the previous translation path.
- Diagnostics never rewrite translations.
- Applying exact glossary matches to existing labels requires explicit confirmation.
