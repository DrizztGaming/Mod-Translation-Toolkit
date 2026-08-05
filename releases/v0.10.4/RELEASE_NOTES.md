# Mod Translation Toolkit v0.10.4 Experimental

## VBScript launcher hotfix

v0.10.3 introduced startup diagnostics using a variable named `log`. In VBScript, `Log()` is a built-in math function, so assigning an object to `log` causes error `800A01F5`.

v0.10.4 renames that variable to `logFile`.
