# Mod Translation Toolkit v0.10.7 Experimental

## Windows PowerShell 5.1 startup hotfix

Fixes the startup parser error:

`Variable reference is not valid. ':' was not followed by a valid variable name character.`

The affected interpolation now uses `${name}` syntax and is compatible with Windows PowerShell 5.1.
