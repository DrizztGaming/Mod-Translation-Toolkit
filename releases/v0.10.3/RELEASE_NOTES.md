# Mod Translation Toolkit v0.10.3 Experimental

## Startup reliability hotfix

Removing `ExecutionPolicy Bypass` exposed a Windows Mark-of-the-Web issue: downloaded/extracted PowerShell scripts could be blocked while the hidden launcher made the failure invisible.

v0.10.3:
- does not override PowerShell execution policy
- removes Mark of the Web only from Toolkit's own PS1
- keeps hidden startup
- reports a startup exit code and creates `STARTUP_ERROR.log` on failure
