# Mod Translation Toolkit v0.8.6 Experimental

## Project Zomboid fixes

The Game profile now reads valid PZ JSON files whose keys differ only by capitalization, avoiding a Windows PowerShell 5.1 `ConvertFrom-Json` limitation.

The Mod profile now detects both local mods and Steam Workshop subscriptions:
- `%USERPROFILE%\Zomboid\mods`
- `steamapps\workshop\content\108600`
- Workshop `mods\<mod>` layouts
- B42 versioned folders
