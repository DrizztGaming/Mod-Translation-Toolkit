# Mod Translation Toolkit v0.10.18 Experimental

This build fixes a RimWorld XML parsing edge case discovered with Glitter Tech. Defs that contain a `Name` XML attribute could be classified under the attribute value instead of their real XML type because of PowerShell XML adapter behavior. The scanner now reads the node `LocalName`, preserving real types such as `ThingDef` and `DamageDef`.

It also adds visible scan-stage status messages so longer recursive Def scans no longer appear to freeze the application.

## Glitter Tech regression target
- v0.10.16 baseline observed by user: 490 entries.
- v0.10.17 recursive scan observed by user: 544 entries, 514 existing translations auto-loaded.
- v0.10.18 keeps the expanded scan but corrects fake DefType values produced by `Name` attributes, allowing cross-file matching to use the proper DefType.

## Important
Implied RimWorld Blueprint/Frame generation is still intentionally not enabled in this build.
