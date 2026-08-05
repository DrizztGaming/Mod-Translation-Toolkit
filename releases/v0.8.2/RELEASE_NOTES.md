# Mod Translation Toolkit v0.8.2 Experimental

## Project Zomboid Game support

This build adds the first base-game translation workflow for Project Zomboid.

### Included
- automatic Project Zomboid detection across Steam libraries
- manual game-folder selection
- base-game translation scanning from `media/lua/shared/Translate/<LANG>`
- multilingual source/target selection
- existing target translation matching
- manual editing
- automatic translation through the configured provider
- CSV export/import
- crash-safe CSV writing
- autosave checkpoints every 25 translated entries

### Autosave improvements
RimWorld Mod automatic translation now saves a checkpoint every 25 completed entries. Project Zomboid Game does the same and stores `latest-pz-game.csv` in `%APPDATA%\ModTranslationToolkit\autosave`.

### Still experimental
Project Zomboid structured localization formats such as `Recorded_Media_*` are not parsed yet.
