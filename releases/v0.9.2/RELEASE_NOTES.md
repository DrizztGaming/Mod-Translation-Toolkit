# Mod Translation Toolkit v0.9.2 Experimental

## LibreTranslate provider hotfix

The automatic-translation readiness check used a different settings source than the translation engine itself. This could report `none` even though LibreTranslate was correctly saved.

v0.9.2 now uses `Get-TranslationProviderSettings` everywhere for readiness validation, matching `Translate-Configured`.

For self-hosted LibreTranslate:
- saved endpoint required
- API key optional
