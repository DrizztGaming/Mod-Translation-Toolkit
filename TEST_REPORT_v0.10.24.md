# Test report — v0.10.24

## Scope

- Version markers updated to v0.10.24.
- Verified update-mode code now replaces target-language coverage data with the loaded existing translation map before refreshing the UI.
- No changes to v0.10.23 RulePack extraction or technical-entry classification.
- ZIP integrity checked.
- Main PowerShell script preserved as UTF-8 with BOM for Windows PowerShell 5.1 compatibility.

## Expected Callouts regression result

After loading the MisterFossil translation into the current Callouts source, the coverage display should reflect approximately:

- translated: 319
- identical to source: 1
- missing: 3
- technical: 30
- total: 353

The exact translated/identical split depends on the loaded translation content, but it must no longer remain at `0/323` after the update is loaded.
