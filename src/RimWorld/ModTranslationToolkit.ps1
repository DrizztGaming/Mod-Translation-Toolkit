# Mod Translation Toolkit v0.1.0
# First supported profile: RimWorld
# Windows PowerShell 5.1+, no Python required.

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$AppVersion = "0.5.5"
$script:UiLanguage = "pl"
$script:Entries = New-Object System.Collections.ArrayList
$script:Mods = New-Object System.Collections.ArrayList
$script:OriginalModPath = ""
$script:OriginalModName = ""
$script:OriginalPackageId = ""
$script:OriginalVersion = ""
$script:DetectedFromDefs = $false
$script:OriginalSupportedVersions = @()
$script:OriginalWorkshopUrl = ""
$script:OriginalDownloadUrl = ""
$script:OriginalAuthor = ""
$script:LastWorkshopDescriptionPath = ""
$script:LanguageCoverage = @{}
$script:ExistingTranslations = @{}
$script:EditingTranslationModPath = ""
$script:EditingTranslationPackageId = ""
$script:EditingTranslationName = ""
$script:UpdateMode = $false
$script:UpdateTranslationPath = ""
$script:UpdateOriginalPath = ""
$script:UpdateStats = $null
$script:SearchFilteredEntries = @()
$script:KeybindDiagnostics = New-Object System.Collections.ArrayList
$script:KeybindDefCount = 0
$script:AssemblyDiagnostics = New-Object System.Collections.ArrayList
$script:AssemblyDiagnosticFiles = 0
$script:AssemblyDiagnosticsScannedPath = ""

$script:KeybindLocalizableCount = 0
$script:WorkshopItems = New-Object System.Collections.ArrayList
$script:CreatorProfile = [ordered]@{
    CreatorName = ""
    SteamProfile = ""
}

$script:SelectedContentVersion = ""
$script:EntryKeys = @{}
$script:KenshiEntries = New-Object System.Collections.ArrayList
$script:KenshiRoot = ""
$script:KenshiUiSource = ""
$script:KenshiFcsBase = ""
$script:KenshiSkippedPlural = 0


# ---------- Core helpers ----------
function XmlEscape([string]$s) {
    if ($null -eq $s) { return "" }
    return [System.Security.SecurityElement]::Escape($s)
}

function Get-TextContent($node) {
    if ($null -eq $node) { return "" }
    return [string]$node.InnerText
}

function Get-Placeholders([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return @() }
    $tokens = @()
    $tokens += ([regex]::Matches($text, '\{\d+(?::[^}]*)?\}') | ForEach-Object Value)
    $tokens += ([regex]::Matches($text, '%[sdif]') | ForEach-Object Value)
    $tokens += ([regex]::Matches($text, '\\n') | ForEach-Object Value)
    return @($tokens | Sort-Object)
}

function Translate-Google([string]$text, [string]$sourceLang="en", [string]$targetLang="pl") {
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    $map = @{}
    $counter = 0
    $protected = $text
    $patterns = @('\{\d+(?::[^}]*)?\}', '%[sdif]', '\\n', '<[^>]+>')

    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches($protected, $pattern)
        foreach ($m in @($matches | Sort-Object Index -Descending)) {
            $key = "__RWPH$counter`__"
            $map[$key] = $m.Value
            $protected = $protected.Remove($m.Index, $m.Length).Insert($m.Index, $key)
            $counter++
        }
    }

    $escaped = [uri]::EscapeDataString($protected)
    $url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$sourceLang&tl=$targetLang&dt=t&q=$escaped"
    $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 25

    $translated = ""
    foreach ($part in $resp[0]) {
        if ($part[0]) { $translated += [string]$part[0] }
    }

    foreach ($k in $map.Keys) {
        $translated = $translated.Replace($k, $map[$k])
    }
    return $translated
}

# ---------- RimWorld profile ----------
function Get-AboutInfo([string]$modPath) {
    $name = Split-Path $modPath -Leaf
    $packageId = ""
    $version = ""
    $author = ""
    $supported = @()
    $workshopUrl = ""
    $downloadUrl = ""
    $about = Join-Path $modPath "About\About.xml"

    if (Test-Path $about) {
        try {
            [xml]$x = Get-Content -LiteralPath $about -Raw -Encoding UTF8

            $nameNode = $x.ModMetaData.SelectSingleNode("name")
            if ($null -ne $nameNode) { $name = $nameNode.InnerText.Trim() }

            $packageNode = $x.ModMetaData.SelectSingleNode("packageId")
            if ($null -ne $packageNode) { $packageId = $packageNode.InnerText.Trim() }

            $versionNode = $x.ModMetaData.SelectSingleNode("modVersion")
            if ($null -ne $versionNode) { $version = $versionNode.InnerText.Trim() }

            $authorNode = $x.ModMetaData.SelectSingleNode("author")
            if ($null -ne $authorNode) { $author = $authorNode.InnerText.Trim() }

            $supportedNodes = $x.ModMetaData.SelectNodes("supportedVersions/li")
            foreach ($n in $supportedNodes) {
                $v = $n.InnerText.Trim()
                if ($v) { $supported += $v }
            }

            $steamNode = $x.ModMetaData.SelectSingleNode("steamWorkshopUrl")
            if ($null -ne $steamNode) { $workshopUrl = $steamNode.InnerText.Trim() }

            $downloadNode = $x.ModMetaData.SelectSingleNode("downloadUrl")
            if ($null -ne $downloadNode) { $downloadUrl = $downloadNode.InnerText.Trim() }
        } catch {}
    }

    # Workshop mods usually do not store their own Workshop URL in About.xml.
    # Derive it from ...\workshop\content\294100\<PublishedFileId>.
    if ([string]::IsNullOrWhiteSpace($workshopUrl)) {
        try {
            $full = [System.IO.Path]::GetFullPath($modPath).TrimEnd('\','/')
            if ($full -match '[\\/]workshop[\\/]content[\\/]294100[\\/]([0-9]+)$') {
                $workshopUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($Matches[1])"
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($downloadUrl) -and [string]::IsNullOrWhiteSpace($workshopUrl) -and $packageId) {
        $q = [uri]::EscapeDataString($packageId)
        $downloadUrl = "https://steamcommunity.com/workshop/browse/?appid=294100&searchtext=$q"
    }

    return [pscustomobject]@{
        Name = $name
        PackageId = $packageId
        Version = $version
        Author = $author
        SupportedVersions = @($supported)
        WorkshopUrl = $workshopUrl
        DownloadUrl = $downloadUrl
    }
}

function Read-AboutXml([string]$modPath) {
    $i = Get-AboutInfo $modPath
    $script:OriginalModName = $i.Name
    $script:OriginalPackageId = $i.PackageId
    $script:OriginalVersion = $i.Version
    $script:OriginalSupportedVersions = @($i.SupportedVersions)
    $script:OriginalWorkshopUrl = $i.WorkshopUrl
    $script:OriginalDownloadUrl = $i.DownloadUrl
    $script:OriginalAuthor = $i.Author
}

function Add-Entry([string]$kind, [string]$relativeFile, [string]$key, [string]$source, [string]$defType="", [string]$defName="", [string]$field="") {
    if ([string]::IsNullOrWhiteSpace($source)) { return }

    # A translation key may occur in several version folders.
    # Keep only one final entry per output file/key to avoid duplicate XML nodes.
    $identity = "$kind|$relativeFile|$key".ToLowerInvariant()
    if ($script:EntryKeys.ContainsKey($identity)) {
        return
    }
    $script:EntryKeys[$identity] = $true

    [void]$script:Entries.Add([pscustomobject]@{
        Kind = $kind
        File = $relativeFile
        Key = $key
        Source = $source.TrimEnd()
        Translation = ""
        DefType = $defType
        DefName = $defName
        Field = $field
    })
}

function Get-LanguageRoots([string]$modPath) {
    $roots = New-Object System.Collections.ArrayList
    $seen = @{}

    function Add-LanguageRoot([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $modPath $p }
        if (-not (Test-Path $p)) { return }

        try {
            $norm = [System.IO.Path]::GetFullPath($p).TrimEnd('\','/').ToLowerInvariant()
        } catch {
            $norm = $p.TrimEnd('\','/').ToLowerInvariant()
        }

        if (-not $seen.ContainsKey($norm)) {
            $seen[$norm] = $true
            [void]$roots.Add($p)
        }
    }

    # Classic root localization.
    Add-LanguageRoot (Join-Path $modPath "Languages\English")

    $preferred = Get-PreferredContentVersion $modPath
    if ($preferred) {
        Add-LanguageRoot (Join-Path (Join-Path $modPath $preferred) "Languages\English")
    }

    # Follow LoadFolders.xml for the selected RimWorld version.
    $loadFolders = Join-Path $modPath "LoadFolders.xml"
    if (Test-Path $loadFolders) {
        try {
            [xml]$lf = Get-Content -LiteralPath $loadFolders -Raw -Encoding UTF8
            $section = $null

            if ($preferred) {
                $section = $lf.loadFolders.SelectSingleNode("v$preferred")
            }

            if ($null -eq $section) {
                $sections = @($lf.loadFolders.ChildNodes | Where-Object {
                    $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.Name -match '^v[0-9]+\.[0-9]+$'
                })

                $section = $sections | Sort-Object {
                    $v = $_.Name.Substring(1)
                    $t = Get-VersionTuple $v
                    ($t[0] * 1000) + $t[1]
                } -Descending | Select-Object -First 1
            }

            if ($null -ne $section) {
                foreach ($li in $section.SelectNodes("li")) {
                    $rel = $li.InnerText.Trim()

                    if (-not $rel -or $rel -eq "/") {
                        Add-LanguageRoot (Join-Path $modPath "Languages\English")
                        continue
                    }

                    $base = Join-Path $modPath $rel
                    Add-LanguageRoot (Join-Path $base "Languages\English")
                }
            }
        } catch {}
    }

    return @($roots)
}


function Get-LanguageFolderName([string]$code) {
    switch ($code) {
        "pl" { return "Polish" }
        "en" { return "English" }
        default { return $code }
    }
}

function Get-LanguageRootsForCode([string]$modPath, [string]$code) {
    $folderName = Get-LanguageFolderName $code
    $roots = New-Object System.Collections.ArrayList
    $seen = @{}

    function Add-Root([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $modPath $p }
        if (-not (Test-Path $p)) { return }

        try {
            $norm = [System.IO.Path]::GetFullPath($p).TrimEnd('\','/').ToLowerInvariant()
        } catch {
            $norm = $p.TrimEnd('\','/').ToLowerInvariant()
        }

        if (-not $seen.ContainsKey($norm)) {
            $seen[$norm] = $true
            [void]$roots.Add($p)
        }
    }

    Add-Root (Join-Path $modPath "Languages\$folderName")

    $preferred = Get-PreferredContentVersion $modPath
    if ($preferred) {
        Add-Root (Join-Path (Join-Path $modPath $preferred) "Languages\$folderName")
    }

    $loadFolders = Join-Path $modPath "LoadFolders.xml"
    if (Test-Path $loadFolders) {
        try {
            [xml]$lf = Get-Content -LiteralPath $loadFolders -Raw -Encoding UTF8
            $section = $null

            if ($preferred) {
                $section = $lf.loadFolders.SelectSingleNode("v$preferred")
            }

            if ($null -eq $section) {
                $sections = @($lf.loadFolders.ChildNodes | Where-Object {
                    $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.Name -match '^v[0-9]+\.[0-9]+$'
                })

                $section = $sections | Sort-Object {
                    $v = $_.Name.Substring(1)
                    $t = Get-VersionTuple $v
                    ($t[0] * 1000) + $t[1]
                } -Descending | Select-Object -First 1
            }

            if ($null -ne $section) {
                foreach ($li in $section.SelectNodes("li")) {
                    $rel = $li.InnerText.Trim()

                    if (-not $rel -or $rel -eq "/") {
                        Add-Root (Join-Path $modPath "Languages\$folderName")
                        continue
                    }

                    $base = Join-Path $modPath $rel
                    Add-Root (Join-Path $base "Languages\$folderName")
                }
            }
        } catch {}
    }

    return @($roots)
}

function Read-LanguageEntries([string]$modPath, [string]$code) {
    $entries = @{}
    $roots = @(Get-LanguageRootsForCode $modPath $code)

    foreach ($langRoot in $roots) {
        if (-not (Test-Path $langRoot)) { continue }

        Get-ChildItem -LiteralPath $langRoot -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | ForEach-Object {
            $file = $_
            try {
                [xml]$doc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                if ($null -eq $doc.DocumentElement -or $doc.DocumentElement.Name -ne "LanguageData") { return }

                $rel = $file.FullName.Substring($langRoot.Length).TrimStart('\','/')
                foreach ($child in $doc.DocumentElement.ChildNodes) {
                    if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    $id = "$rel|$($child.Name)".ToLowerInvariant()
                    if (-not $entries.ContainsKey($id)) {
                        $entries[$id] = [pscustomobject]@{
                            File = $rel
                            Key = $child.Name
                            Text = (Get-TextContent $child)
                        }
                    }
                }
            } catch {}
        }
    }

    return $entries
}

function Update-LanguageCoverage([string]$modPath) {
    $script:LanguageCoverage = @{}
    $script:ExistingTranslations = @{}

    $sourceCount = $script:Entries.Count
    foreach ($code in @("pl","en")) {
        $entries = Read-LanguageEntries $modPath $code
        $script:ExistingTranslations[$code] = $entries

        $matched = 0
        foreach ($e in $script:Entries) {
            $id = "$($e.File)|$($e.Key)".ToLowerInvariant()
            if ($entries.ContainsKey($id)) { $matched++ }
        }

        $percent = if ($sourceCount -gt 0) {
            [Math]::Round(($matched * 100.0) / $sourceCount, 1)
        } else { 0 }

        $status = if ($matched -eq 0) {
            "none"
        } elseif ($matched -lt $sourceCount) {
            "partial"
        } else {
            "complete"
        }

        $script:LanguageCoverage[$code] = [pscustomobject]@{
            Found = $entries.Count
            Matched = $matched
            Total = $sourceCount
            Percent = $percent
            Status = $status
        }
    }
}


function Get-SelectedTargetLanguageCode {
    try {
        if ($null -ne $cmbTargetLang -and $null -ne $cmbTargetLang.SelectedItem) {
            return [string]$cmbTargetLang.SelectedItem.Tag
        }
    } catch {}
    return "pl"
}

function AutoLoad-ExistingTargetTranslation {
    $code = Get-SelectedTargetLanguageCode

    if (-not $script:ExistingTranslations.ContainsKey($code)) {
        return 0
    }

    $entries = $script:ExistingTranslations[$code]
    if ($null -eq $entries -or $entries.Count -eq 0) {
        return 0
    }

    $loaded = 0

    foreach ($e in $script:Entries) {
        $id = "$($e.File)|$($e.Key)".ToLowerInvariant()

        if ($entries.ContainsKey($id)) {
            # Existing localization wins. Do not overwrite it with machine translation.
            $existingText = [string]$entries[$id].Text
            if (-not [string]::IsNullOrWhiteSpace($existingText)) {
                $e.Translation = $existingText
                $loaded++
            }
        }
    }

    Refresh-Grid
    return $loaded
}

function Apply-ExistingTranslation([string]$code) {
    if (-not $script:ExistingTranslations.ContainsKey($code)) { return 0 }

    $entries = $script:ExistingTranslations[$code]
    $loaded = 0

    foreach ($e in $script:Entries) {
        $id = "$($e.File)|$($e.Key)".ToLowerInvariant()
        if ($entries.ContainsKey($id)) {
            $e.Translation = [string]$entries[$id].Text
            $loaded++
        }
    }

    Refresh-Grid
    return $loaded
}

function Scan-EnglishLanguages([string]$modPath) {
    $countBefore = $script:Entries.Count
    $roots = @(Get-LanguageRoots $modPath)

    foreach ($english in $roots) {
        if (-not (Test-Path $english)) { continue }

        Get-ChildItem -LiteralPath $english -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | ForEach-Object {
            $file = $_

            try {
                [xml]$doc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                if ($null -eq $doc.DocumentElement) { return }

                $rootName = $doc.DocumentElement.Name
                if ($rootName -ne "LanguageData") { return }

                $rel = $file.FullName.Substring($english.Length).TrimStart('\','/')

                # Preserve the localization branch:
                # Keyed\Foo.xml -> Keyed\Foo.xml
                # DefInjected\ThingDef\ThingDef.xml -> same relative target path
                $kind = if ($rel -like "DefInjected\*") { "DefInjected" } else { "Language" }

                foreach ($child in $doc.DocumentElement.ChildNodes) {
                    if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                    Add-Entry $kind $rel $child.Name (Get-TextContent $child)
                }
            } catch {}
        }
    }

    return ($script:Entries.Count - $countBefore)
}

function Get-VersionTuple([string]$v) {
    if ($v -match '^\s*([0-9]+)\.([0-9]+)') {
        return @([int]$Matches[1], [int]$Matches[2])
    }
    return @(0,0)
}

function Get-PreferredContentVersion([string]$modPath) {
    # Prefer the newest supported RimWorld version declared by the mod.
    $versions = @($script:OriginalSupportedVersions)
    if ($versions.Count -eq 0) {
        # Fallback: inspect version-like folders.
        Get-ChildItem -LiteralPath $modPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^[0-9]+\.[0-9]+$') { $versions += $_.Name }
        }
    }

    if ($versions.Count -eq 0) { return "" }

    return ($versions | Sort-Object {
        $t = Get-VersionTuple $_
        ($t[0] * 1000) + $t[1]
    } -Descending | Select-Object -First 1)
}

function Get-DefRoots([string]$modPath) {
    $roots = New-Object System.Collections.ArrayList
    $seen = @{}

    function Add-Root([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $modPath $p }
        if (-not (Test-Path $p)) { return }
        try { $norm = [System.IO.Path]::GetFullPath($p).TrimEnd('\','/').ToLowerInvariant() } catch { $norm = $p.ToLowerInvariant() }
        if (-not $seen.ContainsKey($norm)) {
            $seen[$norm] = $true
            [void]$roots.Add($p)
        }
    }

    # Root Defs is always eligible.
    Add-Root (Join-Path $modPath "Defs")

    $preferred = Get-PreferredContentVersion $modPath
    $script:SelectedContentVersion = $preferred

    $loadFolders = Join-Path $modPath "LoadFolders.xml"
    if (Test-Path $loadFolders) {
        try {
            [xml]$lf = Get-Content -LiteralPath $loadFolders -Raw -Encoding UTF8

            $section = $null
            if ($preferred) {
                $section = $lf.loadFolders.SelectSingleNode("v$preferred")
            }

            if ($null -eq $section) {
                # Choose newest vX.Y section when supportedVersions is absent/mismatched.
                $sections = @($lf.loadFolders.ChildNodes | Where-Object {
                    $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.Name -match '^v[0-9]+\.[0-9]+$'
                })
                $section = $sections | Sort-Object {
                    $v = $_.Name.Substring(1)
                    $t = Get-VersionTuple $v
                    ($t[0] * 1000) + $t[1]
                } -Descending | Select-Object -First 1
                if ($null -ne $section) { $script:SelectedContentVersion = $section.Name.Substring(1) }
            }

            if ($null -ne $section) {
                foreach ($li in $section.SelectNodes("li")) {
                    $rel = $li.InnerText.Trim()
                    if (-not $rel -or $rel -eq "/") {
                        Add-Root (Join-Path $modPath "Defs")
                        continue
                    }

                    # Translate optional integration folders too if they physically exist.
                    # This makes the generated translation usable if the integration is enabled later.
                    $base = Join-Path $modPath $rel
                    Add-Root (Join-Path $base "Defs")
                }
            }
        } catch {}
    } elseif ($preferred) {
        Add-Root (Join-Path (Join-Path $modPath $preferred) "Defs")
    }

    # Final fallback for mods with version directories but no LoadFolders.xml.
    if ($roots.Count -le 1 -and $preferred) {
        Add-Root (Join-Path (Join-Path $modPath $preferred) "Defs")
    }

    return @($roots)
}



function Get-PrintableStringsFromBytes([byte[]]$bytes, [int]$minLength = 4) {
    $results = New-Object System.Collections.ArrayList

    # ASCII / UTF-8-ish printable runs
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) {
        if (($b -ge 32 -and $b -le 126) -or $b -eq 9) {
            [void]$sb.Append([char]$b)
        } else {
            if ($sb.Length -ge $minLength) {
                [void]$results.Add($sb.ToString())
            }
            [void]$sb.Clear()
        }
    }
    if ($sb.Length -ge $minLength) {
        [void]$results.Add($sb.ToString())
    }

    # UTF-16LE printable runs
    $sb2 = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt ($bytes.Length - 1); $i += 2) {
        $lo = $bytes[$i]
        $hi = $bytes[$i + 1]

        if ($hi -eq 0 -and $lo -ge 32 -and $lo -le 126) {
            [void]$sb2.Append([char]$lo)
        } else {
            if ($sb2.Length -ge $minLength) {
                [void]$results.Add($sb2.ToString())
            }
            [void]$sb2.Clear()
        }
    }
    if ($sb2.Length -ge $minLength) {
        [void]$results.Add($sb2.ToString())
    }

    return @($results | Select-Object -Unique)
}

function Get-AssemblyUiKeywords {
    return @(
        "Hotkey",
        "KeyBindingDef",
        "KeyBindingDefOf",
        "Tooltip",
        "TooltipHandler",
        "Gizmo",
        "Command",
        "Widgets",
        "FloatMenuOption",
        "MouseoverSounds",
        "Translate",
        "TaggedString",
        "DoTimeControlsGUI",
        "Prefix",
        "Postfix",
        "Transpiler",
        "HarmonyPatch"
    )
}


function Get-ActiveAssemblyDirectories([string]$modPath) {
    $dirs = New-Object System.Collections.ArrayList

    $rootAssemblies = Join-Path $modPath "Assemblies"
    if (Test-Path $rootAssemblies) {
        [void]$dirs.Add($rootAssemblies)
    }

    # Prefer version folders resolved by the same profile logic as Def scanning.
    try {
        $preferredVersion = Get-PreferredVersionFolder $modPath
        if (-not [string]::IsNullOrWhiteSpace([string]$preferredVersion)) {
            $candidate = Join-Path $preferredVersion "Assemblies"
            if (Test-Path $candidate) {
                [void]$dirs.Add($candidate)
            }
        }
    } catch {}

    # Fallback: newest numeric version folder only.
    if ($dirs.Count -eq 0) {
        $versionDirs = @(
            Get-ChildItem -LiteralPath $modPath -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d+(\.\d+)+$' -and
                (Test-Path (Join-Path $_.FullName "Assemblies"))
            } |
            Sort-Object {
                try { [version]$_.Name } catch { [version]"0.0" }
            } -Descending
        )
        if ($versionDirs.Count -gt 0) {
            [void]$dirs.Add((Join-Path $versionDirs[0].FullName "Assemblies"))
        }
    }

    return @($dirs | Select-Object -Unique)
}

function Test-SkipDiagnosticAssembly([string]$fileName) {
    if ([string]::IsNullOrWhiteSpace($fileName)) { return $true }

    $n = $fileName.ToLowerInvariant()
    $skipNames = @(
        "0harmony.dll",
        "harmony.dll",
        "harmonymod.dll",
        "hugslib.dll",
        "newtonsoft.json.dll",
        "system.runtime.compilerservices.unsafe.dll"
    )

    if ($skipNames -contains $n) { return $true }
    if ($n -match '^(system\.|microsoft\.|mono\.|unityengine\.|unity\.|netstandard)') { return $true }

    return $false
}

function Scan-AssemblyUiDiagnostics([string]$modPath) {
    $script:AssemblyDiagnostics.Clear()
    $script:AssemblyDiagnosticFiles = 0

    $assemblyDirs = @(Get-ActiveAssemblyDirectories $modPath)

    $seen = @{}
    foreach ($dir in @($assemblyDirs)) {
        Get-ChildItem -LiteralPath $dir -Filter *.dll -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $dll = $_
            if (Test-SkipDiagnosticAssembly $dll.Name) { return }
            $norm = $dll.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($norm)) { return }
            $seen[$norm] = $true
            $script:AssemblyDiagnosticFiles++

            try {
                $bytes = [System.IO.File]::ReadAllBytes($dll.FullName)
                $strings = @(Get-PrintableStringsFromBytes $bytes 4)
                $hits = New-Object System.Collections.ArrayList

                foreach ($keyword in @(Get-AssemblyUiKeywords)) {
                    foreach ($s in $strings) {
                        if ($s.IndexOf($keyword, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            [void]$hits.Add([pscustomobject]@{
                                Keyword = $keyword
                                Text = $s
                            })
                        }
                    }
                }

                if ($hits.Count -gt 0) {
                    $rel = ""
                    try { $rel = $dll.FullName.Substring($modPath.Length).TrimStart('\','/') }
                    catch { $rel = $dll.Name }

                    # Keep only a compact set of unique evidence lines.
                    $unique = @(
                        $hits |
                        Group-Object Keyword,Text |
                        ForEach-Object { $_.Group[0] } |
                        Select-Object -First 40
                    )

                    [void]$script:AssemblyDiagnostics.Add([pscustomobject]@{
                        File = $rel
                        Hits = $unique
                    })
                }
            } catch {}
        }
    }

    $script:AssemblyDiagnosticsScannedPath = $modPath

    return [pscustomobject]@{
        Files = $script:AssemblyDiagnosticFiles
        Matches = $script:AssemblyDiagnostics.Count
    }
}

function Get-AssemblyDiagnosticsText {
    $isEn = ($script:UiLanguage -eq "en")

    if ($script:AssemblyDiagnosticFiles -eq 0) {
        if ($isEn) { return "No DLL files were found in the active Assemblies folder." }
        return "Nie znaleziono plików DLL w aktywnym folderze Assemblies."
    }

    if ($script:AssemblyDiagnostics.Count -eq 0) {
        if ($isEn) {
            return "DLL files scanned: $($script:AssemblyDiagnosticFiles). No characteristic UI/translation references or strings were found."
        }
        return "Przeskanowano DLL: $($script:AssemblyDiagnosticFiles). Nie znaleziono charakterystycznych odwołań/stringów UI lub tłumaczeń."
    }

    $sb = New-Object System.Text.StringBuilder

    if ($isEn) {
        [void]$sb.AppendLine("DLL files scanned: $($script:AssemblyDiagnosticFiles)")
        [void]$sb.AppendLine("DLLs with potential UI references: $($script:AssemblyDiagnostics.Count)")
    } else {
        [void]$sb.AppendLine("Przeskanowano DLL: $($script:AssemblyDiagnosticFiles)")
        [void]$sb.AppendLine("DLL z potencjalnymi odwołaniami UI: $($script:AssemblyDiagnostics.Count)")
    }

    [void]$sb.AppendLine("")

    foreach ($entry in @($script:AssemblyDiagnostics)) {
        [void]$sb.AppendLine("[$($entry.File)]")

        foreach ($hit in @($entry.Hits)) {
            $display = [string]$hit.Text
            if ($display.Length -gt 180) {
                $display = $display.Substring(0,180) + "..."
            }
            [void]$sb.AppendLine("• $($hit.Keyword): $display")
        }

        [void]$sb.AppendLine("")
    }

    if ($isEn) {
        [void]$sb.AppendLine("How to read this report:")
        [void]$sb.AppendLine("• Tooltip / TooltipHandler / Widgets / Gizmo / Command — the assembly creates or modifies visible UI.")
        [void]$sb.AppendLine("• Translate / TaggedString — the code uses RimWorld's localization API somewhere in the assembly.")
        [void]$sb.AppendLine("• HarmonyPatch / Prefix / Postfix / Transpiler — the mod patches existing RimWorld or mod code.")
        [void]$sb.AppendLine("• DoTimeControlsGUI and similar method names — useful clues about which game screen or UI element is being changed.")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Interpretation:")
        [void]$sb.AppendLine("Several UI + Harmony markers together strongly suggest that some visible text may be generated or modified in code.")
        [void]$sb.AppendLine("That does NOT automatically mean the text is hardcoded, and it does not prove that a normal language file can replace it.")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Toolkit diagnostics are read-only. Assemblies are never patched.")
    } else {
        [void]$sb.AppendLine("Jak czytać ten raport:")
        [void]$sb.AppendLine("• Tooltip / TooltipHandler / Widgets / Gizmo / Command — DLL tworzy lub modyfikuje widoczny interfejs.")
        [void]$sb.AppendLine("• Translate / TaggedString — kod korzysta gdzieś z systemu lokalizacji RimWorlda.")
        [void]$sb.AppendLine("• HarmonyPatch / Prefix / Postfix / Transpiler — mod patchuje istniejący kod gry lub innego moda.")
        [void]$sb.AppendLine("• DoTimeControlsGUI i podobne nazwy metod — wskazują, jaki ekran lub element UI jest modyfikowany.")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Interpretacja:")
        [void]$sb.AppendLine("Kilka sygnałów UI + Harmony naraz mocno sugeruje, że część widocznego tekstu może być generowana lub zmieniana w kodzie.")
        [void]$sb.AppendLine("Nie oznacza to automatycznie tekstu hardcoded i nie gwarantuje, że zwykły plik językowy może go zastąpić.")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Diagnostyka Toolkita jest tylko do odczytu. DLL nigdy nie są patchowane.")
    }

    return $sb.ToString()
}

function Scan-KeyBindingDefs([string]$modPath) {
    $script:KeybindDiagnostics.Clear()
    $script:KeybindDefCount = 0
    $script:KeybindLocalizableCount = 0

    $roots = @(Get-DefRoots $modPath)

    foreach ($defs in $roots) {
        if (-not (Test-Path $defs)) { continue }

        Get-ChildItem -LiteralPath $defs -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | ForEach-Object {
            $file = $_
            try {
                [xml]$doc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                if ($null -eq $doc.DocumentElement -or $doc.DocumentElement.Name -ne "Defs") { return }

                foreach ($def in $doc.DocumentElement.ChildNodes) {
                    if ($def.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    if ($def.Name -ne "KeyBindingDef") { continue }

                    $defNameNode = $def.SelectSingleNode("defName")
                    if ($null -eq $defNameNode -or [string]::IsNullOrWhiteSpace($defNameNode.InnerText)) { continue }

                    $script:KeybindDefCount++
                    $defName = $defNameNode.InnerText.Trim()

                    $labelNode = $def.SelectSingleNode("label")
                    $descNode = $def.SelectSingleNode("description")

                    $hasLabel = ($null -ne $labelNode -and -not [string]::IsNullOrWhiteSpace($labelNode.InnerText))
                    $hasDesc = ($null -ne $descNode -and -not [string]::IsNullOrWhiteSpace($descNode.InnerText))

                    if ($hasLabel -or $hasDesc) {
                        $script:KeybindLocalizableCount++

                        # Scan-Defs already catches these fields. The diagnostics pass
                        # deliberately doesn't duplicate translation entries.
                        continue
                    }

                    $rel = ""
                    try { $rel = $file.FullName.Substring($defs.Length).TrimStart('\','/') } catch { $rel = $file.Name }

                    [void]$script:KeybindDiagnostics.Add([pscustomobject]@{
                        DefName = $defName
                        File = $rel
                        Issue = "No label/description"
                        Explanation = "KeyBindingDef exists but exposes no label or description in Defs. Any visible Hotkey/keybind text may be generated by RimWorld UI or by code and cannot be translated through this Def alone."
                    })
                }
            } catch {}
        }
    }

    return [pscustomobject]@{
        Total = $script:KeybindDefCount
        Localizable = $script:KeybindLocalizableCount
        Diagnostic = $script:KeybindDiagnostics.Count
    }
}

function Get-KeybindDiagnosticsText {
    if ($script:KeybindDefCount -eq 0) {
        return "Nie wykryto KeyBindingDef w tym modzie."
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("KeyBindingDef: $($script:KeybindDefCount)")
    [void]$sb.AppendLine("Z własnym label/description: $($script:KeybindLocalizableCount)")
    [void]$sb.AppendLine("Do diagnostyki UI: $($script:KeybindDiagnostics.Count)")
    [void]$sb.AppendLine("")

    if ($script:KeybindDiagnostics.Count -gt 0) {
        [void]$sb.AppendLine("Potencjalnie generowane przez RimWorld UI / kod moda:")
        foreach ($d in @($script:KeybindDiagnostics)) {
            [void]$sb.AppendLine("• $($d.DefName)  [$($d.File)]")
        }
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Brak label/description nie oznacza błędu moda. Oznacza tylko, że Toolkit nie ma zwykłego pola DefInjected do przetłumaczenia.")
    }

    return $sb.ToString()
}

function Scan-Defs([string]$modPath) {
    $fields = @(
        "label","description","jobString","reportString","gerund",
        "labelShort","labelNoun","labelPlural","labelMale","labelFemale",
        "inspectString","baseDesc","letterLabel","letterText"
    )

    $countBefore = $script:Entries.Count
    $roots = @(Get-DefRoots $modPath)

    foreach ($defs in $roots) {
        if (-not (Test-Path $defs)) { continue }

        Get-ChildItem -LiteralPath $defs -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                [xml]$doc = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
                if ($null -eq $doc.DocumentElement -or $doc.DocumentElement.Name -ne "Defs") { return }

                foreach ($def in $doc.DocumentElement.ChildNodes) {
                    if ($def.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                    $defNameNode = $def.SelectSingleNode("defName")
                    if ($null -eq $defNameNode -or [string]::IsNullOrWhiteSpace($defNameNode.InnerText)) { continue }

                    $defType = $def.Name
                    $defName = $defNameNode.InnerText.Trim()

                    foreach ($field in $fields) {
                        $node = $def.SelectSingleNode($field)
                        if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
                            Add-Entry "DefInjected" "DefInjected\$defType\$defType.xml" "$defName.$field" $node.InnerText $defType $defName $field
                        }
                    }
                }
            } catch {}
        }
    }

    return ($script:Entries.Count - $countBefore)
}

function Get-SearchScopeCode {
    try {
        if ($null -ne $cmbSearchScope.SelectedItem) {
            return [string]$cmbSearchScope.SelectedItem.Tag
        }
    } catch {}
    return "both"
}

function Get-FilteredTranslationEntries {
    $term = ""
    try { $term = [string]$txtSearchTerm.Text } catch {}
    if ([string]::IsNullOrWhiteSpace($term)) {
        return @($script:Entries)
    }

    $scope = Get-SearchScopeCode
    $needle = $term.ToLowerInvariant()

    return @($script:Entries | Where-Object {
        $source = ([string]$_.Source).ToLowerInvariant()
        $translation = ([string]$_.Translation).ToLowerInvariant()

        switch ($scope) {
            "source" { $source.Contains($needle) }
            "translation" { $translation.Contains($needle) }
            default { $source.Contains($needle) -or $translation.Contains($needle) }
        }
    })
}

function Refresh-SearchResults {
    $script:SearchFilteredEntries = @(Get-FilteredTranslationEntries)
    $grid.ItemsSource = $null
    $grid.ItemsSource = $script:SearchFilteredEntries

    $total = $script:Entries.Count
    $shown = $script:SearchFilteredEntries.Count
    $term = ""
    try { $term = [string]$txtSearchTerm.Text } catch {}

    if ([string]::IsNullOrWhiteSpace($term)) {
        $lblCount.Content = "Wpisy: $total"
        if ($null -ne $lblSearchCount) { $lblSearchCount.Content = "" }
    } else {
        $lblCount.Content = "Wpisy: $total"
        if ($null -ne $lblSearchCount) { $lblSearchCount.Content = "Wyniki: $shown / $total" }
    }
}

function Refresh-Grid {
    Refresh-SearchResults
}

function Replace-InFilteredTranslations([string]$search, [string]$replacement, [string]$scope) {
    if ([string]::IsNullOrWhiteSpace($search)) { return 0 }

    $matches = @(Get-FilteredTranslationEntries)
    $changed = 0

    foreach ($e in $matches) {
        if ($scope -eq "source") {
            # Searching the source means the user wants one corrected translation
            # for every matching source phrase.
            if ([string]$e.Translation -ne $replacement) {
                $e.Translation = $replacement
                $changed++
            }
            continue
        }

        $current = [string]$e.Translation
        if ([string]::IsNullOrEmpty($current)) { continue }

        $newText = [regex]::Replace(
            $current,
            [regex]::Escape($search),
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement },
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($newText -ne $current) {
            $e.Translation = $newText
            $changed++
        }
    }

    Refresh-SearchResults
    return $changed
}


function Get-TranslationModInfo([string]$modPath) {
    $info = [ordered]@{
        Name = Split-Path $modPath -Leaf
        PackageId = ""
        Dependencies = @()
        LoadAfter = @()
        LoadBefore = @()
        IsTranslationMod = $false
        TargetCode = ""
        ToolkitGenerated = $false
    }

    $about = Join-Path $modPath "About\About.xml"
    if (Test-Path $about) {
        try {
            [xml]$x = Get-Content -LiteralPath $about -Raw -Encoding UTF8

            $n = $x.ModMetaData.SelectSingleNode("name")
            if ($null -ne $n) { $info.Name = $n.InnerText.Trim() }

            $p = $x.ModMetaData.SelectSingleNode("packageId")
            if ($null -ne $p) { $info.PackageId = $p.InnerText.Trim() }

            $deps = New-Object System.Collections.ArrayList
            foreach ($d in @($x.ModMetaData.SelectNodes("modDependencies/li"))) {
                $packageCandidate = $d.SelectSingleNode("packageId")
                if ($null -ne $packageCandidate -and -not [string]::IsNullOrWhiteSpace($packageCandidate.InnerText)) {
                    [void]$deps.Add($packageCandidate.InnerText.Trim())
                }
            }
            $info.Dependencies = @($deps)

            $after = New-Object System.Collections.ArrayList
            foreach ($node in @($x.ModMetaData.SelectNodes("loadAfter/li"))) {
                if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
                    [void]$after.Add($node.InnerText.Trim())
                }
            }
            $info.LoadAfter = @($after)

            $before = New-Object System.Collections.ArrayList
            foreach ($node in @($x.ModMetaData.SelectNodes("loadBefore/li"))) {
                if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
                    [void]$before.Add($node.InnerText.Trim())
                }
            }
            $info.LoadBefore = @($before)

            $desc = $x.ModMetaData.SelectSingleNode("description")
            if ($null -ne $desc) {
                $descriptionText = $desc.InnerText
                if ($descriptionText -match 'Mod Translation Toolkit|github\.com/DrizztGaming/Mod-Translation-Toolkit') {
                    $info.ToolkitGenerated = $true
                }
            }
        } catch {}
    }

    # Detect supported translation language from actual language folders.
    if (@(Get-LanguageRootsForCode $modPath "pl").Count -gt 0) {
        $info.TargetCode = "pl"
    } elseif (@(Get-LanguageRootsForCode $modPath "en").Count -gt 0) {
        $info.TargetCode = "en"
    }
    $pidLower = ([string]$info.PackageId).ToLowerInvariant()
    $nameLower = ([string]$info.Name).ToLowerInvariant()

    # Be deliberately conservative. A normal mod may contain Languages,
    # modDependencies and loadAfter entries. Those are NOT enough to call it
    # a translation mod.
    $explicitTranslationSignal = (
        $pidLower -match '(^|[._-])(pltranslation|entranslation|polishtranslation|englishtranslation|translation)([._-]|$)' -or
        $nameLower -match 'translation|tłumaczenie|tlumaczenie'
    )

    $info.IsTranslationMod = (
        -not [string]::IsNullOrWhiteSpace($info.TargetCode) -and
        ($explicitTranslationSignal -or $info.ToolkitGenerated)
    )

    return [pscustomobject]$info
}


function Get-TranslationClassificationReason($translationInfo, [string]$modPath) {
    $pidLower = ([string]$translationInfo.PackageId).ToLowerInvariant()
    $nameLower = ([string]$translationInfo.Name).ToLowerInvariant()

    if ($translationInfo.ToolkitGenerated) {
        return "toolkit attribution"
    }

    if ($pidLower -match '(^|[._-])(pltranslation|entranslation|polishtranslation|englishtranslation|translation)([._-]|$)') {
        return "packageId"
    }

    if ($nameLower -match 'translation|tłumaczenie|tlumaczenie') {
        return "name"
    }

    return "normal mod"
}

function Find-ModByPackageId([string]$packageId, [string]$excludePath = "") {
    if ([string]::IsNullOrWhiteSpace($packageId)) { return $null }
    $needle = $packageId.Trim().ToLowerInvariant()

    foreach ($m in @($script:Mods)) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($excludePath)) {
                $a = (Get-NormalizedPath ([string]$m.Path))
                $b = (Get-NormalizedPath $excludePath)
                if ($a -eq $b) { continue }
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$m.PackageId) -and
                ([string]$m.PackageId).Trim().ToLowerInvariant() -eq $needle) {
                return $m
            }
        } catch {}
    }

    return $null
}

function Select-LanguageComboCode($combo, [string]$code) {
    foreach ($item in $combo.Items) {
        if ([string]$item.Tag -eq $code) {
            $combo.SelectedItem = $item
            return
        }
    }
}


function Normalize-TranslationBaseName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return "" }

    $n = $name.Trim()
    $patterns = @(
        '\s*-\s*Polish Translation\s*$',
        '\s*-\s*English Translation\s*$',
        '\s*-\s*Polskie Tłumaczenie\s*$',
        '\s*-\s*Tłumaczenie PL\s*$',
        '\s*-\s*PL Translation\s*$',
        '\s*\(Polish Translation\)\s*$',
        '\s*\[Polish Translation\]\s*$',
        '\s*Translation\s*$'
    )

    foreach ($p in $patterns) {
        $n = [regex]::Replace($n, $p, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    return $n.Trim()
}

function Get-PackageIdSourceCandidates([string]$packageId) {
    $result = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($packageId)) { return @($result) }

    $basePackageId = $packageId.Trim()

    $patterns = @(
        '\.pltranslation$',
        '\.entranslation$',
        '\.polishtranslation$',
        '\.englishtranslation$',
        '\.translation\.pl$',
        '\.translation\.en$',
        '\.translation$',
        '\.polish$',
        '\.english$',
        '\.pl$',
        '\.en$',
        '_pl$',
        '_en$',
        '-pl$',
        '-en$'
    )

    foreach ($p in $patterns) {
        $candidate = [regex]::Replace($basePackageId, $p, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($candidate -ne $basePackageId -and -not [string]::IsNullOrWhiteSpace($candidate)) {
            if (-not (@($result) -contains $candidate)) {
                [void]$result.Add($candidate)
            }
        }
    }

    return @($result)
}

function Find-ModByNormalizedName([string]$name, [string]$excludePath = "") {
    $needle = (Normalize-TranslationBaseName $name).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($needle)) { return $null }

    foreach ($m in @($script:Mods)) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($excludePath)) {
                $a = Get-NormalizedPath ([string]$m.Path)
                $b = Get-NormalizedPath $excludePath
                if ($a -eq $b) { continue }
            }

            $candidate = (Normalize-TranslationBaseName ([string]$m.Name)).ToLowerInvariant()
            if ($candidate -eq $needle) {
                return $m
            }
        } catch {}
    }

    return $null
}

function Test-IsFrameworkDependency([string]$packageId) {
    if ([string]::IsNullOrWhiteSpace($packageId)) { return $false }

    $p = $packageId.Trim().ToLowerInvariant()

    $frameworkIds = @(
        "brrainz.harmony",
        "unlimitedhugs.hugslib",
        "oskarpotocki.vanillafactionsexpanded.core",
        "imranfish.xmlextensions"
    )

    if ($frameworkIds -contains $p) { return $true }

    if ($p -match '(^|\.)(framework|core|library|lib)(\.|$)') { return $true }

    return $false
}

function Resolve-OriginalModForTranslation($translationInfo, [string]$translationModPath) {
    # 1. Strongest practical signal: packageId derived from the translation packageId.
    foreach ($candidatePackageId in @(Get-PackageIdSourceCandidates ([string]$translationInfo.PackageId))) {
        $m = Find-ModByPackageId $candidatePackageId $translationModPath
        if ($null -ne $m) {
            return [pscustomobject]@{
                Mod = $m
                Method = "packageId suffix"
                Value = $candidatePackageId
            }
        }
    }

    # 2. Translation name -> base mod name.
    $m = Find-ModByNormalizedName ([string]$translationInfo.Name) $translationModPath
    if ($null -ne $m) {
        return [pscustomobject]@{
            Mod = $m
            Method = "name"
            Value = $m.Name
        }
    }

    # 3. Explicit dependencies, but ignore common framework/runtime dependencies first.
    foreach ($dependencyPackageId in @($translationInfo.Dependencies)) {
        if (Test-IsFrameworkDependency $dependencyPackageId) { continue }

        $m = Find-ModByPackageId $dependencyPackageId $translationModPath
        if ($null -ne $m) {
            return [pscustomobject]@{
                Mod = $m
                Method = "modDependencies"
                Value = $dependencyPackageId
            }
        }
    }

    # 4. loadAfter/loadBefore, also excluding common frameworks.
    foreach ($loadAfterPackageId in @($translationInfo.LoadAfter)) {
        if (Test-IsFrameworkDependency $loadAfterPackageId) { continue }

        $m = Find-ModByPackageId $loadAfterPackageId $translationModPath
        if ($null -ne $m) {
            return [pscustomobject]@{
                Mod = $m
                Method = "loadAfter"
                Value = $loadAfterPackageId
            }
        }
    }

    foreach ($loadBeforePackageId in @($translationInfo.LoadBefore)) {
        if (Test-IsFrameworkDependency $loadBeforePackageId) { continue }

        $m = Find-ModByPackageId $loadBeforePackageId $translationModPath
        if ($null -ne $m) {
            return [pscustomobject]@{
                Mod = $m
                Method = "loadBefore"
                Value = $loadBeforePackageId
            }
        }
    }

    # 5. Do not guess from an arbitrary framework dependency.
    # If we reached this point, returning the wrong source is worse than asking the user.
    return $null
}

function Open-ExistingTranslationMod([string]$translationModPath) {
    Reset-TranslationUpdateMode
    $t = Get-TranslationModInfo $translationModPath
    if (-not $t.IsTranslationMod) {
        throw "Wybrany mod nie został rozpoznany jako mod tłumaczeniowy."
    }

    $resolved = Resolve-OriginalModForTranslation $t $translationModPath
    if ($null -eq $resolved -or $null -eq $resolved.Mod) {
        $candidateIds = @(Get-PackageIdSourceCandidates ([string]$t.PackageId)
        ) -join ", "
        $baseName = Normalize-TranslationBaseName ([string]$t.Name)

        throw "Nie znaleziono moda źródłowego. Toolkit sprawdził modDependencies, loadAfter/loadBefore, packageId oraz nazwę moda. Nazwa bazowa: '$baseName'. Kandydaci packageId: '$candidateIds'."
    }

    $original = $resolved.Mod

    # Set target before Analyze-Mod so automatic loading uses the intended language.
    Select-LanguageComboCode $cmbTargetLang $t.TargetCode
    if ($t.TargetCode -eq "pl") {
        Select-LanguageComboCode $cmbSourceLang "en"
    } else {
        Select-LanguageComboCode $cmbSourceLang "pl"
    }

    $scan = Analyze-Mod ([string]$original.Path)

    # Overlay translation from the selected translation mod, not from the original mod.
    $existing = Read-LanguageEntries $translationModPath $t.TargetCode
    $loaded = 0

    foreach ($e in $script:Entries) {
        $id = "$($e.File)|$($e.Key)".ToLowerInvariant()
        if ($existing.ContainsKey($id)) {
            $e.Translation = [string]$existing[$id].Text
            $loaded++
        }
    }

    $script:EditingTranslationModPath = $translationModPath
    $script:EditingTranslationPackageId = [string]$t.PackageId
    $script:EditingTranslationName = [string]$t.Name

    Refresh-Grid

    return [pscustomobject]@{
        Translation = $t
        Original = $original
        Scan = $scan
        Loaded = $loaded
        Total = $script:Entries.Count
        ResolveMethod = $resolved.Method
    }
}



function Show-PathInputDialog([string]$title, [string]$prompt, [string]$defaultValue="") {
    $w = New-Object System.Windows.Window
    $w.Title = $title
    $w.Width = 720
    $w.Height = 180
    $w.WindowStartupLocation = "CenterOwner"
    $w.Owner = $window
    $w.ResizeMode = "NoResize"
    $w.Background = [System.Windows.Media.Brushes]::White

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = "12"
    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = "Auto"
    $r2 = New-Object System.Windows.Controls.RowDefinition
    $r2.Height = "*"
    $r3 = New-Object System.Windows.Controls.RowDefinition
    $r3.Height = "Auto"
    [void]$grid.RowDefinitions.Add($r1)
    [void]$grid.RowDefinitions.Add($r2)
    [void]$grid.RowDefinitions.Add($r3)

    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $prompt
    $lbl.Margin = "0,0,0,8"
    [System.Windows.Controls.Grid]::SetRow($lbl,0)
    [void]$grid.Children.Add($lbl)

    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $defaultValue
    $tb.AllowDrop = $true
    $tb.VerticalContentAlignment = "Center"
    [System.Windows.Controls.Grid]::SetRow($tb,1)
    [void]$grid.Children.Add($tb)

    $tb.Add_Drop({
        param($sender,$e)
        $p = Get-DroppedFolderPath $e
        if ($p) { $tb.Text = $p; $e.Handled = $true }
    })
    $tb.Add_PreviewDragOver({
        param($sender,$e)
        $e.Effects = [System.Windows.DragDropEffects]::Copy
        $e.Handled = $true
    })

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Orientation = "Horizontal"
    $panel.HorizontalAlignment = "Right"
    $panel.Margin = "0,10,0,0"

    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = "OK"
    $ok.Width = 90
    $ok.Margin = "0,0,8,0"

    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = "Anuluj"
    $cancel.Width = 90

    [void]$panel.Children.Add($ok)
    [void]$panel.Children.Add($cancel)
    [System.Windows.Controls.Grid]::SetRow($panel,2)
    [void]$grid.Children.Add($panel)

    $result = $null
    $ok.Add_Click({
        $candidate = Normalize-DroppedPath $tb.Text
        if (-not (Test-ExistingFolderSafe $candidate)) {
            [System.Windows.MessageBox]::Show("Folder nie istnieje:`n$candidate",$title) | Out-Null
            return
        }
        $script:__PathDialogResult = $candidate
        $w.DialogResult = $true
        $w.Close()
    })
    $cancel.Add_Click({
        $script:__PathDialogResult = $null
        $w.DialogResult = $false
        $w.Close()
    })

    $script:__PathDialogResult = $null
    $w.Content = $grid
    [void]$w.ShowDialog()
    return $script:__PathDialogResult
}

function Start-TranslationUpdate([string]$updatedOriginalPath, [string]$translationModPath) {
    if (-not (Test-ExistingFolderSafe $updatedOriginalPath)) { throw "Nie znaleziono zaktualizowanego moda źródłowego." }
    if (-not (Test-ExistingFolderSafe $translationModPath)) { throw "Nie znaleziono istniejącego moda tłumaczeniowego." }

    $translationInfo = Get-TranslationModInfo $translationModPath
    if (-not $translationInfo.IsTranslationMod) { throw "Wybrany folder nie wygląda na mod tłumaczeniowy." }

    $targetCode = [string]$translationInfo.TargetCode
    if ([string]::IsNullOrWhiteSpace($targetCode)) { throw "Nie wykryto języka istniejącego tłumaczenia." }

    Select-LanguageComboCode $cmbTargetLang $targetCode
    if ($targetCode -eq "pl") { Select-LanguageComboCode $cmbSourceLang "en" }
    else { Select-LanguageComboCode $cmbSourceLang "pl" }

    $scan = Analyze-Mod $updatedOriginalPath
    $oldMap = Read-LanguageEntries $translationModPath $targetCode

    $preserved = 0
    $newCount = 0
    $missing = 0

    foreach ($e in $script:Entries) {
        $id = "$($e.File)|$($e.Key)".ToLowerInvariant()
        if ($oldMap.ContainsKey($id)) {
            $oldText = [string]$oldMap[$id].Text
            if (-not [string]::IsNullOrWhiteSpace($oldText)) {
                $e.Translation = $oldText
                $preserved++
                if ($oldText -eq [string]$e.Source) { $missing++ }
            } else {
                $e.Translation = ""
                $missing++
            }
        } else {
            $e.Translation = ""
            $newCount++
            $missing++
        }
    }

    $currentIds = @{}
    foreach ($e in $script:Entries) {
        $currentIds["$($e.File)|$($e.Key)".ToLowerInvariant()] = $true
    }

    $obsolete = 0
    foreach ($id in $oldMap.Keys) {
        if (-not $currentIds.ContainsKey($id)) { $obsolete++ }
    }

    $script:EditingTranslationModPath = $translationModPath
    $script:EditingTranslationPackageId = [string]$translationInfo.PackageId
    $script:EditingTranslationName = [string]$translationInfo.Name
    $script:UpdateMode = $true
    $script:UpdateTranslationPath = $translationModPath
    $script:UpdateOriginalPath = $updatedOriginalPath
    $script:UpdateStats = [pscustomobject]@{
        Total = $script:Entries.Count
        Preserved = $preserved
        New = $newCount
        MissingCount = $missing
        Obsolete = $obsolete
        TargetCode = $targetCode
    }

    $txtModPath.Text = $updatedOriginalPath
    $txtModName.Text = [string]$translationInfo.Name
    $txtPackageId.Text = [string]$translationInfo.PackageId
    Refresh-Grid
    Refresh-LanguageCoverageUi

    $btnBuild.Content = if ($script:UiLanguage -eq "en") { "Save translation update" } else { "Zapisz aktualizację" }
    return $script:UpdateStats
}

function Reset-TranslationUpdateMode {
    $script:UpdateMode = $false
    $script:UpdateTranslationPath = ""
    $script:UpdateOriginalPath = ""
    $script:UpdateStats = $null
    $btnBuild.Content = if ($script:UiLanguage -eq "en") { "Build separate mod" } else { "Zbuduj oddzielny mod" }
}




function Set-ControlTextSafe($control, [string]$value) {
    if ($null -eq $control) { return }
    if ($null -ne $control.PSObject.Properties["Text"]) {
        $control.Text = $value
        return
    }
    if ($null -ne $control.PSObject.Properties["Content"]) {
        $control.Content = $value
        return
    }
}

function Test-ExistingFolderSafe([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try {
        return (Test-Path -LiteralPath $path -PathType Container)
    } catch {
        return $false
    }
}

function Normalize-DroppedPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return "" }
    $p = $path.Trim().Trim('"')
    try { return [System.IO.Path]::GetFullPath($p) } catch { return $p }
}

function Load-RimWorldModPath([string]$path, [switch]$Silent) {
    $path = Normalize-DroppedPath $path
    if (-not (Test-ExistingFolderSafe $path)) {
        if (-not $Silent) {
            [System.Windows.MessageBox]::Show("Nie znaleziono folderu moda:`n$path","Mod Translation Toolkit") | Out-Null
        }
        return $null
    }

    try {
        Reset-TranslationUpdateMode
        $script:EditingTranslationModPath = ""
        $script:EditingTranslationPackageId = ""
        $script:EditingTranslationName = ""

        $txtModPath.Text = $path
        $scan = Analyze-Mod $path
        Apply-CreatorProfileToTranslator
        Refresh-LanguageCoverageUi
        $txtStatus.Text = "Załadowano folder moda. Wpisy: $($scan.Total). Automatycznie podstawiono istniejących: $($scan.AutoLoadedExisting)."
        return $scan
    } catch {
        if (-not $Silent) {
            [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd") | Out-Null
        }
        return $null
    }
}

function Load-KenshiPath([string]$path, [switch]$Silent) {
    $path = Normalize-DroppedPath $path
    if (-not (Test-ExistingFolderSafe $path)) {
        if (-not $Silent) {
            [System.Windows.MessageBox]::Show("Nie znaleziono folderu Kenshi:`n$path","Mod Translation Toolkit") | Out-Null
        }
        return $false
    }

    $txtKenshiPath.Text = $path
    $script:KenshiRoot = $path
    $txtKenshiStatus.Text = "Załadowano ścieżkę Kenshi: $path"
    return $true
}

function Get-DroppedFolderPath($e) {
    try {
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $paths = @($e.Data.GetData([System.Windows.DataFormats]::FileDrop))
            foreach ($p in $paths) {
                if (Test-ExistingFolderSafe $p) {
                    return [string]$p
                }
            }
        }
    } catch {}
    return ""
}

function Analyze-Mod([string]$modPath) {
    $script:Entries.Clear()
    $script:EntryKeys = @{}
    $script:OriginalModPath = $modPath
    $script:DetectedFromDefs = $false
    $script:SelectedContentVersion = ""

    Read-AboutXml $modPath

    # IMPORTANT: Languages/English and Defs are complementary.
    # A mod may provide only some strings in Keyed while keeping Def labels/descriptions in Defs.
    $langCount = Scan-EnglishLanguages $modPath
    $defsCount = Scan-Defs $modPath
    $keybindScan = Scan-KeyBindingDefs $modPath

    # DLL/UI diagnostics are intentionally lazy and run only on button press.
    $script:AssemblyDiagnostics.Clear()
    $script:AssemblyDiagnosticFiles = 0
    $script:AssemblyDiagnosticsScannedPath = ""

    if ($defsCount -gt 0) { $script:DetectedFromDefs = $true }

    $txtModName.Text = $script:OriginalModName
    $txtPackageId.Text = $script:OriginalPackageId
    Refresh-Grid
    Update-LanguageCoverage $modPath

    $autoLoaded = AutoLoad-ExistingTargetTranslation
    return [pscustomobject]@{
        LanguageEntries = $langCount
        DefEntries = $defsCount
        ContentVersion = $script:SelectedContentVersion
        Total = $script:Entries.Count
        PolishCoverage = $script:LanguageCoverage["pl"]
        EnglishCoverage = $script:LanguageCoverage["en"]
        AutoLoadedExisting = $autoLoaded
        KeyBindingDefs = $keybindScan.Total
        KeyBindingLocalizable = $keybindScan.Localizable
        KeyBindingDiagnostics = $keybindScan.Diagnostic
        AssemblyFiles = 0
        AssemblyUiDiagnostics = 0
    }
}

function Export-Csv([string]$path) {
    $script:Entries |
        Select-Object Kind,File,Key,Source,Translation,DefType,DefName,Field |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8 -Delimiter ';'
}

function Import-Csv([string]$path) {
    $rows = Import-Csv -LiteralPath $path -Encoding UTF8 -Delimiter ';'
    $lookup = @{}
    foreach ($r in $rows) { $lookup["$($r.Kind)|$($r.File)|$($r.Key)"] = $r }

    foreach ($e in $script:Entries) {
        $k = "$($e.Kind)|$($e.File)|$($e.Key)"
        if ($lookup.ContainsKey($k)) { $e.Translation = [string]$lookup[$k].Translation }
    }
    Refresh-Grid
}

function Write-LanguageFiles([string]$outMod) {
    $targetCode = Get-SelectedTargetLanguageCode
    $targetFolder = Get-LanguageFolderName $targetCode
    $langRoot = Join-Path $outMod "Languages\$targetFolder"
    New-Item -ItemType Directory -Path $langRoot -Force | Out-Null

    # Output path already encodes Keyed vs DefInjected. Grouping by File prevents
    # multiple XML documents for the same target file.
    $groups = $script:Entries | Group-Object File

    foreach ($g in $groups) {
        $first = $g.Group[0]
        $dest = Join-Path $langRoot $first.File
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
        [void]$sb.AppendLine('<LanguageData>')

        $seenKeys = @{}
        foreach ($e in $g.Group) {
            $keyNorm = $e.Key.ToLowerInvariant()
            if ($seenKeys.ContainsKey($keyNorm)) { continue }
            $seenKeys[$keyNorm] = $true

            $value = if ([string]::IsNullOrWhiteSpace($e.Translation)) { $e.Source } else { $e.Translation }
            if ($null -eq $value) { $value = "" }
            $value = $value.TrimEnd()

            [void]$sb.AppendLine("  <$($e.Key)>$(XmlEscape $value)</$($e.Key)>")
        }

        [void]$sb.AppendLine('</LanguageData>')
        [System.IO.File]::WriteAllText($dest, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    }
}


function Draw-FlagOverlay([System.Drawing.Graphics]$g, [string]$flagCode, [int]$x, [int]$y, [int]$w, [int]$h) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $white = [System.Drawing.Brushes]::White
    $black = [System.Drawing.Brushes]::Black
    $red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 25, 35))
    $blue = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(25, 65, 135))
    $yellow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 205, 55))
    $green = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(20, 145, 80))

    try {
        switch ($flagCode) {
            "PL" {
                $g.FillRectangle($white, $x, $y, $w, [int]($h/2))
                $g.FillRectangle($red, $x, $y + [int]($h/2), $w, $h - [int]($h/2))
            }
            "GB" {
                $g.FillRectangle($blue, $x, $y, $w, $h)

                $penW = [Math]::Max(2, [int]($h * 0.18))
                $penW2 = [Math]::Max(1, [int]($h * 0.08))
                $pw = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, $penW)
                $pr = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220,25,35), $penW2)
                $g.DrawLine($pw, $x, $y, $x+$w, $y+$h)
                $g.DrawLine($pw, $x+$w, $y, $x, $y+$h)
                $g.DrawLine($pr, $x, $y, $x+$w, $y+$h)
                $g.DrawLine($pr, $x+$w, $y, $x, $y+$h)
                $pw.Dispose(); $pr.Dispose()

                $crossW = [Math]::Max(2, [int]($h * 0.28))
                $crossR = [Math]::Max(1, [int]($h * 0.14))
                $pww = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, $crossW)
                $prr = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220,25,35), $crossR)
                $g.DrawLine($pww, $x + [int]($w/2), $y, $x + [int]($w/2), $y+$h)
                $g.DrawLine($pww, $x, $y + [int]($h/2), $x+$w, $y + [int]($h/2))
                $g.DrawLine($prr, $x + [int]($w/2), $y, $x + [int]($w/2), $y+$h)
                $g.DrawLine($prr, $x, $y + [int]($h/2), $x+$w, $y + [int]($h/2))
                $pww.Dispose(); $prr.Dispose()
            }
            "DE" {
                $g.FillRectangle($black, $x, $y, $w, [int]($h/3))
                $g.FillRectangle($red, $x, $y+[int]($h/3), $w, [int]($h/3))
                $g.FillRectangle($yellow, $x, $y+[int](2*$h/3), $w, $h-[int](2*$h/3))
            }
            "FR" {
                $g.FillRectangle($blue, $x, $y, [int]($w/3), $h)
                $g.FillRectangle($white, $x+[int]($w/3), $y, [int]($w/3), $h)
                $g.FillRectangle($red, $x+[int](2*$w/3), $y, $w-[int](2*$w/3), $h)
            }
            "ES" {
                $g.FillRectangle($red, $x, $y, $w, [int]($h*0.25))
                $g.FillRectangle($yellow, $x, $y+[int]($h*0.25), $w, [int]($h*0.5))
                $g.FillRectangle($red, $x, $y+[int]($h*0.75), $w, $h-[int]($h*0.75))
            }
            "IT" {
                $g.FillRectangle($green, $x, $y, [int]($w/3), $h)
                $g.FillRectangle($white, $x+[int]($w/3), $y, [int]($w/3), $h)
                $g.FillRectangle($red, $x+[int](2*$w/3), $y, $w-[int](2*$w/3), $h)
            }
            "CZ" {
                $g.FillRectangle($white, $x, $y, $w, [int]($h/2))
                $g.FillRectangle($red, $x, $y+[int]($h/2), $w, $h-[int]($h/2))
                $pts = New-Object 'System.Drawing.Point[]' 3
                $pts[0] = New-Object System.Drawing.Point($x,$y)
                $pts[1] = New-Object System.Drawing.Point($x+[int]($w*0.45),$y+[int]($h/2))
                $pts[2] = New-Object System.Drawing.Point($x,$y+$h)
                $g.FillPolygon($blue,$pts)
            }
            "UA" {
                $g.FillRectangle($blue, $x, $y, $w, [int]($h/2))
                $g.FillRectangle($yellow, $x, $y+[int]($h/2), $w, $h-[int]($h/2))
            }
            "JP" {
                $g.FillRectangle($white, $x, $y, $w, $h)
                $jr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190,0,45))
                $g.FillEllipse($jr, $x+[int]($w*0.34), $y+[int]($h*0.18), [int]($w*0.32), [int]($h*0.64))
                $jr.Dispose()
            }
            "KR" {
                $g.FillRectangle($white, $x, $y, $w, $h)
                $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(205,45,55))
                $bb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(35,80,165))
                $g.FillPie($br, $x+[int]($w*0.34), $y+[int]($h*0.18), [int]($w*0.32), [int]($h*0.64), 180, 180)
                $g.FillPie($bb, $x+[int]($w*0.34), $y+[int]($h*0.18), [int]($w*0.32), [int]($h*0.64), 0, 180)
                $br.Dispose(); $bb.Dispose()
            }
            "CN" {
                $g.FillRectangle($red, $x, $y, $w, $h)
                $g.FillEllipse($yellow, $x+[int]($w*0.12), $y+[int]($h*0.15), [int]($h*0.22), [int]($h*0.22))
            }
            "PT" {
                $g.FillRectangle($green, $x, $y, [int]($w*0.4), $h)
                $g.FillRectangle($red, $x+[int]($w*0.4), $y, $w-[int]($w*0.4), $h)
                $g.FillEllipse($yellow, $x+[int]($w*0.32), $y+[int]($h*0.3), [int]($h*0.4), [int]($h*0.4))
            }
            default {
                $g.FillRectangle($white, $x, $y, $w, $h)
            }
        }

        $borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220,255,255,255), 2)
        $g.DrawRectangle($borderPen, $x, $y, $w, $h)
        $borderPen.Dispose()
    }
    finally {
        $red.Dispose()
        $blue.Dispose()
        $yellow.Dispose()
        $green.Dispose()
    }
}

function Build-TranslationPreview([string]$outMod, [string]$flagCode) {
    if ([string]::IsNullOrWhiteSpace($script:OriginalModPath)) { return $false }

    $previewCandidates = @(
        (Join-Path $script:OriginalModPath "About\Preview.png"),
        (Join-Path $script:OriginalModPath "About\Preview.jpg"),
        (Join-Path $script:OriginalModPath "About\Preview.jpeg")
    )

    $src = $previewCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $src) { return $false }

    $aboutDir = Join-Path $outMod "About"
    New-Item -ItemType Directory -Path $aboutDir -Force | Out-Null
    $dest = Join-Path $aboutDir "Preview.png"

    $img = [System.Drawing.Image]::FromFile($src)
    try {
        $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)

        try {
            $g.DrawImage($img, 0, 0, $img.Width, $img.Height)

            $flagW = [Math]::Max(90, [int]($img.Width * 0.20))
            $flagH = [Math]::Max(55, [int]($flagW * 0.62))
            $margin = [Math]::Max(12, [int]($img.Width * 0.02))
            $x = $img.Width - $flagW - $margin
            $y = $img.Height - $flagH - $margin

            # dark backing plate so the flag reads clearly on any preview
            $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
            $g.FillRectangle($shadow, $x-6, $y-6, $flagW+12, $flagH+12)
            $shadow.Dispose()

            Draw-FlagOverlay $g $flagCode $x $y $flagW $flagH
        }
        finally {
            $g.Dispose()
        }

        $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
    finally {
        $img.Dispose()
    }

    return $true
}


function Get-TargetLanguageInfo {
    $code = "pl"
    try {
        if ($null -ne $cmbTargetLang.SelectedItem) {
            $code = [string]$cmbTargetLang.SelectedItem.Tag
        }
    } catch {}

    switch ($code) {
        "pl" {
            return [pscustomobject]@{
                Code="pl"; RimWorldFolder="Polish"; DisplayEnglish="Polish"; DisplayNative="Polskie"; WorkshopSuffix="Polish Translation"
            }
        }
        "en" {
            return [pscustomobject]@{
                Code="en"; RimWorldFolder="English"; DisplayEnglish="English"; DisplayNative="English"; WorkshopSuffix="English Translation"
            }
        }
        default {
            return [pscustomobject]@{
                Code=$code; RimWorldFolder="Polish"; DisplayEnglish="Translation"; DisplayNative="Translation"; WorkshopSuffix="Translation"
            }
        }
    }
}

function Get-SteamWorkshopDescriptionText([string]$translationAuthor) {
    $lang = Get-TargetLanguageInfo
    $originalLink = $script:OriginalWorkshopUrl
    if ([string]::IsNullOrWhiteSpace($originalLink)) {
        $originalLink = $script:OriginalDownloadUrl
    }

    $toolUrl = "https://github.com/DrizztGaming/Mod-Translation-Toolkit"
    $kofiUrl = "https://ko-fi.com/drizztgaming"

    $originalAuthorLine = ""
    if (-not [string]::IsNullOrWhiteSpace($script:OriginalAuthor)) {
        $originalAuthorLine = "[*]Original mod author: $($script:OriginalAuthor)`r`n"
    }

    $translatorLine = ""
    if (-not [string]::IsNullOrWhiteSpace($translationAuthor)) {
        $translatorLine = "[*]Translation: $translationAuthor`r`n"
    }

    $requirements = if (-not [string]::IsNullOrWhiteSpace($originalLink)) {
        "[url=$originalLink]$($script:OriginalModName)[/url]"
    } else {
        $script:OriginalModName
    }

    $description = @"
[h1]$($script:OriginalModName) - $($lang.WorkshopSuffix)[/h1]

$($lang.DisplayEnglish) translation for [b]$($script:OriginalModName)[/b].

[b]Requires the original mod.[/b]

[h1]Requirements[/h1]
[list]
[*]$requirements
[/list]

[h1]Original Mod[/h1]
$requirements

[h1]Credits[/h1]
[list]
$originalAuthorLine$translatorLine[*]Translation package generated with [url=$toolUrl]Mod Translation Toolkit[/url]
[/list]

[h1]Mod Translation Toolkit[/h1]
This translation package was created with [url=$toolUrl][b]Mod Translation Toolkit[/b][/url].

The toolkit is designed to make both manual and assisted mod translation easier, including file detection, DefInjected generation, placeholder checks, CSV workflows and translation-mod packaging.

[url=$toolUrl]GitHub - Mod Translation Toolkit[/url]

[h1]Support[/h1]
If you enjoy my mods and tools, you can support my work here:

[url=$kofiUrl][b]☕ Support me on Ko-fi[/b][/url]
"@

    return $description
}

function Build-SteamWorkshopDescription([string]$outMod, [string]$translationAuthor) {
    $description = Get-SteamWorkshopDescriptionText $translationAuthor
    $path = Join-Path $outMod "SteamWorkshopDescription.txt"
    [System.IO.File]::WriteAllText(
        $path,
        $description,
        (New-Object System.Text.UTF8Encoding($false))
    )
    return $path
}

function Build-TranslationMod([string]$parentFolder) {
    $lang = Get-TargetLanguageInfo
    if ([string]::IsNullOrWhiteSpace($script:OriginalPackageId)) {
        throw "Oryginalny mod nie ma packageId w About.xml."
    }

    $safeName = ($script:OriginalModName -replace '[\\/:*?"<>|]', '_')
    $isEditingExisting = -not [string]::IsNullOrWhiteSpace($script:EditingTranslationModPath)

    if ($isEditingExisting) {
        $outMod = $script:EditingTranslationModPath

        # Keep Workshop metadata and any extra files. Only refresh the target language data.
        $targetFolder = Get-LanguageFolderName (Get-SelectedTargetLanguageCode)
        $targetLanguageRoot = Join-Path $outMod "Languages\$targetFolder"
        if (Test-Path $targetLanguageRoot) {
            Remove-Item -LiteralPath $targetLanguageRoot -Recurse -Force
        }
    } else {
        $outMod = Join-Path $parentFolder "$safeName - $($lang.WorkshopSuffix)"
        if (Test-Path $outMod) {
            Remove-Item -LiteralPath $outMod -Recurse -Force
        }
    }

    New-Item -ItemType Directory -Path (Join-Path $outMod "About") -Force | Out-Null
    Write-LanguageFiles $outMod

    $author = $txtAuthor.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($author)) { $author = "Community translation" }

    $pkg = ($script:OriginalPackageId + "." + $lang.Code + "translation").ToLowerInvariant()

    $supportedXml = ""
    if ($script:OriginalSupportedVersions.Count -gt 0) {
        $supportedXml += "  <supportedVersions>`r`n"
        foreach ($v in $script:OriginalSupportedVersions) {
            $supportedXml += "    <li>$([System.Security.SecurityElement]::Escape($v))</li>`r`n"
        }
        $supportedXml += "  </supportedVersions>`r`n"
    } elseif ($script:SelectedContentVersion) {
        $supportedXml = "  <supportedVersions>`r`n    <li>$([System.Security.SecurityElement]::Escape($script:SelectedContentVersion))</li>`r`n  </supportedVersions>`r`n"
    }

    $dependencyLinks = ""
    if (-not [string]::IsNullOrWhiteSpace($script:OriginalWorkshopUrl)) {
        $dependencyLinks += "      <steamWorkshopUrl>$([System.Security.SecurityElement]::Escape($script:OriginalWorkshopUrl))</steamWorkshopUrl>`r`n"
    }
    if (-not [string]::IsNullOrWhiteSpace($script:OriginalDownloadUrl)) {
        $dependencyLinks += "      <downloadUrl>$([System.Security.SecurityElement]::Escape($script:OriginalDownloadUrl))</downloadUrl>`r`n"
    }

    # RimWorld warns when a dependency has neither URL. Add a search fallback.
    if ([string]::IsNullOrWhiteSpace($dependencyLinks)) {
        $q = [uri]::EscapeDataString($script:OriginalPackageId)
        $fallback = "https://steamcommunity.com/workshop/browse/?appid=294100&searchtext=$q"
        $dependencyLinks = "      <downloadUrl>$([System.Security.SecurityElement]::Escape($fallback))</downloadUrl>`r`n"
    }

    $aboutText = @"
<?xml version="1.0" encoding="utf-8"?>
<ModMetaData>
  <name>$([System.Security.SecurityElement]::Escape($script:OriginalModName)) - $($lang.WorkshopSuffix)</name>
  <author>$([System.Security.SecurityElement]::Escape($author))</author>
  <packageId>$pkg</packageId>
  <modVersion>1.0.0</modVersion>
$supportedXml  <description>$($lang.DisplayEnglish) translation for $([System.Security.SecurityElement]::Escape($script:OriginalModName)). Requires the original mod.

Created with Mod Translation Toolkit.
Project: https://github.com/DrizztGaming/Mod-Translation-Toolkit</description>
  <modDependencies>
    <li>
      <packageId>$([System.Security.SecurityElement]::Escape($script:OriginalPackageId))</packageId>
      <displayName>$([System.Security.SecurityElement]::Escape($script:OriginalModName))</displayName>
$dependencyLinks    </li>
  </modDependencies>
  <loadAfter>
    <li>$([System.Security.SecurityElement]::Escape($script:OriginalPackageId))</li>
  </loadAfter>
</ModMetaData>
"@

    if (-not $isEditingExisting -or -not (Test-Path (Join-Path $outMod "About\About.xml"))) {
        [System.IO.File]::WriteAllText((Join-Path $outMod "About\About.xml"), $aboutText, (New-Object System.Text.UTF8Encoding($false)))
    }


    $previewCreated = $false
    if ($chkPreviewFlag.IsChecked -eq $true -and $null -ne $cmbPreviewFlag.SelectedItem) {
        $flagCode = [string]$cmbPreviewFlag.SelectedItem.Tag
        try {
            $previewCreated = Build-TranslationPreview $outMod $flagCode
        } catch {
            $previewCreated = $false
        }
    }


    $steamDescriptionPath = ""
    try {
        $steamDescriptionPath = Build-SteamWorkshopDescription $outMod $author
    } catch {
        $steamDescriptionPath = ""
    }

    # Small build report helps diagnose missing/duplicate translation data later.
    $keyed = @($script:Entries | Where-Object { $_.Kind -eq "Language" }).Count
    $defs = @($script:Entries | Where-Object { $_.Kind -eq "DefInjected" }).Count
    $translated = @($script:Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Translation) }).Count

    $report = @"
Mod Translation Toolkit v$AppVersion
Original mod: $($script:OriginalModName)
PackageId: $($script:OriginalPackageId)
Selected content version: $($script:SelectedContentVersion)
Language roots: $((Get-LanguageRoots $script:OriginalModPath) -join "; ")`nKeyed entries: $keyed
DefInjected entries: $defs
Translated entries: $translated
Total unique entries: $($script:Entries.Count)
Steam Workshop description: $steamDescriptionPath
Polish existing coverage: $((Get-CoverageText "pl"))
English existing coverage: $((Get-CoverageText "en"))
Existing target entries auto-loaded: $((AutoLoad-ExistingTargetTranslation))
Preview generated: $previewCreated
"@
    [System.IO.File]::WriteAllText((Join-Path $outMod "TranslationBuildReport.txt"), $report, (New-Object System.Text.UTF8Encoding($false)))

    return $outMod
}


function Get-MissingPlaceholders([string]$source, [string]$translation) {
    $src = @(Get-Placeholders $source)
    $tr = @(Get-Placeholders $translation)

    $missing = New-Object System.Collections.ArrayList
    $remaining = New-Object System.Collections.ArrayList
    foreach ($x in $tr) { [void]$remaining.Add($x) }

    foreach ($token in $src) {
        $idx = $remaining.IndexOf($token)
        if ($idx -ge 0) {
            $remaining.RemoveAt($idx)
        } else {
            [void]$missing.Add($token)
        }
    }

    return @($missing)
}

function Repair-TranslationPlaceholders([string]$source, [string]$translation) {
    if ([string]::IsNullOrWhiteSpace($translation)) { return $translation }

    $missing = @(Get-MissingPlaceholders $source $translation)
    if ($missing.Count -eq 0) { return $translation }

    $result = $translation

    foreach ($token in $missing) {
        if ($token -match '^\{(\d+)(?::[^}]*)?\}$') {
            $n = $Matches[1]

            if ($result -match "(?<!\{)$n\}") {
                $result = [regex]::Replace($result, "(?<!\{)$n\}", "{$n}", 1)
                continue
            }

            if ($result -match "\{$n(?!\})") {
                $result = [regex]::Replace($result, "\{$n(?!\})", "{$n}", 1)
                continue
            }
        }

        if (-not $result.Contains($token)) {
            $result = ($result.TrimEnd() + " " + $token).Trim()
        }
    }

    return $result
}

function Highlight-PlaceholderErrors($badEntries) {
    if ($null -eq $badEntries -or $badEntries.Count -eq 0) { return }

    $grid.SelectedItems.Clear()
    foreach ($e in $badEntries) {
        try { [void]$grid.SelectedItems.Add($e) } catch {}
    }

    if ($badEntries.Count -gt 0) {
        $grid.ScrollIntoView($badEntries[0])
    }
}

function Show-RepairModeDialog {
    $msg = if ($script:UiLanguage -eq "en") {
        "Placeholder problems were found.`n`nYes = let the program repair them`nNo = repair manually (highlight rows only)`nCancel = do nothing"
    } else {
        "Wykryto problemy z placeholderami.`n`nTak = naprawi je program`nNie = napraw ręcznie (tylko podświetl wiersze)`nAnuluj = nic nie rób"
    }

    return [System.Windows.MessageBox]::Show(
        $msg,
        "Placeholder repair",
        [System.Windows.MessageBoxButton]::YesNoCancel,
        [System.Windows.MessageBoxImage]::Warning
    )
}

function Show-AutoRepairScopeDialog {
    $msg = if ($script:UiLanguage -eq "en") {
        "How should the program repair placeholders?`n`nYes = repair all automatically`nNo = review every problem one by one"
    } else {
        "Jak program ma naprawić placeholdery?`n`nTak = napraw wszystko automatycznie`nNie = pokaż każdy błąd osobno do akceptacji"
    }

    return [System.Windows.MessageBox]::Show(
        $msg,
        "Placeholder repair",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
}

function Repair-PlaceholderErrorsInteractive($badEntries) {
    $fixed = 0

    foreach ($e in $badEntries) {
        $proposal = Repair-TranslationPlaceholders $e.Source $e.Translation
        if ($proposal -eq $e.Translation) { continue }

        $msg = if ($script:UiLanguage -eq "en") {
            "Key: $($e.Key)`n`nSOURCE:`n$($e.Source)`n`nCURRENT:`n$($e.Translation)`n`nPROPOSED FIX:`n$proposal`n`nApply this fix?"
        } else {
            "Klucz: $($e.Key)`n`nŹRÓDŁO:`n$($e.Source)`n`nOBECNIE:`n$($e.Translation)`n`nPROPONOWANA NAPRAWA:`n$proposal`n`nZastosować tę poprawkę?"
        }

        $ans = [System.Windows.MessageBox]::Show(
            $msg,
            "Placeholder repair",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
            $e.Translation = $proposal
            $fixed++
        }
    }

    Refresh-Grid
    return $fixed
}

function Repair-PlaceholderErrorsAll($badEntries) {
    $fixed = 0

    foreach ($e in $badEntries) {
        $proposal = Repair-TranslationPlaceholders $e.Source $e.Translation
        if ($proposal -ne $e.Translation) {
            $e.Translation = $proposal
            $fixed++
        }
    }

    Refresh-Grid
    return $fixed
}

function Validate-Placeholders {
    $bad = New-Object System.Collections.ArrayList
    foreach ($e in $script:Entries) {
        if ([string]::IsNullOrWhiteSpace($e.Translation)) { continue }
        if (((Get-Placeholders $e.Source) -join '|') -ne ((Get-Placeholders $e.Translation) -join '|')) {
            [void]$bad.Add($e)
        }
    }
    return $bad
}

# ---------- Steam detection ----------
function Get-SteamRoot {
    $candidates = @()
    try {
        $p = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($p) { $candidates += $p }
    } catch {}
    try {
        $p = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath
        if ($p) { $candidates += $p }
    } catch {}
    $candidates += @("$env:ProgramFiles(x86)\Steam", "$env:ProgramFiles\Steam")

    foreach ($p in $candidates | Select-Object -Unique) {
        if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path }
    }
    return $null
}

function Get-NormalizedPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return "" }
    try {
        $full = [System.IO.Path]::GetFullPath($path)
        return $full.TrimEnd('\','/').ToLowerInvariant()
    } catch {
        return $path.TrimEnd('\','/').ToLowerInvariant()
    }
}

function Get-SteamLibraries {
    $steam = Get-SteamRoot
    if (-not $steam) { return @() }

    $rawLibs = New-Object System.Collections.ArrayList
    [void]$rawLibs.Add($steam)

    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        try {
            $raw = Get-Content -LiteralPath $vdf -Raw
            [regex]::Matches($raw, '"path"\s+"([^"]+)"') | ForEach-Object {
                $p = $_.Groups[1].Value -replace '\\\\','\'
                if (Test-Path $p) { [void]$rawLibs.Add($p) }
            }
        } catch {}
    }

    $seen = @{}
    $result = New-Object System.Collections.ArrayList
    foreach ($p in $rawLibs) {
        $norm = Get-NormalizedPath $p
        if ($norm -and -not $seen.ContainsKey($norm)) {
            $seen[$norm] = $true
            [void]$result.Add($p)
        }
    }

    return @($result)
}

function Find-RimWorldLocations {
    $result = @()
    foreach ($lib in Get-SteamLibraries) {
        $game = Join-Path $lib "steamapps\common\RimWorld"
        $workshop = Join-Path $lib "steamapps\workshop\content\294100"
        if ((Test-Path $game) -or (Test-Path $workshop)) {
            $result += [pscustomobject]@{
                Library = $lib
                Game = $game
                Workshop = $workshop
                LocalMods = (Join-Path $game "Mods")
            }
        }
    }
    return $result
}

function Scan-InstalledMods {
    $all = New-Object System.Collections.ArrayList
    $seenPaths = @{}

    foreach ($loc in Find-RimWorldLocations) {
        if (Test-Path $loc.Workshop) {
            Get-ChildItem -LiteralPath $loc.Workshop -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $modPath = $_.FullName
                $normPath = Get-NormalizedPath $modPath

                if (-not $seenPaths.ContainsKey($normPath) -and (Test-Path (Join-Path $modPath "About\About.xml"))) {
                    $seenPaths[$normPath] = $true
                    $i = Get-AboutInfo $modPath
                    [void]$all.Add([pscustomobject]@{
                        Name=$i.Name
                        PackageId=$i.PackageId
                        Version=$i.Version
                        Author=$i.Author
                        Source="Workshop"
                        Path=$modPath
                    })
                }
            }
        }

        if (Test-Path $loc.LocalMods) {
            Get-ChildItem -LiteralPath $loc.LocalMods -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $modPath = $_.FullName
                $normPath = Get-NormalizedPath $modPath

                if (-not $seenPaths.ContainsKey($normPath) -and (Test-Path (Join-Path $modPath "About\About.xml"))) {
                    $seenPaths[$normPath] = $true
                    $i = Get-AboutInfo $modPath
                    [void]$all.Add([pscustomobject]@{
                        Name=$i.Name
                        PackageId=$i.PackageId
                        Version=$i.Version
                        Author=$i.Author
                        Source="Local"
                        Path=$modPath
                    })
                }
            }
        }
    }

    $script:Mods.Clear()
    foreach ($m in ($all | Sort-Object Name,Source,Path)) {
        [void]$script:Mods.Add($m)
    }
    Refresh-ModList
}

function Refresh-ModList {
    $q = $txtSearch.Text.Trim().ToLowerInvariant()
    $filtered = @($script:Mods)

    if ($q) {
        $filtered = @($filtered | Where-Object {
            ($_.Name -and $_.Name.ToLowerInvariant().Contains($q)) -or
            ($_.PackageId -and $_.PackageId.ToLowerInvariant().Contains($q)) -or
            ($_.Author -and $_.Author.ToLowerInvariant().Contains($q))
        })
    }

    $modsGrid.ItemsSource = $null
    $modsGrid.ItemsSource = $filtered
    $lblMods.Content = "Mody: $($filtered.Count) / $($script:Mods.Count)"
}


# ---------- Startup language selector ----------
[xml]$langXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mod Translation Toolkit"
        Width="430" Height="250"
        ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
        Background="#121018"
        Foreground="#ECE8F6">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#7A3FC2"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#9D64E8"/>
      <Setter Property="Padding" Value="18,10"/>
      <Setter Property="Margin" Value="8"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
  </Window.Resources>
  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <TextBlock Text="MOD TRANSLATION TOOLKIT" FontSize="20" FontWeight="Bold"
               Foreground="#D4B5F5" HorizontalAlignment="Center"/>
    <TextBlock Grid.Row="1" Name="langPrompt"
               Text="Wybierz język interfejsu / Choose interface language"
               Margin="0,18,0,8" HorizontalAlignment="Center" Foreground="#B9AEC9"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
      <Button Name="btnLangPL" Content="Polski" Width="150"/>
      <Button Name="btnLangEN" Content="English" Width="150"/>
    </StackPanel>
  </Grid>
</Window>
'@

$langReader = New-Object System.Xml.XmlNodeReader $langXaml
$langWindow = [Windows.Markup.XamlReader]::Load($langReader)
$btnLangPL = $langWindow.FindName("btnLangPL")
$btnLangEN = $langWindow.FindName("btnLangEN")
$btnLangPL.Add_Click({ $script:UiLanguage = "pl"; $langWindow.DialogResult = $true; $langWindow.Close() })
$btnLangEN.Add_Click({ $script:UiLanguage = "en"; $langWindow.DialogResult = $true; $langWindow.Close() })
$null = $langWindow.ShowDialog()


# ---------- Kenshi base-game profile ----------
function Get-KenshiInstallPath {
    foreach ($lib in @(Get-SteamLibraries)) {
        $manifest = Join-Path $lib "steamapps\appmanifest_233860.acf"
        if (Test-Path $manifest) {
            try {
                $raw = Get-Content -LiteralPath $manifest -Raw
                $m = [regex]::Match($raw, '"installdir"\s+"([^"]+)"')
                if ($m.Success) {
                    $candidate = Join-Path $lib ("steamapps\common\" + $m.Groups[1].Value)
                    if (Test-Path $candidate) { return $candidate }
                }
            } catch {}
        }
        $fallback = Join-Path $lib "steamapps\common\Kenshi"
        if (Test-Path $fallback) { return $fallback }
    }
    return ""
}

function ConvertFrom-PoQuoted([string]$s) {
    if ($null -eq $s) { return "" }
    $v = $s.Trim()
    if ($v.StartsWith('"') -and $v.EndsWith('"') -and $v.Length -ge 2) {
        $v = $v.Substring(1, $v.Length - 2)
    }
    try { return [regex]::Unescape($v) }
    catch { return $v.Replace('\"','"').Replace('\\','\') }
}

function ConvertTo-PoQuoted([string]$s) {
    if ($null -eq $s) { $s = "" }
    $v = $s.Replace('\','\\').Replace('"','\"').Replace("`r","").Replace("`n",'\n')
    return '"' + $v + '"'
}

function Read-KenshiPoFile([string]$path, [string]$relativeFile, [string]$kind) {
    $result = New-Object System.Collections.ArrayList
    if (-not (Test-Path $path)) { return @($result) }

    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    $blocks = New-Object System.Collections.ArrayList
    $current = New-Object System.Collections.ArrayList

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                [void]$blocks.Add(@($current))
                $current = New-Object System.Collections.ArrayList
            }
        } else {
            [void]$current.Add($line)
        }
    }
    if ($current.Count -gt 0) { [void]$blocks.Add(@($current)) }

    $index = 0
    foreach ($block in @($blocks)) {
        $index++
        $comments = New-Object System.Collections.ArrayList
        $context = ""
        $msgid = ""
        $msgstr = ""
        $plural = $false
        $field = ""

        foreach ($line in @($block)) {
            $trim = $line.Trim()
            if ($trim.StartsWith('#')) { [void]$comments.Add($line); continue }

            if ($trim -match '^msgctxt\s+(.+)$') {
                $field = "context"; $context = ConvertFrom-PoQuoted $Matches[1]; continue
            }
            if ($trim -match '^msgid_plural\s+(.+)$') {
                $plural = $true; $field = "plural"; continue
            }
            if ($trim -match '^msgid\s+(.+)$') {
                $field = "msgid"; $msgid = ConvertFrom-PoQuoted $Matches[1]; continue
            }
            if ($trim -match '^msgstr(?:\[[0-9]+\])?\s+(.+)$') {
                if ($trim -match '^msgstr\[') { $plural = $true }
                $field = "msgstr"; $msgstr = ConvertFrom-PoQuoted $Matches[1]; continue
            }
            if ($trim.StartsWith('"')) {
                $piece = ConvertFrom-PoQuoted $trim
                switch ($field) {
                    "context" { $context += $piece }
                    "msgid" { $msgid += $piece }
                    "msgstr" { $msgstr += $piece }
                }
            }
        }

        if ([string]::IsNullOrEmpty($msgid)) { continue }
        if ($plural) { $script:KenshiSkippedPlural++; continue }

        $key = if (-not [string]::IsNullOrWhiteSpace($context)) { $context } else { "$relativeFile#$index" }
        [void]$result.Add([pscustomobject]@{
            Kind = $kind
            File = $relativeFile
            Key = $key
            Context = $context
            Source = $msgid
            Translation = $msgstr
            Comments = @($comments)
        })
    }
    return @($result)
}

function Get-KenshiEntryIdentity($entry) {
    $ctx = [string]$entry.Context
    if ([string]::IsNullOrWhiteSpace($ctx)) {
        return ("$($entry.File)|$($entry.Source)").ToLowerInvariant()
    }
    return ("$($entry.File)|$ctx|$($entry.Source)").ToLowerInvariant()
}

function Read-KenshiExistingTranslationMap([string]$root) {
    $map = @{}
    $ui = Join-Path $root "locale\pl_PL\LC_MESSAGES\main.po"
    foreach ($e in @(Read-KenshiPoFile $ui "LC_MESSAGES\main.po" "UI")) {
        $map[(Get-KenshiEntryIdentity $e)] = $e.Translation
    }

    $work = Join-Path $root "__translations\pl_PL"
    if (Test-Path $work) {
        $game = Join-Path $work "gamedata.po"
        foreach ($e in @(Read-KenshiPoFile $game "gamedata.po" "GameData")) {
            $map[(Get-KenshiEntryIdentity $e)] = $e.Translation
        }

        $dialogue = Join-Path $work "dialogue"
        if (Test-Path $dialogue) {
            Get-ChildItem -LiteralPath $dialogue -Filter *.po -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = "dialogue\" + $_.FullName.Substring($dialogue.Length).TrimStart('\','/')
                foreach ($e in @(Read-KenshiPoFile $_.FullName $rel "Dialogue")) {
                    $map[(Get-KenshiEntryIdentity $e)] = $e.Translation
                }
            }
        }
    }
    return $map
}

function Refresh-KenshiGrid {
    $kenshiGrid.ItemsSource = $null
    $kenshiGrid.ItemsSource = @($script:KenshiEntries)
    $lblKenshiCount.Content = "Wpisy: $($script:KenshiEntries.Count)"
}

function Scan-KenshiBase([string]$root) {
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
        throw "Nie znaleziono folderu Kenshi."
    }

    $script:KenshiEntries.Clear()
    $script:KenshiRoot = $root
    $script:KenshiSkippedPlural = 0
    $script:KenshiUiSource = ""
    $script:KenshiFcsBase = ""

    $uiCandidates = @(
        (Join-Path $root "locale\en\LC_MESSAGES\main.pot"),
        (Join-Path $root "locale\en\LC_MESSAGES\main.po"),
        (Join-Path $root "locale\en_GB\LC_MESSAGES\main.pot"),
        (Join-Path $root "locale\en_GB\LC_MESSAGES\main.po"),
        (Join-Path $root "locale\en-GB\LC_MESSAGES\main.pot"),
        (Join-Path $root "locale\en-GB\LC_MESSAGES\main.po"),
        (Join-Path $root "locale\en_US\LC_MESSAGES\main.pot"),
        (Join-Path $root "locale\en_US\LC_MESSAGES\main.po")
    )
    $ui = $uiCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $ui -and (Test-Path (Join-Path $root "locale"))) {
        $ui = Get-ChildItem -LiteralPath (Join-Path $root "locale") -File -Recurse -ErrorAction SilentlyContinue |
              Where-Object {
                  $_.Name -in @("main.pot","main.po") -and
                  $_.FullName -match '[\\/]en([_\-][A-Za-z]+)?[\\/]LC_MESSAGES[\\/]'
              } |
              Select-Object -First 1 -ExpandProperty FullName
    }

    if ($ui) {
        $script:KenshiUiSource = $ui
        foreach ($e in @(Read-KenshiPoFile $ui "LC_MESSAGES\main.po" "UI")) {
            [void]$script:KenshiEntries.Add($e)
        }
    }

    $base = Join-Path $root "__translations\base"
    if (Test-Path $base) {
        $script:KenshiFcsBase = $base
        $gamedata = Join-Path $base "gamedata.pot"
        if (-not (Test-Path $gamedata)) { $gamedata = Join-Path $base "gamedata.po" }

        if (Test-Path $gamedata) {
            foreach ($e in @(Read-KenshiPoFile $gamedata "gamedata.po" "GameData")) {
                [void]$script:KenshiEntries.Add($e)
            }
        }

        $dialogue = Join-Path $base "dialogue"
        if (Test-Path $dialogue) {
            Get-ChildItem -LiteralPath $dialogue -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".pot",".po") } |
                ForEach-Object {
                    $relTail = $_.FullName.Substring($dialogue.Length).TrimStart('\','/')
                    $rel = "dialogue\$([System.IO.Path]::ChangeExtension($relTail,'.po'))"
                    foreach ($e in @(Read-KenshiPoFile $_.FullName $rel "Dialogue")) {
                        [void]$script:KenshiEntries.Add($e)
                    }
                }
        }
    }

    $existing = Read-KenshiExistingTranslationMap $root
    $loaded = 0
    foreach ($e in @($script:KenshiEntries)) {
        $id = Get-KenshiEntryIdentity $e
        if ($existing.ContainsKey($id) -and -not [string]::IsNullOrWhiteSpace([string]$existing[$id])) {
            $e.Translation = [string]$existing[$id]
            $loaded++
        }
    }

    Refresh-KenshiGrid
    return [pscustomobject]@{
        Total = $script:KenshiEntries.Count
        UiFound = -not [string]::IsNullOrWhiteSpace($script:KenshiUiSource)
        FcsExportFound = -not [string]::IsNullOrWhiteSpace($script:KenshiFcsBase)
        ExistingLoaded = $loaded
        SkippedPlural = $script:KenshiSkippedPlural
    }
}

function Write-KenshiPoFile([string]$path, $entries, [string]$languageCode="pl_PL") {
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Generated/updated with Mod Translation Toolkit')
    [void]$sb.AppendLine('msgid ""')
    [void]$sb.AppendLine('msgstr ""')
    [void]$sb.AppendLine('"Content-Type: text/plain; charset=UTF-8\n"')
    [void]$sb.AppendLine('"Language: ' + $languageCode + '\n"')
    [void]$sb.AppendLine('')

    foreach ($e in @($entries)) {
        foreach ($c in @($e.Comments)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$c)) { [void]$sb.AppendLine([string]$c) }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$e.Context)) {
            [void]$sb.AppendLine("msgctxt $(ConvertTo-PoQuoted ([string]$e.Context))")
        }
        [void]$sb.AppendLine("msgid $(ConvertTo-PoQuoted ([string]$e.Source))")
        [void]$sb.AppendLine("msgstr $(ConvertTo-PoQuoted ([string]$e.Translation))")
        [void]$sb.AppendLine('')
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
}

function Write-KenshiMoFile([string]$path, $entries) {
    $pairs = New-Object System.Collections.ArrayList
    [void]$pairs.Add([pscustomobject]@{ Id=""; Str="Content-Type: text/plain; charset=UTF-8`nLanguage: pl_PL`n" })

    foreach ($e in @($entries)) {
        $id = [string]$e.Source
        $str = [string]$e.Translation
        if ([string]::IsNullOrWhiteSpace($str)) { $str = $id }
        [void]$pairs.Add([pscustomobject]@{ Id=$id; Str=$str })
    }

    $pairs = @($pairs | Sort-Object Id)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $n = $pairs.Count
    $headerSize = 28
    $origTable = $headerSize
    $transTable = $origTable + ($n * 8)
    $dataOffset = $transTable + ($n * 8)

    $origBytes = @()
    $transBytes = @()
    foreach ($p in $pairs) {
        $origBytes += ,($utf8.GetBytes([string]$p.Id))
        $transBytes += ,($utf8.GetBytes([string]$p.Str))
    }

    $origMeta = @()
    $transMeta = @()
    $cursor = $dataOffset
    foreach ($b in $origBytes) { $origMeta += ,@($b.Length, $cursor); $cursor += $b.Length + 1 }
    foreach ($b in $transBytes) { $transMeta += ,@($b.Length, $cursor); $cursor += $b.Length + 1 }

    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        $bw.Write([uint32]0x950412de)
        $bw.Write([uint32]0)
        $bw.Write([uint32]$n)
        $bw.Write([uint32]$origTable)
        $bw.Write([uint32]$transTable)
        $bw.Write([uint32]0)
        $bw.Write([uint32]0)

        foreach ($m in $origMeta) { $bw.Write([uint32]$m[0]); $bw.Write([uint32]$m[1]) }
        foreach ($m in $transMeta) { $bw.Write([uint32]$m[0]); $bw.Write([uint32]$m[1]) }
        foreach ($b in $origBytes) { $bw.Write($b); $bw.Write([byte]0) }
        foreach ($b in $transBytes) { $bw.Write($b); $bw.Write([byte]0) }
    } finally {
        $bw.Close()
        $fs.Close()
    }
}

function Backup-KenshiFile([string]$path) {
    if (-not (Test-Path $path)) { return }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item -LiteralPath $path -Destination "$path.mtt-backup-$stamp" -Force
}

function Build-KenshiBaseTranslation([string]$root) {
    if ($script:KenshiEntries.Count -eq 0) { throw "Najpierw zeskanuj podstawę Kenshi." }

    $uiEntries = @($script:KenshiEntries | Where-Object { $_.Kind -eq "UI" })
    $gameEntries = @($script:KenshiEntries | Where-Object { $_.Kind -eq "GameData" })
    $dialogueEntries = @($script:KenshiEntries | Where-Object { $_.Kind -eq "Dialogue" })

    $localeRoot = Join-Path $root "locale\pl_PL"
    $uiPo = Join-Path $localeRoot "LC_MESSAGES\main.po"
    $uiMo = Join-Path $localeRoot "LC_MESSAGES\main.mo"

    if ($uiEntries.Count -gt 0) {
        Backup-KenshiFile $uiPo
        Backup-KenshiFile $uiMo
        Write-KenshiPoFile $uiPo $uiEntries
        Write-KenshiMoFile $uiMo $uiEntries
    }

    $workRoot = Join-Path $root "__translations\pl_PL"
    if ($gameEntries.Count -gt 0) {
        $gamePath = Join-Path $workRoot "gamedata.po"
        Backup-KenshiFile $gamePath
        Write-KenshiPoFile $gamePath $gameEntries
    }

    foreach ($g in @($dialogueEntries | Group-Object File)) {
        $dest = Join-Path $workRoot $g.Name
        Backup-KenshiFile $dest
        Write-KenshiPoFile $dest $g.Group
    }

    $instructions = @"
Mod Translation Toolkit v$AppVersion
Kenshi base-game translation workspace
Target: pl_PL

UI:
- locale\pl_PL\LC_MESSAGES\main.po
- locale\pl_PL\LC_MESSAGES\main.mo

Game data / dialogues:
- __translations\pl_PL\gamedata.po
- __translations\pl_PL\dialogue\*.po

IMPORTANT:
Kenshi's gameplay/data localization must still be compiled by Forgotten Construction Set (FCS).
Open FCS -> Translations, select pl_PL and use Build.
The resulting pl_PL.translation should be copied to:
locale\pl_PL\pl_PL.translation

Toolkit created backups before overwriting existing PO/MO files.
"@
    New-Item -ItemType Directory -Path $localeRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $localeRoot "ModTranslationToolkit-Kenshi.txt"), $instructions, (New-Object System.Text.UTF8Encoding($false)))
    return $localeRoot
}

function Export-KenshiCsv([string]$path) {
    @($script:KenshiEntries) | Select-Object Kind,File,Key,Context,Source,Translation |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
}

function Import-KenshiCsv([string]$path) {
    $rows = @(Import-Csv -LiteralPath $path)
    $map = @{}
    foreach ($r in $rows) {
        $ctx = [string]$r.Context
        $id = if ([string]::IsNullOrWhiteSpace($ctx)) {
            ("$($r.File)|$($r.Source)").ToLowerInvariant()
        } else {
            ("$($r.File)|$ctx|$($r.Source)").ToLowerInvariant()
        }
        $map[$id] = [string]$r.Translation
    }

    $loaded = 0
    foreach ($e in @($script:KenshiEntries)) {
        $id = Get-KenshiEntryIdentity $e
        if ($map.ContainsKey($id)) { $e.Translation = [string]$map[$id]; $loaded++ }
    }
    Refresh-KenshiGrid
    return $loaded
}



function Set-ClipboardTextSafe([string]$text, [int]$maxAttempts = 8, [int]$delayMs = 80) {
    if ($null -eq $text) { $text = "" }

    $lastError = $null
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            # SetDataObject with persistence is more tolerant than a single SetText call.
            [System.Windows.Clipboard]::SetDataObject($text, $true)
            return $true
        } catch {
            $lastError = $_.Exception
            Start-Sleep -Milliseconds $delayMs
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        }
    }

    # Final fallback through WinForms clipboard API.
    try {
        [System.Windows.Forms.Clipboard]::SetText($text)
        return $true
    } catch {
        if ($null -ne $lastError) { throw $lastError }
        throw
    }
}


# ---------- Steam Workshop dashboard ----------
function Get-MttDataFolder {
    $dir = Join-Path $env:APPDATA "ModTranslationToolkit"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-WorkshopProfilePath {
    return (Join-Path (Get-MttDataFolder) "workshop-profile.json")
}

function Load-WorkshopProfile {
    $path = Get-WorkshopProfilePath
    if (-not (Test-Path $path)) { return }

    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json

        $script:CreatorProfile.CreatorName = [string]$data.creatorName
        $script:CreatorProfile.SteamProfile = [string]$data.steamProfile

        $script:WorkshopItems.Clear()
        foreach ($item in @($data.items)) {
            if ($null -eq $item) { continue }

            [void]$script:WorkshopItems.Add([pscustomobject]@{
                PublishedFileId = [string]$item.publishedFileId
                Title = [string]$item.title
                AppId = [string]$item.appId
                Owner = [string]$item.owner
                Subscriptions = [int64]$item.subscriptions
                Favorites = [int64]$item.favorites
                Views = [int64]$item.views
                FileSize = [int64]$item.fileSize
                TimeCreated = [string]$item.timeCreated
                TimeUpdated = [string]$item.timeUpdated
                Url = [string]$item.url
                LastRefresh = [string]$item.lastRefresh
            })
        }
    } catch {}
}

function Save-WorkshopProfile {
    $items = @()
    foreach ($item in @($script:WorkshopItems)) {
        $items += [ordered]@{
            publishedFileId = [string]$item.PublishedFileId
            title = [string]$item.Title
            appId = [string]$item.AppId
            owner = [string]$item.Owner
            subscriptions = [int64]$item.Subscriptions
            favorites = [int64]$item.Favorites
            views = [int64]$item.Views
            fileSize = [int64]$item.FileSize
            timeCreated = [string]$item.TimeCreated
            timeUpdated = [string]$item.TimeUpdated
            url = [string]$item.Url
            lastRefresh = [string]$item.LastRefresh
        }
    }

    $data = [ordered]@{
        creatorName = [string]$script:CreatorProfile.CreatorName
        steamProfile = [string]$script:CreatorProfile.SteamProfile
        items = $items
    }

    $json = $data | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText(
        (Get-WorkshopProfilePath),
        $json,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Get-PublishedFileIdFromInput([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }

    $v = $value.Trim()

    if ($v -match '^\d{5,}$') {
        return $v
    }

    $m = [regex]::Match($v, '[?&]id=(\d+)')
    if ($m.Success) {
        return $m.Groups[1].Value
    }

    $m = [regex]::Match($v, '/filedetails/\?id=(\d+)')
    if ($m.Success) {
        return $m.Groups[1].Value
    }

    return ""
}

function Convert-UnixToLocalString($unix) {
    try {
        if ([int64]$unix -le 0) { return "" }
        return [DateTimeOffset]::FromUnixTimeSeconds([int64]$unix).LocalDateTime.ToString("yyyy-MM-dd HH:mm")
    } catch {
        return ""
    }
}

function Get-WorkshopPublishedFileDetails([string]$publishedFileId) {
    if ([string]::IsNullOrWhiteSpace($publishedFileId)) {
        throw "Brak PublishedFileID."
    }

    $uri = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
    $body = @{
        itemcount = 1
        "publishedfileids[0]" = $publishedFileId
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 20
    $detail = $response.response.publishedfiledetails | Select-Object -First 1

    if ($null -eq $detail) {
        throw "Steam nie zwrócił szczegółów dla PublishedFileID $publishedFileId."
    }

    if ([string]$detail.result -ne "1") {
        throw "Steam zwrócił błąd dla PublishedFileID $publishedFileId (result: $($detail.result))."
    }

    $views = 0
    if ($null -ne $detail.views) { $views = [int64]$detail.views }

    $subs = 0
    if ($null -ne $detail.subscriptions) { $subs = [int64]$detail.subscriptions }

    $favs = 0
    if ($null -ne $detail.favorited) { $favs = [int64]$detail.favorited }
    elseif ($null -ne $detail.favorites) { $favs = [int64]$detail.favorites }

    return [pscustomobject]@{
        PublishedFileId = [string]$detail.publishedfileid
        Title = [string]$detail.title
        AppId = [string]$detail.consumer_app_id
        Owner = [string]$detail.creator
        Subscriptions = $subs
        Favorites = $favs
        Views = $views
        FileSize = [int64]$detail.file_size
        TimeCreated = Convert-UnixToLocalString $detail.time_created
        TimeUpdated = Convert-UnixToLocalString $detail.time_updated
        Url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($detail.publishedfileid)"
        LastRefresh = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    }
}

function Find-WorkshopItemIndex([string]$publishedFileId) {
    for ($i = 0; $i -lt $script:WorkshopItems.Count; $i++) {
        if ([string]$script:WorkshopItems[$i].PublishedFileId -eq $publishedFileId) {
            return $i
        }
    }
    return -1
}

function Add-OrUpdateWorkshopItem([string]$inputValue) {
    $id = Get-PublishedFileIdFromInput $inputValue
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "Nie rozpoznano linku Workshop ani PublishedFileID."
    }

    $detail = Get-WorkshopPublishedFileDetails $id
    $index = Find-WorkshopItemIndex $id

    if ($index -ge 0) {
        $script:WorkshopItems[$index] = $detail
    } else {
        [void]$script:WorkshopItems.Add($detail)
    }

    Save-WorkshopProfile
    Refresh-WorkshopGrid
    return $detail
}

function Refresh-WorkshopGrid {
    if ($null -eq $workshopGrid) { return }

    $workshopGrid.ItemsSource = $null
    $workshopGrid.ItemsSource = @($script:WorkshopItems)

    $count = $script:WorkshopItems.Count
    $subscriptions = 0
    $favorites = 0
    $views = 0

    foreach ($item in @($script:WorkshopItems)) {
        $subscriptions += [int64]$item.Subscriptions
        $favorites += [int64]$item.Favorites
        $views += [int64]$item.Views
    }

    $lblWorkshopItems.Content = "Publikacje: $count"
    $lblWorkshopSubscriptions.Content = "Subskrypcje: $subscriptions"
    $lblWorkshopFavorites.Content = "Ulubione: $favorites"
    $lblWorkshopViews.Content = "Wyświetlenia: $views"
}

function Refresh-AllWorkshopItems {
    $ids = @($script:WorkshopItems | ForEach-Object { [string]$_.PublishedFileId })
    $done = 0

    foreach ($id in $ids) {
        try {
            $detail = Get-WorkshopPublishedFileDetails $id
            $index = Find-WorkshopItemIndex $id
            if ($index -ge 0) {
                $script:WorkshopItems[$index] = $detail
            }
            $done++
            Refresh-WorkshopGrid
            [System.Windows.Forms.Application]::DoEvents()
        } catch {}
    }

    Save-WorkshopProfile
    return $done
}

function Apply-CreatorProfileToTranslator {
    $name = [string]$script:CreatorProfile.CreatorName
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $txtTranslator.Text = $name
    }
}

# ---------- Dark / Mrokar purple UI ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mod Translation Toolkit v0.5.5"
        Height="840" Width="1260"
        WindowStartupLocation="CenterScreen"
        Background="#121018"
        Foreground="#ECE8F6">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg" Color="#121018"/>
    <SolidColorBrush x:Key="Panel" Color="#1B1723"/>
    <SolidColorBrush x:Key="Panel2" Color="#241D30"/>
    <SolidColorBrush x:Key="Border" Color="#40344F"/>
    <SolidColorBrush x:Key="Purple" Color="#7A3FC2"/>
    <SolidColorBrush x:Key="PurpleHover" Color="#9355DB"/>
    <SolidColorBrush x:Key="PurpleSoft" Color="#B38AE6"/>
    <SolidColorBrush x:Key="Text" Color="#ECE8F6"/>
    <SolidColorBrush x:Key="Muted" Color="#B9AEC9"/>

    <Style TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Purple}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#9D64E8"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{StaticResource PurpleHover}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource Panel2}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
      <Setter Property="CaretBrush" Value="{StaticResource PurpleSoft}"/>
      <Setter Property="Padding" Value="5"/>
    </Style>

    <!-- WPF's native ComboBox chrome may ignore dark Background on some Windows themes.
         Use high-contrast dark text on the native light selection field so language names
         are always readable. Dropdown rows get an explicit light surface too. -->
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="#EEEAF3"/>
      <Setter Property="Foreground" Value="#17131D"/>
      <Setter Property="BorderBrush" Value="#7A3FC2"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="5,2"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style TargetType="ComboBoxItem">
      <Setter Property="Background" Value="#EEEAF3"/>
      <Setter Property="Foreground" Value="#17131D"/>
      <Setter Property="Padding" Value="7,4"/>
      <Style.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
          <Setter Property="Background" Value="#B38AE6"/>
          <Setter Property="Foreground" Value="#17131D"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#9355DB"/>
          <Setter Property="Foreground" Value="White"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="Label">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
    </Style>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
    </Style>

    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="{StaticResource Panel}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#31283D"/>
      <Setter Property="RowBackground" Value="#1B1723"/>
      <Setter Property="AlternatingRowBackground" Value="#211A2B"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
    </Style>

    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#2C2338"/>
      <Setter Property="Foreground" Value="#DCCAF2"/>
      <Setter Property="BorderBrush" Value="#40344F"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="6"/>
    </Style>

    <Style TargetType="DataGridCell">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush" Value="#31283D"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#63309E"/>
          <Setter Property="Foreground" Value="White"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="{StaticResource Panel2}"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="0,0,4,0"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="{StaticResource Purple}"/>
          <Setter Property="Foreground" Value="#17131D"/>
          <Setter Property="FontWeight" Value="Bold"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Grid Background="{StaticResource Bg}">
    <Grid.RowDefinitions>
      <RowDefinition Height="64"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#18131F" BorderBrush="#3A2C49" BorderThickness="0,0,0,1">
      <Grid Margin="16,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="MOD TRANSLATION TOOLKIT" FontSize="20" FontWeight="Bold" Foreground="#D4B5F5"/>
          <TextBlock Text="RimWorld profile • dark Mrokar theme" Foreground="#AFA2C0" FontSize="12"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#2B2038" CornerRadius="5" Padding="10,5" VerticalAlignment="Center">
          <TextBlock Text="v0.5.5" Foreground="#CDA8F2" FontWeight="SemiBold"/>
        </Border>
      </Grid>
    </Border>

    <TabControl Grid.Row="1" Background="{StaticResource Bg}" BorderBrush="{StaticResource Border}" Margin="10">
      <TabItem Name="tabGameProfiles" Header="Profile gier">
        <TabControl Name="tabGameProfilesInner" Background="{StaticResource Bg}" BorderBrush="{StaticResource Border}" Margin="6">
          <TabItem Name="tabRimWorldGame" Header="RimWorld Game">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="btnDetectRimWorldGame" Content="Wykryj RimWorld"/>
            <Button Name="btnChooseRimWorldGame" Content="Wybierz folder gry"/>
            <TextBox Name="txtRimWorldGamePath" Width="650" Margin="8,0" AllowDrop="True"
                     ToolTip="Wklej ścieżkę lub przeciągnij tutaj folder RimWorld."/>
            <Button Name="btnOpenRimWorldGameFolder" Content="Otwórz folder"/>
          </StackPanel>

          <Border Grid.Row="1" Background="#211A2B" BorderBrush="#4A385D" BorderThickness="1"
                  CornerRadius="6" Padding="10" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Text="RimWorld Game — podstawa gry i dodatki" FontSize="18" FontWeight="SemiBold" Foreground="#CDA8F2"/>
              <TextBlock Text="Wybierz Core albo dowolny z wykrytych dodatków. Każdy moduł może być skanowany osobno."
                         Foreground="#B9AEC9" Margin="0,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>

          <Grid Grid.Row="2" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Text="Moduły / DLC:" FontWeight="SemiBold" Margin="0,0,0,4"/>
              <ListBox Name="lstRimWorldGameModules" Height="120" SelectionMode="Extended"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="10,20,0,0">
              <Button Name="btnRwGameSelectAll" Content="Zaznacz wszystko"/>
              <Button Name="btnRwGameCoreOnly" Content="Tylko Core"/>
              <Button Name="btnRwGameDlcOnly" Content="Tylko DLC"/>
              <Button Name="btnScanRimWorldGame" Content="Skanuj wybrane" Margin="0,8,0,0"/>
            </StackPanel>
          </Grid>

          <DataGrid Grid.Row="3" Name="rimWorldGameGrid" AutoGenerateColumns="False" CanUserAddRows="False"
                    SelectionMode="Single" EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Moduł" Binding="{Binding Module}" Width="110"/>
              <DataGridTextColumn Header="Typ" Binding="{Binding Type}" Width="160"/>
              <DataGridTextColumn Header="Klucz" Binding="{Binding Key}" Width="260"/>
              <DataGridTextColumn Header="Angielski" Binding="{Binding Source}" Width="*"/>
              <DataGridTextColumn Header="Polski" Binding="{Binding Translation}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <StackPanel Grid.Row="4" Orientation="Horizontal" Margin="0,10,0,0">
            <TextBlock Name="lblRimWorldGameCount" Text="Wpisy: 0" VerticalAlignment="Center" Margin="0,0,16,0"/>
            <TextBlock Name="txtRimWorldGameStatus" Text="Wybierz folder gry albo użyj automatycznego wykrywania."
                       Foreground="#B9AEC9" VerticalAlignment="Center"/>
          </StackPanel>
        </Grid>
      </TabItem>
          <TabItem Name="tabRimWorldMod" Header="RimWorld Mod">
        <TabControl Name="tabRimWorldModInner" Background="{StaticResource Bg}" BorderBrush="{StaticResource Border}" Margin="6">
          <TabItem Name="tabTranslation" Header="Tłumaczenie">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="btnChooseMod" Content="Wybierz folder moda"/>
            <TextBox Name="txtModPath" Width="670" IsReadOnly="True" VerticalContentAlignment="Center"/>
            <Button Name="btnAnalyze" Content="Skanuj ponownie" Margin="8,0,0,0"/>
            <Button Name="btnUpdateExisting" Content="Aktualizuj istniejące tłumaczenie"/>
            <Button Name="btnOpenCurrentFolder" Content="Otwórz folder moda" Margin="8,0,0,0"/>
          </StackPanel>

          <Grid Grid.Row="1" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="260"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="280"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="170"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="150"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0" Content="Nazwa:"/>
            <TextBox Grid.Column="1" Name="txtModName" IsReadOnly="True" Margin="4"/>
            <Label Grid.Column="2" Content="PackageId:"/>
            <TextBox Grid.Column="3" Name="txtPackageId" IsReadOnly="True" Margin="4"/>
            <Label Grid.Column="4" Content="Autor tłumaczenia:"/>
            <TextBox Grid.Column="5" Name="txtAuthor" Margin="4"/>
            <CheckBox Grid.Column="6" Name="chkPreviewFlag" Content="Preview + flaga" Margin="8,4"
                      Foreground="#ECE8F6" VerticalAlignment="Center" IsChecked="True"/>
            <ComboBox Grid.Column="7" Name="cmbPreviewFlag" Width="145" Height="30" Margin="4" SelectedIndex="0">
              <ComboBoxItem Content="Polska 🇵🇱" Tag="PL"/>
              <ComboBoxItem Content="English / UK 🇬🇧" Tag="GB"/>
              <ComboBoxItem Content="Deutsch 🇩🇪" Tag="DE"/>
              <ComboBoxItem Content="Français 🇫🇷" Tag="FR"/>
              <ComboBoxItem Content="Español 🇪🇸" Tag="ES"/>
              <ComboBoxItem Content="Italiano 🇮🇹" Tag="IT"/>
              <ComboBoxItem Content="Čeština 🇨🇿" Tag="CZ"/>
              <ComboBoxItem Content="Українська 🇺🇦" Tag="UA"/>
              <ComboBoxItem Content="日本語 🇯🇵" Tag="JP"/>
              <ComboBoxItem Content="한국어 🇰🇷" Tag="KR"/>
              <ComboBoxItem Content="中文 🇨🇳" Tag="CN"/>
              <ComboBoxItem Content="Português 🇵🇹" Tag="PT"/>
            </ComboBox>
          </Grid>

          <WrapPanel Grid.Row="2" Margin="0,0,0,10">
            <Button Name="btnExport" Content="Eksport CSV"/>
            <Button Name="btnImport" Content="Import CSV"/>
            <Label Name="lblSourceLang" Content="Z:" VerticalContentAlignment="Center"/>
            <ComboBox Name="cmbSourceLang" Width="105" Height="30" Margin="0,0,8,0" SelectedIndex="0">
              <ComboBoxItem Content="English" Tag="en"/>
              <ComboBoxItem Content="Polski" Tag="pl"/>
            </ComboBox>
            <Label Name="lblTargetLang" Content="Na:" VerticalContentAlignment="Center"/>
            <ComboBox Name="cmbTargetLang" Width="105" Height="30" Margin="0,0,8,0" SelectedIndex="1">
              <ComboBoxItem Content="English" Tag="en"/>
              <ComboBoxItem Content="Polski" Tag="pl"/>
            </ComboBox>
            <Button Name="btnAutoTranslate" Content="Tłumacz brakujące"/>
            <Button Name="btnValidate" Content="Sprawdź / napraw placeholdery"/>
            <Button Name="btnKeybindDiagnostics" Content="Diagnostyka skrótów"/>
            <Button Name="btnAssemblyDiagnostics" Content="Diagnostyka DLL/UI"/>
            <Button Name="btnBuild" Content="Zbuduj oddzielny mod"/>
            <Button Name="btnCopyWorkshop" Content="Kopiuj opis Workshop" IsEnabled="True"/>
            <Label Name="lblCount" Content="Wpisy: 0" VerticalContentAlignment="Center"/>
          </WrapPanel>


          <Border Grid.Row="3" Background="#19151F" BorderBrush="#40344F" BorderThickness="1"
                  CornerRadius="4" Padding="8" Margin="0,0,0,10">
            <StackPanel Orientation="Horizontal">
              <TextBlock Name="lblCoverageTitle" Text="Istniejące języki:" VerticalAlignment="Center"
                         Foreground="#B9AEC9" Margin="0,0,10,0"/>
              <TextBlock Name="txtCoveragePL" Text="Polski: -" VerticalAlignment="Center"
                         Foreground="#D4B5F5" Margin="0,0,12,0"/>
              <Button Name="btnLoadExistingPL" Content="Wczytaj ponownie PL" IsEnabled="False"/>
              <TextBlock Name="txtCoverageEN" Text="English: -" VerticalAlignment="Center"
                         Foreground="#D4B5F5" Margin="8,0,12,0"/>
              <Button Name="btnLoadExistingEN" Content="Wczytaj ponownie EN" IsEnabled="False"/>
            </StackPanel>
          </Border>

          <Border Grid.Row="4" Background="#211A2B" BorderBrush="#4A385D" BorderThickness="1"
                  CornerRadius="4" Padding="8" Margin="0,0,0,10">
            <WrapPanel VerticalAlignment="Center">
              <TextBlock Name="lblSearchTitle" Text="Szukaj:" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBox Name="txtSearchTerm" Width="230" Margin="0,0,8,0"
                       ToolTip="Szukaj w tekście źródłowym lub tłumaczeniu."/>
              <ComboBox Name="cmbSearchScope" Width="140" Margin="0,0,8,0">
                <ComboBoxItem Content="Oba" Tag="both" IsSelected="True"/>
                <ComboBoxItem Content="Oryginał" Tag="source"/>
                <ComboBoxItem Content="Tłumaczenie" Tag="translation"/>
              </ComboBox>
              <Button Name="btnClearSearch" Content="Wyczyść" Margin="0,0,14,0"/>
              <TextBlock Name="lblReplaceTitle" Text="Nowy tekst:" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBox Name="txtReplaceTerm" Width="230" Margin="0,0,8,0"/>
              <Button Name="btnReplaceAll" Content="Zamień wszędzie"/>
              <Label Name="lblSearchCount" Content="" VerticalContentAlignment="Center" Margin="8,0,0,0"/>
            </WrapPanel>
          </Border>

          <DataGrid Grid.Row="5" Name="grid" AutoGenerateColumns="False" CanUserAddRows="False"
                    CanUserDeleteRows="False" IsReadOnly="False" SelectionMode="Extended"
                    EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Typ" Binding="{Binding Kind}" Width="95" IsReadOnly="True"/>
              <DataGridTextColumn Header="Plik" Binding="{Binding File}" Width="180" IsReadOnly="True"/>
              <DataGridTextColumn Header="Klucz" Binding="{Binding Key}" Width="230" IsReadOnly="True"/>
              <DataGridTemplateColumn Header="Angielski" Width="*">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBox Text="{Binding Source}"
                             IsReadOnly="True"
                             IsReadOnlyCaretVisible="True"
                             BorderThickness="0"
                             Background="Transparent"
                             Foreground="#ECE8F6"
                             Padding="2,0"
                             VerticalContentAlignment="Center"
                             TextWrapping="NoWrap"
                             ToolTip="Zaznacz tekst i użyj Ctrl+C lub prawego przycisku myszy."/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Polski" Binding="{Binding Translation, UpdateSourceTrigger=PropertyChanged}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <TextBlock Grid.Row="6" Name="txtStatus" Margin="0,10,0,0" TextWrapping="Wrap"
                     Foreground="#B9AEC9"
                     Text="Wybierz mod ręcznie albo przejdź do zakładki „Zainstalowane mody”."/>
        </Grid>
      </TabItem>
          <TabItem Name="tabInstalledMods" Header="Zainstalowane mody">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="btnDetect" Content="Wykryj Steam i mody"/>
            <Label Content="Szukaj:" VerticalContentAlignment="Center"/>
            <TextBox Name="txtSearch" Width="380" Margin="4,0,8,0"/>
            <Label Name="lblMods" Content="Mody: 0" VerticalContentAlignment="Center"/>
          </StackPanel>

          <DataGrid Grid.Row="1" Name="modsGrid" AutoGenerateColumns="False" CanUserAddRows="False"
                    IsReadOnly="True" SelectionMode="Single" EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Nazwa" Binding="{Binding Name}" Width="*"/>
              <DataGridTextColumn Header="PackageId" Binding="{Binding PackageId}" Width="260"/>
              <DataGridTextColumn Header="Wersja" Binding="{Binding Version}" Width="100"/>
              <DataGridTextColumn Header="Autor" Binding="{Binding Author}" Width="170"/>
              <DataGridTextColumn Header="Źródło" Binding="{Binding Source}" Width="95"/>
              <DataGridTextColumn Header="Folder" Binding="{Binding Path}" Width="330"/>
            </DataGrid.Columns>
          </DataGrid>

          <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
            <Button Name="btnUseSelected" Content="Tłumacz / edytuj wybrany mod"/>
            <Button Name="btnOpenFolder" Content="Otwórz folder moda"/>
          </StackPanel>
        </Grid>
      </TabItem>
        </TabControl>
      </TabItem>
          <TabItem Name="tabKenshi" Header="Kenshi Game">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="btnDetectKenshi" Content="Wykryj Kenshi"/>
            <Button Name="btnChooseKenshi" Content="Wybierz folder Kenshi"/>
            <TextBox Name="txtKenshiPath" Width="650" Margin="8,0" AllowDrop="True" ToolTip="Wklej ścieżkę lub przeciągnij tutaj folder gry."/>
            <Button Name="btnOpenKenshiFolder" Content="Otwórz folder"/>
          </StackPanel>

          <Border Grid.Row="1" Background="#211A2B" BorderBrush="#4A385D" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Text="Kenshi — tłumaczenie podstawowej gry" FontSize="18" FontWeight="SemiBold" Foreground="#CDA8F2"/>
              <TextBlock Text="UI: locale\en\LC_MESSAGES\main.pot/main.po. Dane gry i dialogi: eksport FCS do __translations\base."
                         Foreground="#B9AEC9" Margin="0,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>

          <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="btnScanKenshi" Content="Skanuj podstawę gry"/>
            <Button Name="btnTranslateKenshi" Content="Tłumacz brakujące"/>
            <Button Name="btnExportKenshiCsv" Content="Eksport CSV"/>
            <Button Name="btnImportKenshiCsv" Content="Import CSV"/>
            <Button Name="btnFcsHelpKenshi" Content="Jak wyeksportować dane z FCS?"/>
            <Button Name="btnBuildKenshi" Content="Przygotuj pliki pl_PL"/>
            <Label Name="lblKenshiCount" Content="Wpisy: 0" VerticalContentAlignment="Center" Margin="8,0,0,0"/>
          </StackPanel>

          <DataGrid Grid.Row="3" Name="kenshiGrid" AutoGenerateColumns="False" CanUserAddRows="False"
                    SelectionMode="Single" EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Typ" Binding="{Binding Kind}" Width="100" IsReadOnly="True"/>
              <DataGridTextColumn Header="Plik" Binding="{Binding File}" Width="230" IsReadOnly="True"/>
              <DataGridTextColumn Header="Klucz / kontekst" Binding="{Binding Key}" Width="260" IsReadOnly="True"/>
              <DataGridTemplateColumn Header="Angielski" Width="*">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBox Text="{Binding Source}" IsReadOnly="True" IsReadOnlyCaretVisible="True"
                             BorderThickness="0" Background="Transparent" Foreground="#ECE8F6"
                             Padding="2,0" TextWrapping="NoWrap"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Polski" Binding="{Binding Translation, UpdateSourceTrigger=PropertyChanged}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <TextBlock Grid.Row="4" Name="txtKenshiStatus" Margin="0,10,0,0" TextWrapping="Wrap"
                     Foreground="#B9AEC9"
                     Text="Wykryj Kenshi lub wskaż folder instalacji. Profil obsługuje na razie tylko podstawową grę."/>
        </Grid>
      </TabItem>
        </TabControl>
      </TabItem>
      <TabItem Name="tabWorkshop" Header="Workshop">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <Border Grid.Row="0" Background="#211A2B" BorderBrush="#4A385D" BorderThickness="1"
                  CornerRadius="6" Padding="12" Margin="0,0,0,10">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="260"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <TextBlock Grid.Column="0" Text="Nazwa kreatora:" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBox Grid.Column="1" Name="txtCreatorName" Margin="0,0,12,0"
                       ToolTip="Nazwa używana jako autor tłumaczeń."/>
              <TextBlock Grid.Column="2" Text="SteamID / profil:" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBox Grid.Column="3" Name="txtSteamProfile" Margin="0,0,12,0"
                       ToolTip="Opcjonalny SteamID64 lub link do profilu Steam."/>
              <Button Grid.Column="4" Name="btnSaveCreatorProfile" Content="Zapisz profil"/>
            </Grid>
          </Border>

          <WrapPanel Grid.Row="1" Margin="0,0,0,10">
            <TextBox Name="txtWorkshopItemInput" Width="430" Margin="0,0,8,0"
                     ToolTip="Wklej link do przedmiotu Workshop albo PublishedFileID."/>
            <Button Name="btnAddWorkshopItem" Content="Dodaj publikację"/>
            <Button Name="btnRefreshWorkshop" Content="Odśwież statystyki"/>
            <Button Name="btnRemoveWorkshopItem" Content="Usuń z listy"/>
            <Button Name="btnOpenWorkshopItem" Content="Otwórz Workshop"/>
          </WrapPanel>

          <WrapPanel Grid.Row="2" Margin="0,0,0,10">
            <Border Background="#2B2138" CornerRadius="5" Padding="10,5" Margin="0,0,8,0">
              <Label Name="lblWorkshopItems" Content="Publikacje: 0"/>
            </Border>
            <Border Background="#2B2138" CornerRadius="5" Padding="10,5" Margin="0,0,8,0">
              <Label Name="lblWorkshopSubscriptions" Content="Subskrypcje: 0"/>
            </Border>
            <Border Background="#2B2138" CornerRadius="5" Padding="10,5" Margin="0,0,8,0">
              <Label Name="lblWorkshopFavorites" Content="Ulubione: 0"/>
            </Border>
            <Border Background="#2B2138" CornerRadius="5" Padding="10,5">
              <Label Name="lblWorkshopViews" Content="Wyświetlenia: 0"/>
            </Border>
          </WrapPanel>

          <DataGrid Grid.Row="3" Name="workshopGrid" AutoGenerateColumns="False"
                    CanUserAddRows="False" SelectionMode="Single" IsReadOnly="True">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Tytuł" Binding="{Binding Title}" Width="*"/>
              <DataGridTextColumn Header="PublishedFileID" Binding="{Binding PublishedFileId}" Width="150"/>
              <DataGridTextColumn Header="AppID" Binding="{Binding AppId}" Width="85"/>
              <DataGridTextColumn Header="Subskrypcje" Binding="{Binding Subscriptions}" Width="100"/>
              <DataGridTextColumn Header="Ulubione" Binding="{Binding Favorites}" Width="85"/>
              <DataGridTextColumn Header="Wyświetlenia" Binding="{Binding Views}" Width="100"/>
              <DataGridTextColumn Header="Aktualizacja Workshop" Binding="{Binding TimeUpdated}" Width="150"/>
              <DataGridTextColumn Header="Odświeżono" Binding="{Binding LastRefresh}" Width="135"/>
            </DataGrid.Columns>
          </DataGrid>

          <TextBlock Grid.Row="4" Name="txtWorkshopStatus" Margin="0,10,0,0" TextWrapping="Wrap"
                     Foreground="#B9AEC9"
                     Text="Dodaj publikacje przez link Workshop lub PublishedFileID. Toolkit nie przechowuje hasła Steam ani publisher API key."/>
        </Grid>
      </TabItem>
    </TabControl>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$names = @(
    "btnChooseMod","btnAnalyze","btnExport","btnImport","btnAutoTranslate","btnValidate","btnBuild",
    "txtModPath","txtModName","txtPackageId","txtAuthor","grid","lblCount","txtStatus",
    "btnDetect","txtSearch","lblMods","modsGrid","btnUseSelected","btnOpenFolder","btnOpenCurrentFolder","cmbSourceLang","cmbTargetLang","lblSourceLang","lblTargetLang","tabTranslation","tabInstalledMods","tabGameProfiles","chkPreviewFlag","cmbPreviewFlag","btnCopyWorkshop","lblCoverageTitle","txtCoveragePL","txtCoverageEN","btnLoadExistingPL","btnLoadExistingEN","tabKenshi","btnDetectKenshi","btnChooseKenshi","txtKenshiPath","btnOpenKenshiFolder","btnScanKenshi","btnTranslateKenshi","btnExportKenshiCsv","btnImportKenshiCsv","btnFcsHelpKenshi","btnBuildKenshi","lblKenshiCount","kenshiGrid","txtKenshiStatus",
  "btnUpdateExisting",
  "lblSearchTitle","txtSearchTerm","cmbSearchScope","btnClearSearch","lblReplaceTitle","txtReplaceTerm","btnReplaceAll","lblSearchCount",
  "tabWorkshop","txtCreatorName","txtSteamProfile","btnSaveCreatorProfile","txtWorkshopItemInput","btnAddWorkshopItem","btnRefreshWorkshop","btnRemoveWorkshopItem","btnOpenWorkshopItem","lblWorkshopItems","lblWorkshopSubscriptions","lblWorkshopFavorites","lblWorkshopViews","workshopGrid","txtWorkshopStatus",
  "btnKeybindDiagnostics",
  "btnAssemblyDiagnostics",
  "tabGameProfilesInner",
  "tabRimWorldGame",
  "tabRimWorldMod",
  "tabRimWorldModInner",
  "btnDetectRimWorldGame",
  "btnChooseRimWorldGame",
  "txtRimWorldGamePath",
  "btnOpenRimWorldGameFolder",
  "lstRimWorldGameModules",
  "btnRwGameSelectAll",
  "btnRwGameCoreOnly",
  "btnRwGameDlcOnly",
  "btnScanRimWorldGame",
  "rimWorldGameGrid",
  "lblRimWorldGameCount",
  "txtRimWorldGameStatus"
)
foreach ($n in $names) { Set-Variable -Name $n -Value $window.FindName($n) }



function Get-CoverageText([string]$code) {
    if (-not $script:LanguageCoverage.ContainsKey($code)) {
        return if ($code -eq "pl") { "Polski: -" } else { "English: -" }
    }

    $c = $script:LanguageCoverage[$code]
    $name = if ($code -eq "pl") { "Polski" } else { "English" }

    $statusText = if ($script:UiLanguage -eq "en") {
        switch ($c.Status) {
            "none" { "none" }
            "partial" { "partial" }
            "complete" { "complete" }
            default { $c.Status }
        }
    } else {
        switch ($c.Status) {
            "none" { "brak" }
            "partial" { "częściowe" }
            "complete" { "pełne" }
            default { $c.Status }
        }
    }

    return "$name`: $($c.Matched)/$($c.Total) ($($c.Percent)%) - $statusText"
}

function Refresh-LanguageCoverageUi {
    $txtCoveragePL.Text = Get-CoverageText "pl"
    $txtCoverageEN.Text = Get-CoverageText "en"

    $btnLoadExistingPL.IsEnabled = (
        $script:ExistingTranslations.ContainsKey("pl") -and
        $script:ExistingTranslations["pl"].Count -gt 0
    )

    $btnLoadExistingEN.IsEnabled = (
        $script:ExistingTranslations.ContainsKey("en") -and
        $script:ExistingTranslations["en"].Count -gt 0
    )
}

function Apply-UiLanguage {
    if ($script:UiLanguage -ne "en") {
        $tabTranslation.Header = "Tłumaczenie"
        $tabInstalledMods.Header = "Zainstalowane mody"
        $tabGameProfiles.Header = "Profile gier"
        $tabRimWorldGame.Header = "RimWorld Game"
        $tabRimWorldMod.Header = "RimWorld Mod"
        $btnDetectRimWorldGame.Content = "Wykryj RimWorld"
        $btnChooseRimWorldGame.Content = "Wybierz folder gry"
        $btnOpenRimWorldGameFolder.Content = "Otwórz folder"
        $btnRwGameSelectAll.Content = "Zaznacz wszystko"
        $btnRwGameCoreOnly.Content = "Tylko Core"
        $btnRwGameDlcOnly.Content = "Tylko DLC"
        $btnScanRimWorldGame.Content = "Skanuj wybrane"

        $tabWorkshop.Header = "Workshop"
    $tabKenshi.Header = "Kenshi Game"
    $tabRimWorldGame.Header = "RimWorld Game"
    $tabRimWorldMod.Header = "RimWorld Mod"
        return
    }

    $window.Title = "Mod Translation Toolkit v$AppVersion"
    $tabTranslation.Header = "Translation"
    $tabInstalledMods.Header = "Installed mods"
    $tabGameProfiles.Header = "Game profiles"
    $tabKenshi.Header = "Kenshi Game"
    $tabRimWorldGame.Header = "RimWorld Game"
    $tabRimWorldMod.Header = "RimWorld Mod"
    $btnDetectRimWorldGame.Content = "Detect RimWorld"
    $btnChooseRimWorldGame.Content = "Choose game folder"
    $btnOpenRimWorldGameFolder.Content = "Open folder"
    $btnRwGameSelectAll.Content = "Select all"
    $btnRwGameCoreOnly.Content = "Core only"
    $btnRwGameDlcOnly.Content = "DLC only"
    $btnScanRimWorldGame.Content = "Scan selected"

    $btnOpenKenshiProfile.Content = "Open Kenshi profile"
    $btnDetectKenshi.Content = "Detect Kenshi"
    $btnChooseKenshi.Content = "Choose Kenshi folder"
    $btnOpenKenshiFolder.Content = "Open folder"
    $btnScanKenshi.Content = "Scan base game"
    $btnTranslateKenshi.Content = "Translate missing"
    $btnExportKenshiCsv.Content = "Export CSV"
    $btnImportKenshiCsv.Content = "Import CSV"
    $btnFcsHelpKenshi.Content = "How to export data with FCS?"
    $btnBuildKenshi.Content = "Prepare pl_PL files"
    $lblCoverageTitle.Text = "Existing languages:"
    $btnLoadExistingPL.Content = "Reload Polish"
    $btnLoadExistingEN.Content = "Reload English"
    $btnUpdateExisting.Content = "Update existing translation"
    $lblSearchTitle.Text = "Search:"
    $btnClearSearch.Content = "Clear"
    $lblReplaceTitle.Text = "New text:"
    $btnReplaceAll.Content = "Replace all"
    $btnKeybindDiagnostics.Content = "Keybind diagnostics"
    $btnAssemblyDiagnostics.Content = "DLL/UI diagnostics"
    try {
        $cmbSearchScope.Items[0].Content = "Both"
        $cmbSearchScope.Items[1].Content = "Source"
        $cmbSearchScope.Items[2].Content = "Translation"
    } catch {}
    $window.FindName("btnChooseMod").Content = "Choose mod folder"
    $window.FindName("btnAnalyze").Content = "Scan again"
    $window.FindName("btnOpenCurrentFolder").Content = "Open mod folder"
    $chkPreviewFlag.Content = "Preview + flag"
    $window.FindName("btnExport").Content = "Export CSV"
    $window.FindName("btnImport").Content = "Import CSV"
    $window.FindName("lblSourceLang").Content = "From:"
    $window.FindName("lblTargetLang").Content = "To:"
    $window.FindName("btnAutoTranslate").Content = "Translate missing"
    $window.FindName("btnValidate").Content = "Check / repair placeholders"
    $window.FindName("btnBuild").Content = "Build separate translation mod"
    $btnCopyWorkshop.Content = "Copy Workshop description"
    $window.FindName("lblCount").Content = "Entries: 0"
    $window.FindName("btnDetect").Content = "Detect Steam and mods"
    $window.FindName("lblMods").Content = "Mods: 0"
    $window.FindName("btnUseSelected").Content = "Translate selected mod"
    $window.FindName("btnOpenFolder").Content = "Open mod folder"
    $window.FindName("txtStatus").Text = "Choose a mod manually or use the Installed mods tab."

    # English UI defaults to English -> Polish automatic translation too.
    $cmbSourceLang.SelectedIndex = 0
    $cmbTargetLang.SelectedIndex = 1

    if ($grid.Columns.Count -ge 5) {
        $grid.Columns[0].Header = "Type"
        $grid.Columns[1].Header = "File"
        $grid.Columns[2].Header = "Key"
        $grid.Columns[3].Header = "Source"
        $grid.Columns[4].Header = "Translation"
    }
    if ($modsGrid.Columns.Count -ge 6) {
        $modsGrid.Columns[0].Header = "Name"
        $modsGrid.Columns[1].Header = "PackageId"
        $modsGrid.Columns[2].Header = "Version"
        $modsGrid.Columns[3].Header = "Author"
        $modsGrid.Columns[4].Header = "Source"
        $modsGrid.Columns[5].Header = "Folder"
    }
}

Apply-UiLanguage

$cmbTargetLang.Add_SelectionChanged({
    try {
        $tag = [string]$cmbTargetLang.SelectedItem.Tag
        if ($tag -eq "pl") {
            foreach ($item in $cmbPreviewFlag.Items) {
                if ([string]$item.Tag -eq "PL") { $cmbPreviewFlag.SelectedItem = $item; break }
            }
        } elseif ($tag -eq "en") {
            foreach ($item in $cmbPreviewFlag.Items) {
                if ([string]$item.Tag -eq "GB") { $cmbPreviewFlag.SelectedItem = $item; break }
            }
        }

        if ($script:OriginalModPath) {
            [void](AutoLoad-ExistingTargetTranslation)
            Refresh-LanguageCoverageUi
        }
    } catch {}
})


$btnUpdateExisting.Add_Click({
    try {
        $defaultSource = if (Test-ExistingFolderSafe $txtModPath.Text) { $txtModPath.Text } else { "" }

        $updatedOriginal = Show-PathInputDialog `
            "Aktualizacja tłumaczenia — źródło" `
            "Wklej ścieżkę albo przeciągnij folder ZAKTUALIZOWANEGO moda źródłowego:" `
            $defaultSource
        if ([string]::IsNullOrWhiteSpace($updatedOriginal)) { return }

        $translationMod = Show-PathInputDialog `
            "Aktualizacja tłumaczenia — istniejące tłumaczenie" `
            "Wklej ścieżkę albo przeciągnij folder ISTNIEJĄCEGO moda tłumaczeniowego:" `
            ""
        if ([string]::IsNullOrWhiteSpace($translationMod)) { return }

        $stats = Start-TranslationUpdate $updatedOriginal $translationMod
        if ($null -eq $stats) { throw "Nie udało się utworzyć podsumowania aktualizacji." }

        Set-ControlTextSafe $txtStatus "Tryb aktualizacji. Zachowane: $($stats.Preserved), nowe: $($stats.New), brakujące: $($stats.MissingCount), nieaktualne: $($stats.Obsolete). packageId i About.xml zostaną zachowane."

        [System.Windows.MessageBox]::Show(
            "Wczytano aktualizację tłumaczenia.`n`nZachowane: $($stats.Preserved)`nNowe: $($stats.New)`nBrakujące: $($stats.MissingCount)`nNieaktualne: $($stats.Obsolete)`n`nUzupełnij tylko nowe/brakujące wpisy, a potem kliknij Zapisz aktualizację.",
            "Mod Translation Toolkit"
        ) | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Błąd") | Out-Null
    }
})


$txtModPath.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        [void](Load-RimWorldModPath $txtModPath.Text)
        $e.Handled = $true
    }
})

$txtModPath.Add_LostFocus({
    if (Test-ExistingFolderSafe $txtModPath.Text) {
        if ($script:OriginalModPath -ne $txtModPath.Text) {
            [void](Load-RimWorldModPath $txtModPath.Text -Silent)
        }
    }
})

$txtModPath.Add_PreviewDragOver({
    param($sender, $e)
    $e.Effects = [System.Windows.DragDropEffects]::Copy
    $e.Handled = $true
})

$txtModPath.Add_Drop({
    param($sender, $e)
    $folder = Get-DroppedFolderPath $e
    if (-not [string]::IsNullOrWhiteSpace($folder)) {
        [void](Load-RimWorldModPath $folder)
        $e.Handled = $true
    }
})

$txtKenshiPath.Add_PreviewDragOver({
    param($sender, $e)
    $e.Effects = [System.Windows.DragDropEffects]::Copy
    $e.Handled = $true
})

$txtKenshiPath.Add_Drop({
    param($sender, $e)
    $folder = Get-DroppedFolderPath $e
    if (-not [string]::IsNullOrWhiteSpace($folder)) {
        [void](Load-KenshiPath $folder)
        $e.Handled = $true
    }
})

$txtKenshiPath.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        [void](Load-KenshiPath $txtKenshiPath.Text)
        $e.Handled = $true
    }
})


$txtSearchTerm.Add_TextChanged({
    Refresh-SearchResults
})

$cmbSearchScope.Add_SelectionChanged({
    Refresh-SearchResults
})

$btnClearSearch.Add_Click({
    $txtSearchTerm.Text = ""
    $txtReplaceTerm.Text = ""
    Refresh-SearchResults
})

$btnReplaceAll.Add_Click({
    $search = [string]$txtSearchTerm.Text
    $replacement = [string]$txtReplaceTerm.Text
    if ([string]::IsNullOrWhiteSpace($search)) {
        [System.Windows.MessageBox]::Show("Najpierw wpisz szukane sformułowanie.","Mod Translation Toolkit") | Out-Null
        return
    }

    $scope = Get-SearchScopeCode
    $count = Replace-InFilteredTranslations $search $replacement $scope

    if ($scope -eq "source") {
        Set-ControlTextSafe $txtStatus "Ustawiono tłumaczenie dla $count pasujących wpisów źródłowych."
    } else {
        Set-ControlTextSafe $txtStatus "Zmieniono tekst w $count tłumaczeniach."
    }
})


$btnSaveCreatorProfile.Add_Click({
    $script:CreatorProfile.CreatorName = [string]$txtCreatorName.Text
    $script:CreatorProfile.SteamProfile = [string]$txtSteamProfile.Text
    Save-WorkshopProfile
    Apply-CreatorProfileToTranslator
    Set-ControlTextSafe $txtWorkshopStatus "Zapisano profil kreatora. Nazwa będzie automatycznie używana jako autor tłumaczenia."
})

$btnAddWorkshopItem.Add_Click({
    try {
        $detail = Add-OrUpdateWorkshopItem ([string]$txtWorkshopItemInput.Text)
        $txtWorkshopItemInput.Text = ""
        Set-ControlTextSafe $txtWorkshopStatus "Dodano/odświeżono: $($detail.Title)"
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Workshop") | Out-Null
    }
})

$btnRefreshWorkshop.Add_Click({
    if ($script:WorkshopItems.Count -eq 0) { return }
    $count = Refresh-AllWorkshopItems
    Set-ControlTextSafe $txtWorkshopStatus "Odświeżono statystyki: $count / $($script:WorkshopItems.Count) publikacji."
})

$btnRemoveWorkshopItem.Add_Click({
    $selected = $workshopGrid.SelectedItem
    if ($null -eq $selected) { return }

    $id = [string]$selected.PublishedFileId
    $index = Find-WorkshopItemIndex $id
    if ($index -ge 0) {
        $script:WorkshopItems.RemoveAt($index)
        Save-WorkshopProfile
        Refresh-WorkshopGrid
        Set-ControlTextSafe $txtWorkshopStatus "Usunięto publikację z lokalnej listy. Nic nie zostało usunięte ze Steam."
    }
})

$btnOpenWorkshopItem.Add_Click({
    $selected = $workshopGrid.SelectedItem
    if ($null -eq $selected) { return }

    $url = [string]$selected.Url
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        Start-Process $url
    }
})

$txtWorkshopItemInput.Add_KeyDown({
    param($sender,$e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        $btnAddWorkshopItem.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        $e.Handled = $true
    }
})



$btnAssemblyDiagnostics.Add_Click({
    try {
        $modPath = [string]$txtModPath.Text
        if (-not (Test-ExistingFolderSafe $modPath)) {
            [System.Windows.MessageBox]::Show("Najpierw załaduj mod.","Assembly / UI diagnostics") | Out-Null
            return
        }

        Set-ControlTextSafe $txtStatus "Skanowanie DLL/UI..."
        $btnAssemblyDiagnostics.IsEnabled = $false
        [System.Windows.Forms.Application]::DoEvents()

        $scan = Scan-AssemblyUiDiagnostics $modPath

        Set-ControlTextSafe $txtStatus "Diagnostyka DLL/UI zakończona. Przeskanowano DLL: $($scan.Files), trafienia: $($scan.Matches)."

        [System.Windows.MessageBox]::Show(
            (Get-AssemblyDiagnosticsText),
            "Assembly / UI diagnostics",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Assembly / UI diagnostics") | Out-Null
    } finally {
        $btnAssemblyDiagnostics.IsEnabled = $true
    }
})

$btnKeybindDiagnostics.Add_Click({
    $message = Get-KeybindDiagnosticsText
    [System.Windows.MessageBox]::Show(
        $message,
        "KeyBindingDef / UI diagnostics",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
})

$btnChooseMod.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Wybierz główny folder moda RimWorld"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtModPath.Text = $dlg.SelectedPath
            Reset-TranslationUpdateMode
            $script:EditingTranslationModPath = ""
            $script:EditingTranslationPackageId = ""
            $script:EditingTranslationName = ""
        try {
            $scan = Analyze-Mod $dlg.SelectedPath
            $txtStatus.Text = "Znaleziono $($scan.Total) unikalnych wpisów. Automatycznie podstawiono istniejących wpisów: $($scan.AutoLoadedExisting). Wersja zawartości: $($scan.ContentVersion)."
            Refresh-LanguageCoverageUi
        } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, "Błąd") }
    }
})




$grid.Add_PreviewKeyDown({
    param($sender, $e)

    try {
        if ($e.Key -eq [System.Windows.Input.Key]::C -and
            ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {

            $focused = [System.Windows.Input.Keyboard]::FocusedElement

            # If focus is already inside a TextBox, let the TextBox perform normal selected-text copying.
            if ($focused -is [System.Windows.Controls.TextBox]) {
                return
            }

            if ($null -ne $grid.SelectedItem) {
                $sourceText = [string]$grid.SelectedItem.Source
                if (-not [string]::IsNullOrEmpty($sourceText)) {
                    [void](Set-ClipboardTextSafe $sourceText)
                    $txtStatus.Text = if ($script:UiLanguage -eq "en") {
                        "Source text copied to clipboard."
                    } else {
                        "Skopiowano tekst oryginalny do schowka."
                    }
                    $e.Handled = $true
                }
            }
        }
    } catch {}
})



$btnDetectKenshi.Add_Click({
    $detected = Get-KenshiInstallPath
    if ($detected) {
        $txtKenshiPath.Text = $detected
        $txtKenshiStatus.Text = "Wykryto Kenshi: $detected"
    } else {
        [System.Windows.MessageBox]::Show("Nie znaleziono instalacji Kenshi w bibliotekach Steam.","Mod Translation Toolkit") | Out-Null
    }
})

$btnChooseKenshi.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Wybierz główny folder Kenshi"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtKenshiPath.Text = $dlg.SelectedPath
    }
})

$btnOpenKenshiFolder.Add_Click({
    if (Test-Path $txtKenshiPath.Text) {
        Start-Process explorer.exe -ArgumentList "`"$($txtKenshiPath.Text)`""
    }
})

$btnScanKenshi.Add_Click({
    try {
        $scan = Scan-KenshiBase $txtKenshiPath.Text
        $parts = New-Object System.Collections.ArrayList
        [void]$parts.Add("Wpisy: $($scan.Total)")
        [void]$parts.Add("istniejące PL: $($scan.ExistingLoaded)")
        if ($scan.UiFound) { [void]$parts.Add("UI gettext: OK") }
        else { [void]$parts.Add("UI gettext: nie znaleziono main.po") }

        if ($scan.FcsExportFound) { [void]$parts.Add("eksport FCS: OK") }
        else { [void]$parts.Add("eksport FCS: BRAK — możesz już tłumaczyć UI; dane świata/dialogi pojawią się po eksporcie z FCS") }

        if ($scan.SkippedPlural -gt 0) { [void]$parts.Add("pominięte formy mnogie: $($scan.SkippedPlural)") }
        $txtKenshiStatus.Text = @($parts) -join " | "
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd") | Out-Null
    }
})

$btnTranslateKenshi.Add_Click({
    if ($script:KenshiEntries.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Najpierw zeskanuj podstawę Kenshi.","Mod Translation Toolkit") | Out-Null
        return
    }

    $missing = @($script:KenshiEntries | Where-Object { [string]::IsNullOrWhiteSpace($_.Translation) })
    $done = 0
    foreach ($e in $missing) {
        try {
            $e.Translation = Translate-Google ([string]$e.Source) "en" "pl"
            $done++
            if (($done % 20) -eq 0) {
                Refresh-KenshiGrid
                [System.Windows.Forms.Application]::DoEvents()
            }
        } catch {}
    }
    Refresh-KenshiGrid
    $txtKenshiStatus.Text = "Uzupełniono automatycznie: $done / $($missing.Count)."
})

$btnExportKenshiCsv.Add_Click({
    if ($script:KenshiEntries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    $dlg.FileName = "Kenshi-pl_PL.csv"
    if ($dlg.ShowDialog()) {
        Export-KenshiCsv $dlg.FileName
        $txtKenshiStatus.Text = "Wyeksportowano CSV: $($dlg.FileName)"
    }
})

$btnImportKenshiCsv.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    if ($dlg.ShowDialog()) {
        try {
            $loaded = Import-KenshiCsv $dlg.FileName
            $txtKenshiStatus.Text = "Wczytano z CSV: $loaded wpisów."
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd") | Out-Null
        }
    }
})


$btnFcsHelpKenshi.Add_Click({
    $msg = @"
Aby wyeksportować dane podstawowej gry Kenshi do tłumaczenia:

1. Uruchom Forgotten Construction Set (FCS) z folderu Kenshi.
2. Przy starcie FCS załaduj tylko podstawową grę, bez modów.
3. Otwórz narzędzia tłumaczeń / Translations.
4. Wykonaj Export dla języka bazowego.
5. FCS powinien utworzyć:
   __translations\base\gamedata.pot
   __translations\base\dialogue\*.pot
6. Wróć do Toolkita i kliknij „Skanuj podstawę gry”.

Sam interfejs z locale\en\LC_MESSAGES\main.pot/main.po można tłumaczyć bez eksportu FCS.
"@
    [System.Windows.MessageBox]::Show($msg, "Kenshi — eksport danych przez FCS") | Out-Null
})

$btnBuildKenshi.Add_Click({
    if ($script:KenshiEntries.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Najpierw zeskanuj podstawę Kenshi.","Mod Translation Toolkit") | Out-Null
        return
    }

    $answer = [System.Windows.MessageBox]::Show(
        "Toolkit zapisze pliki pl_PL bezpośrednio w folderze Kenshi.`n`nIstniejące main.po/main.mo/gamedata.po/dialogue zostaną wcześniej skopiowane do plików backup.`n`nKontynuować?",
        "Kenshi — przygotowanie tłumaczenia",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    try {
        $out = Build-KenshiBaseTranslation $txtKenshiPath.Text
        $txtKenshiStatus.Text = "Przygotowano pliki pl_PL. Dane gry/dialogi wymagają teraz Build w FCS. Folder: $out"
        [System.Windows.MessageBox]::Show(
            "Gotowe.`n`nUI main.po/main.mo zostały przygotowane.`nPliki gamedata/dialogue zapisano do __translations\pl_PL.`n`nDla danych gry uruchom FCS -> Translations -> pl_PL -> Build.",
            "Mod Translation Toolkit"
        ) | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd") | Out-Null
    }
})

$btnLoadExistingPL.Add_Click({
    $loaded = Apply-ExistingTranslation "pl"
    $txtStatus.Text = if ($script:UiLanguage -eq "en") {
        "Loaded $loaded existing Polish translation entries."
    } else {
        "Załadowano $loaded istniejących polskich wpisów tłumaczenia."
    }
})

$btnLoadExistingEN.Add_Click({
    $loaded = Apply-ExistingTranslation "en"
    $txtStatus.Text = if ($script:UiLanguage -eq "en") {
        "Loaded $loaded existing English translation entries."
    } else {
        "Załadowano $loaded istniejących angielskich wpisów tłumaczenia."
    }
})

$btnOpenCurrentFolder.Add_Click({
    if ($script:OriginalModPath -and (Test-Path $script:OriginalModPath)) {
        Start-Process explorer.exe $script:OriginalModPath
    } elseif ($txtModPath.Text -and (Test-Path $txtModPath.Text)) {
        Start-Process explorer.exe $txtModPath.Text
    }
})

$btnAnalyze.Add_Click({
    if ($txtModPath.Text) {
        try { $scan = Analyze-Mod $txtModPath.Text; Refresh-LanguageCoverageUi; $txtStatus.Text = "Skan zakończony." }
        catch { [System.Windows.MessageBox]::Show($_.Exception.Message, "Błąd") }
    }
})

$btnExport.Add_Click({
    if ($script:Entries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    $dlg.FileName = "translation_pl.csv"
    if ($dlg.ShowDialog()) { Export-Csv $dlg.FileName; $txtStatus.Text = "CSV zapisany: $($dlg.FileName)" }
})

$btnImport.Add_Click({
    if ($script:Entries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    if ($dlg.ShowDialog()) {
        try { Import-Csv $dlg.FileName; $txtStatus.Text = "Zaimportowano CSV." }
        catch { [System.Windows.MessageBox]::Show($_.Exception.Message, "Błąd") }
    }
})

$btnValidate.Add_Click({
    $bad = Validate-Placeholders

    if ($bad.Count -eq 0) {
        $msg = if ($script:UiLanguage -eq "en") {
            "No placeholder problems detected."
        } else {
            "Nie wykryto problemów z placeholderami."
        }
        [System.Windows.MessageBox]::Show($msg, "Placeholder check")
        return
    }

    Highlight-PlaceholderErrors $bad

    $mode = Show-RepairModeDialog
    if ($mode -eq [System.Windows.MessageBoxResult]::Cancel) { return }

    if ($mode -eq [System.Windows.MessageBoxResult]::No) {
        $txtStatus.Text = if ($script:UiLanguage -eq "en") {
            "$($bad.Count) problematic rows were highlighted."
        } else {
            "Podświetlono $($bad.Count) problematycznych wierszy."
        }
        return
    }

    $scope = Show-AutoRepairScopeDialog
    if ($scope -eq [System.Windows.MessageBoxResult]::Yes) {
        $fixed = Repair-PlaceholderErrorsAll $bad
    } else {
        $fixed = Repair-PlaceholderErrorsInteractive $bad
    }

    $remaining = Validate-Placeholders
    Highlight-PlaceholderErrors $remaining

    $txtStatus.Text = if ($script:UiLanguage -eq "en") {
        "Placeholder repair: fixed $fixed, remaining problems: $($remaining.Count)."
    } else {
        "Naprawa placeholderów: poprawiono $fixed, pozostało problemów: $($remaining.Count)."
    }

    if ($remaining.Count -eq 0) {
        $msg = if ($script:UiLanguage -eq "en") {
            "All detected placeholder problems have been resolved."
        } else {
            "Wszystkie wykryte problemy z placeholderami zostały rozwiązane."
        }
        [System.Windows.MessageBox]::Show($msg, "Placeholder repair")
    }
})

$btnAutoTranslate.Add_Click({
    if ($script:Entries.Count -eq 0) { return }

    $srcItem = $cmbSourceLang.SelectedItem
    $dstItem = $cmbTargetLang.SelectedItem
    if ($null -eq $srcItem -or $null -eq $dstItem) { return }

    $src = [string]$srcItem.Tag
    $dst = [string]$dstItem.Tag

    if ($src -eq $dst) {
        $msg = if ($script:UiLanguage -eq "en") { "Source and target language must be different." } else { "Język źródłowy i docelowy muszą być różne." }
        [System.Windows.MessageBox]::Show($msg, "Mod Translation Toolkit")
        return
    }

    $question = if ($script:UiLanguage -eq "en") {
        "Automatic translation uses an online Google Translate endpoint and may be rate-limited. Review machine-translated text manually.`n`nTranslate all empty entries?"
    } else {
        "Automatyczne tłumaczenie używa internetowego endpointu Google Translate i może mieć limity. Wynik warto przejrzeć ręcznie.`n`nTłumaczyć wszystkie puste wpisy?"
    }

    $answer = [System.Windows.MessageBox]::Show(
        $question,
        "Mod Translation Toolkit",
        [System.Windows.MessageBoxButton]::YesNo
    )
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $todo = @($script:Entries | Where-Object { [string]::IsNullOrWhiteSpace($_.Translation) })
    $total = $todo.Count
    $done = 0
    $failed = 0

    foreach ($e in $todo) {
        try { $e.Translation = Translate-Google $e.Source $src $dst } catch { $failed++ }
        $done++

        if (($done % 5) -eq 0 -or $done -eq $total) {
            if ($script:UiLanguage -eq "en") {
                $txtStatus.Text = "Translation: $done / $total   Errors: $failed"
            } else {
                $txtStatus.Text = "Tłumaczenie: $done / $total   Błędy: $failed"
            }
            $window.Dispatcher.Invoke([action]{}, "Background")
        }
        Start-Sleep -Milliseconds 120
    }

    Refresh-Grid
    if ($script:UiLanguage -eq "en") {
        $txtStatus.Text = "Automatic translation finished. Errors: $failed."
    } else {
        $txtStatus.Text = "Automatyczne tłumaczenie zakończone. Błędy: $failed."
    }
})


$btnCopyWorkshop.Add_Click({
    try {
        $content = $null

        # Prefer the already generated file if it exists.
        if ($script:LastWorkshopDescriptionPath -and (Test-Path $script:LastWorkshopDescriptionPath)) {
            $content = Get-Content -LiteralPath $script:LastWorkshopDescriptionPath -Raw -Encoding UTF8
        }

        # Otherwise generate the exact same Workshop description directly
        # from the currently loaded mod. Building the translation mod is not required.
        if ([string]::IsNullOrWhiteSpace([string]$content)) {
            if ([string]::IsNullOrWhiteSpace([string]$script:OriginalModName)) {
                $msg = if ($script:UiLanguage -eq "en") {
                    "Load a RimWorld mod first."
                } else {
                    "Najpierw załaduj mod RimWorld."
                }
                [System.Windows.MessageBox]::Show($msg, "Workshop") | Out-Null
                return
            }

            $author = [string]$txtAuthor.Text
            $content = Get-SteamWorkshopDescriptionText $author
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$content)) {
            [void](Set-ClipboardTextSafe $content)
            $txtStatus.Text = if ($script:UiLanguage -eq "en") {
                "Steam Workshop description copied to clipboard."
            } else {
                "Opis Steam Workshop skopiowany do schowka."
            }
        }
    } catch {
        $msg = if ($script:UiLanguage -eq "en") {
            "Could not copy the Workshop description after several attempts.`n`n$($_.Exception.Message)"
        } else {
            "Nie udało się skopiować opisu Workshop po kilku próbach.`n`n$($_.Exception.Message)"
        }
        [System.Windows.MessageBox]::Show($msg, "Schowek") | Out-Null
    }
})

$btnBuild.Add_Click({
    if ($script:Entries.Count -eq 0) { return }

    $bad = Validate-Placeholders
    if ($bad.Count -gt 0) {
        Highlight-PlaceholderErrors $bad

        $msg = if ($script:UiLanguage -eq "en") {
            "There are still $($bad.Count) placeholder problems.`n`nYes = open repair workflow`nNo = build anyway`nCancel = stop"
        } else {
            "Nadal są $($bad.Count) problemy z placeholderami.`n`nTak = otwórz naprawę`nNie = zbuduj mimo to`nAnuluj = przerwij"
        }

        $ans = [System.Windows.MessageBox]::Show(
            $msg,
            "Placeholder warning",
            [System.Windows.MessageBoxButton]::YesNoCancel,
            [System.Windows.MessageBoxImage]::Warning
        )

        if ($ans -eq [System.Windows.MessageBoxResult]::Cancel) { return }

        if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
            $mode = Show-RepairModeDialog
            if ($mode -eq [System.Windows.MessageBoxResult]::Cancel) { return }

            if ($mode -eq [System.Windows.MessageBoxResult]::No) {
                Highlight-PlaceholderErrors $bad
                return
            }

            $scope = Show-AutoRepairScopeDialog
            if ($scope -eq [System.Windows.MessageBoxResult]::Yes) {
                [void](Repair-PlaceholderErrorsAll $bad)
            } else {
                [void](Repair-PlaceholderErrorsInteractive $bad)
            }

            $bad = Validate-Placeholders
            if ($bad.Count -gt 0) {
                Highlight-PlaceholderErrors $bad
                $msg2 = if ($script:UiLanguage -eq "en") {
                    "Some placeholder problems are still unresolved. Build cancelled."
                } else {
                    "Część problemów z placeholderami nadal nie jest rozwiązana. Budowanie anulowano."
                }
                [System.Windows.MessageBox]::Show($msg2, "Placeholder warning")
                return
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:EditingTranslationModPath)) {
        try {
            $out = Build-TranslationMod (Split-Path $script:EditingTranslationModPath -Parent)
            $script:LastWorkshopDescriptionPath = Join-Path $out "SteamWorkshopDescription.txt"
            $btnCopyWorkshop.IsEnabled = $true
            $txtStatus.Text = if ($script:UiLanguage -eq "en") {
                "Existing translation mod updated: $out"
            } else {
                "Zaktualizowano istniejący mod tłumaczeniowy: $out"
            }
            [System.Windows.MessageBox]::Show("Zapisano zmiany.`n`n$out","Mod Translation Toolkit")
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd")
        }
        return
    }

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = if ($script:UiLanguage -eq "en") {
        "Choose the folder where the separate translation mod should be created"
    } else {
        "Wybierz folder, w którym ma powstać oddzielny mod tłumaczeniowy"
    }

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $out = Build-TranslationMod $dlg.SelectedPath
            $script:LastWorkshopDescriptionPath = Join-Path $out "SteamWorkshopDescription.txt"
            $btnCopyWorkshop.IsEnabled = $true
            $txtStatus.Text = if ($script:UiLanguage -eq "en") {
                "Translation mod created: $out"
            } else {
                "Gotowy mod: $out"
            }
            [System.Windows.MessageBox]::Show("Gotowe.`n`n$out","Mod Translation Toolkit")
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd")
        }
    }
})


function Get-RimWorldGamePathAuto {
    foreach ($loc in @(Find-RimWorldLocations)) {
        if (Test-Path $loc.Game) { return $loc.Game }
    }
    return $null
}

function Get-RimWorldGameModules([string]$gamePath) {
    $items = New-Object System.Collections.ArrayList
    $dataPath = Join-Path $gamePath "Data"
    if (-not (Test-Path $dataPath)) { return @() }

    $preferred = @("Core","Royalty","Ideology","Biotech","Anomaly","Odyssey")
    $dirs = @(Get-ChildItem -LiteralPath $dataPath -Directory -ErrorAction SilentlyContinue)

    foreach ($name in $preferred) {
        $match = $dirs | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($match) {
            [void]$items.Add([pscustomobject]@{ Name=$match.Name; Path=$match.FullName; IsCore=($match.Name -ieq "Core") })
        }
    }

    foreach ($d in $dirs) {
        if ($items.Name -contains $d.Name) { continue }
        if ((Test-Path (Join-Path $d.FullName "Languages")) -or (Test-Path (Join-Path $d.FullName "Defs"))) {
            [void]$items.Add([pscustomobject]@{ Name=$d.Name; Path=$d.FullName; IsCore=$false })
        }
    }
    return @($items)
}

function Load-RimWorldGameModules([string]$gamePath) {
    $lstRimWorldGameModules.Items.Clear()
    foreach ($m in @(Get-RimWorldGameModules $gamePath)) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = $m.Name
        $item.Tag = $m.Path
        [void]$lstRimWorldGameModules.Items.Add($item)
        if ($m.IsCore) { $item.IsSelected = $true }
    }
    Set-ControlTextSafe $txtRimWorldGameStatus "Wykryto moduły: $($lstRimWorldGameModules.Items.Count)."
}



function Get-RimWorldLanguageAliases([string]$languageCodeOrName) {
    $wanted = $languageCodeOrName.ToLowerInvariant()
    if ($wanted -eq "polish") {
        return @("polish","polski","pl")
    }
    if ($wanted -eq "english") {
        return @("english","en")
    }
    return @($wanted)
}

function Test-RimWorldLanguageNameMatch([string]$name, [string]$languageCodeOrName) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }

    $n = $name.Trim().ToLowerInvariant()

    foreach ($alias in @(Get-RimWorldLanguageAliases $languageCodeOrName)) {
        $a = $alias.Trim().ToLowerInvariant()

        # Exact match is always safe.
        if ($n -eq $a) { return $true }

        # Human-readable language names may appear as:
        # "Polish (Polski)", "English (English)", etc.
        if ($a.Length -gt 2) {
            if ($n.StartsWith($a + " ") -or
                $n.StartsWith($a + "(") -or
                $n -match ('(^|[\s(_-])' + [regex]::Escape($a) + '([\s)_-]|$)')) {
                return $true
            }
        } else {
            # Short codes such as PL / EN must only match as standalone tokens.
            # Never use Contains() here, otherwise "pl" matches "ChineseSimplified".
            if ($n -match ('(^|[\s(_-])' + [regex]::Escape($a) + '([\s)_-]|$)')) {
                return $true
            }
        }
    }

    return $false
}

function Expand-RimWorldLanguageArchive([string]$archivePath) {
    if ([string]::IsNullOrWhiteSpace($archivePath) -or -not (Test-Path -LiteralPath $archivePath)) {
        return $null
    }

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($null -eq $tar) {
        throw "Nie znaleziono tar.exe. Nie można odczytać oficjalnego archiwum językowego RimWorlda:`n$archivePath"
    }

    $stamp = [System.IO.File]::GetLastWriteTimeUtc($archivePath).Ticks
    $safeName = ([System.IO.Path]::GetFileNameWithoutExtension($archivePath) -replace '[^A-Za-z0-9._-]', '_')
    $moduleName = ([System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($archivePath).FullName).Name -replace '[^A-Za-z0-9._-]', '_')

    $cacheRoot = Join-Path $env:TEMP "ModTranslationToolkit\RimWorldGame"
    $target = Join-Path $cacheRoot "$moduleName-$safeName-$stamp"

    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null

        try {
            & $tar.Source -xf $archivePath -C $target 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe zakończył pracę z kodem $LASTEXITCODE."
            }
        } catch {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
            throw "Nie udało się rozpakować archiwum językowego:`n$archivePath`n`n$($_.Exception.Message)"
        }
    }

    if ((Test-Path -LiteralPath (Join-Path $target "Keyed")) -or
        (Test-Path -LiteralPath (Join-Path $target "DefInjected"))) {
        return $target
    }

    foreach ($d in Get-ChildItem -LiteralPath $target -Directory -ErrorAction SilentlyContinue) {
        if ((Test-Path -LiteralPath (Join-Path $d.FullName "Keyed")) -or
            (Test-Path -LiteralPath (Join-Path $d.FullName "DefInjected"))) {
            return $d.FullName
        }
    }

    return $target
}

function Get-RimWorldLanguageFolder([string]$modulePath, [string]$languageCodeOrName) {
    $languagesRoot = Join-Path $modulePath "Languages"
    if (-not (Test-Path $languagesRoot)) { return $null }

    $candidates = @(Get-ChildItem -LiteralPath $languagesRoot -ErrorAction SilentlyContinue)

    # 1) Loose language directories.
    foreach ($dir in @($candidates | Where-Object { $_.PSIsContainer })) {
        if (Test-RimWorldLanguageNameMatch $dir.Name $languageCodeOrName) {
            return $dir.FullName
        }

        $info = Join-Path $dir.FullName "LanguageInfo.xml"
        if (Test-Path $info) {
            try {
                [xml]$xml = Get-Content -LiteralPath $info -Raw -Encoding UTF8
                foreach ($value in @(
                    $xml.LanguageInfo.friendlyNameNative,
                    $xml.LanguageInfo.friendlyNameEnglish,
                    $xml.LanguageInfo.languageCode,
                    $xml.LanguageInfo.isoCode,
                    $xml.LanguageInfo.folderName
                )) {
                    if (Test-RimWorldLanguageNameMatch ([string]$value) $languageCodeOrName) {
                        return $dir.FullName
                    }
                }
            } catch {}
        }
    }

    # 2) Official RimWorld language archives, e.g. Polish (Polski).tar.
    foreach ($file in @($candidates | Where-Object { -not $_.PSIsContainer -and $_.Extension -ieq ".tar" })) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if (Test-RimWorldLanguageNameMatch $baseName $languageCodeOrName) {
            try {
                $resolved = Expand-RimWorldLanguageArchive $file.FullName
                return $resolved
            } catch {
                throw "Błąd odczytu języka '$baseName' w module '$modulePath': $($_.Exception.Message)"
            }
        }
    }

    return $null
}

function Read-RimWorldKeyedXml([string]$filePath, [string]$moduleName, [string]$languageName) {
    $rows = New-Object System.Collections.ArrayList
    try {
        [xml]$xml = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        if (-not $xml.LanguageData) { return @() }

        foreach ($node in $xml.LanguageData.ChildNodes) {
            if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

            [void]$rows.Add([pscustomobject]@{
                Module = $moduleName
                Type = "Keyed"
                File = $filePath
                Key = [string]$node.Name
                Source = $(if ($languageName -eq "English") { [string]$node.InnerText } else { "" })
                Translation = $(if ($languageName -eq "Polish") { [string]$node.InnerText } else { "" })
            })
        }
    } catch {}
    return @($rows)
}

function Read-RimWorldDefInjectedXml([string]$filePath, [string]$moduleName, [string]$languageName, [string]$langRoot) {
    $rows = New-Object System.Collections.ArrayList
    try {
        [xml]$xml = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        if (-not $xml.LanguageData) { return @() }

        $rel = ""
        try { $rel = $filePath.Substring($langRoot.Length).TrimStart('\','/') } catch {}
        $defType = ""
        if ($rel -match 'DefInjected[\\/]+([^\\/]+)') { $defType = $matches[1] }

        foreach ($node in $xml.LanguageData.ChildNodes) {
            if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

            [void]$rows.Add([pscustomobject]@{
                Module = $moduleName
                Type = $(if ([string]::IsNullOrWhiteSpace($defType)) { "DefInjected" } else { "DefInjected/$defType" })
                File = $filePath
                Key = [string]$node.Name
                Source = $(if ($languageName -eq "English") { [string]$node.InnerText } else { "" })
                Translation = $(if ($languageName -eq "Polish") { [string]$node.InnerText } else { "" })
            })
        }
    } catch {}
    return @($rows)
}

function Get-RimWorldLanguageEntries([string]$langRoot, [string]$moduleName, [string]$languageName) {
    $rows = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($langRoot) -or -not (Test-Path $langRoot)) { return @() }

    $keyed = Join-Path $langRoot "Keyed"
    if (Test-Path $keyed) {
        foreach ($f in Get-ChildItem -LiteralPath $keyed -Filter *.xml -File -Recurse -ErrorAction SilentlyContinue) {
            foreach ($r in @(Read-RimWorldKeyedXml $f.FullName $moduleName $languageName)) {
                [void]$rows.Add($r)
            }
        }
    }

    $defInjected = Join-Path $langRoot "DefInjected"
    if (Test-Path $defInjected) {
        foreach ($f in Get-ChildItem -LiteralPath $defInjected -Filter *.xml -File -Recurse -ErrorAction SilentlyContinue) {
            foreach ($r in @(Read-RimWorldDefInjectedXml $f.FullName $moduleName $languageName $langRoot)) {
                [void]$rows.Add($r)
            }
        }
    }

    return @($rows)
}

function Get-RimWorldEntryIdentity($entry) {
    return "$($entry.Module)|$($entry.Type)|$($entry.Key)"
}

function Scan-RimWorldGameSelection {
    $selected = @($lstRimWorldGameModules.SelectedItems)
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Zaznacz co najmniej jeden moduł / DLC.","RimWorld Game") | Out-Null
        return
    }

    $result = New-Object System.Collections.ArrayList
    $statusLines = New-Object System.Collections.ArrayList
    $totalEnglish = 0
    $totalPolish = 0
    $matched = 0

    foreach ($item in $selected) {
        $moduleName = [string]$item.Content
        $modulePath = [string]$item.Tag

        $englishRoot = Get-RimWorldLanguageFolder $modulePath "english"
        $polishRoot  = Get-RimWorldLanguageFolder $modulePath "polish"

        $englishEntries = @(Get-RimWorldLanguageEntries $englishRoot $moduleName "English")
        $polishEntries  = @(Get-RimWorldLanguageEntries $polishRoot  $moduleName "Polish")

        $totalEnglish += $englishEntries.Count
        $totalPolish += $polishEntries.Count

        $polishMap = @{}
        foreach ($p in $polishEntries) {
            $polishMap[(Get-RimWorldEntryIdentity $p)] = [string]$p.Translation
        }

        $moduleMatched = 0
        foreach ($e in $englishEntries) {
            $id = Get-RimWorldEntryIdentity $e
            if ($polishMap.ContainsKey($id)) {
                $e.Translation = [string]$polishMap[$id]
                $moduleMatched++
                $matched++
            }
            [void]$result.Add($e)
        }

        $polishState = if ($polishRoot) {
            "PL znaleziony: $moduleMatched/$($englishEntries.Count)"
        } else {
            "PL NIE znaleziony"
        }

        $plSource = if ($polishRoot) { $polishRoot } else { "(brak)" }
        [void]$statusLines.Add("$moduleName — EN: $($englishEntries.Count), $polishState`r`nŹródło PL: $plSource")
    }

    $rimWorldGameGrid.ItemsSource = $null
    $rimWorldGameGrid.ItemsSource = @($result)

    Set-ControlTextSafe $lblRimWorldGameCount "Wpisy: $($result.Count) | PL: $matched"
    Set-ControlTextSafe $txtRimWorldGameStatus "Skan zakończony. EN: $totalEnglish, PL znalezione: $totalPolish, dopasowane: $matched."

    $details = ($statusLines -join "`r`n")
    if (-not [string]::IsNullOrWhiteSpace($details)) {
        $txtRimWorldGameStatus.ToolTip = $details
    }
}

$btnDetectRimWorldGame.Add_Click({
    $p = Get-RimWorldGamePathAuto
    if ([string]::IsNullOrWhiteSpace([string]$p)) {
        [System.Windows.MessageBox]::Show("Nie wykryto instalacji RimWorld.","RimWorld Game") | Out-Null
        return
    }
    $txtRimWorldGamePath.Text = $p
    Load-RimWorldGameModules $p
})

$btnChooseRimWorldGame.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Wybierz główny folder RimWorld"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtRimWorldGamePath.Text = $dlg.SelectedPath
        Load-RimWorldGameModules $dlg.SelectedPath
    }
})

$btnOpenRimWorldGameFolder.Add_Click({
    if (Test-ExistingFolderSafe $txtRimWorldGamePath.Text) {
        Start-Process explorer.exe -ArgumentList @($txtRimWorldGamePath.Text)
    }
})

$txtRimWorldGamePath.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Enter) {
        if (Test-ExistingFolderSafe $txtRimWorldGamePath.Text) { Load-RimWorldGameModules $txtRimWorldGamePath.Text }
    }
})
$txtRimWorldGamePath.Add_Drop({
    if ($_.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $paths = @($_.Data.GetData([System.Windows.DataFormats]::FileDrop))
        if ($paths.Count -gt 0 -and (Test-ExistingFolderSafe $paths[0])) {
            $txtRimWorldGamePath.Text = $paths[0]
            Load-RimWorldGameModules $paths[0]
        }
    }
})

$btnRwGameSelectAll.Add_Click({
    $lstRimWorldGameModules.SelectAll()
})
$btnRwGameCoreOnly.Add_Click({
    $lstRimWorldGameModules.UnselectAll()
    foreach ($i in $lstRimWorldGameModules.Items) {
        if ([string]$i.Content -ieq "Core") { $i.IsSelected = $true }
    }
})
$btnRwGameDlcOnly.Add_Click({
    $lstRimWorldGameModules.UnselectAll()
    foreach ($i in $lstRimWorldGameModules.Items) {
        if ([string]$i.Content -ine "Core") { $i.IsSelected = $true }
    }
})
$btnScanRimWorldGame.Add_Click({
    try {
        $btnScanRimWorldGame.IsEnabled = $false
        Set-ControlTextSafe $txtRimWorldGameStatus "Skanowanie RimWorld Game..."
        [System.Windows.Forms.Application]::DoEvents()

        Scan-RimWorldGameSelection
    } catch {
        $msg = if ($script:UiLanguage -eq "en") {
            "RimWorld Game scan failed.`n`n$($_.Exception.Message)"
        } else {
            "Skan RimWorld Game nie powiódł się.`n`n$($_.Exception.Message)"
        }

        Set-ControlTextSafe $txtRimWorldGameStatus $msg
        [System.Windows.MessageBox]::Show(
            $msg,
            "RimWorld Game",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    } finally {
        $btnScanRimWorldGame.IsEnabled = $true
    }
})

$btnDetect.Add_Click({
    try {
        $txtStatus.Text = "Skanuję biblioteki Steam..."
        Scan-InstalledMods
        if ($script:Mods.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Nie znaleziono modów. Możesz nadal wybrać folder ręcznie.","Wykrywanie")
        }
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd wykrywania") }
})

$txtSearch.Add_TextChanged({ Refresh-ModList })

$btnUseSelected.Add_Click({
    $m = $modsGrid.SelectedItem
    if ($null -eq $m) { return }

    try {
        $translationInfo = Get-TranslationModInfo ([string]$m.Path)

        if ($translationInfo.IsTranslationMod) {
            $edit = Open-ExistingTranslationMod ([string]$m.Path)
            $txtModPath.Text = [string]$edit.Original.Path
            $window.Content.Children[1].SelectedItem = $tabGameProfiles
            $tabGameProfilesInner.SelectedItem = $tabRimWorldMod
            $tabRimWorldModInner.SelectedItem = $tabTranslation
            Refresh-LanguageCoverageUi
            $txtStatus.Text = if ($script:UiLanguage -eq "en") {
                "Editing: $($translationInfo.Name). Loaded $($edit.Loaded)/$($edit.Total) existing entries. Original: $($edit.Original.Name). Resolved via: $($edit.ResolveMethod)."
            } else {
                "Edycja: $($translationInfo.Name). Wczytano $($edit.Loaded)/$($edit.Total) istniejących wpisów. Oryginał: $($edit.Original.Name). Wykrycie źródła: $($edit.ResolveMethod)."
            }
        } else {
            $script:EditingTranslationModPath = ""
            $script:EditingTranslationPackageId = ""
            $script:EditingTranslationName = ""

            $txtModPath.Text = $m.Path
            $scan = Analyze-Mod $m.Path
            Apply-CreatorProfileToTranslator
            $window.Content.Children[1].SelectedItem = $tabGameProfiles
            $tabGameProfilesInner.SelectedItem = $tabRimWorldMod
            $tabRimWorldModInner.SelectedItem = $tabTranslation
            $txtStatus.Text = "Wybrano: $($m.Name). Wpisy: $($scan.Total). Automatycznie podstawiono istniejących: $($scan.AutoLoadedExisting). KeyBindingDef: $($scan.KeyBindingDefs), diagnostyka UI: $($scan.KeyBindingDiagnostics). Oryginał można zaznaczać i kopiować Ctrl+C."
            Refresh-LanguageCoverageUi
        }
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd")
    }
})

$modsGrid.Add_MouseDoubleClick({
    if ($null -ne $modsGrid.SelectedItem) {
        $btnUseSelected.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    }
})

$btnOpenFolder.Add_Click({
    $m = $modsGrid.SelectedItem
    if ($null -ne $m -and (Test-Path $m.Path)) {
        Start-Process explorer.exe $m.Path
    }
})

try { Scan-InstalledMods } catch {}
$window.ShowDialog() | Out-Null
