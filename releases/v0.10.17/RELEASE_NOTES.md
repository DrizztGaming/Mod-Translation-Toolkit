# Mod Translation Toolkit v0.10.17 Experimental

This release improves RimWorld translation extraction and migration compatibility after comparison with RimTrans 0.18.2.6 and Glitter Tech.

## Highlights
- Existing DefInjected translations can be recovered across XML file moves.
- Keyed translations can be recovered regardless of source XML filename.
- Nested translatable fields are scanned recursively.
- RimWorld field coverage is expanded.
- Missing PawnKind plural labels can be generated.
- Conflicting duplicate historical translations are detected instead of silently selecting one.
- Obsolete-entry statistics use canonical identities.

## Deferred
Implied Blueprint/Frame Def generation is not enabled in this release. It requires a current RimWorld-compatible rule set to avoid generating invalid keys.

- Fixed Windows PowerShell 5.1 compatibility: main script is stored as UTF-8 with BOM, preventing Polish/Chinese UI text from being misparsed as PowerShell syntax.
