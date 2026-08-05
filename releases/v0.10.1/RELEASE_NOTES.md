# Mod Translation Toolkit v0.10.1 Experimental

## Defender-friendly launcher hotfix

This release removes `-ExecutionPolicy Bypass` from the standard hidden launcher.

The launcher still uses:
- `-NoProfile`
- `-STA`
- hidden-window startup

but no longer overrides PowerShell execution policy.

The package structure was also cleaned so the internal top-level folder matches v0.10.1.
