# Mod Translation Toolkit v0.10.18 test notes

## Static checks
- PASS: main PowerShell file is UTF-8 with BOM for Windows PowerShell 5.1 compatibility.
- PASS: `$AppVersion`, window title, UI version badge and generated `modVersion` are all `0.10.18`.
- PASS: RimWorld Def scanners use `XmlElement.LocalName` instead of the PowerShell-adapted `.Name` property.
- PASS: scan-stage status messages are present in `Analyze-Mod`.
- PASS: release ZIP integrity test completed.

## Runtime verification still required
This environment does not provide Windows PowerShell/WPF, so the GUI must be dev-tested on Windows. Glitter Tech is the recommended regression case.
