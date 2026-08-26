# Mod Translation Toolkit v0.10.19 Experimental

Small stability/UI follow-up to v0.10.18.

## Changes
- Removes the non-fatal `Apply-CentralUiLanguage` startup error.
- Makes scan-stage status messages render before synchronous RimWorld scanning blocks the UI thread.
- Shows the wait cursor while scanning and restores it on completion.
- Updates all application/version metadata to v0.10.19.

## Regression target
The RimWorld extraction engine itself is unchanged from v0.10.18. Glitter Tech should still produce 544 entries, with 530 existing translations auto-matched in the current test set.
