# Mod Translation Toolkit v0.9.4 Experimental

## B42 translation-mod structure fix

The previous PZ builder reconstructed a translation-mod layout and could produce a package that Project Zomboid did not detect.

v0.9.4 now inspects the selected source mod and mirrors its actual B42 metadata/version structure.

It detects:
- root `mod.info`
- `common/mod.info`
- versioned `42/mod.info`, `42.x/mod.info`, etc.

Localization files are emitted into the corresponding real source root.

The build dialog now defaults to `%USERPROFILE%\Zomboid\mods` for local testing.
