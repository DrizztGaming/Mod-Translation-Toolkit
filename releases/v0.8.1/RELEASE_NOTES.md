# Mod Translation Toolkit v0.8.1 Experimental

This experimental maintenance release adds crash-safe translation checkpoints after a tester reported a 0-byte CSV and an application exit during export.

## Safety changes
- Translation state is checkpointed before RimWorld Mod CSV export.
- Translation state is checkpointed before building/updating a RimWorld translation mod.
- Checkpoints live in `%APPDATA%\ModTranslationToolkit\autosave`.
- `latest.csv` is designed to be the fastest recovery path after a failed export/build.
- Timestamped CSV + JSON checkpoint pairs are retained, up to 20 snapshots.
- CSV files are written to a temporary file first, verified as non-empty, and only then moved to the requested destination.
- The atomic CSV writer is also used by RimWorld Game and Project Zomboid exports.

The underlying cause of the tester's application exit is not yet confirmed, so this release focuses on preventing translation loss while making the export path safer.
