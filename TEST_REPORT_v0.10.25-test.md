# Test report — v0.10.25 test build

## Automated checks

- Main PowerShell script parses without errors.
- Legacy v0.10.24 `Source` / `Target` glossary CSV loads successfully.
- Saving separates general entries from RimWorld/mod-specific entries.
- A package-specific Mod term overrides both RimWorld and general terms.
- Expert/AI context includes preferred, allowed and forbidden terminology.
- Inline dictionary preview resolves the selected term using Mod > RimWorld > General priority.
- Two allowed Polish variants used for the same resolved English term are reported as an inconsistency.
- Terminology diagnostics are read-only.
- Main script remains UTF-8 with BOM for Windows PowerShell 5.1.

Run the terminology regression test with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Terminology.Tests.ps1
```

Expected result: `Terminology tests: PASS`.

## Manual smoke-test checklist

1. Launch the app and verify `v0.10.25` in the title and header.
2. Open RimWorld Mod → Glosariusz and confirm the new columns and both data layers.
3. Select an entry containing a known term and open Expert / AI.
4. Create two translations using different allowed variants and run Sprawdź terminy.
5. Confirm the report does not alter either translation.
6. Load an existing v0.10.24 project/translation and verify scan, import, coverage and build behavior.
