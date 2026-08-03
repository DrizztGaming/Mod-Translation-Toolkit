# GitHub Release v0.7.8

## Tag
`v0.7.8`

## Release title
`Mod Translation Toolkit v0.7.8`

## Recommended release asset
`ModTranslationToolkit-v0.7.8.zip`

## Summary
Stable multilingual release candidate after Windows smoke testing.

### Highlights
- RimWorld Game multilingual Core/DLC scanning
- RimWorld Game CSV export/import
- RimWorld Mod multilingual workflow
- Translation mod build/update workflow
- Creator ID and Creator name persistence
- Workshop description generation
- Preview flags by target language
- Google Cloud, DeepL and LibreTranslate providers
- LibreTranslate UTF-8 handling fixed for Windows PowerShell 5.1
- Kenshi Game workflow
- PL/EN interface
- Modern folder picker
- Diagnostics for keybinds and DLL/UI strings

### v0.7.8 fix
LibreTranslate responses are now read as raw bytes and explicitly decoded as UTF-8 before JSON parsing, preventing broken characters such as `MoÅ¼na` instead of `Można`.

Use `releases/v0.7.8/RELEASE_NOTES.md` as the full GitHub Release description.
