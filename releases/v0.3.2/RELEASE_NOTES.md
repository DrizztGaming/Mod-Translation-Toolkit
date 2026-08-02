# Mod Translation Toolkit v0.3.2

Clipboard reliability hotfix.

- retries clipboard access when Windows temporarily locks it
- fixes Workshop description copy failures with `CLIPBRD_E_CANT_OPEN`
- adds a fallback clipboard API
- source-text copying uses the same safe routine
