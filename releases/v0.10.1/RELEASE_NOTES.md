# Mod Translation Toolkit v0.10.1 Experimental

## RimWorld placeholder hotfix

- Prevents internal MTT placeholder tokens from leaking into translations.
- Preserves literal `\n`.
- Verifies placeholder count and order.
- Rejects damaged API results.
- Repairs recoverable legacy `__MTTPH<number>__` entries during validation.
