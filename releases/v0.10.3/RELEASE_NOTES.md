# Mod Translation Toolkit v0.10.3 Experimental

## RimWorld grid-to-builder reconciliation fix

This release targets DefInjected entries that are visible in the Toolkit grid but disappear before the generated XML is written.

Before every build the Toolkit now:
- commits pending grid edits,
- merges visible rows into the canonical entry list,
- restores missing DefInjected metadata from key/path,
- verifies no canonical DefInjected row disappears before write,
- verifies every selected key exists again after XML write.

The build report also lists `Tav_1x1Table*` and `Tav_1x2Table*` entries for the reported regression case.
