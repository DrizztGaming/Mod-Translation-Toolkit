# Migration from 0.x

The PowerShell 0.x branch remains useful as the behavior reference.

v1 should not shell out to the legacy PS1.

Feature migration rule:

- port behavior into C#
- add regression tests
- only then remove dependence on the corresponding 0.x implementation

Preview 1 focuses on the application shell, scanners, filters, CSV and Steam detection.
