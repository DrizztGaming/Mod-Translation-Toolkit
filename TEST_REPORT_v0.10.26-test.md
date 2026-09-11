# Test report — v0.10.26 test build

## Automated checks

- PowerShell parser: PASS.
- Terminology and legacy glossary compatibility tests: PASS.
- Glossary priority and preferred/alternative result splitting: PASS.
- Local dictionary lookup and punctuation normalization: PASS.
- Long-selection rejection: PASS.
- Fill-empty, append-without-overwrite and replace-selection behavior: PASS.
- Add-to-Glossary persistence and duplicate prevention: PASS.
- Main WPF XAML parse and runtime load: PASS.
- Required dictionary controls found after WPF load: PASS.
- Bundled local dictionary row count: 138.

## Manual smoke-test checklist

1. Start the app and verify `v0.10.26` in the title and header.
2. Open RimWorld Mod, load a mod, and select an English word such as `damage`.
3. Verify the persistent panel shows `obrażenia` plus `uszkodzenia` without configuring an API.
4. Single-click a result and confirm the Polish text is unchanged.
5. Edit a Polish cell, place the caret or select a fragment, then double-click a dictionary result.
6. Confirm insertion/replacement occurs only at the intended position.
7. Click **Dodaj do Glossary**, reopen Glossary, and verify a Mod-layer rule for the current package.
8. Open Expert/AI and run terminology checks to confirm the existing tools still work.
