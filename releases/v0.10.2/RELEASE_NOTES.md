# Mod Translation Toolkit v0.10.2 Experimental

## Windows Script Host launcher hotfix

v0.10.1 removed `ExecutionPolicy Bypass`, but the launcher was accidentally saved with a UTF-8 BOM. Windows Script Host treated the BOM as an invalid first character and failed with error `800A0408`.

v0.10.2 writes the `.vbs` launcher as BOM-free Windows-compatible text.
