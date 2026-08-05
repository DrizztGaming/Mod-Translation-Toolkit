# Mod Translation Toolkit v0.7.7

Hotfix for v0.7.6.

v0.7.6 introduced a LibreTranslate mojibake-repair helper that could prevent the application from starting under Windows PowerShell 5.1.

v0.7.7:
- restores startup compatibility
- keeps mojibake detection source ASCII-only
- uses a PowerShell 5.1-safe UTF8Encoding constructor
- preserves the guarded LibreTranslate encoding repair
