# Mod Translation Toolkit v0.2.4

Translation-source resolver hotfix.

- resolves original mods from modDependencies
- falls back to loadAfter/loadBefore
- strips common translation suffixes from packageId
- falls back to normalized translation/base mod names
- improves error reporting when no source mod can be matched
