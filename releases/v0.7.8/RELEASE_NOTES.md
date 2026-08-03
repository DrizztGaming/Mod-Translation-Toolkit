# Mod Translation Toolkit v0.7.8

LibreTranslate encoding hotfix.

Windows PowerShell 5.1 could decode LibreTranslate JSON responses using a legacy code page, producing broken characters such as `MoÅ¼na` instead of `Można`.

v0.7.8:
- reads LibreTranslate HTTP responses as raw bytes
- decodes response bytes explicitly as UTF-8
- parses JSON only after UTF-8 decoding
- keeps the mojibake repair helper as a guarded fallback
- preserves placeholder restoration
