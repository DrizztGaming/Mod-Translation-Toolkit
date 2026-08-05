# Mod Translation Toolkit v0.10.6 Experimental

## Restricted PowerShell policy compatibility

Diagnostics confirmed that some Windows systems use the `Restricted` PowerShell execution policy, which blocks `.ps1` files entirely.

v0.10.6 launches Toolkit with process-scoped `RemoteSigned`:
- no global policy change
- no CurrentUser policy change
- no `Bypass`
- downloaded Toolkit script is explicitly unblocked before launch
