# Architecture notes

## Goal

Turn the original RimWorld helper into a profile-driven mod translation toolkit.

## v0.1.0

The RimWorld implementation still contains the UI and profile logic in one PowerShell file. This is intentional for the first public prototype.

## Future split

Suggested structure:

- `src/Core/`
  - shared UI model
  - translation table
  - placeholder validation
  - CSV support
- `src/Profiles/RimWorld/`
- `src/Profiles/ProjectZomboid/`
- `src/Profiles/Paradox/`
- `src/Profiles/Minecraft/`
- `src/Profiles/Generic/`

A later native Windows build can replace the PowerShell front end while keeping the profile concept.


## Kenshi profile

The initial Kenshi profile targets the base game only.

- UI gettext: `locale/en_GB/LC_MESSAGES/main.po` -> `locale/pl_PL/LC_MESSAGES/main.po` + `main.mo`.
- FCS data: `__translations/base/gamedata.pot` and `dialogue/*.pot` -> `__translations/pl_PL/*.po`.
- The final `pl_PL.translation` is built in Forgotten Construction Set.

Kenshi mod localization is deferred until the base-game workflow is stable.
