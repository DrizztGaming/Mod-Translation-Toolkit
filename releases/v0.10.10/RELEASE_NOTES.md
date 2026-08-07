# Mod Translation Toolkit v0.10.10 Experimental

## RimWorld contextual glossary

The Toolkit now supports a persistent contextual glossary for both:
- RimWorld Game Core/DLC
- RimWorld Mods

Rules can be limited by workflow, DLC/module, DefType, field and mod packageId.

Example:
`counter -> lada`, Scope `All`, DefType `ThingDef`, Field `label`

This prevents LibreTranslate from translating a furniture label as `licznik` while leaving unrelated uses of `counter` untouched.
