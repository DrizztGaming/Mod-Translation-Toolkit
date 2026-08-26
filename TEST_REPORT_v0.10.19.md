# Mod Translation Toolkit v0.10.19 test notes

Static package checks performed in the build environment:

- PASS: PowerShell script remains UTF-8 with BOM for Windows PowerShell 5.1 compatibility.
- PASS: `$AppVersion`, window title, UI version badge and generated `modVersion` are `0.10.19`.
- PASS: premature startup `Apply-CentralUiLanguage` call removed; the remaining call is inside `Apply-UiLanguage`, after `Apply-CentralUiLanguage` is defined.
- PASS: work status helper updates layout and pumps the WPF dispatcher using `ContextIdle` before synchronous scan stages.
- PASS: wait cursor is used during scan stages and reset by the final `Gotowe` status.
- PASS: v0.10.18 RimWorld extraction/cross-file matching code is otherwise unchanged.
- PASS: ZIP structure/integrity checked after packaging.

Runtime WPF behavior still requires a Windows/Windows PowerShell devtest.
