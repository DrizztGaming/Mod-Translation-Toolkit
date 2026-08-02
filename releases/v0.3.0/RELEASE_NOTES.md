# Mod Translation Toolkit v0.3.0

First Kenshi profile.

- base-game translation only
- Steam Kenshi detection (AppID 233860)
- UI gettext main.po scanning and main.mo generation
- FCS base export scanning: gamedata + dialogues
- existing pl_PL work is loaded automatically
- manual translation, automatic EN -> PL and CSV workflow
- prepares the pl_PL FCS workspace
- backs up overwritten translation files

Kenshi gameplay-data translation still requires the final **Build** step in Forgotten Construction Set because Kenshi's `.translation` file is a game-specific binary format.
