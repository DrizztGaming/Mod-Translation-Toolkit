# Mod Translation Toolkit v0.2.6

Original-mod resolver fix.

- prevents Harmony from being selected as the source mod just because it appears first in dependencies
- prioritizes packageId-derived matching
- then tries the cleaned base mod name
- skips common framework/runtime dependencies during normal matching
- keeps framework matching only as a last-resort fallback
