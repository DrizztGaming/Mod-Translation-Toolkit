# Mod Translation Toolkit v0.9.8 Experimental

## Project Zomboid Workshop result=9 fix

The Workshop staging package could contain only a versioned `42/mod.info`. The B42 uploader also expects `Contents/mods/<ModName>/mod.info`.

v0.9.8 creates the root `mod.info`, preserves the versioned metadata, and validates the package before upload.
