# Mod Translation Toolkit v0.10.6 Experimental

## RimWorld Game translation mod builder

RimWorld Game can now build a normal translation mod from Core and the selected DLC modules.

The generated mod contains:
- About/About.xml
- About/Preview.png
- Languages/<target>/Keyed
- Languages/<target>/DefInjected
- SteamWorkshopDescription.txt
- TranslationBuildReport.txt

The builder detects conflicting duplicate keys across Core/DLC and refuses to silently overwrite them.
