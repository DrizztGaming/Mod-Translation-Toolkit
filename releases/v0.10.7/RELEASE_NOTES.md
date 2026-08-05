# Mod Translation Toolkit v0.10.7 Experimental

## Startup order hotfix

`Apply-CentralUiLanguage` was called before its function definition had been executed.

PowerShell processes script files top-to-bottom, so the early call failed even though the function existed later in the file.

v0.10.7 removes that premature call. UI language initialization still runs through the later `Apply-UiLanguage` path.
