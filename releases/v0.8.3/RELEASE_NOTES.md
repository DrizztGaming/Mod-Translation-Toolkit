# Mod Translation Toolkit v0.8.3 Experimental

## Project Zomboid B42.15+ localization support

Project Zomboid changed its current Build 42 translation workflow toward UTF-8 JSON files. v0.8.3 updates both Project Zomboid profiles accordingly.

### New
- JSON localization scanning for Project Zomboid Game
- JSON localization scanning for Project Zomboid Mod
- recursive object/array flattening
- source/target matching by flattened JSON key
- UTF-8 JSON validation
- CSV `Format` metadata
- legacy TXT support retained
- B42 versioned mod folders retained
- autosave every 25 translated entries retained

### Still separate
Legacy `Recorded_Media_*.txt` is a special generated format and is not parsed by the generic TXT reader yet.
