# Mod Translation Toolkit v0.10.2 Experimental

## RimWorld DefInjected builder fix

Fixes a case where a translated `.description` was visible in the Toolkit table but was not written to the generated `ThingDef.xml`.

The builder now:
- canonicalizes DefInjected output paths,
- prefers translated duplicate rows,
- verifies generated XML against the selected entries,
- stops the build if a key is missing.
