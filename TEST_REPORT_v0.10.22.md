# Test report — v0.10.22

## Static checks

- Application/version markers updated to v0.10.22.
- Main PowerShell script preserved as UTF-8 with BOM for Windows PowerShell 5.1 compatibility.
- RulePack extraction is context-gated to `rulesStrings`; generic XML `<li>` values remain excluded.
- `name` was added to the supported Def field set.

## Callouts reference

Source mod: Workshop `2362736503` (Callouts).

- English Keyed entries: 28
- `rulesStrings` list entries in current source: 323
- Custom `CM_Callouts.CalloutConstantByTraitDef.name` entries: 2
- Expected current-source total after the v0.10.22 scanner change: 353 entries
- Historical MisterFossil Polish translation: 350 matching entries
- Current source-only RulePack entries vs that historical translation: 3

A full WPF/Windows PowerShell runtime test is still required on Windows.
