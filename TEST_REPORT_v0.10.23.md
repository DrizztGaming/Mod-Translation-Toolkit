# Test report — v0.10.23

Static package checks completed.

- Version markers updated to v0.10.23.
- Main PowerShell script preserved as UTF-8 with BOM.
- Main WPF XAML parses as XML after extraction from the script.
- Technical RulePack classifier targets only `RulePackDef` + `rulesStrings[]` and examines the emitted RHS after `->`.
- Against the supplied Callouts CSV, 30 of 31 source-identical rules are grammar-only/technical; `et tu, [INITIATOR_name]?` remains user-facing and is not classified as technical.
- Full-key tooltip added to the RimWorld Mod grid.

Runtime WPF validation still requires Windows PowerShell 5.1.
