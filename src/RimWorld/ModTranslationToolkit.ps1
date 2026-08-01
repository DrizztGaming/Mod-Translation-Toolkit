# Mod Translation Toolkit v0.1.0
# First supported profile: RimWorld
# Windows PowerShell 5.1+, no Python required.

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$AppVersion = "0.1.4"
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
$script:SelectedContentVersion = ""
$script:EntryKeys = @{}


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

function Scan-EnglishLanguages([string]$modPath) {
    $english = Join-Path $modPath "Languages\English"
    if (-not (Test-Path $english)) { return 0 }

    $count = 0
    Get-ChildItem -LiteralPath $english -Recurse -Filter *.xml -File | ForEach-Object {
        $file = $_
        $rel = $file.FullName.Substring($english.Length).TrimStart('\','/')
        try {
            [xml]$doc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            foreach ($child in $doc.DocumentElement.ChildNodes) {
                if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                Add-Entry "Language" $rel $child.Name (Get-TextContent $child)
                $count++
            }
        } catch {}
    }
    return $count
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

function Refresh-Grid {
    $grid.ItemsSource = $null
    $grid.ItemsSource = $script:Entries
    $lblCount.Content = "Wpisy: $($script:Entries.Count)"
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
    if ($defsCount -gt 0) { $script:DetectedFromDefs = $true }

    $txtModName.Text = $script:OriginalModName
    $txtPackageId.Text = $script:OriginalPackageId
    Refresh-Grid

    return [pscustomobject]@{
        LanguageEntries = $langCount
        DefEntries = $defsCount
        ContentVersion = $script:SelectedContentVersion
        Total = $script:Entries.Count
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
    $langRoot = Join-Path $outMod "Languages\Polish"
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

function Build-TranslationMod([string]$parentFolder) {
    if ([string]::IsNullOrWhiteSpace($script:OriginalPackageId)) {
        throw "Oryginalny mod nie ma packageId w About.xml."
    }

    $safeName = ($script:OriginalModName -replace '[\\/:*?"<>|]', '_')
    $outMod = Join-Path $parentFolder "$safeName - Polish Translation"

    if (Test-Path $outMod) {
        Remove-Item -LiteralPath $outMod -Recurse -Force
    }

    New-Item -ItemType Directory -Path (Join-Path $outMod "About") -Force | Out-Null
    Write-LanguageFiles $outMod

    $author = $txtAuthor.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($author)) { $author = "Community translation" }

    $pkg = ($script:OriginalPackageId + ".polishtranslation").ToLowerInvariant()

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
  <name>$([System.Security.SecurityElement]::Escape($script:OriginalModName)) - Polish Translation</name>
  <author>$([System.Security.SecurityElement]::Escape($author))</author>
  <packageId>$pkg</packageId>
  <modVersion>1.0.0</modVersion>
$supportedXml  <description>Polish translation for $([System.Security.SecurityElement]::Escape($script:OriginalModName)). Requires the original mod.</description>
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

    [System.IO.File]::WriteAllText((Join-Path $outMod "About\About.xml"), $aboutText, (New-Object System.Text.UTF8Encoding($false)))

    # Small build report helps diagnose missing/duplicate translation data later.
    $keyed = @($script:Entries | Where-Object { $_.Kind -eq "Language" }).Count
    $defs = @($script:Entries | Where-Object { $_.Kind -eq "DefInjected" }).Count
    $translated = @($script:Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Translation) }).Count

    $report = @"
Mod Translation Toolkit v$AppVersion
Original mod: $($script:OriginalModName)
PackageId: $($script:OriginalPackageId)
Selected content version: $($script:SelectedContentVersion)
Keyed entries: $keyed
DefInjected entries: $defs
Translated entries: $translated
Total unique entries: $($script:Entries.Count)
"@
    [System.IO.File]::WriteAllText((Join-Path $outMod "TranslationBuildReport.txt"), $report, (New-Object System.Text.UTF8Encoding($false)))

    return $outMod
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

# ---------- Dark / Mrokar purple UI ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mod Translation Toolkit v0.1.4"
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
          <TextBlock Text="v0.1.4" Foreground="#CDA8F2" FontWeight="SemiBold"/>
        </Border>
      </Grid>
    </Border>

    <TabControl Grid.Row="1" Background="{StaticResource Bg}" BorderBrush="{StaticResource Border}" Margin="10">
      <TabItem Name="tabTranslation" Header="Tłumaczenie">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
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
            <Button Name="btnOpenCurrentFolder" Content="Otwórz folder moda" Margin="8,0,0,0"/>
          </StackPanel>

          <Grid Grid.Row="1" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="300"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="320"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="190"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0" Content="Nazwa:"/>
            <TextBox Grid.Column="1" Name="txtModName" IsReadOnly="True" Margin="4"/>
            <Label Grid.Column="2" Content="PackageId:"/>
            <TextBox Grid.Column="3" Name="txtPackageId" IsReadOnly="True" Margin="4"/>
            <Label Grid.Column="4" Content="Autor tłumaczenia:"/>
            <TextBox Grid.Column="5" Name="txtAuthor" Margin="4"/>
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
            <Button Name="btnAutoTranslate" Content="Tłumacz automatycznie"/>
            <Button Name="btnValidate" Content="Sprawdź placeholdery"/>
            <Button Name="btnBuild" Content="Zbuduj oddzielny mod"/>
            <Label Name="lblCount" Content="Wpisy: 0" VerticalContentAlignment="Center"/>
          </WrapPanel>

          <DataGrid Grid.Row="3" Name="grid" AutoGenerateColumns="False" CanUserAddRows="False"
                    CanUserDeleteRows="False" IsReadOnly="False" SelectionMode="Extended"
                    EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Typ" Binding="{Binding Kind}" Width="95" IsReadOnly="True"/>
              <DataGridTextColumn Header="Plik" Binding="{Binding File}" Width="180" IsReadOnly="True"/>
              <DataGridTextColumn Header="Klucz" Binding="{Binding Key}" Width="230" IsReadOnly="True"/>
              <DataGridTextColumn Header="Angielski" Binding="{Binding Source}" Width="*" IsReadOnly="True"/>
              <DataGridTextColumn Header="Polski" Binding="{Binding Translation, UpdateSourceTrigger=PropertyChanged}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <TextBlock Grid.Row="4" Name="txtStatus" Margin="0,10,0,0" TextWrapping="Wrap"
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
            <Button Name="btnUseSelected" Content="Tłumacz wybrany mod"/>
            <Button Name="btnOpenFolder" Content="Otwórz folder moda"/>
          </StackPanel>
        </Grid>
      </TabItem>

      <TabItem Name="tabGameProfiles" Header="Profile gier">
        <Grid Margin="24" Background="{StaticResource Bg}">
          <StackPanel>
            <TextBlock Text="Profile gier" FontSize="24" FontWeight="Bold" Foreground="#D4B5F5" Margin="0,0,0,12"/>
            <Border Background="#211A2B" BorderBrush="#4A385D" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,10">
              <StackPanel>
                <TextBlock Text="RimWorld" FontSize="18" FontWeight="SemiBold" Foreground="#CDA8F2"/>
                <TextBlock Text="Aktywny profil. Languages/English, DefInjected, Defs, Steam Workshop." Foreground="#B9AEC9" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
            <Border Background="#19151F" BorderBrush="#33293E" BorderThickness="1" CornerRadius="6" Padding="16">
              <StackPanel>
                <TextBlock Text="Kolejne profile" FontSize="18" FontWeight="SemiBold" Foreground="#8F819F"/>
                <TextBlock Text="Planowane: gry Paradoxu, Project Zomboid, Minecraft i profile generyczne XML/JSON/CSV." Foreground="#8F819F" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
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
    "btnDetect","txtSearch","lblMods","modsGrid","btnUseSelected","btnOpenFolder","btnOpenCurrentFolder","cmbSourceLang","cmbTargetLang","lblSourceLang","lblTargetLang","tabTranslation","tabInstalledMods","tabGameProfiles"
)
foreach ($n in $names) { Set-Variable -Name $n -Value $window.FindName($n) }


function Apply-UiLanguage {
    if ($script:UiLanguage -ne "en") {
        $tabTranslation.Header = "Tłumaczenie"
        $tabInstalledMods.Header = "Zainstalowane mody"
        $tabGameProfiles.Header = "Profile gier"
        return
    }

    $window.Title = "Mod Translation Toolkit v$AppVersion"
    $tabTranslation.Header = "Translation"
    $tabInstalledMods.Header = "Installed mods"
    $tabGameProfiles.Header = "Game profiles"
    $window.FindName("btnChooseMod").Content = "Choose mod folder"
    $window.FindName("btnAnalyze").Content = "Scan again"
    $window.FindName("btnOpenCurrentFolder").Content = "Open mod folder"
    $window.FindName("btnExport").Content = "Export CSV"
    $window.FindName("btnImport").Content = "Import CSV"
    $window.FindName("lblSourceLang").Content = "From:"
    $window.FindName("lblTargetLang").Content = "To:"
    $window.FindName("btnAutoTranslate").Content = "Auto translate"
    $window.FindName("btnValidate").Content = "Check placeholders"
    $window.FindName("btnBuild").Content = "Build separate translation mod"
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

$btnChooseMod.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Wybierz główny folder moda RimWorld"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtModPath.Text = $dlg.SelectedPath
        try {
            $scan = Analyze-Mod $dlg.SelectedPath
            $txtStatus.Text = "Znaleziono $($scan.Total) unikalnych wpisów: Keyed $($scan.LanguageEntries), DefInjected $($scan.DefEntries). Wersja zawartości: $($scan.ContentVersion)."
        } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, "Błąd") }
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
        try { Analyze-Mod $txtModPath.Text; $txtStatus.Text = "Skan zakończony." }
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
        [System.Windows.MessageBox]::Show("Nie wykryto problemów z placeholderami.", "Kontrola")
    } else {
        $names2 = ($bad | Select-Object -First 15 | ForEach-Object { "$($_.File) :: $($_.Key)" }) -join "`n"
        [System.Windows.MessageBox]::Show("Wykryto $($bad.Count) podejrzanych wpisów:`n`n$names2", "Kontrola")
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

$btnBuild.Add_Click({
    if ($script:Entries.Count -eq 0) { return }

    $bad = Validate-Placeholders
    if ($bad.Count -gt 0) {
        $ans = [System.Windows.MessageBox]::Show(
            "Wykryto $($bad.Count) wpisów z potencjalnie uszkodzonymi placeholderami. Mimo to budować?",
            "Uwaga",
            [System.Windows.MessageBoxButton]::YesNo
        )
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Wybierz folder, w którym ma powstać oddzielny mod PL"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $out = Build-TranslationMod $dlg.SelectedPath
            $txtStatus.Text = "Gotowy mod: $out"
            [System.Windows.MessageBox]::Show("Gotowe.`n`n$out","Mod Translation Toolkit")
        } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd") }
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

    $txtModPath.Text = $m.Path
    try {
        $scan = Analyze-Mod $m.Path
        $window.Content.Children[1].SelectedIndex = 0
        $txtStatus.Text = "Wybrano: $($m.Name). Wpisy: $($scan.Total), w tym DefInjected: $($scan.DefEntries)."
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,"Błąd") }
})

$modsGrid.Add_MouseDoubleClick({
    $m = $modsGrid.SelectedItem
    if ($null -ne $m) {
        $txtModPath.Text = $m.Path
        try {
            Analyze-Mod $m.Path
            $window.Content.Children[1].SelectedIndex = 0
            $txtStatus.Text = "Wybrano: $($m.Name)."
        } catch {}
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
