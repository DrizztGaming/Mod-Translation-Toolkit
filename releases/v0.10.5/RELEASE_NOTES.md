# Mod Translation Toolkit v0.10.5 Experimental

## Startup diagnostics rebuild

If startup fails, Toolkit now records the real PowerShell exception instead of only an exit code.

`STARTUP_ERROR.log` contains:
- exception message
- exception type
- script stack trace
- source position / line information
- category
- FullyQualifiedErrorId
