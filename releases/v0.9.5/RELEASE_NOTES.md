# Mod Translation Toolkit v0.9.5 Experimental

## Project Zomboid preview fix

Project Zomboid could detect the generated translation mod but fail to display its poster because `poster.png` was only written to the outer package root.

v0.9.5 copies the generated poster beside every detected/generated `mod.info`, matching the active B42 metadata location.

It also cleans the generated description so it appears only once in the in-game mod browser.
