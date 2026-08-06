# Mod Translation Toolkit v0.10.4 Experimental

## RimWorld ParentName inheritance fix

The RimWorld Def scanner now resolves inherited localizable fields from abstract/template parents.

Example:

```xml
<ThingDef Name="Tav_TableBase" Abstract="True">
  <description>Sturdy reinforced table...</description>
</ThingDef>

<ThingDef ParentName="Tav_TableBase">
  <defName>Tav_1x1Table</defName>
  <label>sturdy table (1x1)</label>
</ThingDef>
```

The Toolkit will now generate both:
- `Tav_1x1Table.label`
- `Tav_1x1Table.description`

The same logic supports recursive ParentName chains.
