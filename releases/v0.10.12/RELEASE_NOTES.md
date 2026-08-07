# Mod Translation Toolkit v0.10.12 Experimental

## Smarter translation-mod detection

RimWorld translation mods can now be recognized even when their About.xml name does not contain words such as `Translation` or `Tłumaczenie`.

Detection combines:
- real Languages payload,
- language-only package structure,
- dependencies/loadAfter resolving to the original installed mod,
- packageId/name/description hints,
- Toolkit metadata when available.

This improves `Aktualizuj istniejące tłumaczenie` for custom About.xml conventions.
