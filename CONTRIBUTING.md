# Contributing

Contributions are welcome.

For new game support, prefer adding a separate profile rather than hard-coding game-specific logic into the common UI.

A profile should eventually define:
1. How the game/mod directory is detected.
2. Which files contain source strings.
3. Which placeholders or markup must be preserved.
4. How translated files are written.
5. How a distributable translation package is built.

Current code is still an early Windows PowerShell prototype and will be refactored as more profiles are added.
