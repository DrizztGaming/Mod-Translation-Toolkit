# Mod Translation Toolkit v0.6.4

## Provider-aware language validation
Automatic translation now checks whether the selected provider actually supports the selected source/target pair.

- Google: central Toolkit mappings
- DeepL: live API language capability check
- LibreTranslate: live `/languages` check against the configured server
- unsupported pairs are blocked before translation
- new Check languages button in Translation API settings
