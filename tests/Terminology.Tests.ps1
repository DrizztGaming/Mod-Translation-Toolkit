$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework

$sourcePath = Join-Path $PSScriptRoot "..\src\RimWorld\ModTranslationToolkit.ps1"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $sourcePath), [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) { throw "Main script has parser errors." }

$requiredFunctions = @(
    "Get-RimWorldGlossaryPath","Get-GeneralGlossaryPath","New-RimWorldGlossaryRule",
    "Get-DefaultRimWorldGlossary","Get-DefaultGeneralGlossary","ConvertTo-RimWorldGlossaryListText",
    "Write-RimWorldGlossaryFile","Save-RimWorldGlossary","Read-RimWorldGlossaryFile",
    "Get-RimWorldGlossary","Get-RimWorldEntryGlossaryContext","Split-RimWorldGlossaryValues",
    "Get-RimWorldGlossaryLayerPriority","Test-RimWorldGlossaryRuleMatches",
    "Get-MatchingRimWorldGlossaryRules","Protect-RimWorldGlossaryTerms",
    "Restore-RimWorldGlossaryTerms","Test-RimWorldTermInText",
    "Get-RimWorldAiTerminologyContext","Get-RimWorldTerminologyIssues",
    "Get-LocalEnPlDictionaryPath","Get-LocalEnPlDictionary",
    "Normalize-RimWorldDictionarySelection","Add-RimWorldDictionaryChoiceRows",
    "Get-RimWorldDictionaryPreviewRows","Update-RimWorldModDictionaryPreview",
    "Use-RimWorldDictionaryChoice","Add-RimWorldDictionaryChoiceToGlossary"
)

$definitions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $requiredFunctions -contains $node.Name
}, $true) | Sort-Object { $_.Extent.StartOffset }

foreach ($definition in $definitions) {
    Invoke-Expression $definition.Extent.Text
}

$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("mtt-terminology-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($testDirectory)
function Get-ToolkitSettingsDirectory { return $testDirectory }

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERTION FAILED: $message" }
}

try {
    # v0.10.24 compatibility: old Source/Target-only CSV must still load.
    $oldCsv = @"
"Enabled";"Source";"Target";"Scope";"Module";"DefType";"Field";"PackageId";"Confidence";"Learned"
"True";"armor";"pancerz RW";"All";"";"ThingDef";"label";"";"0";"False"
"@
    [System.IO.File]::WriteAllText(
        (Get-RimWorldGlossaryPath), $oldCsv,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $loaded = @(Get-RimWorldGlossary)
    Assert-True ($loaded.Count -ge 4) "Old glossary and general defaults should load together."
    Assert-True (@($loaded | Where-Object { $_.Source -eq "armor" -and $_.Target -eq "pancerz RW" }).Count -eq 1) "Old Source/Target columns were not migrated."

    $modRule = New-RimWorldGlossaryRule "armor" "pancerz modowy" "Mod" "" "ThingDef" "label" "test.mod" $true "zbroja modowa" "armour" "ThingDef | apparel" "Test override" "Mod"
    [void](Save-RimWorldGlossary @($loaded + $modRule))
    Assert-True (Test-Path -LiteralPath (Get-GeneralGlossaryPath)) "General glossary file was not written."
    Assert-True (Test-Path -LiteralPath (Get-RimWorldGlossaryPath)) "RimWorld/mod glossary file was not written."

    $script:OriginalPackageId = "test.mod"
    $entry = [pscustomobject]@{
        Source="armor"; Translation="pancerz modowy"; DefType="ThingDef"; Field="label"
        Key="TestArmor.label"; File="DefInjected/ThingDef/Test.xml"; Kind="DefInjected"
    }
    $matching = @(Get-MatchingRimWorldGlossaryRules $entry "Mod")
    Assert-True ($matching.Count -ge 1) "No terminology rule matched the entry."
    Assert-True ($matching[0].Target -eq "pancerz modowy") "Mod layer did not override RimWorld and general layers."

    $termMap = $null
    $protected = Protect-RimWorldGlossaryTerms "advanced armor" $matching ([ref]$termMap)
    $restored = Restore-RimWorldGlossaryTerms $protected $termMap
    Assert-True ($restored -eq "advanced pancerz modowy") "Preferred term was not protected/restored for automatic translation."

    $aiContext = Get-RimWorldAiTerminologyContext $entry "Mod"
    Assert-True ($aiContext -match "pancerz modowy") "Preferred term is missing from AI context."
    Assert-True ($aiContext -match "zbroja modowa") "Allowed alternative is missing from AI context."
    Assert-True ($aiContext -match "armour") "Forbidden variant is missing from AI context."

    $previewRows = @(Get-RimWorldDictionaryPreviewRows $entry "Mod" "armor")
    Assert-True ($previewRows.Count -eq 2) "Preferred term and its alternative were not split into selectable results."
    $preferredRows = @($previewRows | Where-Object { $_.Translation -eq "pancerz modowy" })
    $alternativeRows = @($previewRows | Where-Object { $_.Translation -eq "zbroja modowa" })
    Assert-True ($preferredRows.Count -eq 1) "Dictionary preview ignored terminology priority."
    Assert-True ($alternativeRows.Count -eq 1) "Dictionary preview omitted an alternative."

    $script:LocalEnPlDictionaryCache = @([pscustomobject]@{
        Term="damage"; Preferred="obrazenia-test"; Alternatives="uszkodzenia-test"; Notes="Local test row"
    })
    $localEntry = [pscustomobject]@{
        Source="Damage: 10"; Translation=""; DefType="StatDef"; Field="label"
        Key="Damage.label"; File="DefInjected/StatDef/Test.xml"; Kind="DefInjected"
    }
    $localRows = @(Get-RimWorldDictionaryPreviewRows $localEntry "Mod" " damage! ")
    Assert-True ($localRows.Count -eq 2) "Bundled local dictionary did not return its preferred and alternative results."
    $localPreferredRows = @($localRows | Where-Object { $_.Layer -eq "Lokalny" -and $_.Kind -ne "Alternatywa" })
    Assert-True ($localPreferredRows.Count -eq 1) "Local dictionary preferred result is missing."
    Assert-True ((Normalize-RimWorldDictionarySelection "  damage! ") -eq "damage") "Selected punctuation was not normalized."
    Assert-True ([string]::IsNullOrEmpty((Normalize-RimWorldDictionarySelection "one two three four five six seven"))) "Long selections should not trigger dictionary lookup."

    # Single-click has no mutation handler. The double-click target function must
    # fill an empty value, append instead of overwrite, and replace a selected fragment.
    $grid = New-Object System.Windows.Controls.DataGrid
    $grid.ItemsSource = @($localEntry)
    $grid.SelectedIndex = 0
    $txtDictionaryPreviewHint = New-Object System.Windows.Controls.TextBlock
    $dictionaryPreviewGrid = New-Object System.Windows.Controls.DataGrid
    Assert-True (Use-RimWorldDictionaryChoice $localRows[0]) "Dictionary choice was not applied."
    Assert-True ($localEntry.Translation -eq "obrazenia-test") "An empty translation was not filled."
    Assert-True (Use-RimWorldDictionaryChoice $localRows[1]) "Dictionary alternative was not applied."
    Assert-True ($localEntry.Translation -eq "obrazenia-test uszkodzenia-test") "Existing translation was overwritten instead of appended."

    $localEntry.Translation = "prefix old suffix"
    $editorBox = New-Object System.Windows.Controls.TextBox
    $editorBox.Text = $localEntry.Translation
    $script:RimWorldModActiveTranslationEntry = $localEntry
    $script:RimWorldModActiveTranslationBox = $editorBox
    $script:RimWorldModTranslationSelectionStart = 7
    $script:RimWorldModTranslationSelectionLength = 3
    Assert-True (Use-RimWorldDictionaryChoice $localRows[0]) "Dictionary choice did not replace the selected fragment."
    Assert-True ($localEntry.Translation -eq "prefix obrazenia-test suffix") "Selected fragment replacement produced the wrong text."

    Assert-True (Add-RimWorldDictionaryChoiceToGlossary $localRows[0]) "Add to Glossary did not create a rule."
    $addedRules = @(Get-RimWorldGlossary | Where-Object {
        $_.Source -eq "damage" -and $_.Target -eq "obrazenia-test" -and $_.Layer -eq "Mod"
    })
    Assert-True ($addedRules.Count -eq 1) "The dictionary choice is missing from the Mod glossary layer."
    Assert-True (-not (Add-RimWorldDictionaryChoiceToGlossary $localRows[0])) "Duplicate Add to Glossary should be rejected."

    $entry2 = [pscustomobject]@{
        Source="armor"; Translation="zbroja modowa"; DefType="ThingDef"; Field="label"
        Key="OtherArmor.label"; File="DefInjected/ThingDef/Test.xml"; Kind="DefInjected"
    }
    $issues = @(Get-RimWorldTerminologyIssues @($entry,$entry2) "Mod")
    Assert-True ($issues.Count -eq 2) "Expected two inconsistency rows for two different allowed variants."

    "Terminology tests: PASS"
} finally {
    if ([System.IO.Directory]::Exists($testDirectory)) {
        [System.IO.Directory]::Delete($testDirectory, $true)
    }
}
