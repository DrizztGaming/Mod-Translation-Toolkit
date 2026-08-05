# Mod Translation Toolkit v0.8.5 Experimental

## Startup hotfix

`STARTUP_ERROR.log` identified the startup failure precisely: a misplaced parenthesis in the autosave translation counter caused a PowerShell parse error before the UI could open.

v0.8.5 fixes that expression while preserving:
- RimWorld autosave checkpoints
- atomic CSV export
- Project Zomboid Game detection
- Project Zomboid Game/Mod TXT + JSON parsing
- autosave every 25 translated entries
- LibreTranslate UTF-8 handling

`START_DEBUG.ps1` remains included.
