# Mod Translation Toolkit v0.10.16 Experimental

## Existing translation update detection

`Update existing translation` now uses the source-mod folder selected by the user as a direct classification signal.

This fixes valid custom-named translations such as `Exosuit Framework [PL]`, whose About.xml:
- contains Polish language files,
- depends on `Aoba.Exosuit.Framework`,
- loads after `Aoba.Exosuit.Framework`,
- uses packageId `pl.Aoba.Exosuit.Framework`.

The translation no longer needs `Translation` or `Tłumaczenie` in its display name.
