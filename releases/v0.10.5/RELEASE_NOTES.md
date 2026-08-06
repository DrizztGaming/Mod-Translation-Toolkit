# Mod Translation Toolkit v0.10.5 Experimental

## RimWorld Core and DLC inheritance fix

The RimWorld Game scanner now resolves inherited localizable fields through `ParentName`, just like the RimWorld Mod scanner introduced in v0.10.4.

This applies to:
- Core
- Royalty
- Ideology
- Biotech
- Anomaly
- Odyssey
- any other detected official module that uses the same Def structure

Supported localizable fields remain the same as the existing scanner, but inherited values are now materialized under the concrete child Def key.
