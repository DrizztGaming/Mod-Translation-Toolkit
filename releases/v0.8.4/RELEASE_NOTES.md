# Mod Translation Toolkit v0.8.4 Experimental

## Startup hotfix

v0.8.3 could fail before opening the UI on Windows PowerShell 5.1.

The cause was constructor syntax added to the Project Zomboid JSON reader. v0.8.4 restores the PowerShell 5.1-safe form.

Project Zomboid Game/Mod TXT + JSON support, Steam detection, autosave every 25 entries and crash-safe CSV export remain enabled.

`START_DEBUG.ps1` is included. If startup fails, run it and send `STARTUP_ERROR.log`.
