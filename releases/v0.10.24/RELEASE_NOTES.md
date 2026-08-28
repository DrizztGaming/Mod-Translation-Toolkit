# Mod Translation Toolkit v0.10.24

Small UI correctness fix following the Callouts regression test.

## Fixed

- Target-language coverage now refreshes correctly after **Update existing translation**.
- Preserved translations loaded into the grid are immediately included in translated/identical/missing/technical counters.
- Fixes the misleading case where the grid contained hundreds of translated entries while the coverage label still displayed `0 translated`.

No extraction or matching rules were changed in this release.
