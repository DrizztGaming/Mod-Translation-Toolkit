# Test report — v0.10.21

## Static checks performed in the build environment

- Main PowerShell file preserved as UTF-8 with BOM for Windows PowerShell 5.1 compatibility.
- Main WPF XAML block parses as valid XML.
- Application title/badge and generated mod metadata updated to v0.10.21.
- New controls are present in XAML and registered by `FindName`: external translation loader and multiline editor.
- Coverage logic separates translated, identical-to-source and missing entries.
- Source localization text handles the no-`Languages/English` / Defs-source case.
- External target loader accepts a translation mod root, `Languages` folder, or target-language folder.
- Multiline editor converts literal RimWorld `\n` / `\r\n` markers to real line breaks for editing and back on save.
- Existing automatic translation placeholder protection already includes `\n` and `\r\n`, so line-break markers remain protected during provider calls.

## Runtime check still required on Windows

The build environment does not provide Windows PowerShell/WPF, so the first launch and UI interactions should be treated as a devtest. Recommended checks:

1. Open Glitter Tech and confirm scanning remains 544 entries.
2. Confirm the new target status reports translated / identical / missing separately.
3. Click **Load from folder...** and point it at the old Glitter Tech Polish translation mod.
4. Select `OrionCo.description`, open **Edit multiline...**, verify that `\n\n` appears as a blank paragraph, save, and confirm the grid stores `\n\n` again.
5. Build/export and verify the saved XML still contains literal RimWorld line-break markers.
