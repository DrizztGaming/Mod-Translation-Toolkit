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
