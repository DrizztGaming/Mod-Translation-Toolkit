# Mod Translation Toolkit v0.1.0
# First supported profile: RimWorld
# Windows PowerShell 5.1+, no Python required.

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$AppVersion = "0.10.24"
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
$script:RimWorldGameInheritedCounts = @{}
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

    $found = New-Object System.Collections.ArrayList
    $patterns = @(
        '\{\d+(?::[^}]*)?\}',
        '%(?:\d+\$)?[sdif]',
        '\\r\\n',
        '\\n',
        '<[^>]+>'
    )

    foreach ($pattern in $patterns) {
        foreach ($m in [regex]::Matches($text, $pattern)) {
            [void]$found.Add([pscustomobject]@{
                Index = $m.Index
                Length = $m.Length
                Value = [string]$m.Value
            })
        }
    }

    $result = New-Object System.Collections.ArrayList
    $lastEnd = -1
    foreach ($m in @($found | Sort-Object Index, Length)) {
        if ($m.Index -lt $lastEnd) { continue }
        [void]$result.Add([string]$m.Value)
        $lastEnd = $m.Index + $m.Length
    }

    return @($result)
}


function Get-ToolkitSettingsDirectory {
    $dir = Join-Path $env:APPDATA "ModTranslationToolkit"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}


function Get-TranslationProviderSettingsPath {
    return (Join-Path (Get-ToolkitSettingsDirectory) "translation-provider.dat")
}

function Protect-ToolkitSecret([string]$plainText) {
    if ([string]::IsNullOrWhiteSpace($plainText)) { return "" }
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
    $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $plainBytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($protectedBytes)
}

function Unprotect-ToolkitSecret([string]$protectedText) {
    if ([string]::IsNullOrWhiteSpace($protectedText)) { return "" }
    try {
        $protectedBytes = [Convert]::FromBase64String($protectedText)
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } catch { return "" }
}

function Get-DefaultTranslationProviderSettings {
    return [pscustomobject]@{
        Provider = "Google"
        GoogleKey = ""
        DeepLKey = ""
        DeepLPlan = "Free"
        LibreEndpoint = "http://localhost:5000"
        LibreKey = ""
    }
}

function Get-TranslationProviderSettings {
    $defaults = Get-DefaultTranslationProviderSettings
    $path = Get-TranslationProviderSettingsPath

    # Migration from v0.5.7 Google-only encrypted key.
    $legacyPath = Join-Path (Get-ToolkitSettingsDirectory) "google-translate-api.dat"
    if (-not (Test-Path -LiteralPath $path) -and (Test-Path -LiteralPath $legacyPath)) {
        try {
            $protectedBytes = [System.IO.File]::ReadAllBytes($legacyPath)
            $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $protectedBytes,
                $null,
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            $defaults.GoogleKey = [System.Text.Encoding]::UTF8.GetString($plainBytes)
            Save-TranslationProviderSettings $defaults
        } catch {}
    }

    if (-not (Test-Path -LiteralPath $path)) { return $defaults }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $s = Get-DefaultTranslationProviderSettings

        if ($raw.Provider) { $s.Provider = [string]$raw.Provider }
        if ($raw.GoogleKey) { $s.GoogleKey = Unprotect-ToolkitSecret ([string]$raw.GoogleKey) }
        if ($raw.DeepLKey) { $s.DeepLKey = Unprotect-ToolkitSecret ([string]$raw.DeepLKey) }
        if ($raw.DeepLPlan) { $s.DeepLPlan = [string]$raw.DeepLPlan }
        if ($raw.LibreEndpoint) { $s.LibreEndpoint = [string]$raw.LibreEndpoint }
        if ($raw.LibreKey) { $s.LibreKey = Unprotect-ToolkitSecret ([string]$raw.LibreKey) }

        return $s
    } catch {
        return $defaults
    }
}

function Save-TranslationProviderSettings($settings) {
    $path = Get-TranslationProviderSettingsPath
    $obj = [ordered]@{
        Provider = [string]$settings.Provider
        GoogleKey = Protect-ToolkitSecret ([string]$settings.GoogleKey)
        DeepLKey = Protect-ToolkitSecret ([string]$settings.DeepLKey)
        DeepLPlan = [string]$settings.DeepLPlan
        LibreEndpoint = [string]$settings.LibreEndpoint
        LibreKey = Protect-ToolkitSecret ([string]$settings.LibreKey)
    }
    [System.IO.File]::WriteAllText(
        $path,
        ($obj | ConvertTo-Json),
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )
}


$script:TranslationProviderLanguageCache = @{}

function Clear-TranslationProviderLanguageCache {
    $script:TranslationProviderLanguageCache = @{}
}

function Get-ActiveTranslationProvider {
    return (Get-TranslationProviderSettings).Provider
}

function Show-TranslationApiHelp([string]$provider) {
    $isEn = ($script:UiLanguage -eq "en")

    switch ($provider) {
        "Google" {
            $msg = if ($isEn) {
@" 
Google Cloud Translation:

1. Open https://console.cloud.google.com/
2. Create/select a project.
3. Enable Cloud Translation API.
4. Configure billing if required by Google.
5. Open APIs & Services > Credentials.
6. Create an API key.
7. Restrict the key to Cloud Translation API.
8. Paste it into Toolkit API Settings.

Google Cloud costs and quotas belong to the key owner.
"@
            } else {
@"
Google Cloud Translation:

1. Otwórz https://console.cloud.google.com/
2. Utwórz lub wybierz projekt.
3. Włącz Cloud Translation API.
4. Skonfiguruj rozliczenia, jeśli Google tego wymaga.
5. Wejdź w APIs & Services > Credentials.
6. Utwórz API key.
7. Ogranicz klucz do Cloud Translation API.
8. Wklej go w Ustawieniach API Toolkita.

Koszty i limity Google Cloud należą do właściciela klucza.
"@
            }
        }
        "DeepL" {
            $msg = if ($isEn) {
@"
DeepL API:

1. Open https://www.deepl.com/pro-api
2. Create a DeepL API account.
3. Choose API Free or API Pro.
4. Copy the authentication key from your DeepL account.
5. Paste it into Toolkit API Settings and select the matching plan.

Note: DeepL API Free may still request payment details for abuse prevention.
"@
            } else {
@"
DeepL API:

1. Otwórz https://www.deepl.com/pro-api
2. Utwórz konto DeepL API.
3. Wybierz API Free albo API Pro.
4. Skopiuj klucz uwierzytelniający z konta DeepL.
5. Wklej go w Ustawieniach API Toolkita i wybierz odpowiedni plan.

Uwaga: DeepL API Free może nadal wymagać danych płatniczych w celu zapobiegania nadużyciom.
"@
            }
        }
        default {
            $msg = if ($isEn) {
@"
LibreTranslate:

Option A — self-hosted, no API key required:
1. Install LibreTranslate locally.
2. Start it, commonly at http://localhost:5000
3. Enter that address as the Endpoint.
4. Leave API key empty unless your server requires one.

Option B — managed libretranslate.com:
1. Get an API key from https://portal.libretranslate.com/
2. Set Endpoint to https://libretranslate.com
3. Paste the API key.

A self-hosted LibreTranslate instance can work without billing or a card.
"@
            } else {
@"
LibreTranslate:

Opcja A — własny serwer, bez wymaganego klucza:
1. Zainstaluj LibreTranslate lokalnie.
2. Uruchom je, zwykle pod http://localhost:5000
3. Wpisz ten adres jako Endpoint.
4. Klucz API zostaw pusty, chyba że Twój serwer go wymaga.

Opcja B — zarządzane libretranslate.com:
1. Zdobądź klucz na https://portal.libretranslate.com/
2. Ustaw Endpoint na https://libretranslate.com
3. Wklej klucz API.

Własny LibreTranslate może działać bez billingu i bez karty.
"@
            }
        }
    }

    [System.Windows.MessageBox]::Show($msg, "Translation API") | Out-Null
}

function Show-TranslationApiSettingsWindow {
    $settings = Get-TranslationProviderSettings

    [xml]$apiXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Translation API Settings"
        Width="660" Height="510"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="#121018"
        Foreground="#ECE8F6">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Name="txtApiTitle" Grid.Row="0" Text="Automatyczne tłumaczenie"
               FontSize="20" FontWeight="Bold" Foreground="#D4B5F5" Margin="0,0,0,10"/>

    <StackPanel Grid.Row="1" Margin="0,0,0,12">
      <TextBlock Name="lblProvider" Text="Dostawca:" Margin="0,0,0,4"/>
      <ComboBox Name="cmbProvider" Height="32">
        <ComboBoxItem Content="Google Cloud Translation" Tag="Google"/>
        <ComboBoxItem Content="DeepL API" Tag="DeepL"/>
        <ComboBoxItem Content="LibreTranslate" Tag="LibreTranslate"/>
      </ComboBox>
    </StackPanel>

    <Border Grid.Row="2" Name="panelGoogle" Background="#1B1723" BorderBrush="#40344F" BorderThickness="1" Padding="12" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Text="Google Cloud Translation" FontWeight="Bold" Foreground="#CDA8F2" Margin="0,0,0,8"/>
        <TextBlock Name="lblGoogleKey" Text="API key:"/>
        <PasswordBox Name="txtGoogleKey" Height="30" Background="#241D30" Foreground="#ECE8F6" BorderBrush="#40344F" Padding="5"/>
      </StackPanel>
    </Border>

    <Border Grid.Row="2" Name="panelDeepL" Background="#1B1723" BorderBrush="#40344F" BorderThickness="1" Padding="12" Margin="0,0,0,10" Visibility="Collapsed">
      <StackPanel>
        <TextBlock Text="DeepL API" FontWeight="Bold" Foreground="#CDA8F2" Margin="0,0,0,8"/>
        <TextBlock Text="Authentication key:"/>
        <PasswordBox Name="txtDeepLKey" Height="30" Background="#241D30" Foreground="#ECE8F6" BorderBrush="#40344F" Padding="5" Margin="0,0,0,8"/>
        <TextBlock Name="lblDeepLPlan" Text="Plan:"/>
        <ComboBox Name="cmbDeepLPlan" Height="30">
          <ComboBoxItem Content="API Free" Tag="Free"/>
          <ComboBoxItem Content="API Pro" Tag="Pro"/>
        </ComboBox>
      </StackPanel>
    </Border>

    <Border Grid.Row="2" Name="panelLibre" Background="#1B1723" BorderBrush="#40344F" BorderThickness="1" Padding="12" Margin="0,0,0,10" Visibility="Collapsed">
      <StackPanel>
        <TextBlock Text="LibreTranslate" FontWeight="Bold" Foreground="#CDA8F2" Margin="0,0,0,8"/>
        <TextBlock Name="lblLibreEndpoint" Text="Endpoint:"/>
        <TextBox Name="txtLibreEndpoint" Height="30" Background="#241D30" Foreground="#ECE8F6" BorderBrush="#40344F" Padding="5" Margin="0,0,0,8"/>
        <TextBlock Name="lblLibreKey" Text="API key (opcjonalny dla self-hosted):"/>
        <PasswordBox Name="txtLibreKey" Height="30" Background="#241D30" Foreground="#ECE8F6" BorderBrush="#40344F" Padding="5"/>
      </StackPanel>
    </Border>

    <TextBlock Name="txtApiInfo" Grid.Row="3" Foreground="#B9AEC9" TextWrapping="Wrap"
               Text="Klucze są przechowywane lokalnie i szyfrowane przez Windows DPAPI dla bieżącego użytkownika."/>

    <TextBlock Name="txtApiWarning" Grid.Row="4" Foreground="#B9AEC9" TextWrapping="Wrap" Margin="0,10,0,0"
               Text="Google i DeepL mogą wymagać konta rozliczeniowego. Obsługa języków jest sprawdzana przed tłumaczeniem; dla LibreTranslate według możliwości konkretnego serwera."/>

    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button Name="btnApiHelp" Content="Instrukcja" Background="#7A3FC2" Foreground="White" BorderBrush="#9D64E8" Padding="12,7" Margin="0,0,8,0"/>
      <Button Name="btnApiTest" Content="Sprawdź języki" Background="#4A385D" Foreground="White" BorderBrush="#6D587D" Padding="12,7" Margin="0,0,8,0"/>
      <Button Name="btnApiSave" Content="Zapisz" Background="#7A3FC2" Foreground="White" BorderBrush="#9D64E8" Padding="12,7" Margin="0,0,8,0"/>
      <Button Name="btnApiCancel" Content="Anuluj" Background="#4A385D" Foreground="White" BorderBrush="#6D587D" Padding="12,7"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $apiXaml
    $dlg = [Windows.Markup.XamlReader]::Load($reader)
    $dlg.Owner = $window

    foreach ($n in @("txtApiTitle","lblProvider","cmbProvider","panelGoogle","txtGoogleKey","panelDeepL","txtDeepLKey","cmbDeepLPlan","panelLibre","txtLibreEndpoint","txtLibreKey","txtApiInfo","txtApiWarning","btnApiHelp","btnApiTest","btnApiSave","btnApiCancel","lblLibreKey")) {
        Set-Variable -Name $n -Value $dlg.FindName($n) -Scope Local
    }

    $txtGoogleKey.Password = [string]$settings.GoogleKey
    $txtDeepLKey.Password = [string]$settings.DeepLKey
    $txtLibreEndpoint.Text = [string]$settings.LibreEndpoint
    $txtLibreKey.Password = [string]$settings.LibreKey

    foreach ($i in $cmbProvider.Items) {
        if ([string]$i.Tag -eq [string]$settings.Provider) { $cmbProvider.SelectedItem = $i; break }
    }
    if ($null -eq $cmbProvider.SelectedItem) { $cmbProvider.SelectedIndex = 0 }

    foreach ($i in $cmbDeepLPlan.Items) {
        if ([string]$i.Tag -eq [string]$settings.DeepLPlan) { $cmbDeepLPlan.SelectedItem = $i; break }
    }
    if ($null -eq $cmbDeepLPlan.SelectedItem) { $cmbDeepLPlan.SelectedIndex = 0 }

    if ($script:UiLanguage -eq "en") {
        $txtApiTitle.Text = "Automatic translation"
        $lblProvider.Text = "Provider:"
        $txtApiInfo.Text = "Keys are stored locally and encrypted with Windows DPAPI for the current user."
        $txtApiWarning.Text = "Google and DeepL may require billing/payment details. Language support is checked before translation; LibreTranslate is validated against the selected server."
        $lblLibreKey.Text = "API key (optional for self-hosted):"
        $btnApiHelp.Content = "Instructions"
        $btnApiTest.Content = "Check languages"
        $btnApiSave.Content = "Save"
        $btnApiCancel.Content = "Cancel"
    }

    $refreshPanels = {
        $provider = [string]$cmbProvider.SelectedItem.Tag
        $panelGoogle.Visibility = if ($provider -eq "Google") { "Visible" } else { "Collapsed" }
        $panelDeepL.Visibility = if ($provider -eq "DeepL") { "Visible" } else { "Collapsed" }
        $panelLibre.Visibility = if ($provider -eq "LibreTranslate") { "Visible" } else { "Collapsed" }
    }
    $cmbProvider.Add_SelectionChanged($refreshPanels)
    & $refreshPanels

    $btnApiHelp.Add_Click({
        Show-TranslationApiHelp ([string]$cmbProvider.SelectedItem.Tag)
    })

    $btnApiTest.Add_Click({
        $temp = Get-DefaultTranslationProviderSettings
        $temp.Provider = [string]$cmbProvider.SelectedItem.Tag
        $temp.GoogleKey = [string]$txtGoogleKey.Password
        $temp.DeepLKey = [string]$txtDeepLKey.Password
        $temp.DeepLPlan = [string]$cmbDeepLPlan.SelectedItem.Tag
        $temp.LibreEndpoint = ([string]$txtLibreEndpoint.Text).Trim().TrimEnd('/')
        $temp.LibreKey = [string]$txtLibreKey.Password

        $oldCaption = [string]$btnApiTest.Content
        $btnApiTest.IsEnabled = $false
        $btnApiTest.Content = if ($script:UiLanguage -eq "en") { "Checking..." } else { "Sprawdzanie..." }
        $txtApiWarning.Text = if ($script:UiLanguage -eq "en") {
            "Checking provider language capabilities..."
        } else {
            "Sprawdzanie języków obsługiwanych przez dostawcę..."
        }
        [System.Windows.Forms.Application]::DoEvents()

        Clear-TranslationProviderLanguageCache

        try {
            $sourceCodes = @()
            $targetCodes = @()

            switch ($temp.Provider) {
                "Google" {
                    if ([string]::IsNullOrWhiteSpace($temp.GoogleKey)) {
                        throw $(if ($script:UiLanguage -eq "en") { "Enter a Google Cloud API key first." } else { "Najpierw wpisz klucz Google Cloud API." })
                    }

                    # One lightweight official API request, not one request per language pair.
                    $headers = @{ "X-goog-api-key" = [string]$temp.GoogleKey }
                    $resp = Invoke-RestMethod `
                        -Uri "https://translation.googleapis.com/language/translate/v2/languages?target=en" `
                        -Method Get -Headers $headers -TimeoutSec 8
                    $sourceCodes = @($resp.data.languages | ForEach-Object { [string]$_.language })
                    $targetCodes = @($sourceCodes)
                }

                "DeepL" {
                    if ([string]::IsNullOrWhiteSpace($temp.DeepLKey)) {
                        throw $(if ($script:UiLanguage -eq "en") { "Enter a DeepL API key first." } else { "Najpierw wpisz klucz DeepL API." })
                    }

                    # Exactly two requests: current source list and current target list.
                    $sourceCodes = @(Get-DeepLSupportedLanguages "Source" $temp)
                    $targetCodes = @(Get-DeepLSupportedLanguages "Target" $temp)
                }

                "LibreTranslate" {
                    if ([string]::IsNullOrWhiteSpace($temp.LibreEndpoint)) {
                        throw $(if ($script:UiLanguage -eq "en") { "Enter a LibreTranslate endpoint first." } else { "Najpierw wpisz endpoint LibreTranslate." })
                    }

                    # Exactly one /languages request. Pair support is read from its targets arrays.
                    $languageData = @(Get-LibreTranslateLanguageData $temp)
                    $sourceCodes = @($languageData | ForEach-Object { [string]$_.code } | Where-Object { $_ })
                    $targetCodes = @(
                        $languageData | ForEach-Object { @($_.targets) } | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique
                    )
                    if ($targetCodes.Count -eq 0) { $targetCodes = @($sourceCodes) }
                }

                default { throw "Unknown translation provider: $($temp.Provider)" }
            }

            $registeredSource = 0
            $registeredTarget = 0
            foreach ($lang in $script:Languages) {
                $src = Get-ProviderLanguageCode $temp.Provider $lang.Code "Source"
                $dst = Get-ProviderLanguageCode $temp.Provider $lang.Code "Target"

                if (-not [string]::IsNullOrWhiteSpace($src)) {
                    $baseSrc = $src.ToUpperInvariant().Split('-')[0]
                    if (@($sourceCodes | Where-Object {
                        $c = ([string]$_).ToUpperInvariant()
                        $c -eq $src.ToUpperInvariant() -or $c.Split('-')[0] -eq $baseSrc
                    }).Count -gt 0) { $registeredSource++ }
                }

                if (-not [string]::IsNullOrWhiteSpace($dst)) {
                    $baseDst = $dst.ToUpperInvariant().Split('-')[0]
                    if (@($targetCodes | Where-Object {
                        $c = ([string]$_).ToUpperInvariant()
                        $c -eq $dst.ToUpperInvariant() -or $c.Split('-')[0] -eq $baseDst
                    }).Count -gt 0) { $registeredTarget++ }
                }
            }

            $msg = if ($script:UiLanguage -eq "en") {
                "Provider: $($temp.Provider)`nAvailable source languages: $($sourceCodes.Count)`nAvailable target languages: $($targetCodes.Count)`nToolkit registry matches: $registeredSource source / $registeredTarget target."
            } else {
                "Dostawca: $($temp.Provider)`nDostępne języki źródłowe: $($sourceCodes.Count)`nDostępne języki docelowe: $($targetCodes.Count)`nDopasowania rejestru Toolkita: $registeredSource źródłowych / $registeredTarget docelowych."
            }

            [System.Windows.MessageBox]::Show($msg, "Translation API") | Out-Null
        } catch {
            $msg = if ($script:UiLanguage -eq "en") {
                "Language check failed.`n`n$($_.Exception.Message)"
            } else {
                "Sprawdzanie języków nie powiodło się.`n`n$($_.Exception.Message)"
            }
            [System.Windows.MessageBox]::Show($msg, "Translation API") | Out-Null
        } finally {
            $btnApiTest.Content = $oldCaption
            $btnApiTest.IsEnabled = $true
            $txtApiWarning.Text = if ($script:UiLanguage -eq "en") {
                "Google and DeepL may require billing/payment details. Language support is checked before translation; LibreTranslate is validated against the selected server."
            } else {
                "Google i DeepL mogą wymagać konta rozliczeniowego. Obsługa języków jest sprawdzana przed tłumaczeniem; dla LibreTranslate według możliwości konkretnego serwera."
            }
        }
    })

    $btnApiSave.Add_Click({
        $provider = [string]$cmbProvider.SelectedItem.Tag
        $new = Get-DefaultTranslationProviderSettings
        $new.Provider = $provider
        $new.GoogleKey = [string]$txtGoogleKey.Password
        $new.DeepLKey = [string]$txtDeepLKey.Password
        $new.DeepLPlan = [string]$cmbDeepLPlan.SelectedItem.Tag
        $new.LibreEndpoint = ([string]$txtLibreEndpoint.Text).Trim().TrimEnd('/')
        $new.LibreKey = [string]$txtLibreKey.Password

        if ($provider -eq "Google" -and [string]::IsNullOrWhiteSpace($new.GoogleKey)) {
            [System.Windows.MessageBox]::Show("Google Cloud wymaga klucza API.","Translation API") | Out-Null
            return
        }
        if ($provider -eq "DeepL" -and [string]::IsNullOrWhiteSpace($new.DeepLKey)) {
            [System.Windows.MessageBox]::Show("DeepL wymaga klucza API.","Translation API") | Out-Null
            return
        }
        if ($provider -eq "LibreTranslate" -and [string]::IsNullOrWhiteSpace($new.LibreEndpoint)) {
            [System.Windows.MessageBox]::Show("Podaj endpoint LibreTranslate.","Translation API") | Out-Null
            return
        }

        Save-TranslationProviderSettings $new
        Clear-TranslationProviderLanguageCache
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    $btnApiCancel.Add_Click({
        $dlg.DialogResult = $false
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
}

function Get-ConfiguredTranslationProviderName {
    try {
        $settings = Get-TranslationProviderSettings
        if ($null -eq $settings) { return "" }

        $provider = [string]$settings.Provider
        switch -Regex ($provider) {
            '^Google' { return "Google" }
            '^DeepL' { return "DeepL" }
            '^LibreTranslate$' { return "LibreTranslate" }
            '^Libre' { return "LibreTranslate" }
            default { return $provider }
        }
    } catch {
        return ""
    }
}

function Test-TranslationProviderConfigured {
    try {
        # IMPORTANT: use the exact same persisted settings object consumed by
        # Translate-Configured / Test-TranslationLanguagePair.
        $settings = Get-TranslationProviderSettings
        if ($null -eq $settings) { return $false }

        $provider = [string]$settings.Provider
        switch ($provider) {
            "Google" {
                return -not [string]::IsNullOrWhiteSpace([string]$settings.GoogleKey)
            }
            "DeepL" {
                return -not [string]::IsNullOrWhiteSpace([string]$settings.DeepLKey)
            }
            "LibreTranslate" {
                # Self-hosted LibreTranslate does not require an API key.
                return -not [string]::IsNullOrWhiteSpace([string]$settings.LibreEndpoint)
            }
            default {
                return $false
            }
        }
    } catch {
        return $false
    }
}

function Show-MissingTranslationProviderMessage {
    $provider = Get-ConfiguredTranslationProviderName
    $providerText = if ([string]::IsNullOrWhiteSpace($provider)) { "none" } else { $provider }

    $detail = ""
    try {
        $settings = Get-TranslationProviderSettings
        if ($provider -eq "LibreTranslate") {
            $endpoint = [string]$settings.LibreEndpoint
            if ([string]::IsNullOrWhiteSpace($endpoint)) {
                $detail = if ($script:UiLanguage -eq "en") { "`nLibreTranslate endpoint is empty." } else { "`nEndpoint LibreTranslate jest pusty." }
            } else {
                $detail = if ($script:UiLanguage -eq "en") { "`nLibreTranslate endpoint: $endpoint" } else { "`nEndpoint LibreTranslate: $endpoint" }
            }
        }
    } catch {}

    $msg = if ($script:UiLanguage -eq "en") {
        "The selected translation provider is not ready: $providerText.$detail`n`nOpen API / Translation and verify its configuration."
    } else {
        "Wybrany dostawca tłumaczeń nie jest gotowy: $providerText.$detail`n`nOtwórz API / Tłumaczenie i sprawdź konfigurację."
    }

    [System.Windows.MessageBox]::Show($msg, "Mod Translation Toolkit") | Out-Null
}

function Require-TranslationProvider {
    if (Test-TranslationProviderConfigured) { return $true }

    $msg = if ($script:UiLanguage -eq "en") {
        "Automatic translation is not configured.`n`nOpen Translation API Settings now?"
    } else {
        "Automatyczne tłumaczenie nie jest skonfigurowane.`n`nOtworzyć teraz Ustawienia API?"
    }

    $ans = [System.Windows.MessageBox]::Show($msg,"Translation API",[System.Windows.MessageBoxButton]::YesNo)
    if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
        Show-TranslationApiSettingsWindow
    }
    return (Test-TranslationProviderConfigured)
}

function Protect-TranslationPlaceholders([string]$text, [ref]$mapRef) {
    $map = [ordered]@{}
    $protected = [string]$text
    $tokens = @(Get-Placeholders $text)

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $value = [string]$tokens[$i]

        # Alphanumeric tokens survive Google, DeepL and LibreTranslate more
        # reliably than the legacy __MTTPH0__ form.
        $key = "ZXQMTTPH{0:D4}QXZ" -f $i
        $map[$key] = $value

        $escaped = [regex]::Escape($value)
        $protected = [regex]::Replace(
            $protected,
            $escaped,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($m)
                return $key
            },
            1
        )
    }

    $mapRef.Value = $map
    return $protected
}

function Restore-TranslationPlaceholders([string]$text, $map) {
    $result = [string]$text
    if ($null -eq $map) { return $result }

    foreach ($k in @($map.Keys)) {
        $value = [string]$map[$k]
        $number = ([regex]::Match([string]$k, '\d{4}')).Value

        # Translation providers sometimes add spaces or change letter case.
        $pattern = "Z\s*X\s*Q\s*M\s*T\s*T\s*P\s*H\s*0*$number\s*Q\s*X\s*Z"
        if (-not [regex]::IsMatch($result, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            return $null
        }

        $result = [regex]::Replace(
            $result,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($m)
                return $value
            },
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    return $result
}

function Test-TranslationPlaceholderIntegrity([string]$source, [string]$translation) {
    if ($null -eq $translation) { return $false }

    if ($translation -match '__MTTPH\d+__' -or
        $translation -match 'ZXQ\s*MTTPH\s*\d+\s*QXZ') {
        return $false
    }

    $src = @(Get-Placeholders $source)
    $dst = @(Get-Placeholders $translation)

    if ($src.Count -ne $dst.Count) { return $false }

    for ($i = 0; $i -lt $src.Count; $i++) {
        if ([string]$src[$i] -cne [string]$dst[$i]) {
            return $false
        }
    }

    return $true
}

function Finalize-TranslatedText([string]$source, [string]$translated, $map) {
    $restored = Restore-TranslationPlaceholders $translated $map

    if ($null -eq $restored) {
        throw "Translation provider changed or removed a protected placeholder."
    }

    if (-not (Test-TranslationPlaceholderIntegrity $source $restored)) {
        throw "Placeholder validation failed after translation."
    }

    return $restored
}


function Translate-GoogleCloud([string]$text,[string]$sourceLang,[string]$targetLang,$settings) {
    $map = $null
    $protected = Protect-TranslationPlaceholders $text ([ref]$map)

    $body = @{
        q = $protected
        source = $sourceLang
        target = $targetLang
        format = "text"
    } | ConvertTo-Json -Compress

    $headers = @{ "X-goog-api-key" = [string]$settings.GoogleKey }
    $resp = Invoke-RestMethod -Uri "https://translation.googleapis.com/language/translate/v2" `
        -Method Post -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body -TimeoutSec 30

    $translated = [System.Net.WebUtility]::HtmlDecode([string]$resp.data.translations[0].translatedText)
    return (Finalize-TranslatedText $text $translated $map)
}

function Translate-DeepL([string]$text,[string]$sourceLang,[string]$targetLang,$settings) {
    $map = $null
    $protected = Protect-TranslationPlaceholders $text ([ref]$map)

    $base = Get-DeepLApiBase $settings
    $headers = @{ "Authorization" = "DeepL-Auth-Key $($settings.DeepLKey)" }

    $body = @{
        text = $protected
        source_lang = $sourceLang.ToUpperInvariant()
        target_lang = $targetLang.ToUpperInvariant()
    }

    $resp = Invoke-RestMethod -Uri "$base/v2/translate" -Method Post -Headers $headers `
        -ContentType "application/x-www-form-urlencoded" -Body $body -TimeoutSec 30

    $translated = [string]$resp.translations[0].text
    return (Finalize-TranslatedText $text $translated $map)
}


function Get-MojibakeSuspicionScore([string]$value) {
    if ([string]::IsNullOrEmpty($value)) { return 0 }

    $score = 0

    # Keep this function source ASCII-only. These Unicode code points are the
    # common leading characters produced when UTF-8 bytes are decoded as CP1252.
    $suspectChars = @(
        [char]0x00C3, # Ã
        [char]0x00C2, # Â
        [char]0x00C4, # Ä
        [char]0x00C5, # Å
        [char]0x00C6, # Æ
        [char]0x00D0, # Ð
        [char]0x00D1  # Ñ
    )

    foreach ($ch in $suspectChars) {
        foreach ($c in $value.ToCharArray()) {
            if ($c -eq $ch) { $score++ }
        }
    }

    # Extra markers for common smart-quote / emoji mojibake prefixes.
    if ($value.Contains(([char]0x00E2).ToString())) { $score++ } # â
    if ($value.Contains(([char]0x00EF).ToString())) { $score++ } # ï
    if ($value.Contains(([char]0x00F0).ToString())) { $score++ } # ð

    return $score
}

function Repair-TranslationMojibake([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $value }

    $before = Get-MojibakeSuspicionScore $value
    if ($before -le 0) { return $value }

    try {
        $cp1252 = [System.Text.Encoding]::GetEncoding(
            1252,
            [System.Text.EncoderFallback]::ExceptionFallback,
            [System.Text.DecoderFallback]::ExceptionFallback
        )

        # Parser-safe on Windows PowerShell 5.1.
        $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)

        $bytes = $cp1252.GetBytes($value)
        $candidate = $utf8.GetString($bytes)

        if ($candidate.Contains([char]0xFFFD)) { return $value }

        $after = Get-MojibakeSuspicionScore $candidate
        if ($after -lt $before) {
            return $candidate
        }
    } catch {
        # If a safe round-trip is impossible, preserve the provider response.
    }

    return $value
}

function Translate-LibreTranslate([string]$text,[string]$sourceLang,[string]$targetLang,$settings) {
    $map = $null
    $protected = Protect-TranslationPlaceholders $text ([ref]$map)

    $payload = [ordered]@{
        q = $protected
        source = $sourceLang
        target = $targetLang
        format = "text"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$settings.LibreKey)) {
        $payload.api_key = [string]$settings.LibreKey
    }

    $endpoint = ([string]$settings.LibreEndpoint).TrimEnd('/')
    $jsonBody = $payload | ConvertTo-Json -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    # Windows PowerShell 5.1 can decode JSON HTTP responses using the wrong
    # legacy code page. Read the response stream as raw bytes and decode UTF-8
    # explicitly before ConvertFrom-Json.
    $request = [System.Net.HttpWebRequest]::Create("$endpoint/translate")
    $request.Method = "POST"
    $request.ContentType = "application/json; charset=utf-8"
    $request.Accept = "application/json"
    $request.Timeout = 45000
    $request.ReadWriteTimeout = 45000
    $request.ContentLength = $bodyBytes.Length

    $requestStream = $null
    $response = $null
    $responseStream = $null
    $memory = $null

    try {
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Flush()
        $requestStream.Close()
        $requestStream = $null

        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()

        $memory = New-Object System.IO.MemoryStream
        $buffer = New-Object byte[] 8192
        while (($read = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $memory.Write($buffer, 0, $read)
        }

        $rawBytes = $memory.ToArray()
        $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)
        $jsonText = $utf8.GetString($rawBytes)
        $resp = $jsonText | ConvertFrom-Json

        $translated = [string]$resp.translatedText
        $translated = Repair-TranslationMojibake $translated
        return (Finalize-TranslatedText $text $translated $map)
    } catch [System.Net.WebException] {
        $err = $_.Exception
        if ($null -ne $err.Response) {
            try {
                $errStream = $err.Response.GetResponseStream()
                $errMemory = New-Object System.IO.MemoryStream
                $errBuffer = New-Object byte[] 4096
                while (($errRead = $errStream.Read($errBuffer, 0, $errBuffer.Length)) -gt 0) {
                    $errMemory.Write($errBuffer, 0, $errRead)
                }
                $errBytes = $errMemory.ToArray()
                $errUtf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $false)
                $errText = $errUtf8.GetString($errBytes)
                throw "LibreTranslate HTTP error: $errText"
            } catch {
                if ($_.Exception.Message -like "LibreTranslate HTTP error:*") { throw }
            }
        }
        throw
    } finally {
        if ($null -ne $requestStream) { $requestStream.Dispose() }
        if ($null -ne $responseStream) { $responseStream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $memory) { $memory.Dispose() }
    }
}


function Get-DeepLApiBase($settings) {
    if ($settings.DeepLPlan -eq "Pro") { return "https://api.deepl.com" }
    return "https://api-free.deepl.com"
}

function Get-DeepLSupportedLanguages([string]$role, $settings) {
    $kind = if ($role -eq "Target") { "target" } else { "source" }
    $cacheKey = "DeepL|$($settings.DeepLPlan)|$kind"
    if ($script:TranslationProviderLanguageCache.ContainsKey($cacheKey)) {
        return @($script:TranslationProviderLanguageCache[$cacheKey])
    }

    $base = Get-DeepLApiBase $settings
    $headers = @{ "Authorization" = "DeepL-Auth-Key $($settings.DeepLKey)" }
    $resp = Invoke-RestMethod -Uri "$base/v2/languages?type=$kind" -Method Get -Headers $headers -TimeoutSec 8

    $codes = @($resp | ForEach-Object { ([string]$_.language).ToUpperInvariant() } | Where-Object { $_ })
    $script:TranslationProviderLanguageCache[$cacheKey] = $codes
    return @($codes)
}

function Resolve-DeepLLanguageCode([string]$languageCode, [string]$role, $settings) {
    $wanted = Get-ProviderLanguageCode "DeepL" $languageCode $role
    if ([string]::IsNullOrWhiteSpace($wanted)) { return $null }

    $supported = @(Get-DeepLSupportedLanguages $role $settings)
    $wantedUpper = $wanted.ToUpperInvariant()

    if ($supported -contains $wantedUpper) { return $wantedUpper }

    # API language naming can evolve. Prefer a returned regional/script variant
    # that belongs to the same language family.
    $baseCode = $wantedUpper.Split('-')[0]
    $family = @($supported | Where-Object { $_ -eq $baseCode -or $_.StartsWith("$baseCode-") })

    if ($role -eq "Source" -and $family -contains $baseCode) {
        return $baseCode
    }

    if ($family.Count -eq 1) { return [string]$family[0] }

    # Stable preferences for ambiguous target families.
    if ($role -eq "Target") {
        switch ($languageCode) {
            "en" {
                foreach ($candidate in @("EN-US","EN-GB")) {
                    if ($supported -contains $candidate) { return $candidate }
                }
            }
            "pt" {
                foreach ($candidate in @("PT-PT","PT-BR")) {
                    if ($supported -contains $candidate) { return $candidate }
                }
            }
            "pt-br" {
                foreach ($candidate in @("PT-BR","PT-PT")) {
                    if ($supported -contains $candidate) { return $candidate }
                }
            }
            "zh-cn" {
                foreach ($candidate in @("ZH-HANS","ZH")) {
                    if ($supported -contains $candidate) { return $candidate }
                }
            }
            "zh-tw" {
                foreach ($candidate in @("ZH-HANT","ZH")) {
                    if ($supported -contains $candidate) { return $candidate }
                }
            }
        }
    }

    return $null
}

function Get-LibreTranslateLanguageData($settings) {
    $endpoint = ([string]$settings.LibreEndpoint).TrimEnd('/')
    $cacheKey = "LibreTranslate|$endpoint"
    if ($script:TranslationProviderLanguageCache.ContainsKey($cacheKey)) {
        return @($script:TranslationProviderLanguageCache[$cacheKey])
    }

    $uri = "$endpoint/languages"
    if (-not [string]::IsNullOrWhiteSpace([string]$settings.LibreKey)) {
        $escaped = [uri]::EscapeDataString([string]$settings.LibreKey)
        $separator = if ($uri.Contains("?")) { "&" } else { "?" }
        $uri = "$uri$separator" + "api_key=$escaped"
    }

    $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 8
    $items = @($resp)
    $script:TranslationProviderLanguageCache[$cacheKey] = $items
    return @($items)
}

function Test-TranslationLanguagePair([string]$sourceLanguageCode, [string]$targetLanguageCode, $settings=$null) {
    if ($null -eq $settings) { $settings = Get-TranslationProviderSettings }

    if ($sourceLanguageCode -ieq $targetLanguageCode) {
        return [pscustomobject]@{
            Supported = $false
            SourceProviderCode = ""
            TargetProviderCode = ""
            MessagePL = "Język źródłowy i docelowy muszą być różne."
            MessageEN = "Source and target language must be different."
        }
    }

    $provider = [string]$settings.Provider
    try {
        switch ($provider) {
            "Google" {
                $src = Get-ProviderLanguageCode "Google" $sourceLanguageCode "Source"
                $dst = Get-ProviderLanguageCode "Google" $targetLanguageCode "Target"
                $ok = -not [string]::IsNullOrWhiteSpace($src) -and -not [string]::IsNullOrWhiteSpace($dst)

                return [pscustomobject]@{
                    Supported = $ok
                    SourceProviderCode = $src
                    TargetProviderCode = $dst
                    MessagePL = $(if ($ok) { "" } else { "Google Cloud nie ma mapowania dla jednego z wybranych języków." })
                    MessageEN = $(if ($ok) { "" } else { "Google Cloud has no mapping for one of the selected languages." })
                }
            }

            "DeepL" {
                $src = Resolve-DeepLLanguageCode $sourceLanguageCode "Source" $settings
                $dst = Resolve-DeepLLanguageCode $targetLanguageCode "Target" $settings
                $ok = -not [string]::IsNullOrWhiteSpace($src) -and -not [string]::IsNullOrWhiteSpace($dst)

                return [pscustomobject]@{
                    Supported = $ok
                    SourceProviderCode = $src
                    TargetProviderCode = $dst
                    MessagePL = $(if ($ok) { "" } else { "DeepL nie obsługuje obecnie jednej ze stron wybranej pary językowej." })
                    MessageEN = $(if ($ok) { "" } else { "DeepL currently does not support one side of the selected language pair." })
                }
            }

            "LibreTranslate" {
                $src = Get-ProviderLanguageCode "LibreTranslate" $sourceLanguageCode "Source"
                $dst = Get-ProviderLanguageCode "LibreTranslate" $targetLanguageCode "Target"

                if ([string]::IsNullOrWhiteSpace($src) -or [string]::IsNullOrWhiteSpace($dst)) {
                    return [pscustomobject]@{
                        Supported = $false
                        SourceProviderCode = $src
                        TargetProviderCode = $dst
                        MessagePL = "Brak mapowania LibreTranslate dla jednego z wybranych języków."
                        MessageEN = "LibreTranslate mapping is missing for one of the selected languages."
                    }
                }

                $languages = @(Get-LibreTranslateLanguageData $settings)
                $sourceInfo = $languages | Where-Object { ([string]$_.code) -ieq $src } | Select-Object -First 1
                $targetExists = @($languages | Where-Object { ([string]$_.code) -ieq $dst }).Count -gt 0

                $pairSupported = $false
                if ($null -ne $sourceInfo) {
                    $targets = @($sourceInfo.targets | ForEach-Object { [string]$_ })
                    if ($targets.Count -gt 0) {
                        $pairSupported = @($targets | Where-Object { $_ -ieq $dst }).Count -gt 0
                    } else {
                        # Older/custom LibreTranslate implementations may expose only codes.
                        $pairSupported = $targetExists
                    }
                }

                return [pscustomobject]@{
                    Supported = $pairSupported
                    SourceProviderCode = $src
                    TargetProviderCode = $dst
                    MessagePL = $(if ($pairSupported) { "" } else { "Ten serwer LibreTranslate nie udostępnia wybranej pary językowej: $src → $dst." })
                    MessageEN = $(if ($pairSupported) { "" } else { "This LibreTranslate server does not provide the selected language pair: $src -> $dst." })
                }
            }

            default {
                return [pscustomobject]@{
                    Supported = $false
                    SourceProviderCode = ""
                    TargetProviderCode = ""
                    MessagePL = "Nieznany dostawca automatycznego tłumaczenia."
                    MessageEN = "Unknown automatic translation provider."
                }
            }
        }
    } catch {
        $detail = $_.Exception.Message
        return [pscustomobject]@{
            Supported = $false
            SourceProviderCode = ""
            TargetProviderCode = ""
            MessagePL = "Nie udało się sprawdzić obsługi języków przez $provider.`n`n$detail"
            MessageEN = "Could not verify language support for $provider.`n`n$detail"
        }
    }
}

function Require-TranslationLanguagePair([string]$sourceLanguageCode, [string]$targetLanguageCode) {
    $settings = Get-TranslationProviderSettings
    $result = Test-TranslationLanguagePair $sourceLanguageCode $targetLanguageCode $settings

    if (-not $result.Supported) {
        $msg = if ($script:UiLanguage -eq "en") { $result.MessageEN } else { $result.MessagePL }
        [System.Windows.MessageBox]::Show($msg, "Translation API") | Out-Null
        return $null
    }

    return $result
}

function Translate-Configured([string]$text,[string]$sourceLang="en",[string]$targetLang="pl") {
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    $settings = Get-TranslationProviderSettings
    $pair = Test-TranslationLanguagePair $sourceLang $targetLang $settings

    if (-not $pair.Supported) {
        $message = if ($script:UiLanguage -eq "en") { $pair.MessageEN } else { $pair.MessagePL }
        throw $message
    }

    $src = [string]$pair.SourceProviderCode
    $dst = [string]$pair.TargetProviderCode

    switch ($settings.Provider) {
        "Google" { return Translate-GoogleCloud $text $src $dst $settings }
        "DeepL" { return Translate-DeepL $text $src $dst $settings }
        "LibreTranslate" { return Translate-LibreTranslate $text $src $dst $settings }
        default { throw "Nieznany dostawca tłumaczenia: $($settings.Provider)" }
    }
}



# ---------- RimWorld contextual glossary ----------
function Get-RimWorldGlossaryPath {
    return (Join-Path (Get-ToolkitSettingsDirectory) "rimworld-glossary.csv")
}

function New-RimWorldGlossaryRule(
    [string]$source,
    [string]$target,
    [string]$scope="All",
    [string]$module="",
    [string]$defType="",
    [string]$field="",
    [string]$packageId="",
    [bool]$enabled=$true
) {
    return [pscustomobject]@{
        Enabled = $enabled
        Source = $source
        Target = $target
        Scope = $scope
        Module = $module
        DefType = $defType
        Field = $field
        PackageId = $packageId
        Confidence = 0
        Learned = $false
    }
}

function Get-DefaultRimWorldGlossary {
    # Conservative starter rule: only ThingDef.label, where "counter" is a
    # furniture/object label rather than a generic verb/statistic term.
    return @(
        (New-RimWorldGlossaryRule "counter" "lada" "All" "" "ThingDef" "label" "" $true)
    )
}

function Save-RimWorldGlossary($rules) {
    $path = Get-RimWorldGlossaryPath
    $rows = @($rules | Select-Object Enabled,Source,Target,Scope,Module,DefType,Field,PackageId,Confidence,Learned)
    if ($rows.Count -eq 0) {
        [System.IO.File]::WriteAllText(
            $path,
            "Enabled;Source;Target;Scope;Module;DefType;Field;PackageId;Confidence;Learned`r`n",
            (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
        )
        return $path
    }

    $tmp = "$path.tmp"
    $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Move-Item -LiteralPath $tmp -Destination $path -Force
    return $path
}

function Get-RimWorldGlossary {
    $path = Get-RimWorldGlossaryPath
    if (-not (Test-Path -LiteralPath $path)) {
        $defaults = @(Get-DefaultRimWorldGlossary)
        [void](Save-RimWorldGlossary $defaults)
        return $defaults
    }

    try {
        $rows = @(Import-Csv -LiteralPath $path -Encoding UTF8 -Delimiter ';')
        $result = New-Object System.Collections.ArrayList

        foreach ($r in $rows) {
            if ([string]::IsNullOrWhiteSpace([string]$r.Source)) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$r.Target)) { continue }

            $enabled = $true
            try { $enabled = [System.Convert]::ToBoolean([string]$r.Enabled) } catch {}

            $rule = New-RimWorldGlossaryRule `
                    ([string]$r.Source) `
                    ([string]$r.Target) `
                    ([string]$r.Scope) `
                    ([string]$r.Module) `
                    ([string]$r.DefType) `
                    ([string]$r.Field) `
                    ([string]$r.PackageId) `
                    $enabled

            $confidence = 0
            try { $confidence = [int]$r.Confidence } catch {}
            $learned = $false
            try { $learned = [System.Convert]::ToBoolean([string]$r.Learned) } catch {}

            $rule.Confidence = $confidence
            $rule.Learned = $learned
            [void]$result.Add($rule)
        }

        return @($result)
    } catch {
        return @(Get-DefaultRimWorldGlossary)
    }
}

function Get-RimWorldEntryGlossaryContext($entry, [string]$workflow) {
    $defType = ""
    $field = ""
    $module = ""
    $packageId = ""

    if ($workflow -eq "Game") {
        $module = [string]$entry.Module
        $type = [string]$entry.Type
        if ($type -match '^DefInjected/(.+)$') {
            $defType = [string]$Matches[1]
        }

        $key = [string]$entry.Key
        if ($key -match '\.([^.]+)$') {
            $field = [string]$Matches[1]
        }
    } else {
        $defType = [string]$entry.DefType
        $field = [string]$entry.Field
        $packageId = [string]$script:OriginalPackageId

        if ([string]::IsNullOrWhiteSpace($defType)) {
            $file = [string]$entry.File
            if ($file -match '(?i)DefInjected[\\/]+([^\\/]+)') {
                $defType = [string]$Matches[1]
            }
        }

        if ([string]::IsNullOrWhiteSpace($field)) {
            $key = [string]$entry.Key
            if ($key -match '\.([^.]+)$') {
                $field = [string]$Matches[1]
            }
        }
    }

    return [pscustomobject]@{
        Workflow = $workflow
        Module = $module
        DefType = $defType
        Field = $field
        PackageId = $packageId
    }
}

function Test-RimWorldGlossaryRuleMatches($rule, $context) {
    if ($null -eq $rule -or $null -eq $context) { return $false }
    if (-not [bool]$rule.Enabled) { return $false }

    $scope = [string]$rule.Scope
    if ([string]::IsNullOrWhiteSpace($scope)) { $scope = "All" }
    if ($scope -ne "All" -and $scope -ne [string]$context.Workflow) { return $false }

    if (-not [string]::IsNullOrWhiteSpace([string]$rule.Module) -and
        ([string]$rule.Module) -ine ([string]$context.Module)) { return $false }

    if (-not [string]::IsNullOrWhiteSpace([string]$rule.DefType) -and
        ([string]$rule.DefType) -ine ([string]$context.DefType)) { return $false }

    if (-not [string]::IsNullOrWhiteSpace([string]$rule.Field) -and
        ([string]$rule.Field) -ine ([string]$context.Field)) { return $false }

    if (-not [string]::IsNullOrWhiteSpace([string]$rule.PackageId) -and
        ([string]$rule.PackageId) -ine ([string]$context.PackageId)) { return $false }

    return $true
}

function Get-MatchingRimWorldGlossaryRules($entry, [string]$workflow) {
    $context = Get-RimWorldEntryGlossaryContext $entry $workflow
    $rules = @(Get-RimWorldGlossary)
    return @($rules | Where-Object { Test-RimWorldGlossaryRuleMatches $_ $context })
}

function Protect-RimWorldGlossaryTerms([string]$text, $rules, [ref]$mapRef) {
    $map = [ordered]@{}
    $result = [string]$text
    $index = 0

    # Longer source terms first, so a short term cannot consume part of a longer one.
    $orderedRules = @($rules | Sort-Object @{Expression={([string]$_.Source).Length};Descending=$true})

    foreach ($rule in $orderedRules) {
        $source = [string]$rule.Source
        $target = [string]$rule.Target
        if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($target)) { continue }

        $token = "ZXQGLOSS{0:D4}QXZ" -f $index

        # Whole-word matching for simple terms. Multi-word terms are matched as an
        # exact phrase. This avoids "counter" matching inside "counterattack".
        $escaped = [regex]::Escape($source)
        if ($source -match '^[\p{L}\p{N}_-]+$') {
            $pattern = "(?i)(?<![\p{L}\p{N}_])$escaped(?![\p{L}\p{N}_])"
        } else {
            $pattern = "(?i)$escaped"
        }

        if ([regex]::IsMatch($result, $pattern)) {
            $result = [regex]::Replace($result, $pattern, $token)
            $map[$token] = $target
            $index++
        }
    }

    $mapRef.Value = $map
    return $result
}

function Restore-RimWorldGlossaryTerms([string]$text, $map) {
    $result = [string]$text
    if ($null -eq $map) { return $result }

    foreach ($token in $map.Keys) {
        $target = [string]$map[$token]
        $result = $result.Replace([string]$token, $target)

        # Tolerate providers inserting spaces into the alphanumeric token.
        $chars = ([string]$token).ToCharArray() | ForEach-Object { [regex]::Escape([string]$_) }
        $pattern = "(?i)" + ($chars -join '\s*')
        $result = [regex]::Replace($result, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return $target
        })
    }

    return $result
}

function Translate-RimWorldEntryWithGlossary($entry, [string]$workflow, [string]$sourceLang, [string]$targetLang) {
    $source = [string]$entry.Source
    if ([string]::IsNullOrWhiteSpace($source)) { return $source }

    $rules = @(Get-MatchingRimWorldGlossaryRules $entry $workflow)
    if ($rules.Count -eq 0) {
        return (Translate-Configured $source $sourceLang $targetLang)
    }

    # Exact whole-entry rule bypasses the provider entirely.
    foreach ($rule in $rules) {
        if ($source.Trim() -ieq ([string]$rule.Source).Trim()) {
            return [string]$rule.Target
        }
    }

    $map = $null
    $protected = Protect-RimWorldGlossaryTerms $source $rules ([ref]$map)
    $translated = Translate-Configured $protected $sourceLang $targetLang
    $restored = Restore-RimWorldGlossaryTerms $translated $map

    # Never save an internal glossary token.
    if ($restored -match '(?i)ZXQ\s*GLOSS') {
        throw "Glossary token restoration failed."
    }

    return $restored
}

function Apply-RimWorldGlossaryToExistingEntry($entry, [string]$workflow) {
    $source = [string]$entry.Source
    if ([string]::IsNullOrWhiteSpace($source)) { return $false }

    $rules = @(Get-MatchingRimWorldGlossaryRules $entry $workflow)
    if ($rules.Count -eq 0) { return $false }

    foreach ($rule in $rules) {
        if ($source.Trim() -ieq ([string]$rule.Source).Trim()) {
            if ([string]$entry.Translation -cne [string]$rule.Target) {
                $entry.Translation = [string]$rule.Target
                return $true
            }
        }
    }

    return $false
}


# ---------- RimWorld terminology learning ----------
$script:RimWorldLearningBaseline = @{}
$script:RimWorldLearningEditOldValue = @{}

function Get-RimWorldLearningIdentity($entry, [string]$workflow) {
    if ($null -eq $entry) { return "" }

    if ($workflow -eq "Game") {
        return ("Game|$([string]$entry.Module)|$([string]$entry.Type)|$([string]$entry.Key)").ToLowerInvariant()
    }

    return ("Mod|$([string]$script:OriginalPackageId)|$([string]$entry.Kind)|$([string]$entry.File)|$([string]$entry.Key)").ToLowerInvariant()
}

function Set-RimWorldLearningBaseline($entry, [string]$workflow, [string]$machineTranslation) {
    $id = Get-RimWorldLearningIdentity $entry $workflow
    if ([string]::IsNullOrWhiteSpace($id)) { return }
    $script:RimWorldLearningBaseline[$id] = [string]$machineTranslation
}

function Get-RimWorldLearningBaseline($entry, [string]$workflow) {
    $id = Get-RimWorldLearningIdentity $entry $workflow
    if ([string]::IsNullOrWhiteSpace($id)) { return $null }
    if ($script:RimWorldLearningBaseline.ContainsKey($id)) {
        return [string]$script:RimWorldLearningBaseline[$id]
    }
    return $null
}

function Get-RimWorldLearnedRuleSpecificity($entry, [string]$workflow) {
    $ctx = Get-RimWorldEntryGlossaryContext $entry $workflow

    return [pscustomobject]@{
        Scope = $workflow
        Module = $(if ($workflow -eq "Game") { [string]$ctx.Module } else { "" })
        DefType = [string]$ctx.DefType
        Field = [string]$ctx.Field
        PackageId = $(if ($workflow -eq "Mod") { [string]$ctx.PackageId } else { "" })
    }
}

function Find-RimWorldLearnedRule($rules, [string]$source, [string]$target, $spec) {
    return @($rules | Where-Object {
        [bool]$_.Learned -and
        ([string]$_.Source).Trim() -ieq $source.Trim() -and
        ([string]$_.Target).Trim() -ieq $target.Trim() -and
        ([string]$_.Scope) -ieq ([string]$spec.Scope) -and
        ([string]$_.Module) -ieq ([string]$spec.Module) -and
        ([string]$_.DefType) -ieq ([string]$spec.DefType) -and
        ([string]$_.Field) -ieq ([string]$spec.Field) -and
        ([string]$_.PackageId) -ieq ([string]$spec.PackageId)
    } | Select-Object -First 1)
}

function Register-RimWorldCorrectionLearning($entry, [string]$workflow, [string]$oldMachineTranslation, [string]$correctedTranslation, [bool]$askFirst=$true) {
    if ($null -eq $entry) { return $null }

    $source = ([string]$entry.Source).Trim()
    $oldValue = ([string]$oldMachineTranslation).Trim()
    $newValue = ([string]$correctedTranslation).Trim()

    if ([string]::IsNullOrWhiteSpace($source)) { return $null }
    if ([string]::IsNullOrWhiteSpace($newValue)) { return $null }
    if ($newValue -ceq $oldValue) { return $null }

    $spec = Get-RimWorldLearnedRuleSpecificity $entry $workflow
    $rules = New-Object System.Collections.ArrayList
    foreach ($r in @(Get-RimWorldGlossary)) { [void]$rules.Add($r) }

    $existing = @(Find-RimWorldLearnedRule $rules $source $newValue $spec)
    if ($existing.Count -gt 0) {
        $rule = $existing[0]
        $rule.Confidence = [Math]::Min(99, ([int]$rule.Confidence + 1))
        if ([int]$rule.Confidence -ge 3) {
            $rule.Enabled = $true
        }
        [void](Save-RimWorldGlossary @($rules))
        return $rule
    }

    if ($askFirst) {
        $contextText = @(
            $(if (-not [string]::IsNullOrWhiteSpace([string]$spec.Module)) { "Module/DLC: $($spec.Module)" }),
            $(if (-not [string]::IsNullOrWhiteSpace([string]$spec.DefType)) { "DefType: $($spec.DefType)" }),
            $(if (-not [string]::IsNullOrWhiteSpace([string]$spec.Field)) { "Field: $($spec.Field)" }),
            $(if (-not [string]::IsNullOrWhiteSpace([string]$spec.PackageId)) { "PackageId: $($spec.PackageId)" })
        ) | Where-Object { $_ }

        $msg = if ($script:UiLanguage -eq "en") {
            "You changed an automatic translation.`n`nSource:`n$source`n`nAutomatic:`n$oldValue`n`nCorrection:`n$newValue`n`n$($contextText -join "`n")`n`nRemember this correction? After 3 consistent corrections the learned rule will activate automatically."
        } else {
            "Zmieniono wynik automatycznego tłumaczenia.`n`nŹródło:`n$source`n`nAutomatycznie:`n$oldValue`n`nPoprawka:`n$newValue`n`n$($contextText -join "`n")`n`nZapamiętać tę poprawkę? Po 3 zgodnych korektach nauczona reguła włączy się automatycznie."
        }

        $ans = [System.Windows.MessageBox]::Show(
            $msg,
            "RimWorld - uczenie glosariusza",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return $null }
    }

    $rule = New-RimWorldGlossaryRule `
        $source `
        $newValue `
        ([string]$spec.Scope) `
        ([string]$spec.Module) `
        ([string]$spec.DefType) `
        ([string]$spec.Field) `
        ([string]$spec.PackageId) `
        $false

    $rule.Confidence = 1
    $rule.Learned = $true
    [void]$rules.Add($rule)
    [void](Save-RimWorldGlossary @($rules))
    return $rule
}

function Get-RimWorldLearningModePath {
    return (Join-Path (Get-ToolkitSettingsDirectory) "rimworld-learning-mode.txt")
}

function Get-RimWorldLearningMode {
    $path = Get-RimWorldLearningModePath
    if (-not (Test-Path -LiteralPath $path)) { return "Silent" }
    try {
        $mode = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
        if ($mode -in @("Silent","Ask","Off")) { return $mode }
    } catch {}
    return "Silent"
}

function Set-RimWorldLearningMode([string]$mode) {
    if ($mode -notin @("Silent","Ask","Off")) { $mode = "Silent" }
    [System.IO.File]::WriteAllText(
        (Get-RimWorldLearningModePath),
        $mode,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )
    Update-RimWorldLearningUi
    return $mode
}

function Get-RimWorldLearningSuggestionPath {
    return (Join-Path (Get-ToolkitSettingsDirectory) "rimworld-learning-suggestions.csv")
}

function Get-RimWorldLearningSuggestions {
    $path = Get-RimWorldLearningSuggestionPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        return @(Import-Csv -LiteralPath $path -Encoding UTF8 -Delimiter ';')
    } catch {
        return @()
    }
}

function Save-RimWorldLearningSuggestions($items) {
    $path = Get-RimWorldLearningSuggestionPath
    $rows = @($items | Select-Object Source,Target,Workflow,Module,DefType,Field,PackageId,Count,LastSeen)
    if ($rows.Count -eq 0) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        Update-RimWorldLearningUi
        return
    }

    $tmp = "$path.tmp"
    $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Move-Item -LiteralPath $tmp -Destination $path -Force
    Update-RimWorldLearningUi
}

function Get-RimWorldLearningSuggestionIdentity($item) {
    return (
        "$([string]$item.Workflow)|$([string]$item.Source)|$([string]$item.Target)|" +
        "$([string]$item.Module)|$([string]$item.DefType)|$([string]$item.Field)|$([string]$item.PackageId)"
    ).ToLowerInvariant()
}

function Add-RimWorldLearningSuggestion($entry, [string]$workflow, [string]$correctedTranslation) {
    if ($null -eq $entry) { return $null }

    $source = ([string]$entry.Source).Trim()
    $target = ([string]$correctedTranslation).Trim()
    if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($target)) { return $null }

    $spec = Get-RimWorldLearnedRuleSpecificity $entry $workflow
    $candidate = [pscustomobject]@{
        Source = $source
        Target = $target
        Workflow = $workflow
        Module = [string]$spec.Module
        DefType = [string]$spec.DefType
        Field = [string]$spec.Field
        PackageId = [string]$spec.PackageId
        Count = 1
        LastSeen = (Get-Date).ToString("s")
    }

    $items = New-Object System.Collections.ArrayList
    foreach ($i in @(Get-RimWorldLearningSuggestions)) { [void]$items.Add($i) }

    $id = Get-RimWorldLearningSuggestionIdentity $candidate
    $found = $null
    foreach ($i in @($items)) {
        if ((Get-RimWorldLearningSuggestionIdentity $i) -eq $id) {
            $found = $i
            break
        }
    }

    if ($null -ne $found) {
        $count = 1
        try { $count = [int]$found.Count + 1 } catch {}
        $found.Count = $count
        $found.LastSeen = (Get-Date).ToString("s")
        $candidate = $found
    } else {
        [void]$items.Add($candidate)
    }

    Save-RimWorldLearningSuggestions @($items)
    return $candidate
}

function Accept-RimWorldLearningSuggestion($suggestion) {
    if ($null -eq $suggestion) { return $null }

    $rules = New-Object System.Collections.ArrayList
    foreach ($r in @(Get-RimWorldGlossary)) { [void]$rules.Add($r) }

    $spec = [pscustomobject]@{
        Scope = [string]$suggestion.Workflow
        Module = [string]$suggestion.Module
        DefType = [string]$suggestion.DefType
        Field = [string]$suggestion.Field
        PackageId = [string]$suggestion.PackageId
    }

    $existing = @(Find-RimWorldLearnedRule $rules ([string]$suggestion.Source) ([string]$suggestion.Target) $spec)
    $increment = 1
    try { $increment = [Math]::Max(1, [int]$suggestion.Count) } catch {}

    if ($existing.Count -gt 0) {
        $rule = $existing[0]
        $rule.Confidence = [Math]::Min(99, ([int]$rule.Confidence + $increment))
    } else {
        $rule = New-RimWorldGlossaryRule `
            ([string]$suggestion.Source) `
            ([string]$suggestion.Target) `
            ([string]$spec.Scope) `
            ([string]$spec.Module) `
            ([string]$spec.DefType) `
            ([string]$spec.Field) `
            ([string]$spec.PackageId) `
            $false
        $rule.Confidence = $increment
        $rule.Learned = $true
        [void]$rules.Add($rule)
    }

    if ([int]$rule.Confidence -ge 3) {
        $rule.Enabled = $true
    }

    [void](Save-RimWorldGlossary @($rules))
    return $rule
}

function Remove-RimWorldLearningSuggestionsByIdentity($toRemove) {
    $removeIds = @{}
    foreach ($r in @($toRemove)) {
        $removeIds[(Get-RimWorldLearningSuggestionIdentity $r)] = $true
    }

    $remaining = @(
        Get-RimWorldLearningSuggestions | Where-Object {
            -not $removeIds.ContainsKey((Get-RimWorldLearningSuggestionIdentity $_))
        }
    )
    Save-RimWorldLearningSuggestions $remaining
}

function Get-RimWorldLearningSuggestionCount([string]$workflow="") {
    $items = @(Get-RimWorldLearningSuggestions)
    if (-not [string]::IsNullOrWhiteSpace($workflow)) {
        $items = @($items | Where-Object { ([string]$_.Workflow) -eq $workflow })
    }
    return $items.Count
}

function Get-RimWorldLearningModeLabel {
    $mode = Get-RimWorldLearningMode
    if ($script:UiLanguage -eq "en") {
        switch ($mode) {
            "Ask" { return "Learning: Ask" }
            "Off" { return "Learning: Off" }
            default { return "Learning: Silent" }
        }
    }

    switch ($mode) {
        "Ask" { return "Nauka: Pytaj" }
        "Off" { return "Nauka: Wyłączona" }
        default { return "Nauka: Ciche" }
    }
}

function Update-RimWorldLearningUi {
    try {
        $modeText = Get-RimWorldLearningModeLabel
        $gameCount = Get-RimWorldLearningSuggestionCount "Game"
        $modCount = Get-RimWorldLearningSuggestionCount "Mod"

        if ($null -ne $btnRimWorldGameLearningMode) { $btnRimWorldGameLearningMode.Content = $modeText }
        if ($null -ne $btnRimWorldModLearningMode) { $btnRimWorldModLearningMode.Content = $modeText }

        if ($null -ne $btnRimWorldGameLearningSuggestions) {
            $btnRimWorldGameLearningSuggestions.Content = $(if ($script:UiLanguage -eq "en") { "Suggestions: $gameCount" } else { "Propozycje: $gameCount" })
        }
        if ($null -ne $btnRimWorldModLearningSuggestions) {
            $btnRimWorldModLearningSuggestions.Content = $(if ($script:UiLanguage -eq "en") { "Suggestions: $modCount" } else { "Propozycje: $modCount" })
        }
    } catch {}
}

function Cycle-RimWorldLearningMode {
    $current = Get-RimWorldLearningMode
    $next = switch ($current) {
        "Silent" { "Ask" }
        "Ask" { "Off" }
        default { "Silent" }
    }
    [void](Set-RimWorldLearningMode $next)
    return $next
}

function Show-RimWorldLearningSuggestionReview([string]$workflow) {
    $all = @(Get-RimWorldLearningSuggestions)
    $visible = New-Object System.Collections.ObjectModel.ObservableCollection[object]

    foreach ($s in @($all | Where-Object { ([string]$_.Workflow) -eq $workflow })) {
        $count = 1
        try { $count = [int]$s.Count } catch {}
        $visible.Add([pscustomobject]@{
            Source = [string]$s.Source
            Target = [string]$s.Target
            Workflow = [string]$s.Workflow
            Module = [string]$s.Module
            DefType = [string]$s.DefType
            Field = [string]$s.Field
            PackageId = [string]$s.PackageId
            Count = $count
            LastSeen = [string]$s.LastSeen
        })
    }

    [xml]$reviewXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RimWorld - Propozycje glosariusza"
        Width="1200" Height="650" MinWidth="900" MinHeight="450"
        WindowStartupLocation="CenterOwner"
        Background="#121018" Foreground="#ECE8F6">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Name="txtReviewInfo" Grid.Row="0" Margin="0,0,0,10" Foreground="#B9AEC9" TextWrapping="Wrap"
               Text="Ciche uczenie zbiera tutaj ręczne poprawki. Licznik pokazuje, ile razy pojawiła się ta sama korekta. Po akceptacji pewność reguły rośnie; od 3 reguła może działać automatycznie."/>

    <DataGrid Name="gridSuggestions" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="False"
              CanUserDeleteRows="False" IsReadOnly="True" SelectionMode="Extended"
              Background="#1B1723" Foreground="#ECE8F6" BorderBrush="#4A3B5B"
              RowBackground="#1B1723" AlternatingRowBackground="#211A2B">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="220"/>
        <DataGridTextColumn Header="Propozycja" Binding="{Binding Target}" Width="220"/>
        <DataGridTextColumn Header="Ile razy" Binding="{Binding Count}" Width="75"/>
        <DataGridTextColumn Header="Module/DLC" Binding="{Binding Module}" Width="100"/>
        <DataGridTextColumn Header="DefType" Binding="{Binding DefType}" Width="110"/>
        <DataGridTextColumn Header="Field" Binding="{Binding Field}" Width="90"/>
        <DataGridTextColumn Header="PackageId" Binding="{Binding PackageId}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>

    <Grid Grid.Row="2" Margin="0,12,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Horizontal">
        <Button Name="btnAcceptSelected" Content="Akceptuj zaznaczone" Padding="12,7" Margin="0,0,8,0"/>
        <Button Name="btnAcceptAll" Content="Akceptuj wszystkie" Padding="12,7" Margin="0,0,8,0"/>
        <Button Name="btnRejectSelected" Content="Odrzuć zaznaczone" Padding="12,7" Margin="0,0,8,0"/>
        <Button Name="btnRejectAll" Content="Odrzuć wszystkie" Padding="12,7"/>
      </StackPanel>
      <Button Grid.Column="1" Name="btnClose" Content="Zamknij" Padding="18,7"/>
    </Grid>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $reviewXaml
    $review = [Windows.Markup.XamlReader]::Load($reader)
    try { $review.Owner = $window } catch {}

    $gridSuggestions = $review.FindName("gridSuggestions")
    $btnAcceptSelected = $review.FindName("btnAcceptSelected")
    $btnAcceptAll = $review.FindName("btnAcceptAll")
    $btnRejectSelected = $review.FindName("btnRejectSelected")
    $btnRejectAll = $review.FindName("btnRejectAll")
    $btnClose = $review.FindName("btnClose")

    $gridSuggestions.ItemsSource = $visible

    $refresh = {
        $gridSuggestions.ItemsSource = $null
        $gridSuggestions.ItemsSource = $visible
        Update-RimWorldLearningUi
    }

    $acceptItems = {
        param($items)
        $chosen = @($items)
        if ($chosen.Count -eq 0) { return }
        foreach ($s in $chosen) {
            [void](Accept-RimWorldLearningSuggestion $s)
            [void]$visible.Remove($s)
        }
        Remove-RimWorldLearningSuggestionsByIdentity $chosen
        & $refresh
    }

    $rejectItems = {
        param($items)
        $chosen = @($items)
        if ($chosen.Count -eq 0) { return }
        foreach ($s in $chosen) { [void]$visible.Remove($s) }
        Remove-RimWorldLearningSuggestionsByIdentity $chosen
        & $refresh
    }

    $btnAcceptSelected.Add_Click({ & $acceptItems @($gridSuggestions.SelectedItems) })
    $btnAcceptAll.Add_Click({ & $acceptItems @($visible) })
    $btnRejectSelected.Add_Click({ & $rejectItems @($gridSuggestions.SelectedItems) })
    $btnRejectAll.Add_Click({ & $rejectItems @($visible) })
    $btnClose.Add_Click({ $review.Close() })

    [void]$review.ShowDialog()
}

function Handle-RimWorldManualTranslationEdit($entry, [string]$workflow, [string]$newValue) {
    if ($null -eq $entry) { return }

    $baseline = Get-RimWorldLearningBaseline $entry $workflow
    if ($null -eq $baseline) { return }

    $corrected = [string]$newValue
    if ($corrected.Trim() -ceq ([string]$baseline).Trim()) { return }

    $mode = Get-RimWorldLearningMode

    if ($mode -eq "Ask") {
        $rule = Register-RimWorldCorrectionLearning $entry $workflow $baseline $corrected $true
        if ($null -ne $rule) {
            $confidence = [int]$rule.Confidence
            $active = [bool]$rule.Enabled
            $msg = if ($script:UiLanguage -eq "en") {
                "Learned correction saved. Confidence: $confidence/3. Active: $active"
            } else {
                "Zapamiętano poprawkę. Pewność: $confidence/3. Aktywna: $active"
            }
            if ($workflow -eq "Game") { Set-ControlTextSafe $txtRimWorldGameStatus $msg }
            else { Set-ControlTextSafe $txtStatus $msg }
        }
    } elseif ($mode -eq "Silent") {
        [void](Add-RimWorldLearningSuggestion $entry $workflow $corrected)
        $count = Get-RimWorldLearningSuggestionCount $workflow
        $msg = if ($script:UiLanguage -eq "en") {
            "Learning suggestion queued. Suggestions: $count"
        } else {
            "Poprawka dodana do cichej nauki. Propozycje: $count"
        }
        if ($workflow -eq "Game") { Set-ControlTextSafe $txtRimWorldGameStatus $msg }
        else { Set-ControlTextSafe $txtStatus $msg }
    }

    # Always consume this baseline after the edit. A future automatic translation
    # can establish a new baseline.
    $id = Get-RimWorldLearningIdentity $entry $workflow
    if ($script:RimWorldLearningBaseline.ContainsKey($id)) {
        $script:RimWorldLearningBaseline.Remove($id)
    }
    Update-RimWorldLearningUi
}

function Show-RimWorldLearningStats {
    $rules = @(Get-RimWorldGlossary | Where-Object { [bool]$_.Learned })
    $active = @($rules | Where-Object { [bool]$_.Enabled }).Count
    $pending = @($rules | Where-Object { -not [bool]$_.Enabled }).Count

    return [pscustomobject]@{
        Total = $rules.Count
        Active = $active
        Pending = $pending
    }
}

function Show-RimWorldGlossaryEditor([string]$workflow) {
    $rules = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($r in @(Get-RimWorldGlossary)) {
        $rules.Add([pscustomobject]@{
            Enabled = [bool]$r.Enabled
            Source = [string]$r.Source
            Target = [string]$r.Target
            Scope = [string]$r.Scope
            Module = [string]$r.Module
            DefType = [string]$r.DefType
            Field = [string]$r.Field
            PackageId = [string]$r.PackageId
            Confidence = [int]$r.Confidence
            Learned = [bool]$r.Learned
        })
    }

    [xml]$glossaryXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RimWorld - Glosariusz kontekstowy"
        Width="1180" Height="660"
        MinWidth="900" MinHeight="480"
        WindowStartupLocation="CenterOwner"
        Background="#121018" Foreground="#ECE8F6">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Margin="0,0,0,10" Foreground="#B9AEC9" TextWrapping="Wrap"
               Text="Reguły są stosowane przed automatycznym tłumaczeniem. Scope: All, Game lub Mod. Puste pola Module / DefType / Field / PackageId oznaczają dowolną wartość."/>

    <DataGrid Name="gridGlossary" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="True"
              CanUserDeleteRows="True" Background="#1B1723" Foreground="#ECE8F6"
              BorderBrush="#4A3B5B" RowBackground="#1B1723" AlternatingRowBackground="#211A2B">
      <DataGrid.Columns>
        <DataGridCheckBoxColumn Header="On" Binding="{Binding Enabled}" Width="45"/>
        <DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="145"/>
        <DataGridTextColumn Header="Target" Binding="{Binding Target}" Width="145"/>
        <DataGridTextColumn Header="Scope" Binding="{Binding Scope}" Width="75"/>
        <DataGridTextColumn Header="Module/DLC" Binding="{Binding Module}" Width="110"/>
        <DataGridTextColumn Header="DefType" Binding="{Binding DefType}" Width="115"/>
        <DataGridTextColumn Header="Field" Binding="{Binding Field}" Width="95"/>
        <DataGridTextColumn Header="PackageId moda" Binding="{Binding PackageId}" Width="*"/>
        <DataGridTextColumn Header="Pewność" Binding="{Binding Confidence}" Width="70" IsReadOnly="True"/>
        <DataGridCheckBoxColumn Header="Nauczona" Binding="{Binding Learned}" Width="75" IsReadOnly="True"/>
      </DataGrid.Columns>
    </DataGrid>

    <Grid Grid.Row="2" Margin="0,12,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Horizontal">
        <Button Name="btnAdd" Content="Dodaj regułę" Padding="12,7" Margin="0,0,8,0"/>
        <Button Name="btnDefaults" Content="Dodaj domyślne" Padding="12,7" Margin="0,0,8,0"/>
        <Button Name="btnApplyExisting" Content="Zastosuj do istniejących etykiet" Padding="12,7"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button Name="btnCancel" Content="Anuluj" Padding="16,7" Margin="0,0,8,0"/>
        <Button Name="btnSave" Content="Zapisz glosariusz" Padding="16,7" Background="#7A3FC2" Foreground="White"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $glossaryXaml
    $editor = [Windows.Markup.XamlReader]::Load($reader)
    try { $editor.Owner = $window } catch {}

    $gridGlossary = $editor.FindName("gridGlossary")
    $btnAdd = $editor.FindName("btnAdd")
    $btnDefaults = $editor.FindName("btnDefaults")
    $btnApplyExisting = $editor.FindName("btnApplyExisting")
    $btnCancel = $editor.FindName("btnCancel")
    $btnSave = $editor.FindName("btnSave")

    $gridGlossary.ItemsSource = $rules

    $btnAdd.Add_Click({
        $rules.Add([pscustomobject]@{
            Enabled = $true
            Source = ""
            Target = ""
            Scope = $workflow
            Module = ""
            DefType = ""
            Field = ""
            PackageId = $(if ($workflow -eq "Mod") { [string]$script:OriginalPackageId } else { "" })
            Confidence = 0
            Learned = $false
        })
    })

    $btnDefaults.Add_Click({
        foreach ($d in @(Get-DefaultRimWorldGlossary)) {
            $exists = @($rules | Where-Object {
                ([string]$_.Source) -ieq ([string]$d.Source) -and
                ([string]$_.Target) -ieq ([string]$d.Target) -and
                ([string]$_.DefType) -ieq ([string]$d.DefType) -and
                ([string]$_.Field) -ieq ([string]$d.Field)
            }).Count -gt 0
            if (-not $exists) {
                $rules.Add($d)
            }
        }
    })

    $btnApplyExisting.Add_Click({
        try {
            [void]$gridGlossary.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
            [void]$gridGlossary.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        } catch {}
        [void](Save-RimWorldGlossary @($rules))

        $changed = 0
        if ($workflow -eq "Game") {
            foreach ($e in @($script:RimWorldGameEntries)) {
                if (Apply-RimWorldGlossaryToExistingEntry $e "Game") { $changed++ }
            }
            Apply-RimWorldGameFilter
            Set-ControlTextSafe $txtRimWorldGameStatus "Glosariusz: poprawiono $changed istniejących etykiet."
        } else {
            foreach ($e in @($script:Entries)) {
                if (Apply-RimWorldGlossaryToExistingEntry $e "Mod") { $changed++ }
            }
            Refresh-Grid
            Set-ControlTextSafe $txtStatus "Glosariusz: poprawiono $changed istniejących etykiet."
        }
    })

    $btnCancel.Add_Click({
        $editor.DialogResult = $false
        $editor.Close()
    })

    $btnSave.Add_Click({
        try {
            [void]$gridGlossary.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
            [void]$gridGlossary.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        } catch {}

        $clean = @($rules | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.Source) -and
            -not [string]::IsNullOrWhiteSpace([string]$_.Target)
        })
        [void](Save-RimWorldGlossary $clean)
        $editor.DialogResult = $true
        $editor.Close()
    })

    [void]$editor.ShowDialog()
}

# ---------- Central language registry ----------
$script:Languages = @(
    [pscustomobject]@{ Code="en"; Name="English"; NativeName="English"; RimWorldFolder="English"; GoogleCode="en"; DeepLCode="EN"; LibreCode="en"; Flag="GB" },
    [pscustomobject]@{ Code="pl"; Name="Polish"; NativeName="Polski"; RimWorldFolder="Polish"; GoogleCode="pl"; DeepLCode="PL"; LibreCode="pl"; Flag="PL" },
    [pscustomobject]@{ Code="de"; Name="German"; NativeName="Deutsch"; RimWorldFolder="German"; GoogleCode="de"; DeepLCode="DE"; LibreCode="de"; Flag="DE" },
    [pscustomobject]@{ Code="fr"; Name="French"; NativeName="Français"; RimWorldFolder="French"; GoogleCode="fr"; DeepLCode="FR"; LibreCode="fr"; Flag="FR" },
    [pscustomobject]@{ Code="es"; Name="Spanish"; NativeName="Español"; RimWorldFolder="Spanish"; GoogleCode="es"; DeepLCode="ES"; LibreCode="es"; Flag="ES" },
    [pscustomobject]@{ Code="it"; Name="Italian"; NativeName="Italiano"; RimWorldFolder="Italian"; GoogleCode="it"; DeepLCode="IT"; LibreCode="it"; Flag="IT" },
    [pscustomobject]@{ Code="pt"; Name="Portuguese"; NativeName="Português"; RimWorldFolder="Portuguese"; GoogleCode="pt"; DeepLCode="PT-PT"; LibreCode="pt"; Flag="PT" },
    [pscustomobject]@{ Code="pt-br"; Name="Portuguese (Brazil)"; NativeName="Português (Brasil)"; RimWorldFolder="Brazilian"; GoogleCode="pt"; DeepLCode="PT-BR"; LibreCode="pt"; Flag="BR" },
    [pscustomobject]@{ Code="cs"; Name="Czech"; NativeName="Čeština"; RimWorldFolder="Czech"; GoogleCode="cs"; DeepLCode="CS"; LibreCode="cs"; Flag="CZ" },
    [pscustomobject]@{ Code="uk"; Name="Ukrainian"; NativeName="Українська"; RimWorldFolder="Ukrainian"; GoogleCode="uk"; DeepLCode="UK"; LibreCode="uk"; Flag="UA" },
    [pscustomobject]@{ Code="ru"; Name="Russian"; NativeName="Русский"; RimWorldFolder="Russian"; GoogleCode="ru"; DeepLCode="RU"; LibreCode="ru"; Flag="RU" },
    [pscustomobject]@{ Code="ja"; Name="Japanese"; NativeName="日本語"; RimWorldFolder="Japanese"; GoogleCode="ja"; DeepLCode="JA"; LibreCode="ja"; Flag="JP" },
    [pscustomobject]@{ Code="ko"; Name="Korean"; NativeName="한국어"; RimWorldFolder="Korean"; GoogleCode="ko"; DeepLCode="KO"; LibreCode="ko"; Flag="KR" },
    [pscustomobject]@{ Code="zh-cn"; Name="Chinese (Simplified)"; NativeName="简体中文"; RimWorldFolder="ChineseSimplified"; GoogleCode="zh-CN"; DeepLCode="ZH"; LibreCode="zh"; Flag="CN" },
    [pscustomobject]@{ Code="zh-tw"; Name="Chinese (Traditional)"; NativeName="繁體中文"; RimWorldFolder="ChineseTraditional"; GoogleCode="zh-TW"; DeepLCode="ZH"; LibreCode="zt"; Flag="TW" },
    [pscustomobject]@{ Code="nl"; Name="Dutch"; NativeName="Nederlands"; RimWorldFolder="Dutch"; GoogleCode="nl"; DeepLCode="NL"; LibreCode="nl"; Flag="NL" },
    [pscustomobject]@{ Code="sv"; Name="Swedish"; NativeName="Svenska"; RimWorldFolder="Swedish"; GoogleCode="sv"; DeepLCode="SV"; LibreCode="sv"; Flag="SE" }
)

function Get-LanguageByCode([string]$code) {
    if ([string]::IsNullOrWhiteSpace($code)) { return $null }
    return $script:Languages | Where-Object { $_.Code -ieq $code } | Select-Object -First 1
}

function Get-LanguageByRimWorldFolder([string]$folderName) {
    if ([string]::IsNullOrWhiteSpace($folderName)) { return $null }
    return $script:Languages | Where-Object { $_.RimWorldFolder -ieq $folderName } | Select-Object -First 1
}

function Get-LanguageDisplayName($lang) {
    if ($null -eq $lang) { return "" }
    if ([string]::IsNullOrWhiteSpace([string]$lang.NativeName) -or $lang.NativeName -eq $lang.Name) {
        return [string]$lang.Name
    }
    return "$($lang.Name) / $($lang.NativeName)"
}

function Populate-LanguageCombo($combo, [string]$selectedCode) {
    if ($null -eq $combo) { return }
    $combo.Items.Clear()

    foreach ($lang in $script:Languages) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = Get-LanguageDisplayName $lang
        $item.Tag = $lang.Code
        [void]$combo.Items.Add($item)
        if ($lang.Code -ieq $selectedCode) {
            $combo.SelectedItem = $item
        }
    }

    if ($null -eq $combo.SelectedItem -and $combo.Items.Count -gt 0) {
        $combo.SelectedIndex = 0
    }
}

function Get-SelectedLanguageFromCombo($combo) {
    if ($null -eq $combo -or $null -eq $combo.SelectedItem) { return $null }
    return Get-LanguageByCode ([string]$combo.SelectedItem.Tag)
}



# ---------- Project Zomboid Game experimental profile ----------
$script:PzGameSourceMap = @{}
$script:PzGameTargetMap = @{}
$script:PzGameTargetOnlyCount = 0
$script:PzGameEntries = @()

function Get-PzInstallPath {
    $candidates = New-Object System.Collections.ArrayList

    try {
        $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
        if ($steamPath) { [void]$candidates.Add($steamPath) }
    } catch {}

    foreach ($envPath in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($envPath)) {
            $p = Join-Path $envPath "Steam"
            if (Test-Path -LiteralPath $p) { [void]$candidates.Add($p) }
        }
    }

    $libraries = New-Object System.Collections.ArrayList
    foreach ($steam in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $steam)) { continue }
        [void]$libraries.Add($steam)

        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            try {
                foreach ($line in Get-Content -LiteralPath $vdf -Encoding UTF8 -ErrorAction SilentlyContinue) {
                    if ($line -match '"path"\s+"([^"]+)"') {
                        $lib = [string]$Matches[1]
                        $lib = $lib -replace '\\\\','\'
                        if (Test-Path -LiteralPath $lib) {
                            [void]$libraries.Add($lib)
                        }
                    }
                }
            } catch {}
        }
    }

    foreach ($lib in @($libraries | Select-Object -Unique)) {
        $game = Join-Path $lib "steamapps\common\ProjectZomboid"
        if (Test-Path -LiteralPath (Join-Path $game "media\lua\shared\Translate")) {
            return $game
        }

        # Some installs may expose the display-name folder.
        $game2 = Join-Path $lib "steamapps\common\Project Zomboid"
        if (Test-Path -LiteralPath (Join-Path $game2 "media\lua\shared\Translate")) {
            return $game2
        }
    }

    return $null
}

function Read-PzGameTranslationFolder([string]$gameRoot, [string]$pzCode, [string]$role) {
    $folder = Join-Path $gameRoot "media\lua\shared\Translate\$pzCode"
    if (-not (Test-Path -LiteralPath $folder)) { return @() }

    $rows = New-Object System.Collections.ArrayList
    $files = @(Get-PzTranslationFiles $folder)
    $fileIndex = 0
    $fileTotal = $files.Count

    foreach ($f in $files) {
        $fileIndex++
        if (($fileIndex % 10) -eq 0 -or $fileIndex -eq 1 -or $fileIndex -eq $fileTotal) {
            if ($role -eq "Source") {
                $pct = 5 + [int](35 * ($fileIndex / [math]::Max(1,$fileTotal)))
                Set-PzGameScanProgress $pct $(if ($script:UiLanguage -eq "en") {
                    "Scanning source files: $fileIndex / $fileTotal"
                } else {
                    "Skanowanie plików źródłowych: $fileIndex / $fileTotal"
                })
            } else {
                $pct = 40 + [int](35 * ($fileIndex / [math]::Max(1,$fileTotal)))
                Set-PzGameScanProgress $pct $(if ($script:UiLanguage -eq "en") {
                    "Scanning target files: $fileIndex / $fileTotal"
                } else {
                    "Skanowanie plików docelowych: $fileIndex / $fileTotal"
                })
            }
        }
        if ($f.Name -like "Recorded_Media_*" -and $f.Extension -ieq ".txt") { continue }

        if ($f.Extension -ieq ".json") {
            foreach ($jr in @(Read-PzJsonTranslationFile $f.FullName)) {
                [void]$rows.Add([pscustomobject]@{
                    File = [System.IO.Path]::GetFileName($f.FullName)
                    Key = [string]$jr.Key
                    Source = if ($role -eq "Source") { [string]$jr.Value } else { "" }
                    Translation = if ($role -eq "Target") { [string]$jr.Value } else { "" }
                    Line = 0
                    Format = "JSON"
                })
            }
            continue
        }

        $lineNo = 0
        foreach ($line in Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue) {
            $lineNo++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $key = $null
            $value = $null

            if ($line -match '^\s*([A-Za-z0-9_.\-\[\]]+)\s*=\s*"((?:\\.|[^"])*)"\s*,?\s*$') {
                $key = [string]$Matches[1]
                $value = ConvertFrom-PzQuotedValue ([string]$Matches[2])
            } elseif ($line -match "^\s*([A-Za-z0-9_.\-\[\]]+)\s*=\s*'((?:\\.|[^'])*)'\s*,?\s*$") {
                $key = [string]$Matches[1]
                $value = ConvertFrom-PzQuotedValue ([string]$Matches[2])
            }

            if ([string]::IsNullOrWhiteSpace($key)) { continue }

            [void]$rows.Add([pscustomobject]@{
                File = [System.IO.Path]::GetFileName($f.FullName)
                Key = $key
                Source = if ($role -eq "Source") { $value } else { "" }
                Translation = if ($role -eq "Target") { $value } else { "" }
                Line = $lineNo
                Format = "TXT"
            })
        }
    }
    return @($rows)
}

function Get-PzGameEntryIdentity($entry) {
    return "$($entry.File)|$($entry.Key)"
}



function Set-PzGameScanProgress([int]$percent, [string]$message="") {
    if ($percent -lt 0) { $percent = 0 }
    if ($percent -gt 100) { $percent = 100 }

    if ($null -ne $prgPzGameScan) {
        $prgPzGameScan.Value = $percent
    }
    if ($null -ne $lblPzGameProgress) {
        $lblPzGameProgress.Text = "$percent%"
    }
    if (-not [string]::IsNullOrWhiteSpace($message) -and $null -ne $txtPzGameStatus) {
        $txtPzGameStatus.Text = $message
    }

    try {
        [System.Windows.Forms.Application]::DoEvents()
    } catch {}
}

function Set-PzGameWorkProgress([int]$percent, [string]$message="") {
    if ($percent -lt 0) { $percent = 0 }
    if ($percent -gt 100) { $percent = 100 }

    if ($null -ne $prgPzGameScan) {
        $prgPzGameScan.Value = $percent
    }
    if ($null -ne $lblPzGameProgress) {
        $lblPzGameProgress.Text = "$percent%"
    }
    if (-not [string]::IsNullOrWhiteSpace($message) -and $null -ne $txtPzGameStatus) {
        $txtPzGameStatus.Text = $message
    }

    try {
        [System.Windows.Forms.Application]::DoEvents()
    } catch {}
}


function Get-PzGameCoverage {
    $srcMap = $script:PzGameSourceMap
    $dstMap = $script:PzGameTargetMap

    if ($null -eq $srcMap -or $null -eq $dstMap) {
        return [pscustomobject]@{ Total=0; Missing=0; Identical=0; Translated=0; TargetOnly=0 }
    }

    $missing = 0
    $identical = 0
    $translated = 0

    foreach ($key in $srcMap.Keys) {
        if (-not $dstMap.ContainsKey($key)) {
            $missing++
            continue
        }

        $s = [string]$srcMap[$key]
        $d = [string]$dstMap[$key]
        if ($s.Trim() -ceq $d.Trim()) { $identical++ } else { $translated++ }
    }

    return [pscustomobject]@{
        Total = $srcMap.Count
        Missing = $missing
        Identical = $identical
        Translated = $translated
        TargetOnly = $script:PzGameTargetOnlyCount
    }
}


function Apply-PzGameFilter {
    if ($null -eq $cmbPzGameFilter -or $null -eq $pzGameGrid) {
        Refresh-PzGameGrid
        return
    }

    $mode = if ($null -ne $cmbPzGameFilter.SelectedItem) { [string]$cmbPzGameFilter.SelectedItem.Tag } else { "all" }
    $items = @($script:PzGameEntries)

    switch ($mode) {
        "missing" {
            $items = @($items | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Translation) })
        }
        "identical" {
            $items = @($items | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.Translation) -and
                ([string]$_.Source).Trim() -ceq ([string]$_.Translation).Trim()
            })
        }
        "suspicious" {
            $items = @($items | Where-Object {
                [string]::IsNullOrWhiteSpace([string]$_.Translation) -or
                (([string]$_.Source).Trim() -ceq ([string]$_.Translation).Trim())
            })
        }
    }

    $pzGameGrid.ItemsSource = $null
    $pzGameGrid.ItemsSource = $items
    if ($null -ne $lblPzGameCount) {
        $lblPzGameCount.Content = if ($script:UiLanguage -eq "en") {
            "Entries: $($items.Count) / $($script:PzGameEntries.Count)"
        } else {
            "Wpisy: $($items.Count) / $($script:PzGameEntries.Count)"
        }
    }
}

function Refresh-PzGameGrid {
    if ($null -eq $pzGameGrid) { return }
    $pzGameGrid.ItemsSource = $null
    $pzGameGrid.ItemsSource = @($script:PzGameEntries)
    if ($null -ne $lblPzGameCount) {
        $lblPzGameCount.Content = if ($script:UiLanguage -eq "en") {
            "Entries: $($script:PzGameEntries.Count)"
        } else {
            "Wpisy: $($script:PzGameEntries.Count)"
        }
    }
}

function Scan-PzGame([string]$gameRoot) {
    Set-PzGameScanProgress 0 $(if ($script:UiLanguage -eq "en") { "Preparing Project Zomboid scan..." } else { "Przygotowanie skanowania Project Zomboid..." })
    if ($null -ne $btnScanPzGame) { $btnScanPzGame.IsEnabled = $false }
    try {
    if ([string]::IsNullOrWhiteSpace($gameRoot) -or -not (Test-Path -LiteralPath $gameRoot)) {
        throw $(if ($script:UiLanguage -eq "en") { "Choose a valid Project Zomboid game folder." } else { "Wybierz prawidłowy folder gry Project Zomboid." })
    }

    $srcLang = Get-PzSelectedLanguage $cmbPzGameSourceLang
    $dstLang = Get-PzSelectedLanguage $cmbPzGameTargetLang
    if ($null -eq $srcLang -or $null -eq $dstLang) { return $null }

    if ($srcLang.Code -ieq $dstLang.Code) {
        throw $(if ($script:UiLanguage -eq "en") { "Source and target language must be different." } else { "Język źródłowy i docelowy muszą być różne." })
    }

    $srcCode = Get-PzLanguageCode ([string]$srcLang.Code)
    $dstCode = Get-PzLanguageCode ([string]$dstLang.Code)
    if ([string]::IsNullOrWhiteSpace($srcCode) -or [string]::IsNullOrWhiteSpace($dstCode)) {
        throw "Selected language is not mapped for Project Zomboid."
    }

    Set-PzGameScanProgress 5 $(if ($script:UiLanguage -eq "en") { "Scanning source language..." } else { "Skanowanie języka źródłowego..." })
    $sourceRows = @(Read-PzGameTranslationFolder $gameRoot $srcCode "Source")
    Set-PzGameScanProgress 40 $(if ($script:UiLanguage -eq "en") { "Source scan complete. Scanning target language..." } else { "Źródło zeskanowane. Skanowanie języka docelowego..." })
    $targetRows = @(Read-PzGameTranslationFolder $gameRoot $dstCode "Target")
    Set-PzGameScanProgress 75 $(if ($script:UiLanguage -eq "en") { "Building source/target indexes..." } else { "Budowanie indeksów source/target..." })

    $sourceMap = @{}
    foreach ($r in $sourceRows) {
        $sourceMap[(Get-PzGameEntryIdentity $r).ToLowerInvariant()] = [string]$r.Source
    }

    $targetMap = @{}
    foreach ($r in $targetRows) {
        $targetMap[(Get-PzGameEntryIdentity $r).ToLowerInvariant()] = [string]$r.Translation
    }

    $targetOnly = 0
    foreach ($key in $targetMap.Keys) {
        if (-not $sourceMap.ContainsKey($key)) { $targetOnly++ }
    }

    $script:PzGameSourceMap = $sourceMap
    $script:PzGameTargetMap = $targetMap
    $script:PzGameTargetOnlyCount = $targetOnly

    Set-PzGameScanProgress 85 $(if ($script:UiLanguage -eq "en") { "Matching translations..." } else { "Dopasowywanie tłumaczeń..." })
    $matched = 0
    foreach ($r in $sourceRows) {
        $id = (Get-PzGameEntryIdentity $r).ToLowerInvariant()
        if ($targetMap.ContainsKey($id)) {
            $r.Translation = [string]$targetMap[$id]
            $matched++
        }
    }

    $script:PzGameEntries = @($sourceRows)
    Refresh-PzGameGrid
    try { Apply-PzGameFilter } catch {}

    if ($pzGameGrid.Columns.Count -ge 4) {
        $pzGameGrid.Columns[2].Header = [string]$srcLang.NativeName
        $pzGameGrid.Columns[3].Header = [string]$dstLang.NativeName
    }

    Set-PzGameScanProgress 95 $(if ($script:UiLanguage -eq "en") { "Calculating coverage..." } else { "Liczenie pokrycia..." })
    $coverage = Get-PzGameCoverage
    $txtPzGameStatus.Text = if ($script:UiLanguage -eq "en") {
        "Scan complete. Source: $($sourceRows.Count), target: $($targetRows.Count), matched: $matched | Missing: $($coverage.Missing) | Identical: $($coverage.Identical) | Translated: $($coverage.Translated) | Target-only: $($coverage.TargetOnly)"
    } else {
        "Skan zakończony. Źródło: $($sourceRows.Count), cel: $($targetRows.Count), dopasowane: $matched | Brak: $($coverage.Missing) | Identyczne: $($coverage.Identical) | Przetłumaczone: $($coverage.Translated) | Tylko target: $($coverage.TargetOnly)"
    }

    Set-PzGameScanProgress 100 $(if ($script:UiLanguage -eq "en") { "Project Zomboid scan complete." } else { "Skanowanie Project Zomboid zakończone." })

    return [pscustomobject]@{
        SourceEntries = $sourceRows.Count
        TargetEntries = $targetRows.Count
        Matched = $matched
    }
    }
    finally {
        if ($null -ne $btnScanPzGame) { $btnScanPzGame.IsEnabled = $true }
    }
}

function Save-PzGameCheckpoint([string]$reason = "autosave") {
    if ($script:PzGameEntries.Count -eq 0) { return $null }

    $srcLang = Get-PzSelectedLanguage $cmbPzGameSourceLang
    $dstLang = Get-PzSelectedLanguage $cmbPzGameTargetLang
    $src = if ($null -ne $srcLang) { [string]$srcLang.Code } else { "" }
    $dst = if ($null -ne $dstLang) { [string]$dstLang.Code } else { "" }

    $autosaveDir = Get-ToolkitAutosaveDirectory
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $path = Join-Path $autosaveDir "$stamp-ProjectZomboidGame-$src-$dst.csv"
    $latest = Join-Path $autosaveDir "latest-pz-game.csv"

    $rows = @(
        $script:PzGameEntries |
            Select-Object File,Key,Source,Translation,Line,Format,
                @{N="SourceLanguage";E={$src}},
                @{N="TargetLanguage";E={$dst}}
    )
    Write-ToolkitCsvAtomic $rows $path
    Copy-Item -LiteralPath $path -Destination $latest -Force
    return $path
}

function Export-PzGameCsv([string]$path) {
    [void](Save-PzGameCheckpoint "before-csv-export")

    $srcLang = Get-PzSelectedLanguage $cmbPzGameSourceLang
    $dstLang = Get-PzSelectedLanguage $cmbPzGameTargetLang
    $src = if ($null -ne $srcLang) { [string]$srcLang.Code } else { "" }
    $dst = if ($null -ne $dstLang) { [string]$dstLang.Code } else { "" }

    $rows = @(
        $script:PzGameEntries |
            Select-Object File,Key,Source,Translation,Line,Format,
                @{N="SourceLanguage";E={$src}},
                @{N="TargetLanguage";E={$dst}}
    )
    Write-ToolkitCsvAtomic $rows $path
}

function Import-PzGameCsv([string]$path) {
    $rows = @(Microsoft.PowerShell.Utility\Import-Csv -LiteralPath $path -Encoding UTF8 -Delimiter ';')
    if ($rows.Count -eq 0) { return 0 }

    $lookup = @{}
    foreach ($r in $rows) {
        $id = "$([string]$r.File)|$([string]$r.Key)".ToLowerInvariant()
        $lookup[$id] = [string]$r.Translation
    }

    $updated = 0
    foreach ($e in $script:PzGameEntries) {
        $id = (Get-PzGameEntryIdentity $e).ToLowerInvariant()
        if ($lookup.ContainsKey($id)) {
            $e.Translation = [string]$lookup[$id]
            $updated++
        }
    }

    Refresh-PzGameGrid
    return $updated
}

# ---------- Project Zomboid experimental profile ----------
$script:PzEditingTranslationPath = ""
$script:PzLastBuildPath = ""
$script:PzLastWorkshopDescriptionPath = ""
$script:PzLastWorkshopStagePath = ""
$script:PzDetectedMods = @()
$script:PzEntries = @()
$script:PzContentRoots = @()

function Get-PzLanguageCode([string]$code) {
    switch ($code.ToLowerInvariant()) {
        "en" { return "EN" }
        "pl" { return "PL" }
        "de" { return "DE" }
        "fr" { return "FR" }
        "es" { return "ES" }
        "it" { return "IT" }
        "pt" { return "PT" }
        "pt-br" { return "PTBR" }
        "cs" { return "CZ" }
        "uk" { return "UA" }
        "ru" { return "RU" }
        "ja" { return "JP" }
        "ko" { return "KO" }
        "zh-cn" { return "CN" }
        "zh-tw" { return "CH" }
        "nl" { return "NL" }
        default { return $null }
    }
}

function Populate-PzLanguageCombo($combo, [string]$selectedCode) {
    if ($null -eq $combo) { return }
    $combo.Items.Clear()

    foreach ($lang in $script:Languages) {
        $pzCode = Get-PzLanguageCode ([string]$lang.Code)
        if ([string]::IsNullOrWhiteSpace($pzCode)) { continue }

        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = Get-LanguageDisplayName $lang
        $item.Tag = [string]$lang.Code
        [void]$combo.Items.Add($item)

        if ($lang.Code -ieq $selectedCode) {
            $combo.SelectedItem = $item
        }
    }

    if ($null -eq $combo.SelectedItem -and $combo.Items.Count -gt 0) {
        $combo.SelectedIndex = 0
    }
}

function Get-PzSelectedLanguage($combo) {
    if ($null -eq $combo -or $null -eq $combo.SelectedItem) { return $null }
    return Get-LanguageByCode ([string]$combo.SelectedItem.Tag)
}

function Test-PzTranslateRoot([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    return Test-Path -LiteralPath (Join-Path $path "media\lua\shared\Translate")
}

function Get-PzVersionSortValue([string]$name) {
    try {
        if ($name -match '^\d+(\.\d+){0,3}$') {
            return [version]$name
        }
    } catch {}
    return [version]"0.0"
}

function Get-PzWorkshopRoots {
    $roots = New-Object System.Collections.ArrayList
    $steamCandidates = New-Object System.Collections.ArrayList

    try {
        $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
        if ($steamPath) { [void]$steamCandidates.Add($steamPath) }
    } catch {}

    foreach ($envPath in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($envPath)) {
            $candidate = Join-Path $envPath "Steam"
            if (Test-Path -LiteralPath $candidate) { [void]$steamCandidates.Add($candidate) }
        }
    }

    $libraries = New-Object System.Collections.ArrayList
    foreach ($steam in @($steamCandidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $steam)) { continue }
        [void]$libraries.Add($steam)

        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            try {
                foreach ($line in Get-Content -LiteralPath $vdf -Encoding UTF8 -ErrorAction SilentlyContinue) {
                    if ($line -match '"path"\s+"([^"]+)"') {
                        $lib = [string]$Matches[1]
                        $lib = $lib -replace '\\\\','\'
                        if (Test-Path -LiteralPath $lib) { [void]$libraries.Add($lib) }
                    }
                }
            } catch {}
        }
    }

    foreach ($lib in @($libraries | Select-Object -Unique)) {
        $workshop = Join-Path $lib "steamapps\workshop\content\108600"
        if (Test-Path -LiteralPath $workshop) {
            [void]$roots.Add($workshop)
        }
    }

    return @($roots | Select-Object -Unique)
}

function Get-PzLocalModsRoot {
    $candidate = Join-Path $env:USERPROFILE "Zomboid\mods"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}


function Get-PzModInfo([string]$modPath, [string]$fallbackName="", [string]$workshopId="") {
    $name = $fallbackName
    $id = ""
    $version = ""
    $infoCandidates = @((Join-Path $modPath "mod.info"))

    try {
        $latestVersion = Get-ChildItem -LiteralPath $modPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+){0,3}$' } |
            Sort-Object @{ Expression = { Get-PzVersionSortValue $_.Name }; Descending = $true } |
            Select-Object -First 1
        if ($latestVersion) {
            $infoCandidates += (Join-Path $latestVersion.FullName "mod.info")
            $version = [string]$latestVersion.Name
        }
    } catch {}

    foreach ($info in $infoCandidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $info)) { continue }
        try {
            foreach ($line in Get-Content -LiteralPath $info -Encoding UTF8 -ErrorAction SilentlyContinue) {
                if ($line -match '^\s*name\s*=\s*(.+?)\s*$') {
                    $name = [string]$Matches[1]
                } elseif ($line -match '^\s*id\s*=\s*(.+?)\s*$') {
                    $id = [string]$Matches[1]
                }
            }
        } catch {}
        break
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = Split-Path $modPath -Leaf
    }

    $translationRoots = @(Find-PzModContentRoots $modPath)
    $hasLocalization = ($translationRoots.Count -gt 0)

    $baseDisplay = if ([string]::IsNullOrWhiteSpace($workshopId)) {
        if ([string]::IsNullOrWhiteSpace($id)) { $name } else { "$name [$id]" }
    } else {
        "$name [Workshop $workshopId]"
    }

    $statusSuffix = if ($hasLocalization) { " [LOC OK]" } else { " [NO LOC]" }

    return [pscustomobject]@{
        Name = $name
        ModId = $id
        WorkshopId = $workshopId
        Version = $version
        Path = $modPath
        HasLocalization = $hasLocalization
        TranslationRoots = $translationRoots.Count
        Display = "$baseDisplay$statusSuffix"
    }
}

function Find-PzInstalledMods {
    $mods = New-Object System.Collections.ArrayList
    $seen = @{}

    function Add-DetectedPzMod([string]$path, [string]$fallbackName, [string]$workshopId) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) { return }

        try { $full = [System.IO.Path]::GetFullPath($path) } catch { $full = $path }
        $key = $full.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true

        [void]$mods.Add((Get-PzModInfo $path $fallbackName $workshopId))
    }

    $localRoot = Get-PzLocalModsRoot
    if ($localRoot) {
        foreach ($dir in Get-ChildItem -LiteralPath $localRoot -Directory -ErrorAction SilentlyContinue) {
            Add-DetectedPzMod $dir.FullName $dir.Name ""
        }
    }

    foreach ($workshopRoot in @(Get-PzWorkshopRoots)) {
        foreach ($item in Get-ChildItem -LiteralPath $workshopRoot -Directory -ErrorAction SilentlyContinue) {
            $wid = [string]$item.Name
            $itemMods = Join-Path $item.FullName "mods"

            if (Test-Path -LiteralPath $itemMods) {
                foreach ($modDir in Get-ChildItem -LiteralPath $itemMods -Directory -ErrorAction SilentlyContinue) {
                    Add-DetectedPzMod $modDir.FullName $modDir.Name $wid
                }
            } else {
                Add-DetectedPzMod $item.FullName $item.Name $wid
            }
        }
    }

    return @($mods | Sort-Object Name,WorkshopId)
}

function Refresh-PzDetectedModsCombo {
    if ($null -eq $cmbPzDetectedMods) { return }
    $cmbPzDetectedMods.Items.Clear()

    foreach ($mod in @($script:PzDetectedMods)) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = [string]$mod.Display
        $item.Tag = [string]$mod.Path
        $item.ToolTip = if ($mod.HasLocalization) {
            "$($mod.Path)`nLocalization roots: $($mod.TranslationRoots)"
        } else {
            "$($mod.Path)`nNo supported localization files detected."
        }
        [void]$cmbPzDetectedMods.Items.Add($item)
    }

    if ($cmbPzDetectedMods.Items.Count -gt 0) {
        $cmbPzDetectedMods.SelectedIndex = 0
    }
}

function Find-PzKnownModRoots {
    $roots = New-Object System.Collections.ArrayList

    $local = Get-PzLocalModsRoot
    if ($local) {
        [void]$roots.Add([pscustomobject]@{ Path=$local; Type="Local" })
    }

    foreach ($w in @(Get-PzWorkshopRoots)) {
        [void]$roots.Add([pscustomobject]@{ Path=$w; Type="Workshop" })
    }

    return @($roots)
}

function Find-PzModContentRoots([string]$selectedPath) {
    if ([string]::IsNullOrWhiteSpace($selectedPath) -or -not (Test-Path -LiteralPath $selectedPath)) {
        return @()
    }

    $found = New-Object System.Collections.ArrayList
    $seen = @{}

    function Add-PzRoot([string]$candidate, [string]$label) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { return }
        try { $candidate = [System.IO.Path]::GetFullPath($candidate) } catch {}
        if (-not (Test-PzTranslateRoot $candidate)) { return }

        $key = $candidate.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true

        [void]$found.Add([pscustomobject]@{
            Path = $candidate
            Label = $label
        })
    }

    function Inspect-PzModFolder([string]$modPath, [string]$labelPrefix) {
        if (-not (Test-Path -LiteralPath $modPath -PathType Container)) { return }

        Add-PzRoot $modPath $labelPrefix

        foreach ($v in @(
            Get-ChildItem -LiteralPath $modPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+){0,3}$' } |
            Sort-Object @{ Expression = { Get-PzVersionSortValue $_.Name }; Descending = $true }
        )) {
            Add-PzRoot $v.FullName "$labelPrefix/$($v.Name)"
        }
    }

    # Exact mod folder.
    Inspect-PzModFolder $selectedPath "root"

    # Workshop item or other package with mods/<mod-name>/...
    $modsRoot = Join-Path $selectedPath "mods"
    if (Test-Path -LiteralPath $modsRoot) {
        foreach ($modDir in Get-ChildItem -LiteralPath $modsRoot -Directory -ErrorAction SilentlyContinue) {
            Inspect-PzModFolder $modDir.FullName $modDir.Name
        }
    }

    # Root containing many local mods OR Steam Workshop content/108600.
    foreach ($direct in Get-ChildItem -LiteralPath $selectedPath -Directory -ErrorAction SilentlyContinue) {
        if ($direct.Name -eq "mods") { continue }

        Inspect-PzModFolder $direct.FullName $direct.Name

        if ($direct.Name -match '^\d+$') {
            $itemMods = Join-Path $direct.FullName "mods"
            if (Test-Path -LiteralPath $itemMods) {
                foreach ($modDir in Get-ChildItem -LiteralPath $itemMods -Directory -ErrorAction SilentlyContinue) {
                    Inspect-PzModFolder $modDir.FullName "$($direct.Name)/$($modDir.Name)"
                }
            }
        }
    }

    return @($found)
}

function ConvertFrom-PzJsonNode([object]$node, [string]$prefix="", [string]$fileName="") {
    $rows = New-Object System.Collections.ArrayList
    if ($null -eq $node) { return @() }

    if ($node -is [System.Collections.IDictionary]) {
        foreach ($key in $node.Keys) {
            $childPrefix = if ([string]::IsNullOrWhiteSpace($prefix)) { [string]$key } else { "$prefix.$key" }
            $childRows = @(ConvertFrom-PzJsonNode $node[$key] $childPrefix $fileName)
            foreach ($r in $childRows) { [void]$rows.Add($r) }
        }
        return @($rows)
    }

    if ($node -is [pscustomobject]) {
        foreach ($prop in $node.PSObject.Properties) {
            $childPrefix = if ([string]::IsNullOrWhiteSpace($prefix)) { [string]$prop.Name } else { "$prefix.$($prop.Name)" }
            $childRows = @(ConvertFrom-PzJsonNode $prop.Value $childPrefix $fileName)
            foreach ($r in $childRows) { [void]$rows.Add($r) }
        }
        return @($rows)
    }

    if (($node -is [System.Collections.IEnumerable]) -and -not ($node -is [string])) {
        $i = 0
        foreach ($item in $node) {
            $childPrefix = "$prefix[$i]"
            $childRows = @(ConvertFrom-PzJsonNode $item $childPrefix $fileName)
            foreach ($r in $childRows) { [void]$rows.Add($r) }
            $i++
        }
        return @($rows)
    }

    # Only string leaf values are translatable. Numbers/bools/null remain structure.
    if ($node -is [string]) {
        [void]$rows.Add([pscustomobject]@{
            Key = $prefix
            Value = [string]$node
            File = $fileName
        })
    }

    return @($rows)
}

function Read-PzJsonTranslationFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }

    try {
        $utf8Strict = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)
        $raw = [System.IO.File]::ReadAllText($path, $utf8Strict)
    } catch {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    }

    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    try {
        # Windows PowerShell 5.1 ConvertFrom-Json treats object keys
        # case-insensitively and rejects valid PZ files with names such as
        # Farming_Lemongrass and Farming_LemonGrass.
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $serializer.MaxJsonLength = [int]::MaxValue
        $serializer.RecursionLimit = 512
        $obj = $serializer.DeserializeObject($raw)
    } catch {
        throw "Invalid Project Zomboid JSON translation file: $path`n$($_.Exception.Message)"
    }

    return @(ConvertFrom-PzJsonNode $obj "" ([System.IO.Path]::GetFileName($path)))
}

function Get-PzTranslationFiles([string]$folder) {
    if (-not (Test-Path -LiteralPath $folder)) { return @() }

    $all = New-Object System.Collections.ArrayList
    foreach ($f in Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue) {
        if ($f.Extension -ieq ".txt" -or $f.Extension -ieq ".json") {
            [void]$all.Add($f)
        }
    }
    return @($all)
}


function Protect-PzMarkup([string]$text) {
    if ($null -eq $text) { return [pscustomobject]@{ Text=""; Map=@{} } }

    $map = @{}
    $index = 0
    $protected = [regex]::Replace(
        $text,
        '<[^<>]+>',
        {
            param($m)
            $token = "__PZTAG$index`__"
            $map[$token] = [string]$m.Value
            $script:__PzTmpIndex = $index + 1
            $index++
            return $token
        }
    )

    return [pscustomobject]@{
        Text = $protected
        Map = $map
    }
}

function Restore-PzMarkup([string]$translated, $map) {
    if ($null -eq $translated) { $translated = "" }
    $result = [string]$translated

    foreach ($key in $map.Keys) {
        $result = $result.Replace([string]$key, [string]$map[$key])
    }

    # Some providers may add spaces around token fragments. Repair conservative variants.
    foreach ($key in $map.Keys) {
        $compact = [regex]::Escape([string]$key)
        $result = [regex]::Replace($result, $compact, [string]$map[$key])
    }

    return $result
}

function Test-PzMarkupIntegrity([string]$source, [string]$translation) {
    $srcTags = @([regex]::Matches([string]$source, '<[^<>]+>') | ForEach-Object { $_.Value })
    $dstTags = @([regex]::Matches([string]$translation, '<[^<>]+>') | ForEach-Object { $_.Value })

    if ($translation -match '__MTTPH\d+__' -or $translation -match '__PZTAG\d+__') {
        return $false
    }

    if ($srcTags.Count -ne $dstTags.Count) { return $false }

    for ($i=0; $i -lt $srcTags.Count; $i++) {
        if ([string]$srcTags[$i] -cne [string]$dstTags[$i]) { return $false }
    }
    return $true
}

function Translate-PzText([string]$text, [string]$sourceCode, [string]$targetCode) {
    $pz = Protect-PzMarkup $text
    $translated = Translate-Configured ([string]$pz.Text) $sourceCode $targetCode
    $restored = Restore-PzMarkup ([string]$translated) $pz.Map

    if (-not (Test-PzMarkupIntegrity $text $restored)) {
        throw $(if ($script:UiLanguage -eq "en") {
            "Project Zomboid markup validation failed after translation."
        } else {
            "Walidacja znaczników Project Zomboid po tłumaczeniu nie powiodła się."
        })
    }

    return $restored
}

function ConvertFrom-PzQuotedValue([string]$value) {
    if ($null -eq $value) { return "" }
    return $value.Replace('\"','"').Replace("\\'","'").Replace('\\\\','\\')
}

function Read-PzTranslationFolder([string]$contentRoot, [string]$rootLabel, [string]$pzCode, [string]$role) {
    $rows = New-Object System.Collections.ArrayList
    $folder = Join-Path $contentRoot "media\lua\shared\Translate\$pzCode"
    if (-not (Test-Path -LiteralPath $folder)) { return @() }

    foreach ($f in @(Get-PzTranslationFiles $folder)) {
        # Legacy Recorded_Media TXT remains a special generated format.
        if ($f.Name -like "Recorded_Media_*" -and $f.Extension -ieq ".txt") { continue }

        if ($f.Extension -ieq ".json") {
            foreach ($jr in @(Read-PzJsonTranslationFile $f.FullName)) {
                [void]$rows.Add([pscustomobject]@{
                    Root = $rootLabel
                    File = [System.IO.Path]::GetFileName($f.FullName)
                    Key = [string]$jr.Key
                    Source = if ($role -eq "Source") { [string]$jr.Value } else { "" }
                    Translation = if ($role -eq "Target") { [string]$jr.Value } else { "" }
                    Line = 0
                    Format = "JSON"
                })
            }
            continue
        }

        $lineNo = 0
        foreach ($line in Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue) {
            $lineNo++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $key = $null
            $value = $null

            if ($line -match '^\s*([A-Za-z0-9_.\-\[\]]+)\s*=\s*"((?:\\.|[^"])*)"\s*,?\s*$') {
                $key = [string]$Matches[1]
                $value = ConvertFrom-PzQuotedValue ([string]$Matches[2])
            } elseif ($line -match "^\s*([A-Za-z0-9_.\-\[\]]+)\s*=\s*'((?:\\.|[^'])*)'\s*,?\s*$") {
                $key = [string]$Matches[1]
                $value = ConvertFrom-PzQuotedValue ([string]$Matches[2])
            }

            if ([string]::IsNullOrWhiteSpace($key)) { continue }

            [void]$rows.Add([pscustomobject]@{
                Root = $rootLabel
                File = [System.IO.Path]::GetFileName($f.FullName)
                Key = $key
                Source = if ($role -eq "Source") { $value } else { "" }
                Translation = if ($role -eq "Target") { $value } else { "" }
                Line = $lineNo
                Format = "TXT"
            })
        }
    }

    return @($rows)
}

function Get-PzEntryIdentity($entry) {
    return "$($entry.Root)|$($entry.File)|$($entry.Key)"
}

function Refresh-PzGrid {
    if ($null -eq $pzGrid) { return }
    $pzGrid.ItemsSource = $null
    $pzGrid.ItemsSource = @($script:PzEntries)
    if ($null -ne $lblPzCount) {
        $lblPzCount.Content = if ($script:UiLanguage -eq "en") {
            "Entries: $($script:PzEntries.Count)"
        } else {
            "Wpisy: $($script:PzEntries.Count)"
        }
    }
}

function Scan-PzMod([string]$selectedPath) {
    if (Test-IsPzToolkitTranslationMod $selectedPath) {
        return Scan-PzToolkitTranslationMod $selectedPath
    }

    $script:PzEditingTranslationPath = ""
    $sourceLang = Get-PzSelectedLanguage $cmbPzSourceLang
    $targetLang = Get-PzSelectedLanguage $cmbPzTargetLang
    if ($null -eq $sourceLang -or $null -eq $targetLang) { return $null }

    if ($sourceLang.Code -ieq $targetLang.Code) {
        throw $(if ($script:UiLanguage -eq "en") {
            "Source and target language must be different."
        } else {
            "Jezyk zrodlowy i docelowy musza byc rozne."
        })
    }

    $srcCode = Get-PzLanguageCode ([string]$sourceLang.Code)
    $dstCode = Get-PzLanguageCode ([string]$targetLang.Code)

    $roots = @(Find-PzModContentRoots $selectedPath)
    if ($roots.Count -eq 0) {
        throw $(if ($script:UiLanguage -eq "en") {
            "No Project Zomboid translation root was found. Expected media/lua/shared/Translate, optionally inside a B42 version folder."
        } else {
            "Nie znaleziono katalogu tlumaczen Project Zomboid. Oczekiwano media/lua/shared/Translate, opcjonalnie w wersjonowanym folderze B42."
        })
    }

    $result = New-Object System.Collections.ArrayList
    $matched = 0
    $targetCount = 0

    foreach ($root in $roots) {
        $sourceRows = @(Read-PzTranslationFolder $root.Path $root.Label $srcCode "Source")
        $targetRows = @(Read-PzTranslationFolder $root.Path $root.Label $dstCode "Target")
        $targetCount += $targetRows.Count

        $targetMap = @{}
        foreach ($r in $targetRows) {
            $targetMap[(Get-PzEntryIdentity $r).ToLowerInvariant()] = [string]$r.Translation
        }

        foreach ($r in $sourceRows) {
            $id = (Get-PzEntryIdentity $r).ToLowerInvariant()
            if ($targetMap.ContainsKey($id)) {
                $r.Translation = [string]$targetMap[$id]
                $matched++
            }
            [void]$result.Add($r)
        }
    }

    $script:PzEntries = @($result)
    $script:PzContentRoots = @($roots)
    Refresh-PzGrid

    if ($pzGrid.Columns.Count -ge 5) {
        $pzGrid.Columns[3].Header = [string]$sourceLang.NativeName
        $pzGrid.Columns[4].Header = [string]$targetLang.NativeName
    }

    $status = if ($script:UiLanguage -eq "en") {
        "Scan complete. Roots: $($roots.Count), source entries: $($result.Count), target entries: $targetCount, matched: $matched. TXT + JSON."
    } else {
        "Skan zakonczony. Rooty: $($roots.Count), wpisy zrodlowe: $($result.Count), wpisy docelowe: $targetCount, dopasowane: $matched. TXT + JSON."
    }
    $txtPzStatus.Text = $status

    return [pscustomobject]@{
        Roots = $roots.Count
        SourceEntries = $result.Count
        TargetEntries = $targetCount
        Matched = $matched
    }
}


function Get-PzTargetFolderCode {
    $lang = Get-PzSelectedLanguage $cmbPzTargetLang
    if ($null -eq $lang) { return "PL" }
    return Get-PzLanguageCode ([string]$lang.Code)
}


function Get-PzTranslationMetadata([string]$modPath) {
    if ([string]::IsNullOrWhiteSpace($modPath)) { return $null }
    $metaPath = Join-Path $modPath "ModTranslationToolkit.json"
    if (-not (Test-Path -LiteralPath $metaPath)) { return $null }

    try {
        return Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-IsPzToolkitTranslationMod([string]$modPath) {
    $meta = Get-PzTranslationMetadata $modPath
    return ($null -ne $meta -and -not [string]::IsNullOrWhiteSpace([string]$meta.OriginalModId))
}

function Resolve-PzOriginalModPathFromMetadata($meta) {
    if ($null -eq $meta) { return $null }

    $savedPath = [string]$meta.OriginalPath
    if (-not [string]::IsNullOrWhiteSpace($savedPath) -and (Test-Path -LiteralPath $savedPath)) {
        return $savedPath
    }

    $wantedWorkshop = [string]$meta.OriginalWorkshopId
    $wantedModId = [string]$meta.OriginalModId

    foreach ($m in @($script:PzDetectedMods)) {
        if (-not [string]::IsNullOrWhiteSpace($wantedWorkshop) -and [string]$m.WorkshopId -eq $wantedWorkshop) {
            return [string]$m.Path
        }
        if (-not [string]::IsNullOrWhiteSpace($wantedModId) -and [string]$m.ModId -eq $wantedModId) {
            return [string]$m.Path
        }
    }

    return $null
}

function Scan-PzToolkitTranslationMod([string]$translationModPath) {
    $meta = Get-PzTranslationMetadata $translationModPath
    if ($null -eq $meta) {
        throw "Missing ModTranslationToolkit.json."
    }

    $originalPath = Resolve-PzOriginalModPathFromMetadata $meta
    if ([string]::IsNullOrWhiteSpace($originalPath) -or -not (Test-Path -LiteralPath $originalPath)) {
        throw $(if ($script:UiLanguage -eq "en") {
            "The original Project Zomboid mod could not be found. Detect installed mods again or restore the original mod."
        } else {
            "Nie znaleziono oryginalnego moda Project Zomboid. Wykryj ponownie zainstalowane mody albo przywróć oryginalny mod."
        })
    }

    $sourceLang = Get-PzSelectedLanguage $cmbPzSourceLang
    $targetLang = Get-PzSelectedLanguage $cmbPzTargetLang
    if ($null -eq $sourceLang -or $null -eq $targetLang) { return $null }

    $srcCode = Get-PzLanguageCode ([string]$sourceLang.Code)
    $dstCode = Get-PzLanguageCode ([string]$targetLang.Code)

    $sourceRoots = @(Find-PzModContentRoots $originalPath)
    $targetRoots = @(Find-PzModContentRoots $translationModPath)

    if ($sourceRoots.Count -eq 0) {
        throw "Original mod has no supported Project Zomboid translation roots."
    }

    $targetByLabel = @{}
    foreach ($r in $targetRoots) {
        $targetByLabel[[string]$r.Label] = $r
    }

    $result = New-Object System.Collections.ArrayList
    $targetCount = 0
    $matched = 0

    foreach ($sourceRoot in $sourceRoots) {
        $sourceRows = @(Read-PzTranslationFolder $sourceRoot.Path $sourceRoot.Label $srcCode "Source")

        $targetRows = @()
        if ($targetByLabel.ContainsKey([string]$sourceRoot.Label)) {
            $targetRoot = $targetByLabel[[string]$sourceRoot.Label]
            $targetRows = @(Read-PzTranslationFolder $targetRoot.Path $targetRoot.Label $dstCode "Target")
        }
        $targetCount += $targetRows.Count

        $targetMap = @{}
        foreach ($r in $targetRows) {
            $targetMap[(Get-PzEntryIdentity $r).ToLowerInvariant()] = [string]$r.Translation
        }

        foreach ($r in $sourceRows) {
            $id = (Get-PzEntryIdentity $r).ToLowerInvariant()
            if ($targetMap.ContainsKey($id)) {
                $r.Translation = [string]$targetMap[$id]
                $matched++
            }
            [void]$result.Add($r)
        }
    }

    $script:PzEntries = @($result)
    $script:PzContentRoots = @($sourceRoots)
    $script:PzEditingTranslationPath = $translationModPath

    Refresh-PzGrid

    if ($pzGrid.Columns.Count -ge 5) {
        $pzGrid.Columns[3].Header = [string]$sourceLang.NativeName
        $pzGrid.Columns[4].Header = [string]$targetLang.NativeName
    }

    $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
        "Opened Toolkit translation. Source: $($meta.OriginalName) | source entries: $($result.Count) | target entries: $targetCount | matched: $matched"
    } else {
        "Otwarto translację Toolkita. Źródło: $($meta.OriginalName) | wpisy źródłowe: $($result.Count) | wpisy targetu: $targetCount | dopasowane: $matched"
    }

    return [pscustomobject]@{
        Roots = $sourceRoots.Count
        SourceEntries = $result.Count
        TargetEntries = $targetCount
        Matched = $matched
        OriginalPath = $originalPath
    }
}

function Get-PzCurrentDetectedModInfo {
    $path = [string]$txtPzModPath.Text
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }

    foreach ($m in @($script:PzDetectedMods)) {
        if ([string]$m.Path -ieq $path) { return $m }
    }

    $workshopId = ""
    try {
        if ($path -match '[\\/]workshop[\\/]content[\\/]108600[\\/]([0-9]+)[\\/]') {
            $workshopId = [string]$Matches[1]
        }
    } catch {}

    return Get-PzModInfo $path (Split-Path $path -Leaf) $workshopId
}


function Find-PzModInfoFiles([string]$sourceModPath) {
    if ([string]::IsNullOrWhiteSpace($sourceModPath) -or -not (Test-Path -LiteralPath $sourceModPath)) {
        return @()
    }

    $files = New-Object System.Collections.ArrayList

    foreach ($f in Get-ChildItem -LiteralPath $sourceModPath -File -Filter "mod.info" -Recurse -ErrorAction SilentlyContinue) {
        # Ignore accidental nested copies outside sensible B42 roots.
        $rel = $f.FullName.Substring($sourceModPath.TrimEnd('\').Length).TrimStart('\')
        if ($rel -match '^(mod\.info|common\\mod\.info|\d+(\.\d+){0,3}\\mod\.info)$') {
            [void]$files.Add([pscustomobject]@{
                Path = $f.FullName
                RelativePath = $rel
                Root = if ($rel -eq "mod.info") { "" } else { Split-Path $rel -Parent }
            })
        }
    }

    return @($files)
}

function Get-PzPreferredModInfo([string]$sourceModPath) {
    $files = @(Find-PzModInfoFiles $sourceModPath)
    if ($files.Count -eq 0) { return $null }

    # Prefer newest numeric B42 version, then root mod.info, then common.
    $numeric = @(
        $files | Where-Object { $_.Root -match '^\d+(\.\d+){0,3}$' } |
        Sort-Object @{ Expression = {
            try { [version]$_.Root } catch { [version]"0.0" }
        }; Descending = $true }
    )
    if ($numeric.Count -gt 0) { return $numeric[0] }

    $rootInfo = $files | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Root) } | Select-Object -First 1
    if ($rootInfo) { return $rootInfo }

    return $files | Select-Object -First 1
}

function Copy-PzStructureSkeleton([string]$sourceModPath, [string]$outMod) {
    # Copy metadata/container structure only. Do not copy gameplay files.
    $infoFiles = @(Find-PzModInfoFiles $sourceModPath)

    foreach ($info in $infoFiles) {
        $dest = Join-Path $outMod $info.RelativePath
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $info.Path -Destination $dest -Force
    }

    # Preserve source poster/preview only as source for generated poster.
    foreach ($candidate in @("poster.png","preview.png")) {
        $src = Join-Path $sourceModPath $candidate
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $outMod $candidate) -Force
            break
        }
    }

    # Preserve empty version/common roots if present so the layout mirrors source.
    foreach ($dir in Get-ChildItem -LiteralPath $sourceModPath -Directory -ErrorAction SilentlyContinue) {
        if ($dir.Name -eq "common" -or $dir.Name -match '^\d+(\.\d+){0,3}$') {
            New-Item -ItemType Directory -Path (Join-Path $outMod $dir.Name) -Force | Out-Null
        }
    }
}

function Update-PzModInfoFile(
    [string]$path,
    [string]$displayName,
    [string]$translationId,
    [string]$originalModId,
    [string]$targetName
) {
    $lines = @()
    if (Test-Path -LiteralPath $path) {
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    }

    $output = New-Object System.Collections.ArrayList
    $seenName = $false
    $seenId = $false
    $seenPoster = $false
    $seenRequire = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*name\s*=') {
            if (-not $seenName) {
                [void]$output.Add("name=$displayName")
                $seenName = $true
            }
            continue
        }

        if ($line -match '^\s*id\s*=') {
            if (-not $seenId) {
                [void]$output.Add("id=$translationId")
                $seenId = $true
            }
            continue
        }

        if ($line -match '^\s*description\s*=') {
            # Drop every source description line. A single clean translation
            # description is added below so inherited multiline descriptions
            # cannot repeat our suffix several times.
            continue
        }

        if ($line -match '^\s*poster\s*=') {
            if (-not $seenPoster) {
                [void]$output.Add("poster=poster.png")
                $seenPoster = $true
            }
            continue
        }

        if ($line -match '^\s*require\s*=') {
            if (-not $seenRequire -and -not [string]::IsNullOrWhiteSpace($originalModId)) {
                [void]$output.Add("require=$originalModId")
                $seenRequire = $true
            }
            continue
        }

        # Do not inherit gameplay/package declarations from the source mod.
        if ($line -match '^\s*(pack|tiledef|versionMin|versionMax)\s*=') {
            continue
        }

        [void]$output.Add($line)
    }

    if (-not $seenName) { [void]$output.Add("name=$displayName") }
    if (-not $seenId) { [void]$output.Add("id=$translationId") }

    # Always write exactly one clean description.
    [void]$output.Add("description=$targetName translation for the original mod. Created with Mod Translation Toolkit.")

    if (-not $seenPoster) { [void]$output.Add("poster=poster.png") }
    if (-not $seenRequire -and -not [string]::IsNullOrWhiteSpace($originalModId)) {
        [void]$output.Add("require=$originalModId")
    }

    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllLines(
        $path,
        [string[]]$output,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )
}

function Install-PzPosterBesideModInfos([string]$outMod, [string]$rootPoster) {
    if (-not (Test-Path -LiteralPath $rootPoster)) { return }

    foreach ($info in @(Find-PzModInfoFiles $outMod)) {
        $dir = Split-Path $info.Path -Parent
        $dest = Join-Path $dir "poster.png"

        if ($dest -ine $rootPoster) {
            Copy-Item -LiteralPath $rootPoster -Destination $dest -Force
        }
    }
}


function Get-PzLocalInstallRoot {
    $root = Join-Path $env:USERPROFILE "Zomboid\mods"
    if (-not (Test-Path -LiteralPath $root)) {
        try { New-Item -ItemType Directory -Path $root -Force | Out-Null } catch {}
    }
    return $root
}

function Get-PzBuildVersionRoot([string]$sourceModPath) {
    # Preserve the newest numeric B42 folder if one is present.
    try {
        $latest = Get-ChildItem -LiteralPath $sourceModPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+){0,3}$' } |
            Sort-Object @{ Expression = { Get-PzVersionSortValue $_.Name }; Descending = $true } |
            Select-Object -First 1

        if ($latest) { return [string]$latest.Name }
    } catch {}

    # If the localization lives in common/, keep common as the shared root.
    if (Test-Path -LiteralPath (Join-Path $sourceModPath "common")) { return "common" }

    # B42-safe fallback.
    return "42"
}

function Get-PzTranslationBuildId([string]$originalId, [string]$targetCode) {
    $creator = Get-ToolkitCreatorId
    $creator = ($creator -replace '[^a-zA-Z0-9_.-]', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($creator)) { $creator = "mtt" }

    $base = $originalId
    if ([string]::IsNullOrWhiteSpace($base)) { $base = "projectzomboidmod" }
    $base = ($base -replace '[^a-zA-Z0-9_.-]', '').ToLowerInvariant()

    return "$base.translation.$creator.$($targetCode.ToLowerInvariant())"
}

function Convert-PzJsonForOutput([object]$node, [string]$prefix, $translationMap) {
    if ($null -eq $node) { return $null }

    if ($node -is [System.Collections.IDictionary]) {
        $result = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($key in $node.Keys) {
            $childPrefix = if ([string]::IsNullOrWhiteSpace($prefix)) { [string]$key } else { "$prefix.$key" }
            $result[[string]$key] = Convert-PzJsonForOutput $node[$key] $childPrefix $translationMap
        }
        return $result
    }

    if (($node -is [System.Collections.IEnumerable]) -and -not ($node -is [string])) {
        $list = New-Object System.Collections.ArrayList
        $i = 0
        foreach ($item in $node) {
            $childPrefix = "$prefix[$i]"
            [void]$list.Add((Convert-PzJsonForOutput $item $childPrefix $translationMap))
            $i++
        }
        return ,$list.ToArray()
    }

    if ($node -is [string]) {
        if ($translationMap.ContainsKey($prefix) -and
            -not [string]::IsNullOrWhiteSpace([string]$translationMap[$prefix])) {
            return [string]$translationMap[$prefix]
        }
        return [string]$node
    }

    return $node
}

function Write-PzJsonTranslationFile([string]$sourceFile, [string]$destFile, $translationMap) {
    $utf8Strict = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)
    $raw = [System.IO.File]::ReadAllText($sourceFile, $utf8Strict)

    Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $serializer.RecursionLimit = 512

    $obj = $serializer.DeserializeObject($raw)
    $outObj = Convert-PzJsonForOutput $obj "" $translationMap
    $json = $serializer.Serialize($outObj)

    # Pretty-print is intentionally avoided here: JavaScriptSerializer keeps
    # case-sensitive keys safely and Project Zomboid only needs valid UTF-8 JSON.
    New-Item -ItemType Directory -Path (Split-Path $destFile -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($destFile, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
}

function Write-PzTxtTranslationFile([string]$sourceFile, [string]$destFile, $translationMap) {
    $lines = @(Get-Content -LiteralPath $sourceFile -Encoding UTF8)
    $out = New-Object System.Collections.ArrayList

    foreach ($line in $lines) {
        $written = $false

        if ($line -match '^\s*([A-Za-z0-9_.\-\[\]]+)\s*=\s*"((?:\\.|[^"])*)"\s*,?\s*$') {
            $key = [string]$Matches[1]
            if ($translationMap.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$translationMap[$key])) {
                $value = [string]$translationMap[$key]
                $value = $value.Replace('\','\\').Replace('"','\"')
                $indent = [regex]::Match($line,'^\s*').Value
                $comma = if ($line.TrimEnd().EndsWith(',')) { ',' } else { '' }
                [void]$out.Add("$indent$key = `"$value`"$comma")
                $written = $true
            }
        }

        if (-not $written) { [void]$out.Add($line) }
    }

    New-Item -ItemType Directory -Path (Split-Path $destFile -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllLines($destFile, [string[]]$out, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
}

function New-PzTranslationPoster([string]$sourceModPath, [string]$destPath, [string]$targetCode) {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $bmp = New-Object System.Drawing.Bitmap 256,256
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(18,16,24))
        $x=28; $y=58; $w=200; $h=120
        $g.FillRectangle([System.Drawing.Brushes]::White,$x,$y,$w,[int]($h/2))
        $g.FillRectangle([System.Drawing.Brushes]::Red,$x,$y+[int]($h/2),$w,$h-[int]($h/2))
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230,235,235,235),3)
        $g.DrawRectangle($pen,$x,$y,$w,$h); $pen.Dispose()
        $font = New-Object System.Drawing.Font("Segoe UI",14,[System.Drawing.FontStyle]::Bold)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF(18,196,220,34)
        $g.DrawString("POLISH TRANSLATION",$font,$brush,$rect,$fmt)
        $font.Dispose(); $brush.Dispose(); $fmt.Dispose()
    } finally { $g.Dispose() }
    New-Item -ItemType Directory -Path (Split-Path $destPath -Parent) -Force | Out-Null
    $bmp.Save($destPath,[System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function New-PzWorkshopPreview([string]$sourceImage, [string]$destPath) {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $bmp = New-Object System.Drawing.Bitmap 256,256
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::Black)
        if (Test-Path -LiteralPath $sourceImage) {
            $img = [System.Drawing.Image]::FromFile($sourceImage)
            try {
                $scale=[math]::Min(256.0/$img.Width,256.0/$img.Height)
                $w=[int]($img.Width*$scale); $h=[int]($img.Height*$scale)
                $x=[int]((256-$w)/2); $y=[int]((256-$h)/2)
                $g.DrawImage($img,$x,$y,$w,$h)
            } finally { $img.Dispose() }
        }
        $fw=58; $fh=36; $fx=188; $fy=210
        $g.FillRectangle([System.Drawing.Brushes]::White,$fx,$fy,$fw,[int]($fh/2))
        $g.FillRectangle([System.Drawing.Brushes]::Red,$fx,$fy+[int]($fh/2),$fw,$fh-[int]($fh/2))
        $pen=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235,20,20,20),2)
        $g.DrawRectangle($pen,$fx,$fy,$fw,$fh); $pen.Dispose()
        New-Item -ItemType Directory -Path (Split-Path $destPath -Parent) -Force | Out-Null
        $bmp.Save($destPath,[System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $g.Dispose(); $bmp.Dispose() }
}

function Test-PzWorkshopStage([string]$stagePath) {
    $issues = New-Object System.Collections.ArrayList

    if (-not (Test-Path -LiteralPath (Join-Path $stagePath "Contents"))) {
        [void]$issues.Add("Missing Contents folder")
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stagePath "Contents\mods"))) {
        [void]$issues.Add("Missing Contents\\mods folder")
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stagePath "preview.png"))) {
        [void]$issues.Add("Missing preview.png")
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stagePath "workshop.txt"))) {
        [void]$issues.Add("Missing workshop.txt")
    }

    $modsRoot = Join-Path $stagePath "Contents\mods"
    if (Test-Path -LiteralPath $modsRoot) {
        $mods = @(Get-ChildItem -LiteralPath $modsRoot -Directory -ErrorAction SilentlyContinue)
        if ($mods.Count -eq 0) {
            [void]$issues.Add("No mod folder inside Contents\\mods")
        }

        foreach ($m in $mods) {
            if (-not (Test-Path -LiteralPath (Join-Path $m.FullName "mod.info"))) {
                [void]$issues.Add("Missing root mod.info: $($m.Name)")
            }

            $versionInfos = @(Get-ChildItem -LiteralPath $m.FullName -Filter "mod.info" -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -ne (Join-Path $m.FullName "mod.info") })
            if ($versionInfos.Count -eq 0) {
                [void]$issues.Add("Missing versioned mod.info: $($m.Name)")
            }
        }
    }

    return @($issues)
}

function Get-PzPublishedWorkshopId([string]$translationModPath) {
    $meta = Get-PzTranslationMetadata $translationModPath
    if ($null -eq $meta) { return "" }
    try { return [string]$meta.TranslationWorkshopId } catch { return "" }
}

function Set-PzPublishedWorkshopId([string]$translationModPath, [string]$workshopId) {
    if ([string]::IsNullOrWhiteSpace($translationModPath) -or -not (Test-Path -LiteralPath $translationModPath) -or
        [string]::IsNullOrWhiteSpace($workshopId) -or $workshopId -notmatch '^\d+$') { return $false }
    $metaPath = Join-Path $translationModPath "ModTranslationToolkit.json"
    if (-not (Test-Path -LiteralPath $metaPath)) { return $false }
    try {
        $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $meta | Add-Member -NotePropertyName TranslationWorkshopId -NotePropertyValue $workshopId -Force
        [System.IO.File]::WriteAllText($metaPath,($meta | ConvertTo-Json -Depth 6),(New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
        return $true
    } catch { return $false }
}

function New-PzWorkshopStage(
    [string]$builtModPath,
    [string]$displayName,
    [string]$descriptionText
) {
    if ([string]::IsNullOrWhiteSpace($builtModPath) -or -not (Test-Path -LiteralPath $builtModPath)) {
        throw "Built Project Zomboid mod path is invalid."
    }

    $stageRoot = Get-PzWorkshopStageRoot
    $folderName = ($displayName -replace '[\\/:*?"<>|]', '_')
    $stagePath = Join-Path $stageRoot $folderName

    if (Test-Path -LiteralPath $stagePath) {
        Remove-Item -LiteralPath $stagePath -Recurse -Force
    }

    $contentsMods = Join-Path $stagePath "Contents\mods"
    $innerName = Split-Path $builtModPath -Leaf
    $innerDest = Join-Path $contentsMods $innerName

    New-Item -ItemType Directory -Path $contentsMods -Force | Out-Null
    Copy-Item -LiteralPath $builtModPath -Destination $innerDest -Recurse -Force

    # B42 Workshop uploader expects a mod.info directly in
    # Contents\mods\<ModName> as well as versioned 42/42.x metadata.
    $rootInfo = Join-Path $innerDest "mod.info"
    if (-not (Test-Path -LiteralPath $rootInfo)) {
        $preferred = Get-PzPreferredModInfo $innerDest
        if ($null -ne $preferred -and (Test-Path -LiteralPath $preferred.Path)) {
            Copy-Item -LiteralPath $preferred.Path -Destination $rootInfo -Force
        } else {
            throw "Workshop package could not create root mod.info."
        }
    }

    $rootPoster = Join-Path $innerDest "poster.png"
    if (-not (Test-Path -LiteralPath $rootPoster)) {
        $candidatePoster = Get-ChildItem -LiteralPath $innerDest -Filter "poster.png" -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidatePoster) {
            Copy-Item -LiteralPath $candidatePoster.FullName -Destination $rootPoster -Force
        }
    }

    $poster = Join-Path $builtModPath "poster.png"
    New-PzWorkshopPreview $poster (Join-Path $stagePath "preview.png")

    $publishedId = Get-PzPublishedWorkshopId $builtModPath
    $workshopTxt = @"
version=1
id=$publishedId
title=$displayName
description=$descriptionText
tags=Translation
visibility=public
"@

    [System.IO.File]::WriteAllText(
        (Join-Path $stagePath "workshop.txt"),
        $workshopTxt,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )

    $stageIssues = @(Test-PzWorkshopStage $stagePath)
    if ($stageIssues.Count -gt 0) {
        throw ("Workshop package validation failed: " + ($stageIssues -join "; "))
    }

    return $stagePath
}

function Build-PzTranslationMod([string]$parentFolder) {
    if ($script:PzEntries.Count -eq 0) {
        throw "No Project Zomboid entries are loaded."
    }

    $selectedPath = [string]$txtPzModPath.Text
    if ([string]::IsNullOrWhiteSpace($selectedPath) -or -not (Test-Path -LiteralPath $selectedPath)) {
        throw "Project Zomboid source mod folder is invalid."
    }

    $sourceModPath = $selectedPath
    $mod = $null

    if (Test-IsPzToolkitTranslationMod $selectedPath) {
        $metaExisting = Get-PzTranslationMetadata $selectedPath
        $resolvedOriginal = Resolve-PzOriginalModPathFromMetadata $metaExisting

        if ([string]::IsNullOrWhiteSpace($resolvedOriginal) -or -not (Test-Path -LiteralPath $resolvedOriginal)) {
            throw "Could not resolve the original Project Zomboid mod."
        }

        $sourceModPath = $resolvedOriginal
        $mod = Get-PzModInfo $sourceModPath ([string]$metaExisting.OriginalName) ([string]$metaExisting.OriginalWorkshopId)
        $script:PzEditingTranslationPath = $selectedPath
    } else {
        $mod = Get-PzCurrentDetectedModInfo
    }

    if ($null -eq $mod) {
        throw "Could not resolve Project Zomboid mod metadata."
    }

    $preferredInfo = Get-PzPreferredModInfo $sourceModPath
    if ($null -eq $preferredInfo) {
        throw "The selected Project Zomboid mod does not contain a supported mod.info layout."
    }

    $targetLang = Get-PzSelectedLanguage $cmbPzTargetLang
    $targetCode = Get-PzTargetFolderCode
    $targetName = if ($null -ne $targetLang) { [string]$targetLang.DisplayEnglish } else { "Polish" }

    $displayName = "$($mod.Name) - $targetName Translation"
    $safeName = ($displayName -replace '[\\/:*?"<>|]', '_')

    if (-not [string]::IsNullOrWhiteSpace([string]$script:PzEditingTranslationPath) -and
        (Test-Path -LiteralPath $script:PzEditingTranslationPath)) {
        $outMod = [string]$script:PzEditingTranslationPath
        Remove-Item -LiteralPath $outMod -Recurse -Force
        New-Item -ItemType Directory -Path $outMod -Force | Out-Null
    } else {
        $outMod = Join-Path $parentFolder $safeName
        if (Test-Path -LiteralPath $outMod) {
            Remove-Item -LiteralPath $outMod -Recurse -Force
        }
        New-Item -ItemType Directory -Path $outMod -Force | Out-Null
    }

    Copy-PzStructureSkeleton $sourceModPath $outMod

    $translationId = Get-PzTranslationBuildId ([string]$mod.ModId) ([string](Get-PzSelectedLanguage $cmbPzTargetLang).Code)

    $copiedInfos = @(Find-PzModInfoFiles $outMod)
    if ($copiedInfos.Count -eq 0) {
        $fallbackInfo = Join-Path $outMod $preferredInfo.RelativePath
        New-Item -ItemType Directory -Path (Split-Path $fallbackInfo -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText(
            $fallbackInfo,
            "",
            (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
        )
        $copiedInfos = @(Find-PzModInfoFiles $outMod)
    }

    foreach ($info in $copiedInfos) {
        Update-PzModInfoFile $info.Path $displayName $translationId ([string]$mod.ModId) $targetName
    }

    $groups = @($script:PzEntries | Group-Object Root,File)

    foreach ($group in $groups) {
        $first = $group.Group | Select-Object -First 1
        $rootLabel = [string]$first.Root
        $fileName = [string]$first.File
        $format = [string]$first.Format

        $sourceRoot = $script:PzContentRoots | Where-Object { $_.Label -eq $rootLabel } | Select-Object -First 1
        if ($null -eq $sourceRoot) { continue }

        $srcLang = Get-PzSelectedLanguage $cmbPzSourceLang
        $srcCode = Get-PzLanguageCode ([string]$srcLang.Code)
        $sourceFile = Join-Path $sourceRoot.Path "media\lua\shared\Translate\$srcCode\$fileName"
        if (-not (Test-Path -LiteralPath $sourceFile)) { continue }

        $contentRel = ""
        try {
            $contentRel = $sourceRoot.Path.Substring($sourceModPath.TrimEnd('\').Length).TrimStart('\')
        } catch {}

        $outRoot = if ([string]::IsNullOrWhiteSpace($contentRel)) {
            $outMod
        } else {
            Join-Path $outMod $contentRel
        }

        $destFile = Join-Path $outRoot "media\lua\shared\Translate\$targetCode\$fileName"

        $map = @{}
        foreach ($e in $group.Group) {
            $value = if ([string]::IsNullOrWhiteSpace([string]$e.Translation)) {
                [string]$e.Source
            } else {
                [string]$e.Translation
            }
            $map[[string]$e.Key] = $value
        }

        if ($format -eq "JSON" -or $fileName.ToLowerInvariant().EndsWith(".json")) {
            Write-PzJsonTranslationFile $sourceFile $destFile $map
        } else {
            Write-PzTxtTranslationFile $sourceFile $destFile $map
        }
    }

    $rootPoster = Join-Path $outMod "poster.png"
    New-PzTranslationPoster $sourceModPath $rootPoster $targetCode
    Install-PzPosterBesideModInfos $outMod $rootPoster

    $originalWorkshopUrl = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$mod.WorkshopId)) {
        $originalWorkshopUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($mod.WorkshopId)"
    }

    $workshop = @"
[h1]$displayName[/h1]

$targetName translation for [b]$($mod.Name)[/b].

[b]Target language:[/b] $targetName
[b]Original mod ID:[/b] $($mod.ModId)
[b]Original Workshop ID:[/b] $($mod.WorkshopId)

This mod contains localization files only and requires the original mod.

Original mod:
$originalWorkshopUrl

Created with Mod Translation Toolkit.
https://github.com/DrizztGaming/Mod-Translation-Toolkit
"@

    $workshopPath = Join-Path $outMod "SteamWorkshopDescription.txt"
    [System.IO.File]::WriteAllText(
        $workshopPath,
        $workshop,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )

    $meta = [pscustomobject]@{
        ToolkitVersion = $AppVersion
        OriginalName = [string]$mod.Name
        OriginalModId = [string]$mod.ModId
        OriginalWorkshopId = [string]$mod.WorkshopId
        TranslationWorkshopId = Get-PzPublishedWorkshopId $selectedPath
        OriginalPath = $sourceModPath
        SourcePreferredModInfo = [string]$preferredInfo.RelativePath
        TranslationId = $translationId
        TargetLanguage = [string](Get-PzSelectedLanguage $cmbPzTargetLang).Code
        BuiltAt = (Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 4

    [System.IO.File]::WriteAllText(
        (Join-Path $outMod "ModTranslationToolkit.json"),
        $meta,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )

    $stageDescription = "$targetName translation for $($mod.Name). Requires the original mod."
    $workshopStage = New-PzWorkshopStage $outMod $displayName $stageDescription

    $script:PzEditingTranslationPath = $outMod
    $script:PzLastBuildPath = $outMod
    $script:PzLastWorkshopDescriptionPath = $workshopPath
    $script:PzLastWorkshopStagePath = $workshopStage
    return $outMod
}


function Export-PzCsv([string]$path) {
    $sourceLang = Get-PzSelectedLanguage $cmbPzSourceLang
    $targetLang = Get-PzSelectedLanguage $cmbPzTargetLang

    $src = if ($null -ne $sourceLang) { [string]$sourceLang.Code } else { "" }
    $dst = if ($null -ne $targetLang) { [string]$targetLang.Code } else { "" }

    $rows = @(
        $script:PzEntries |
            Select-Object Root,File,Key,Source,Translation,Line,Format,
                @{N="SourceLanguage";E={$src}},
                @{N="TargetLanguage";E={$dst}}
    )
    Write-ToolkitCsvAtomic $rows $path
}

function Import-PzCsv([string]$path) {
    $rows = @(Microsoft.PowerShell.Utility\Import-Csv -LiteralPath $path -Encoding UTF8 -Delimiter ';')
    if ($rows.Count -eq 0) { return 0 }

    $lookup = @{}
    foreach ($r in $rows) {
        $id = "$([string]$r.Root)|$([string]$r.File)|$([string]$r.Key)".ToLowerInvariant()
        $lookup[$id] = [string]$r.Translation
    }

    $updated = 0
    foreach ($e in $script:PzEntries) {
        $id = (Get-PzEntryIdentity $e).ToLowerInvariant()
        if ($lookup.ContainsKey($id)) {
            $e.Translation = [string]$lookup[$id]
            $updated++
        }
    }

    Refresh-PzGrid
    return $updated
}

function Get-ProviderLanguageCode([string]$provider, [string]$languageCode, [string]$role="Any") {
    $lang = Get-LanguageByCode $languageCode
    if ($null -eq $lang) { return $null }

    switch ($provider) {
        "Google" {
            return [string]$lang.GoogleCode
        }
        "LibreTranslate" {
            return [string]$lang.LibreCode
        }
        "DeepL" {
            # DeepL distinguishes some source and target language variants.
            switch ([string]$lang.Code) {
                "en" {
                    if ($role -eq "Target") { return "EN-US" }
                    return "EN"
                }
                "pt" {
                    if ($role -eq "Target") { return "PT-PT" }
                    return "PT"
                }
                "pt-br" {
                    if ($role -eq "Target") { return "PT-BR" }
                    return "PT"
                }
                "zh-cn" {
                    if ($role -eq "Target") { return "ZH-HANS" }
                    return "ZH"
                }
                "zh-tw" {
                    if ($role -eq "Target") { return "ZH-HANT" }
                    return "ZH"
                }
                default {
                    return [string]$lang.DeepLCode
                }
            }
        }
        default { return $null }
    }
}

function Get-SelectedSourceLanguage {
    return Get-SelectedLanguageFromCombo $cmbSourceLang
}
function Get-SelectedTargetLanguage {
    return Get-SelectedLanguageFromCombo $cmbTargetLang
}
function Get-SelectedSourceLanguageCode {
    $l = Get-SelectedSourceLanguage
    if ($null -eq $l) { return "en" }
    return [string]$l.Code
}
function Get-SelectedTargetLanguageCode {
    $l = Get-SelectedTargetLanguage
    if ($null -eq $l) { return "pl" }
    return [string]$l.Code
}
function Get-SelectedSourceRimWorldFolder {
    $l = Get-SelectedSourceLanguage
    if ($null -eq $l) { return "English" }
    return [string]$l.RimWorldFolder
}
function Get-SelectedTargetRimWorldFolder {
    $l = Get-SelectedTargetLanguage
    if ($null -eq $l) { return "Polish" }
    return [string]$l.RimWorldFolder
}




function Test-MultilingualConfiguration {
    $issues = New-Object System.Collections.ArrayList

    foreach ($lang in $script:Languages) {
        if ([string]::IsNullOrWhiteSpace([string]$lang.Code)) { [void]$issues.Add("Language without Code") }
        if ([string]::IsNullOrWhiteSpace([string]$lang.RimWorldFolder)) { [void]$issues.Add("$($lang.Code): missing RimWorldFolder") }
        if ([string]::IsNullOrWhiteSpace([string]$lang.GoogleCode)) { [void]$issues.Add("$($lang.Code): missing GoogleCode") }
        if ([string]::IsNullOrWhiteSpace([string]$lang.LibreCode)) { [void]$issues.Add("$($lang.Code): missing LibreCode") }
    }

    $seenFolders = @{}
    foreach ($lang in $script:Languages) {
        $key = ([string]$lang.RimWorldFolder).ToLowerInvariant()
        if ($seenFolders.ContainsKey($key)) {
            [void]$issues.Add("Duplicate RimWorldFolder: $($lang.RimWorldFolder)")
        } else {
            $seenFolders[$key] = $true
        }
    }

    foreach ($lang in $script:Languages) {
        $pkg = Get-TranslationPackageId "example.mod" $lang.Code
        if ($pkg -notmatch '^example\.mod\.[a-z0-9]+\.[a-z0-9]+$') {
            [void]$issues.Add("$($lang.Code): invalid generated packageId $pkg")
        }
    }

    return @($issues)
}

$script:RimWorldGameEntries = @()

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
    return @(Get-LanguageRootsForCode $modPath (Get-SelectedSourceLanguageCode))
}


function Get-LanguageFolderName([string]$code) {
    $lang = Get-LanguageByCode $code
    if ($null -ne $lang) { return [string]$lang.RimWorldFolder }
    return $code
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

function Test-RimWorldSourceCopy([string]$source,[string]$translation) {
    if ([string]::IsNullOrWhiteSpace($translation)) { return $false }
    $a = ([string]$source).Replace("`r`n","`n").Trim()
    $b = ([string]$translation).Replace("`r`n","`n").Trim()
    return ($a -ceq $b)
}

function Test-RimWorldTechnicalEntry($entry) {
    if ($null -eq $entry) { return $false }
    if ([string]$entry.DefType -ine 'RulePackDef' -or [string]$entry.Field -ine 'rulesStrings[]') { return $false }

    $source = ([string]$entry.Source).Trim()
    $arrow = $source.IndexOf('->')
    if ($arrow -lt 0) { return $false }

    # Only inspect the emitted value. Conditions and rule names on the left side
    # are grammar syntax and are never user-facing text.
    $rhs = $source.Substring($arrow + 2).Trim()
    if ([string]::IsNullOrWhiteSpace($rhs)) { return $true }

    # Remove RimWorld grammar placeholders and identifier-like symbols. If no
    # natural-language letters remain, the rule is structural and does not need
    # translation (e.g. destroyed_part->[PART_destroyed0_label]).
    $probe = [regex]::Replace($rhs, '\[[^\]]+\]', '')
    $probe = [regex]::Replace($probe, '\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b', '')
    $probe = [regex]::Replace($probe, '[\s\p{P}\p{S}\d]+', '')
    return [string]::IsNullOrWhiteSpace($probe)
}

function Get-RimWorldCoverageStats($languageEntries) {
    $total = $script:Entries.Count
    $matched = 0
    $translated = 0
    $identical = 0
    $empty = 0
    $technical = 0

    foreach ($e in $script:Entries) {
        if (Test-RimWorldTechnicalEntry $e) {
            $technical++
            continue
        }

        $oldEntry = Find-RimWorldExistingLanguageEntry $languageEntries $e
        if ($null -eq $oldEntry) {
            $empty++
            continue
        }

        $matched++
        $text = [string]$oldEntry.Text
        if ([string]::IsNullOrWhiteSpace($text)) {
            $empty++
        } elseif (Test-RimWorldSourceCopy ([string]$e.Source) $text) {
            $identical++
        } else {
            $translated++
        }
    }

    $translatable = [Math]::Max(0, $total - $technical)
    $percent = if ($translatable -gt 0) { [Math]::Round(($translated * 100.0) / $translatable, 1) } else { 100 }
    $status = if ($translatable -eq 0) { "complete" } elseif ($translated -eq 0) { "none" } elseif (($translated + $identical) -lt $translatable -or $identical -gt 0) { "partial" } else { "complete" }

    return [pscustomobject]@{
        Found = if ($null -eq $languageEntries) { 0 } else { $languageEntries.Count }
        Matched = $matched
        Translated = $translated
        Identical = $identical
        Missing = $empty
        Technical = $technical
        Translatable = $translatable
        Total = $total
        Percent = $percent
        Status = $status
    }
}

function Update-LanguageCoverage([string]$modPath) {
    $script:LanguageCoverage = @{}
    $script:ExistingTranslations = @{}

    foreach ($lang in $script:Languages) {
        $code = [string]$lang.Code
        $entries = Read-LanguageEntries $modPath $code
        $script:ExistingTranslations[$code] = $entries
        $script:LanguageCoverage[$code] = Get-RimWorldCoverageStats $entries
    }
}




function Read-LanguageEntriesFromRoot([string]$langRoot) {
    $entries = @{}
    if (-not (Test-ExistingFolderSafe $langRoot)) { return $entries }

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
                    $entries[$id] = [pscustomobject]@{ File=$rel; Key=$child.Name; Text=(Get-TextContent $child) }
                }
            }
        } catch {}
    }
    return $entries
}

function Read-ExternalTargetTranslation([string]$pickedPath,[string]$code) {
    if (-not (Test-ExistingFolderSafe $pickedPath)) { return @{} }
    $folderName = Get-LanguageFolderName $code

    $candidate = Join-Path $pickedPath "Languages\$folderName"
    if (Test-ExistingFolderSafe $candidate) { return Read-LanguageEntriesFromRoot $candidate }

    $candidate = Join-Path $pickedPath $folderName
    if ((Split-Path $pickedPath -Leaf) -ieq "Languages" -and (Test-ExistingFolderSafe $candidate)) {
        return Read-LanguageEntriesFromRoot $candidate
    }

    if ((Split-Path $pickedPath -Leaf) -ieq $folderName -or
        (Test-Path (Join-Path $pickedPath "DefInjected")) -or
        (Test-Path (Join-Path $pickedPath "Keyed"))) {
        return Read-LanguageEntriesFromRoot $pickedPath
    }

    return @{}
}

function Apply-TranslationEntries($entries) {
    $loaded = 0
    $identical = 0
    $translated = 0

    foreach ($e in $script:Entries) {
        $oldEntry = Find-RimWorldExistingLanguageEntry $entries $e
        if ($null -eq $oldEntry) { continue }
        $text = [string]$oldEntry.Text
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $e.Translation = $text
        $loaded++
        if (Test-RimWorldSourceCopy ([string]$e.Source) $text) { $identical++ } else { $translated++ }
    }

    Refresh-Grid
    return [pscustomobject]@{ Loaded=$loaded; Identical=$identical; Translated=$translated }
}

function Convert-RimWorldEscapesToEditor([string]$text) {
    if ($null -eq $text) { return "" }
    return ([string]$text).Replace('\r\n',"`r`n").Replace('\n',"`r`n")
}

function Convert-EditorToRimWorldEscapes([string]$text) {
    if ($null -eq $text) { return "" }
    $t = ([string]$text).Replace("`r`n","`n").Replace("`r","`n")
    return $t.Replace("`n",'\n')
}

function Show-RimWorldMultilineEditor($entry) {
    if ($null -eq $entry) { return }
    $editor = New-Object System.Windows.Window
    $editor.Title = if ($script:UiLanguage -eq "en") { "Multiline translation editor" } else { "Edytor tekstu wieloliniowego" }
    $editor.Width = 900
    $editor.Height = 620
    $editor.WindowStartupLocation = "CenterOwner"
    $editor.Owner = $window
    $editor.Background = [System.Windows.Media.Brushes]::White

    $gridEdit = New-Object System.Windows.Controls.Grid
    $gridEdit.Margin = '12'
    [void]$gridEdit.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height='Auto'}))
    [void]$gridEdit.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height='*'}))
    [void]$gridEdit.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height='Auto'}))
    [void]$gridEdit.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height='*'}))
    [void]$gridEdit.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height='Auto'}))

    $lblSrc = New-Object System.Windows.Controls.TextBlock
    $lblSrc.Text = if ($script:UiLanguage -eq "en") { "Source (line breaks shown normally):" } else { "Oryginał (podziały linii pokazane normalnie):" }
    $lblSrc.Margin='0,0,0,6'
    [System.Windows.Controls.Grid]::SetRow($lblSrc,0)
    $gridEdit.Children.Add($lblSrc) | Out-Null

    $srcBox = New-Object System.Windows.Controls.TextBox
    $srcBox.Text = Convert-RimWorldEscapesToEditor ([string]$entry.Source)
    $srcBox.IsReadOnly = $true
    $srcBox.AcceptsReturn = $true
    $srcBox.TextWrapping = 'Wrap'
    $srcBox.VerticalScrollBarVisibility = 'Auto'
    [System.Windows.Controls.Grid]::SetRow($srcBox,1)
    $gridEdit.Children.Add($srcBox) | Out-Null

    $lblDst = New-Object System.Windows.Controls.TextBlock
    $lblDst.Text = if ($script:UiLanguage -eq "en") { "Translation:" } else { "Tłumaczenie:" }
    $lblDst.Margin='0,10,0,6'
    [System.Windows.Controls.Grid]::SetRow($lblDst,2)
    $gridEdit.Children.Add($lblDst) | Out-Null

    $dstBox = New-Object System.Windows.Controls.TextBox
    $dstBox.Text = Convert-RimWorldEscapesToEditor ([string]$entry.Translation)
    $dstBox.AcceptsReturn = $true
    $dstBox.TextWrapping = 'Wrap'
    $dstBox.VerticalScrollBarVisibility = 'Auto'
    [System.Windows.Controls.Grid]::SetRow($dstBox,3)
    $gridEdit.Children.Add($dstBox) | Out-Null

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation='Horizontal'
    $buttons.HorizontalAlignment='Right'
    $buttons.Margin='0,10,0,0'
    $save = New-Object System.Windows.Controls.Button
    $save.Content = if ($script:UiLanguage -eq "en") { "Save" } else { "Zapisz" }
    $save.MinWidth=90
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = if ($script:UiLanguage -eq "en") { "Cancel" } else { "Anuluj" }
    $cancel.MinWidth=90
    $cancel.Margin='8,0,0,0'
    $buttons.Children.Add($save)|Out-Null
    $buttons.Children.Add($cancel)|Out-Null
    [System.Windows.Controls.Grid]::SetRow($buttons,4)
    $gridEdit.Children.Add($buttons)|Out-Null

    $save.Add_Click({
        $entry.Translation = Convert-EditorToRimWorldEscapes ([string]$dstBox.Text)
        $editor.DialogResult = $true
        $editor.Close()
    })
    $cancel.Add_Click({ $editor.DialogResult=$false; $editor.Close() })
    $editor.Content=$gridEdit
    [void]$editor.ShowDialog()
    Refresh-Grid
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
        $oldEntry = Find-RimWorldExistingLanguageEntry $entries $e

        if ($null -ne $oldEntry) {
            # Existing localization wins. Do not overwrite it with machine translation.
            $existingText = [string]$oldEntry.Text
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
    if (-not $script:ExistingTranslations.ContainsKey($code)) { return [pscustomobject]@{Loaded=0;Identical=0;Translated=0} }
    return Apply-TranslationEntries $script:ExistingTranslations[$code]
}

function Scan-EnglishLanguages([string]$modPath) {
    $countBefore = $script:Entries.Count
    $roots = @(Get-LanguageRoots $modPath)

    foreach ($sourceRoot in $roots) {
        if (-not (Test-Path $sourceRoot)) { continue }

        Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | ForEach-Object {
            $file = $_

            try {
                [xml]$doc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                if ($null -eq $doc.DocumentElement) { return }

                $rootName = $doc.DocumentElement.Name
                if ($rootName -ne "LanguageData") { return }

                $rel = $file.FullName.Substring($sourceRoot.Length).TrimStart('\','/')

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
                    if ([string]$def.LocalName -ne "KeyBindingDef") { continue }

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

function Get-DirectDefFieldNode($defNode, [string]$field) {
    if ($null -eq $defNode -or [string]::IsNullOrWhiteSpace($field)) { return $null }

    foreach ($child in @($defNode.ChildNodes)) {
        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        if ([string]$child.Name -ceq $field) { return $child }
    }

    return $null
}

function Resolve-InheritedDefField(
    $record,
    [string]$field,
    $parentIndex,
    [System.Collections.Generic.HashSet[string]]$visited
) {
    if ($null -eq $record) { return $null }

    $direct = Get-DirectDefFieldNode $record.Node $field
    if ($null -ne $direct -and -not [string]::IsNullOrWhiteSpace([string]$direct.InnerText)) {
        return [pscustomobject]@{
            Node = $direct
            Inherited = $false
            From = [string]$record.DefName
        }
    }

    $parentName = [string]$record.ParentName
    if ([string]::IsNullOrWhiteSpace($parentName)) { return $null }

    $visitKey = "$($record.DefType)|$parentName".ToLowerInvariant()
    if ($visited.Contains($visitKey)) { return $null }
    [void]$visited.Add($visitKey)

    $parentRecord = $null

    # ParentName is normally scoped to the same Def type. Prefer that.
    $typedKey = "$($record.DefType)|$parentName".ToLowerInvariant()
    if ($parentIndex.ContainsKey($typedKey)) {
        $parentRecord = $parentIndex[$typedKey]
    } else {
        # Conservative fallback for unusual mods that reference a parent
        # template by Name across a slightly different XML type.
        $suffix = "|$parentName".ToLowerInvariant()
        foreach ($k in @($parentIndex.Keys)) {
            if ([string]$k -like "*$suffix") {
                $parentRecord = $parentIndex[$k]
                break
            }
        }
    }

    if ($null -eq $parentRecord) { return $null }

    $resolved = Resolve-InheritedDefField $parentRecord $field $parentIndex $visited
    if ($null -eq $resolved) { return $null }

    return [pscustomobject]@{
        Node = $resolved.Node
        Inherited = $true
        From = $(if (-not [string]::IsNullOrWhiteSpace([string]$parentRecord.TemplateName)) {
            [string]$parentRecord.TemplateName
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$parentRecord.DefName)) {
            [string]$parentRecord.DefName
        } else {
            [string]$parentName
        })
    }
}

# ---------- RimWorld v0.10.18 extraction/update compatibility ----------
function Get-RimWorldCanonicalLanguageId([string]$file, [string]$key, [string]$defType = "") {
    $normFile = ([string]$file).Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($defType) -and $normFile -match '(?i)^DefInjected\\([^\\]+)\\') {
        $defType = [string]$Matches[1]
    }
    if (-not [string]::IsNullOrWhiteSpace($defType)) {
        return ("definjected|$defType|$key").ToLowerInvariant()
    }
    if ($normFile -match '(?i)^Keyed\\') {
        return ("keyed|$key").ToLowerInvariant()
    }
    return ("file|$normFile|$key").ToLowerInvariant()
}

function Find-RimWorldExistingLanguageEntry($entries, $entry) {
    if ($null -eq $entries -or $null -eq $entry) { return $null }

    # Exact historical match always wins.
    $exact = "$($entry.File)|$($entry.Key)".ToLowerInvariant()
    if ($entries.ContainsKey($exact)) { return $entries[$exact] }

    $wanted = Get-RimWorldCanonicalLanguageId ([string]$entry.File) ([string]$entry.Key) ([string]$entry.DefType)
    $candidates = New-Object System.Collections.ArrayList
    foreach ($old in @($entries.Values)) {
        if ($null -eq $old) { continue }
        $oldCanonical = Get-RimWorldCanonicalLanguageId ([string]$old.File) ([string]$old.Key)
        if ($oldCanonical -eq $wanted) { [void]$candidates.Add($old) }
    }
    if ($candidates.Count -eq 0) { return $null }

    $texts = @($candidates | ForEach-Object { ([string]$_.Text).Trim() } | Sort-Object -Unique)
    if ($texts.Count -gt 1) {
        if ($null -eq $script:CrossFileTranslationConflicts) { $script:CrossFileTranslationConflicts = New-Object System.Collections.ArrayList }
        [void]$script:CrossFileTranslationConflicts.Add([pscustomobject]@{
            Id = $wanted
            Key = [string]$entry.Key
            DefType = [string]$entry.DefType
            Values = ($texts -join ' || ')
        })
        return $null
    }
    return $candidates[0]
}

function Get-RimWorldNestedLocalizableNodes($node, [string]$path, $fieldSet, $listContainerSet) {
    $result = New-Object System.Collections.ArrayList
    if ($null -eq $node) { return @() }

    $children = @($node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    foreach ($child in $children) {
        $name = [string]$child.LocalName
        if ($name -eq 'defName') { continue }

        $segment = $name
        if ($name -eq 'li') {
            $siblings = @($node.ChildNodes | Where-Object {
                $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.LocalName -eq 'li'
            })
            $idx = 0
            for ($i = 0; $i -lt $siblings.Count; $i++) {
                if ([object]::ReferenceEquals($siblings[$i], $child)) { $idx = $i; break }
            }
            $segment = [string]$idx
        }

        $childPath = if ([string]::IsNullOrWhiteSpace($path)) { $segment } else { "$path.$segment" }
        $grandChildren = @($child.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })

        $isNamedField = $fieldSet.Contains($name) -and $grandChildren.Count -eq 0

        # RimWorld uses some string lists where the translatable values are bare <li>
        # nodes rather than named fields. Only explicitly known containers are treated
        # as localizable, so reference lists such as <include><li>SomeRulePack</li></include>
        # are never translated by accident.
        $parentName = ''
        try { $parentName = [string]$node.LocalName } catch {}
        $isLocalizableListItem = (
            $name -eq 'li' -and
            $grandChildren.Count -eq 0 -and
            $null -ne $listContainerSet -and
            $listContainerSet.Contains($parentName)
        )

        if ($isNamedField -or $isLocalizableListItem) {
            $value = [string]$child.InnerText
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $fieldName = if ($isLocalizableListItem) { "$parentName[]" } else { $name }
                [void]$result.Add([pscustomobject]@{
                    Path = $childPath
                    Field = $fieldName
                    Value = $value.TrimEnd()
                })
            }
        }

        if ($grandChildren.Count -gt 0) {
            foreach ($nested in @(Get-RimWorldNestedLocalizableNodes $child $childPath $fieldSet $listContainerSet)) {
                [void]$result.Add($nested)
            }
        }
    }
    return @($result)
}

function ConvertTo-RimWorldEnglishPlural([string]$label) {
    if ([string]::IsNullOrWhiteSpace($label)) { return '' }
    $s = $label.Trim()
    if ($s -match '(?i)[^aeiou]y$') { return ($s.Substring(0, $s.Length - 1) + 'ies') }
    if ($s -match '(?i)(s|x|z|ch|sh)$') { return ($s + 'es') }
    return ($s + 's')
}

function Add-RimWorldGeneratedDefEntries($record, [string]$defType, [string]$defName, $parentIndex) {
    # RimTrans/RimWorld compatibility: PawnKind labelPlural when absent.
    if ($defType -eq 'PawnKindDef') {
        $localPlural = Get-DirectDefFieldNode $record.Node 'labelPlural'
        if ($null -eq $localPlural -or [string]::IsNullOrWhiteSpace([string]$localPlural.InnerText)) {
            $visited = New-Object 'System.Collections.Generic.HashSet[string]'
            $labelResolved = Resolve-InheritedDefField $record 'label' $parentIndex $visited
            if ($null -ne $labelResolved -and $null -ne $labelResolved.Node) {
                $plural = ConvertTo-RimWorldEnglishPlural ([string]$labelResolved.Node.InnerText)
                if (-not [string]::IsNullOrWhiteSpace($plural)) {
                    Add-Entry 'DefInjected' "DefInjected\$defType\$defType.xml" "$defName.labelPlural" $plural $defType $defName 'labelPlural'
                }
            }
        }
    }
}
# ---------- end v0.10.18 helpers ----------
function Scan-Defs([string]$modPath) {
    $fields = @(
        "label","description","jobString","reportString","gerund","verb",
        "labelShort","labelNoun","labelPlural","labelMale","labelMalePlural","labelFemale","labelFemalePlural",
        "inspectString","baseDesc","letterLabel","letterText","deathMessage","leaderTitle","pawnsPlural",
        "fixedName","formatString","labelTendedWell","labelTendedWellInner","labelSolidTendedWell",
        "destroyedLabel","destroyedOutLabel","adjective","helpText","summary","text","name","customLabel","useLabel",
        "ingestCommandString","ingestReportString","recoveryMessage","discoverLetterLabel","discoverLetterText"
    )

    # Bare <li> values are translatable only inside explicitly known string-list
    # containers. This mirrors RimWorld/RimTrans behavior without translating every
    # XML list item (many lists contain Def references, enum values, etc.).
    $localizableListContainers = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    [void]$localizableListContainers.Add('rulesStrings')

    $countBefore = $script:Entries.Count
    $roots = @(Get-DefRoots $modPath)

    # First pass: collect every Def node, including abstract/template defs that
    # have Name= but no defName. Those are required for ParentName inheritance.
    $records = New-Object System.Collections.ArrayList
    $parentIndex = @{}

    foreach ($defs in $roots) {
        if (-not (Test-Path $defs)) { continue }

        Get-ChildItem -LiteralPath $defs -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue | ForEach-Object {
            $file = $_
            try {
                [xml]$doc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                if ($null -eq $doc.DocumentElement -or $doc.DocumentElement.Name -ne "Defs") { return }

                foreach ($def in @($doc.DocumentElement.ChildNodes)) {
                    if ($def.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                    $defType = [string]$def.LocalName
                    $defName = ""
                    $defNameNode = Get-DirectDefFieldNode $def "defName"
                    if ($null -ne $defNameNode -and -not [string]::IsNullOrWhiteSpace([string]$defNameNode.InnerText)) {
                        $defName = [string]$defNameNode.InnerText.Trim()
                    }

                    $templateName = ""
                    try {
                        if ($null -ne $def.Attributes["Name"]) {
                            $templateName = [string]$def.Attributes["Name"].Value
                        }
                    } catch {}

                    $parentName = ""
                    try {
                        if ($null -ne $def.Attributes["ParentName"]) {
                            $parentName = [string]$def.Attributes["ParentName"].Value
                        }
                    } catch {}

                    $record = [pscustomobject]@{
                        DefType = $defType
                        DefName = $defName
                        TemplateName = $templateName
                        ParentName = $parentName
                        Node = $def
                        File = [string]$file.FullName
                    }
                    [void]$records.Add($record)

                    # ParentName resolves against the XML Name attribute.
                    if (-not [string]::IsNullOrWhiteSpace($templateName)) {
                        $key = "$defType|$templateName".ToLowerInvariant()
                        if (-not $parentIndex.ContainsKey($key)) {
                            $parentIndex[$key] = $record
                        }
                    }
                }
            } catch {}
        }
    }

    $script:InheritedDefFieldCount = 0
    $script:InheritedDefDiagnostics = New-Object System.Collections.ArrayList

    # Second pass: emit concrete defs. If a localizable field is absent on the
    # concrete Def, resolve it recursively through ParentName.
    foreach ($record in @($records)) {
        if ([string]::IsNullOrWhiteSpace([string]$record.DefName)) { continue }

        $defType = [string]$record.DefType
        $defName = [string]$record.DefName

        foreach ($field in $fields) {
            $visited = New-Object 'System.Collections.Generic.HashSet[string]'
            $resolved = Resolve-InheritedDefField $record $field $parentIndex $visited

            if ($null -eq $resolved -or $null -eq $resolved.Node) { continue }

            $value = [string]$resolved.Node.InnerText
            if ([string]::IsNullOrWhiteSpace($value)) { continue }

            Add-Entry "DefInjected" "DefInjected\$defType\$defType.xml" "$defName.$field" $value $defType $defName $field

            if ($resolved.Inherited) {
                $script:InheritedDefFieldCount++
                [void]$script:InheritedDefDiagnostics.Add([pscustomobject]@{
                    Key = "$defName.$field"
                    DefType = $defType
                    ParentName = [string]$record.ParentName
                    ResolvedFrom = [string]$resolved.From
                })
            }
        }

        # Recursive local fields (tools.0.label, comps.0.tools.0.label, injuryProps.*, etc.).
        $fieldSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($f in $fields) { [void]$fieldSet.Add([string]$f) }
        foreach ($nested in @(Get-RimWorldNestedLocalizableNodes $record.Node '' $fieldSet $localizableListContainers)) {
            Add-Entry "DefInjected" "DefInjected\$defType\$defType.xml" "$defName.$($nested.Path)" ([string]$nested.Value) $defType $defName ([string]$nested.Field)
        }

        Add-RimWorldGeneratedDefEntries $record $defType $defName $parentIndex
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


function Get-RimWorldTranslationContentShape([string]$modPath) {
    $languageFiles = 0
    $hasGameplayContent = $false
    $gameplayFolders = @("Defs","Patches","Assemblies","Textures","Sounds","Shaders","Source")

    try {
        foreach ($langDir in @(Get-ChildItem -LiteralPath $modPath -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "Languages" })) {

            $languageFiles += @(Get-ChildItem -LiteralPath $langDir.FullName -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".xml",".txt") }).Count
        }

        foreach ($dir in @(Get-ChildItem -LiteralPath $modPath -Directory -Recurse -ErrorAction SilentlyContinue)) {
            if ($gameplayFolders -contains [string]$dir.Name) {
                # Do not count folders located under Languages as gameplay payload.
                if ($dir.FullName -notmatch '(?i)[\\/]Languages[\\/]') {
                    $hasGameplayContent = $true
                    break
                }
            }
        }
    } catch {}

    return [pscustomobject]@{
        LanguageFiles = $languageFiles
        HasGameplayContent = $hasGameplayContent
        TranslationOnly = ($languageFiles -gt 0 -and -not $hasGameplayContent)
    }
}

function Test-RimWorldTranslationReferenceResolves([string]$packageId, [string]$excludePath = "") {
    if ([string]::IsNullOrWhiteSpace($packageId)) { return $false }
    if (Test-IsFrameworkDependency $packageId) { return $false }

    try {
        $m = Find-ModByPackageId $packageId $excludePath
        return ($null -ne $m)
    } catch {
        return $false
    }
}


function Test-TranslationReferencesExpectedOriginal($translationInfo, [string]$expectedOriginalPackageId) {
    if ($null -eq $translationInfo) { return $false }
    if ([string]::IsNullOrWhiteSpace($expectedOriginalPackageId)) { return $false }

    $expected = $expectedOriginalPackageId.Trim().ToLowerInvariant()

    foreach ($p in @($translationInfo.Dependencies)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$p) -and
            ([string]$p).Trim().ToLowerInvariant() -eq $expected) {
            return $true
        }
    }

    foreach ($p in @($translationInfo.LoadAfter)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$p) -and
            ([string]$p).Trim().ToLowerInvariant() -eq $expected) {
            return $true
        }
    }

    foreach ($p in @($translationInfo.LoadBefore)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$p) -and
            ([string]$p).Trim().ToLowerInvariant() -eq $expected) {
            return $true
        }
    }

    foreach ($candidate in @(Get-PackageIdSourceCandidates ([string]$translationInfo.PackageId))) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and
            ([string]$candidate).Trim().ToLowerInvariant() -eq $expected) {
            return $true
        }
    }

    return $false
}

function Confirm-TranslationAgainstSelectedOriginal($translationInfo, [string]$originalModPath) {
    if ($null -eq $translationInfo) { return $translationInfo }
    if ([string]::IsNullOrWhiteSpace($originalModPath) -or
        -not (Test-Path -LiteralPath $originalModPath -PathType Container)) {
        return $translationInfo
    }

    $original = Get-AboutInfo $originalModPath
    $expectedPackageId = [string]$original.PackageId
    if ([string]::IsNullOrWhiteSpace($expectedPackageId)) { return $translationInfo }

    if (-not (Test-TranslationReferencesExpectedOriginal $translationInfo $expectedPackageId)) {
        return $translationInfo
    }

    # A selected source folder plus a direct dependency/load-order/packageId
    # reference is a stronger signal than relying on the global installed-mod scan.
    if (-not [string]::IsNullOrWhiteSpace([string]$translationInfo.TargetCode) -and
        [int]$translationInfo.LanguageFileCount -gt 0) {

        $translationInfo.IsTranslationMod = $true
        if ([int]$translationInfo.ClassificationScore -lt 80) {
            $translationInfo.ClassificationScore = 80
        }

        $signals = New-Object System.Collections.ArrayList
        foreach ($s in @($translationInfo.ClassificationSignals)) { [void]$signals.Add([string]$s) }
        if (-not (@($signals) -contains "references selected original")) {
            [void]$signals.Add("references selected original")
        }
        $translationInfo.ClassificationSignals = @($signals)
        $translationInfo.ReferencedOriginalPackageId = $expectedPackageId
    }

    return $translationInfo
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
        DescriptionTranslationSignal = $false
        TranslationOnlyContent = $false
        LanguageFileCount = 0
        ClassificationScore = 0
        ClassificationSignals = @()
        ReferencedOriginalPackageId = ""
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
                $descriptionText = [string]$desc.InnerText
                if ($descriptionText -match 'Mod Translation Toolkit|github\.com/DrizztGaming/Mod-Translation-Toolkit') {
                    $info.ToolkitGenerated = $true
                }

                if ($descriptionText -match '(?i)\btranslation\b|tłumaczenie|tlumaczenie|requires?\s+(the\s+)?original\s+mod|wymaga\s+oryginalnego\s+moda') {
                    $info.DescriptionTranslationSignal = $true
                }
            }
        } catch {}
    }

    # A Toolkit metadata file is an explicit signal independent of About.xml naming.
    if (Test-Path -LiteralPath (Join-Path $modPath "ModTranslationToolkit.json")) {
        $info.ToolkitGenerated = $true
    }

    # Detect supported target language from the actual language folders.
    if (@(Get-LanguageRootsForCode $modPath "pl").Count -gt 0) {
        $info.TargetCode = "pl"
    } elseif (@(Get-LanguageRootsForCode $modPath "en").Count -gt 0) {
        $info.TargetCode = "en"
    }

    $shape = Get-RimWorldTranslationContentShape $modPath
    $info.TranslationOnlyContent = [bool]$shape.TranslationOnly
    $info.LanguageFileCount = [int]$shape.LanguageFiles

    $pidLower = ([string]$info.PackageId).ToLowerInvariant()
    $nameLower = ([string]$info.Name).ToLowerInvariant()
    $signals = New-Object System.Collections.ArrayList
    $score = 0

    if (-not [string]::IsNullOrWhiteSpace($info.TargetCode) -and $info.LanguageFileCount -gt 0) {
        $score += 10
        [void]$signals.Add("language payload")
    }

    if ($info.ToolkitGenerated) {
        $score += 100
        [void]$signals.Add("toolkit metadata/attribution")
    }

    if ($pidLower -match '(^|[._-])(pltranslation|entranslation|polishtranslation|englishtranslation|translation)([._-]|$)') {
        $score += 60
        [void]$signals.Add("translation packageId")
    }

    if ($nameLower -match 'translation|tłumaczenie|tlumaczenie') {
        $score += 60
        [void]$signals.Add("translation name")
    }

    if ($info.DescriptionTranslationSignal) {
        $score += 20
        [void]$signals.Add("translation description")
    }

    if ($info.TranslationOnlyContent) {
        $score += 35
        [void]$signals.Add("language-only content")
    }

    # PackageId derived from a known installed original is a strong signal.
    foreach ($candidatePackageId in @(Get-PackageIdSourceCandidates ([string]$info.PackageId))) {
        if (Test-RimWorldTranslationReferenceResolves $candidatePackageId $modPath) {
            $score += 40
            $info.ReferencedOriginalPackageId = $candidatePackageId
            [void]$signals.Add("packageId resolves original")
            break
        }
    }

    # Explicit dependency on another installed, non-framework mod is the most
    # useful signal for custom-named translation packages.
    foreach ($dependencyPackageId in @($info.Dependencies)) {
        if (Test-RimWorldTranslationReferenceResolves $dependencyPackageId $modPath) {
            $score += 35
            if ([string]::IsNullOrWhiteSpace($info.ReferencedOriginalPackageId)) {
                $info.ReferencedOriginalPackageId = [string]$dependencyPackageId
            }
            [void]$signals.Add("modDependency resolves original")
            break
        }
    }

    foreach ($loadAfterPackageId in @($info.LoadAfter)) {
        if (Test-RimWorldTranslationReferenceResolves $loadAfterPackageId $modPath) {
            $score += 20
            if ([string]::IsNullOrWhiteSpace($info.ReferencedOriginalPackageId)) {
                $info.ReferencedOriginalPackageId = [string]$loadAfterPackageId
            }
            [void]$signals.Add("loadAfter resolves original")
            break
        }
    }

    $info.ClassificationScore = $score
    $info.ClassificationSignals = @($signals)

    # Mandatory language payload prevents ordinary dependency/patch mods from
    # being treated as translations. Score >= 60 requires at least two useful
    # structural signals unless an explicit name/package/Toolkit signal exists.
    $info.IsTranslationMod = (
        -not [string]::IsNullOrWhiteSpace($info.TargetCode) -and
        $info.LanguageFileCount -gt 0 -and
        $score -ge 60
    )

    return [pscustomobject]$info
}


function Get-TranslationClassificationReason($translationInfo, [string]$modPath) {
    if ($null -eq $translationInfo) { return "unknown" }

    $signals = @($translationInfo.ClassificationSignals)
    $score = 0
    try { $score = [int]$translationInfo.ClassificationScore } catch {}

    if ($signals.Count -gt 0) {
        return "score ${score}: " + ($signals -join ", ")
    }

    return "score ${score}: no translation signals"
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

    # Common community convention: prefix the original packageId with language.
    # Example: pl.Aoba.Exosuit.Framework -> Aoba.Exosuit.Framework
    foreach ($prefix in @('pl.','en.','de.','fr.','es.','it.','ru.','pt.','br.','cz.','uk.','ua.','jp.','kr.','cn.','tw.')) {
        if ($basePackageId.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidate = $basePackageId.Substring($prefix.Length)
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not (@($result) -contains $candidate)) {
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
        $reason = Get-TranslationClassificationReason $t $translationModPath
        throw "Wybrany mod nie został rozpoznany jako mod tłumaczeniowy. Klasyfikacja: $reason"
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
        $oldEntry = Find-RimWorldExistingLanguageEntry $existing $e
        if ($null -ne $oldEntry) {
            $e.Translation = [string]$oldEntry.Text
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




function Show-ModernFolderPicker([string]$description, [string]$initialPath="") {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $description
    $dlg.ShowNewFolderButton = $true

    # On supported Windows/.NET versions this switches FolderBrowserDialog
    # to the newer Explorer-style shell picker with breadcrumb/address navigation.
    try { $dlg.AutoUpgradeEnabled = $true } catch {}

    if (-not [string]::IsNullOrWhiteSpace($initialPath) -and (Test-Path -LiteralPath $initialPath)) {
        try { $dlg.SelectedPath = [System.IO.Path]::GetFullPath($initialPath) } catch {}
    }

    $result = $dlg.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
        -not [string]::IsNullOrWhiteSpace([string]$dlg.SelectedPath)) {
        return [string]$dlg.SelectedPath
    }
    return $null
}

function Show-PathInputDialog([string]$title, [string]$prompt, [string]$defaultValue="") {
    $w = New-Object System.Windows.Window
    $w.Title = $title
    $w.Width = 780
    $w.Height = 195
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

    $pathGrid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = "*"
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = "Auto"
    [void]$pathGrid.ColumnDefinitions.Add($c1)
    [void]$pathGrid.ColumnDefinitions.Add($c2)

    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $defaultValue
    $tb.AllowDrop = $true
    $tb.VerticalContentAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($tb,0)
    [void]$pathGrid.Children.Add($tb)

    $browse = New-Object System.Windows.Controls.Button
    $browse.Content = if ($script:UiLanguage -eq "en") { "Browse..." } else { "Przeglądaj..." }
    $browse.Margin = "8,0,0,0"
    $browse.MinWidth = 105
    [System.Windows.Controls.Grid]::SetColumn($browse,1)
    [void]$pathGrid.Children.Add($browse)

    [System.Windows.Controls.Grid]::SetRow($pathGrid,1)
    [void]$grid.Children.Add($pathGrid)

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
    $cancel.Content = if ($script:UiLanguage -eq "en") { "Cancel" } else { "Anuluj" }
    $cancel.Width = 90

    [void]$panel.Children.Add($ok)
    [void]$panel.Children.Add($cancel)
    [System.Windows.Controls.Grid]::SetRow($panel,2)
    [void]$grid.Children.Add($panel)

    $browse.Add_Click({
        $picked = Show-ModernFolderPicker $title $tb.Text
        if ($picked) { $tb.Text = $picked }
    })

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
    $translationInfo = Confirm-TranslationAgainstSelectedOriginal $translationInfo $updatedOriginalPath
    if (-not $translationInfo.IsTranslationMod) {
        $reason = Get-TranslationClassificationReason $translationInfo $translationModPath
        throw "Wybrany folder nie wygląda na mod tłumaczeniowy. Klasyfikacja: $reason"
    }

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
        $oldEntry = Find-RimWorldExistingLanguageEntry $oldMap $e
        if ($null -ne $oldEntry) {
            $oldText = [string]$oldEntry.Text
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
        $cid = Get-RimWorldCanonicalLanguageId ([string]$e.File) ([string]$e.Key) ([string]$e.DefType)
        $currentIds[$cid] = $true
    }

    $obsolete = 0
    $oldCanonicalSeen = @{}
    foreach ($oldEntry in @($oldMap.Values)) {
        $cid = Get-RimWorldCanonicalLanguageId ([string]$oldEntry.File) ([string]$oldEntry.Key)
        if ($oldCanonicalSeen.ContainsKey($cid)) { continue }
        $oldCanonicalSeen[$cid] = $true
        if (-not $currentIds.ContainsKey($cid)) { $obsolete++ }
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

    # The scan above initializes coverage from the UPDATED SOURCE MOD.
    # In update mode, the target-language coverage must instead describe the
    # translation mod that has just been merged into the grid. Without this,
    # the UI can show 0 translated entries even though the Translation column
    # is already populated with preserved strings.
    $script:ExistingTranslations[$targetCode] = $oldMap
    $script:LanguageCoverage[$targetCode] = Get-RimWorldCoverageStats $oldMap

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

function Set-ToolkitWorkStatus([string]$text) {
    try {
        $isDone = ($text -match '^(Gotowe|Done)')

        if ($null -ne $txtStatus) {
            $txtStatus.Text = $text
        }

        if ($null -ne $busyOverlay) {
            if ($isDone) {
                $busyOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            } else {
                if ($null -ne $txtBusyTitle) {
                    $txtBusyTitle.Text = if ($script:UiLanguage -eq "en") { "Scanning mod..." } else { "Skanowanie moda..." }
                }
                if ($null -ne $txtBusyStage) { $txtBusyStage.Text = $text }
                if ($null -ne $txtBusyHint) {
                    $txtBusyHint.Text = if ($script:UiLanguage -eq "en") {
                        "The program is working. Large mods may take a moment."
                    } else {
                        "Program pracuje. Przy dużych modach może to potrwać chwilę."
                    }
                }
                $busyOverlay.Visibility = [System.Windows.Visibility]::Visible
            }
        }

        if ($null -ne $window) {
            $window.Cursor = if ($isDone) { [System.Windows.Input.Cursors]::Arrow } else { [System.Windows.Input.Cursors]::Wait }
            $window.UpdateLayout()
            if ($null -ne $window.Dispatcher) {
                # Force the busy overlay to be painted before entering the next synchronous scan stage.
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            }
        }
    } catch {}
}

function Analyze-Mod([string]$modPath) {
    $script:Entries.Clear()
    $script:EntryKeys = @{}
    $script:CrossFileTranslationConflicts = New-Object System.Collections.ArrayList
    $script:OriginalModPath = $modPath
    $script:DetectedFromDefs = $false
    $script:SelectedContentVersion = ""

    Set-ToolkitWorkStatus "Odczytywanie informacji o modzie..."
    Read-AboutXml $modPath

    $sourceCode = Get-SelectedSourceLanguageCode
    Set-ToolkitWorkStatus "Skanowanie istniejących lokalizacji..."
    $langCount = Scan-EnglishLanguages $modPath

    $defsCount = 0
    if ($sourceCode -eq "en") {
        Set-ToolkitWorkStatus "Skanowanie Defów i zagnieżdżonych pól..."
        $defsCount = Scan-Defs $modPath
    }

    Set-ToolkitWorkStatus "Analiza KeyBindingDef..."
    $keybindScan = Scan-KeyBindingDefs $modPath

    # DLL/UI diagnostics are intentionally lazy and run only on button press.
    $script:AssemblyDiagnostics.Clear()
    $script:AssemblyDiagnosticFiles = 0
    $script:AssemblyDiagnosticsScannedPath = ""

    if ($defsCount -gt 0) { $script:DetectedFromDefs = $true }

    $txtModName.Text = $script:OriginalModName
    $txtPackageId.Text = $script:OriginalPackageId
    Refresh-Grid

    Set-ToolkitWorkStatus "Dopasowywanie istniejących tłumaczeń..."
    Update-LanguageCoverage $modPath
    $autoLoaded = AutoLoad-ExistingTargetTranslation
    Set-ToolkitWorkStatus "Gotowe. Wpisy: $($script:Entries.Count)."

    return [pscustomobject]@{
        LanguageEntries = $langCount
        DefEntries = $defsCount
        ContentVersion = $script:SelectedContentVersion
        Total = $script:Entries.Count
        SourceLanguage = $sourceCode
        TargetLanguage = Get-SelectedTargetLanguageCode
        SourceCoverage = $script:LanguageCoverage[$sourceCode]
        TargetCoverage = $script:LanguageCoverage[(Get-SelectedTargetLanguageCode)]
        AutoLoadedExisting = $autoLoaded
        KeyBindingDefs = $keybindScan.Total
        KeyBindingLocalizable = $keybindScan.Localizable
        KeyBindingDiagnostics = $keybindScan.Diagnostic
        AssemblyFiles = 0
        AssemblyUiDiagnostics = 0
    }
}


# ---------- Crash-safe translation checkpoints ----------
function Get-ToolkitAutosaveDirectory {
    $root = Join-Path $env:APPDATA "ModTranslationToolkit\autosave"
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function ConvertTo-SafeFileName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return "translation" }
    $safe = $name -replace '[\\/:*?"<>|]', '_'
    $safe = $safe.Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { return "translation" }
    return $safe
}

function Write-ToolkitCsvAtomic([object[]]$rows, [string]$path) {
    if ($null -eq $rows -or $rows.Count -eq 0) {
        throw $(if ($script:UiLanguage -eq "en") {
            "There are no rows to write to CSV."
        } else {
            "Brak wpisów do zapisania w CSV."
        })
    }

    $parent = Split-Path -Parent $path
    if ([string]::IsNullOrWhiteSpace($parent)) {
        $parent = (Get-Location).Path
    }
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $leaf = Split-Path -Leaf $path
    $tmp = Join-Path $parent (".$leaf.$([guid]::NewGuid().ToString('N')).tmp")

    try {
        $rows | Microsoft.PowerShell.Utility\Export-Csv `
            -LiteralPath $tmp -NoTypeInformation -Encoding UTF8 -Delimiter ';'

        if (-not (Test-Path -LiteralPath $tmp)) {
            throw "Temporary CSV file was not created."
        }

        $length = (Get-Item -LiteralPath $tmp).Length
        if ($length -le 0) {
            throw "Temporary CSV file is empty."
        }

        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }

        Move-Item -LiteralPath $tmp -Destination $path -Force

        if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -le 0) {
            throw "CSV verification failed after writing."
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Save-ToolkitTranslationCheckpoint([string]$reason = "manual") {
    if ($script:Entries.Count -eq 0) { return $null }

    $autosaveDir = Get-ToolkitAutosaveDirectory
    $sourceCode = Get-SelectedSourceLanguageCode
    $targetCode = Get-SelectedTargetLanguageCode
    $modName = ConvertTo-SafeFileName $script:OriginalModName
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseName = "$stamp-$modName-$sourceCode-$targetCode"

    $csvPath = Join-Path $autosaveDir "$baseName.csv"
    $metaPath = Join-Path $autosaveDir "$baseName.json"
    $latestCsv = Join-Path $autosaveDir "latest.csv"
    $latestMeta = Join-Path $autosaveDir "latest.json"

    $rows = @(
        $script:Entries |
            Select-Object Kind,File,Key,Source,Translation,DefType,DefName,Field,
                @{N="SourceLanguage";E={$sourceCode}},
                @{N="TargetLanguage";E={$targetCode}}
    )

    Write-ToolkitCsvAtomic $rows $csvPath
    Copy-Item -LiteralPath $csvPath -Destination $latestCsv -Force

    $translated = @($script:Entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Translation) }).Count
    $meta = [pscustomobject]@{
        Version = $AppVersion
        SavedAt = (Get-Date).ToString("o")
        Reason = $reason
        OriginalModName = [string]$script:OriginalModName
        OriginalModPath = [string]$script:OriginalModPath
        OriginalPackageId = [string]$script:OriginalPackageId
        EditingTranslationModPath = [string]$script:EditingTranslationModPath
        SourceLanguage = $sourceCode
        TargetLanguage = $targetCode
        Entries = $script:Entries.Count
        TranslatedEntries = $translated
        CsvPath = $csvPath
    }

    $json = $meta | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($metaPath, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
    [System.IO.File]::WriteAllText($latestMeta, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))

    # Keep the autosave directory bounded. Preserve latest.* plus 20 newest timestamped pairs.
    try {
        $oldCsv = @(Get-ChildItem -LiteralPath $autosaveDir -File -Filter "*.csv" |
            Where-Object { $_.Name -ne "latest.csv" } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 20)
        foreach ($f in $oldCsv) {
            $jsonPeer = [System.IO.Path]::ChangeExtension($f.FullName, ".json")
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $jsonPeer) {
                Remove-Item -LiteralPath $jsonPeer -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    return $csvPath
}

function Export-ToolkitCsv([string]$path) {
    $sourceCode = Get-SelectedSourceLanguageCode
    $targetCode = Get-SelectedTargetLanguageCode

    [void](Save-ToolkitTranslationCheckpoint "before-csv-export")

    $rows = @(
        $script:Entries |
            Select-Object Kind,File,Key,Source,Translation,DefType,DefName,Field,
                @{N="SourceLanguage";E={$sourceCode}},
                @{N="TargetLanguage";E={$targetCode}}
    )

    Write-ToolkitCsvAtomic $rows $path
}

function Import-ToolkitCsv([string]$path) {
    $rows = Microsoft.PowerShell.Utility\Import-Csv -LiteralPath $path -Encoding UTF8 -Delimiter ';'
    # CSV language metadata is optional for backward compatibility.
    # When present, warn if the file was exported for a different pair.
    try {
        $metaRow = $rows | Select-Object -First 1
        if ($null -ne $metaRow -and
            $metaRow.PSObject.Properties.Name -contains "SourceLanguage" -and
            $metaRow.PSObject.Properties.Name -contains "TargetLanguage") {

            $csvSource = [string]$metaRow.SourceLanguage
            $csvTarget = [string]$metaRow.TargetLanguage
            $currentSource = Get-SelectedSourceLanguageCode
            $currentTarget = Get-SelectedTargetLanguageCode

            if ((-not [string]::IsNullOrWhiteSpace($csvSource) -and $csvSource -ine $currentSource) -or
                (-not [string]::IsNullOrWhiteSpace($csvTarget) -and $csvTarget -ine $currentTarget)) {

                $msg = if ($script:UiLanguage -eq "en") {
                    "CSV language metadata: $csvSource → $csvTarget`nCurrent selection: $currentSource → $currentTarget`n`nThe file will still be imported. Verify that this is intentional."
                } else {
                    "Języki zapisane w CSV: $csvSource → $csvTarget`nAktualny wybór: $currentSource → $currentTarget`n`nPlik zostanie zaimportowany. Sprawdź, czy to zamierzone."
                }
                [System.Windows.MessageBox]::Show($msg,"CSV") | Out-Null
            }
        }
    } catch {}

    $lookup = @{}
    foreach ($r in $rows) { $lookup["$($r.Kind)|$($r.File)|$($r.Key)"] = $r }

    foreach ($e in $script:Entries) {
        $k = "$($e.Kind)|$($e.File)|$($e.Key)"
        if ($lookup.ContainsKey($k)) { $e.Translation = [string]$lookup[$k].Translation }
    }
    Refresh-Grid
}

function Get-TranslationOutputRelativeFile($entry) {
    if ($null -eq $entry) { return "" }

    $kind = [string]$entry.Kind
    $file = [string]$entry.File
    $defType = [string]$entry.DefType

    if ($kind -eq "DefInjected") {
        if (-not [string]::IsNullOrWhiteSpace($defType)) {
            return "DefInjected\$defType\$defType.xml"
        }

        # Fallback for entries loaded from existing language XML where DefType
        # metadata may not be populated. Preserve a valid DefInjected path.
        if ($file -match '(?i)^DefInjected[\\/]+([^\\/]+)') {
            $typeFromPath = [string]$Matches[1]
            return "DefInjected\$typeFromPath\$typeFromPath.xml"
        }
    }

    return $file
}

function Select-BestTranslationEntry($entries) {
    $items = @($entries)
    if ($items.Count -eq 0) { return $null }

    # Prefer an explicitly translated row. This matters when the same key was
    # discovered from both a language pack and Defs/versioned roots.
    $translated = @($items | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Translation)
    })
    if ($translated.Count -gt 0) {
        return $translated[0]
    }

    $withSource = @($items | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Source)
    })
    if ($withSource.Count -gt 0) {
        return $withSource[0]
    }

    return $items[0]
}

function Test-WrittenLanguageFile([string]$filePath, $expectedEntries) {
    $missing = New-Object System.Collections.ArrayList

    if (-not (Test-Path -LiteralPath $filePath)) {
        foreach ($e in @($expectedEntries)) { [void]$missing.Add([string]$e.Key) }
        return @($missing)
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        if ($null -eq $doc.DocumentElement -or $doc.DocumentElement.Name -ne "LanguageData") {
            foreach ($e in @($expectedEntries)) { [void]$missing.Add([string]$e.Key) }
            return @($missing)
        }

        $written = @{}
        foreach ($node in @($doc.DocumentElement.ChildNodes)) {
            if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            $written[[string]$node.Name.ToLowerInvariant()] = $true
        }

        foreach ($e in @($expectedEntries)) {
            $key = [string]$e.Key
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if (-not $written.ContainsKey($key.ToLowerInvariant())) {
                [void]$missing.Add($key)
            }
        }
    } catch {
        foreach ($e in @($expectedEntries)) { [void]$missing.Add([string]$e.Key) }
    }

    return @($missing | Select-Object -Unique)
}

function Write-LanguageFiles([string]$outMod) {
    $targetCode = Get-SelectedTargetLanguageCode
    $targetFolder = Get-LanguageFolderName $targetCode
    $langRoot = Join-Path $outMod "Languages\$targetFolder"
    New-Item -ItemType Directory -Path $langRoot -Force | Out-Null

    # Canonicalize output paths before grouping. DefInjected entries generated
    # from different source roots/versions must end up in one deterministic XML.
    $prepared = New-Object System.Collections.ArrayList
    foreach ($e in @($script:Entries)) {
        $relativeFile = Get-TranslationOutputRelativeFile $e
        if ([string]::IsNullOrWhiteSpace($relativeFile)) { continue }

        [void]$prepared.Add([pscustomobject]@{
            Entry = $e
            RelativeFile = $relativeFile
            KeyNorm = ([string]$e.Key).ToLowerInvariant()
        })
    }


    # Build-time invariant: every canonical DefInjected row must have a prepared
    # output row. This catches losses before any XML is written.
    $preparedIds = @{}
    foreach ($p in @($prepared)) {
        $preparedIds[(Get-RimWorldEntryIdentity $p.Entry)] = $true
    }

    $lostBeforeWrite = New-Object System.Collections.ArrayList
    foreach ($e in @($script:Entries | Where-Object { $_.Kind -eq "DefInjected" })) {
        $id = Get-RimWorldEntryIdentity $e
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if (-not $preparedIds.ContainsKey($id)) {
            [void]$lostBeforeWrite.Add([string]$e.Key)
        }
    }

    if ($lostBeforeWrite.Count -gt 0) {
        throw "DefInjected reconciliation failed before XML write. Missing prepared entries: $($lostBeforeWrite.Count) :: $((@($lostBeforeWrite | Select-Object -First 20)) -join ', ')"
    }

    $fileGroups = @($prepared | Group-Object RelativeFile)
    $allMissing = New-Object System.Collections.ArrayList
    $writtenCount = 0

    foreach ($fileGroup in $fileGroups) {
        $relativeFile = [string]$fileGroup.Name
        $dest = Join-Path $langRoot $relativeFile
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null

        # Group duplicate keys inside the canonical target file and deliberately
        # select the row that actually contains a translation.
        $selected = New-Object System.Collections.ArrayList
        foreach ($keyGroup in @($fileGroup.Group | Group-Object KeyNorm)) {
            $candidates = @($keyGroup.Group | ForEach-Object { $_.Entry })
            $best = Select-BestTranslationEntry $candidates
            if ($null -ne $best) { [void]$selected.Add($best) }
        }

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
        [void]$sb.AppendLine('<LanguageData>')

        foreach ($e in @($selected | Sort-Object Key)) {
            $value = if ([string]::IsNullOrWhiteSpace([string]$e.Translation)) {
                [string]$e.Source
            } else {
                [string]$e.Translation
            }

            if ($null -eq $value) { $value = "" }
            $value = $value.TrimEnd()

            [void]$sb.AppendLine("  <$($e.Key)>$(XmlEscape $value)</$($e.Key)>")
            $writtenCount++
        }

        [void]$sb.AppendLine('</LanguageData>')
        [System.IO.File]::WriteAllText(
            $dest,
            $sb.ToString(),
            (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
        )

        # Never silently ship a translation mod that is missing rows visible in
        # the Toolkit table.
        $missing = @(Test-WrittenLanguageFile $dest $selected)
        foreach ($key in $missing) {
            [void]$allMissing.Add("$relativeFile :: $key")
        }
    }

    if ($allMissing.Count -gt 0) {
        $preview = (@($allMissing | Select-Object -First 20) -join "`r`n")
        throw "Translation build verification failed. Missing XML entries: $($allMissing.Count)`r`n`r`n$preview"
    }

    return [pscustomobject]@{
        Files = $fileGroups.Count
        Entries = $writtenCount
        Missing = 0
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


function Select-PreviewFlagForTargetLanguage {
    if ($null -eq $cmbPreviewFlag) { return }
    $lang = Get-SelectedTargetLanguage
    if ($null -eq $lang) { return }
    foreach ($item in $cmbPreviewFlag.Items) {
        if ([string]$item.Tag -ieq [string]$lang.Flag) {
            $cmbPreviewFlag.SelectedItem = $item
            break
        }
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



function Get-ToolkitCreatorId {
    $path = Join-Path (Get-ToolkitSettingsDirectory) "creator-id.txt"
    if (Test-Path -LiteralPath $path) {
        try {
            $v = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
            if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
        } catch {}
    }
    $author = ""
    try { $author = [string]$txtAuthor.Text } catch {}
    if ([string]::IsNullOrWhiteSpace($author)) { $author = "mtt" }
    $id = ($author.ToLowerInvariant() -replace '[^a-z0-9]+','').Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { $id = "mtt" }
    return $id
}

function Save-ToolkitCreatorId([string]$creatorId) {
    $creatorId = ($creatorId.ToLowerInvariant() -replace '[^a-z0-9]+','').Trim()
    if ([string]::IsNullOrWhiteSpace($creatorId)) { throw "Creator ID cannot be empty." }
    $path = Join-Path (Get-ToolkitSettingsDirectory) "creator-id.txt"
    [System.IO.File]::WriteAllText($path, $creatorId, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
    return $creatorId
}

function Get-TranslationPackageId([string]$originalPackageId, [string]$targetLanguageCode) {
    if ([string]::IsNullOrWhiteSpace($originalPackageId)) { return "" }
    $creatorId = Get-ToolkitCreatorId
    $lang = ($targetLanguageCode.ToLowerInvariant() -replace '[^a-z0-9]+','').Trim()
    if ([string]::IsNullOrWhiteSpace($lang)) { $lang = "translation" }
    return ("$originalPackageId.$creatorId.$lang").ToLowerInvariant()
}

function Get-TranslationModDisplayName([string]$originalName, $langInfo) {
    $languageName = [string]$langInfo.DisplayEnglish
    if ([string]::IsNullOrWhiteSpace($languageName)) { $languageName = [string]$langInfo.Name }
    if ([string]::IsNullOrWhiteSpace($languageName)) { $languageName = "Translation" }

    if ($languageName -eq "Translation") { return "$originalName - Translation" }
    return "$originalName - $languageName Translation"
}

function Get-TargetLanguageInfo {
    $lang = Get-SelectedTargetLanguage
    if ($null -eq $lang) { $lang = Get-LanguageByCode "pl" }

    return [pscustomobject]@{
        Code = [string]$lang.Code
        RimWorldFolder = [string]$lang.RimWorldFolder
        DisplayEnglish = [string]$lang.Name
        DisplayNative = [string]$lang.NativeName
        WorkshopSuffix = "$($lang.Name) Translation"
        WorkshopTitle = "$($lang.Name) Translation"
        NativeDisplay = [string]$lang.NativeName
        Flag = [string]$lang.Flag
    }
}


function Get-RimWorldModWorkshopDescriptionPath {
    $package = [string]$script:OriginalPackageId
    if ([string]::IsNullOrWhiteSpace($package)) { $package = "unknown" }
    $safe = ($package.ToLowerInvariant() -replace '[^a-z0-9_.-]','_')
    return (Join-Path (Get-ToolkitSettingsDirectory) "rimworld-mod-workshop-$safe.txt")
}

function Get-RimWorldModWorkshopDescription {
    $path = Get-RimWorldModWorkshopDescriptionPath
    if (Test-Path -LiteralPath $path) {
        try {
            $saved = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($saved)) {
                return [string]$saved
            }
        } catch {}
    }

    $author = ""
    try { $author = [string]$txtAuthor.Text } catch {}
    return (Get-SteamWorkshopDescriptionText $author)
}

function Save-RimWorldModWorkshopDescription([string]$value) {
    $path = Get-RimWorldModWorkshopDescriptionPath
    [System.IO.File]::WriteAllText(
        $path,
        [string]$value,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )
    return $path
}

function Reset-RimWorldModWorkshopDescription {
    $path = Get-RimWorldModWorkshopDescriptionPath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Show-RimWorldModWorkshopDescriptionEditor {
    if ([string]::IsNullOrWhiteSpace([string]$script:OriginalPackageId)) {
        [System.Windows.MessageBox]::Show(
            $(if ($script:UiLanguage -eq "en") { "Load a RimWorld mod first." } else { "Najpierw załaduj mod RimWorld." }),
            "Workshop description"
        ) | Out-Null
        return
    }

    [xml]$editorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RimWorld Mod - Workshop Description"
        Width="900" Height="680"
        MinWidth="700" MinHeight="500"
        WindowStartupLocation="CenterOwner"
        Background="#121018"
        Foreground="#ECE8F6">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0"
               Text="Opis Steam Workshop dla aktualnego moda tłumaczeniowego. Obsługuje BBCode Steam."
               Margin="0,0,0,10"
               Foreground="#B9AEC9"/>

    <TextBox Name="txtDescription"
             Grid.Row="1"
             AcceptsReturn="True"
             AcceptsTab="True"
             TextWrapping="Wrap"
             VerticalScrollBarVisibility="Auto"
             HorizontalScrollBarVisibility="Auto"
             FontFamily="Consolas"
             FontSize="13"
             Background="#1B1723"
             Foreground="#ECE8F6"
             BorderBrush="#4A3B5B"
             Padding="10"/>

    <Grid Grid.Row="2" Margin="0,12,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>

      <StackPanel Grid.Column="0" Orientation="Horizontal">
        <Button Name="btnDefault"
                Content="Wczytaj domyślny"
                Padding="14,7"
                Margin="0,0,8,0"
                Background="#2A2334"
                Foreground="White"/>
        <Button Name="btnDeleteSaved"
                Content="Usuń zapisany custom"
                Padding="14,7"
                Background="#2A2334"
                Foreground="White"/>
      </StackPanel>

      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button Name="btnCancel"
                Content="Anuluj"
                Padding="18,7"
                Margin="0,0,8,0"
                Background="#2A2334"
                Foreground="White"/>
        <Button Name="btnSave"
                Content="Zapisz opis"
                Padding="18,7"
                Background="#7A3FC2"
                Foreground="White"
                FontWeight="SemiBold"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $editorXaml
    $editor = [Windows.Markup.XamlReader]::Load($reader)
    try { $editor.Owner = $window } catch {}

    $txt = $editor.FindName("txtDescription")
    $btnDefault = $editor.FindName("btnDefault")
    $btnDeleteSaved = $editor.FindName("btnDeleteSaved")
    $btnCancel = $editor.FindName("btnCancel")
    $btnSave = $editor.FindName("btnSave")

    $txt.Text = Get-RimWorldModWorkshopDescription

    $btnDefault.Add_Click({
        $author = ""
        try { $author = [string]$txtAuthor.Text } catch {}
        $txt.Text = Get-SteamWorkshopDescriptionText $author
    })

    $btnDeleteSaved.Add_Click({
        Reset-RimWorldModWorkshopDescription
        $author = ""
        try { $author = [string]$txtAuthor.Text } catch {}
        $txt.Text = Get-SteamWorkshopDescriptionText $author
        Set-ControlTextSafe $txtStatus $(if ($script:UiLanguage -eq "en") {
            "Saved custom Workshop description removed."
        } else {
            "Usunięto zapisany własny opis Workshop."
        })
    })

    $btnCancel.Add_Click({
        $editor.DialogResult = $false
        $editor.Close()
    })

    $btnSave.Add_Click({
        try {
            [void](Save-RimWorldModWorkshopDescription ([string]$txt.Text))
            Set-ControlTextSafe $txtStatus $(if ($script:UiLanguage -eq "en") {
                "Custom Workshop description saved."
            } else {
                "Zapisano własny opis Workshop."
            })
            $editor.DialogResult = $true
            $editor.Close()
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message,"Workshop description") | Out-Null
        }
    })

    [void]$editor.ShowDialog()
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

$($lang.DisplayEnglish) translation for [b]$($script:OriginalModName)[/b].`r`nTarget language: [b]$($lang.DisplayNative)[/b].

[b]Requires the original mod.[/b]

[h1]Translation Info[/h1]`r`n[list]`r`n[*]Language: $($lang.DisplayEnglish) / $($lang.DisplayNative)`r`n[*]PackageId: $(Get-TranslationPackageId $script:OriginalPackageId $lang.Code)`r`n[/list]`r`n`r`n[h1]Requirements[/h1]
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
    $description = Get-RimWorldModWorkshopDescription
    $path = Join-Path $outMod "SteamWorkshopDescription.txt"
    [System.IO.File]::WriteAllText(
        $path,
        [string]$description,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )
    return $path
}


function Get-RimWorldEntryIdentity($entry) {
    if ($null -eq $entry) { return "" }

    $kind = [string]$entry.Kind
    $file = [string]$entry.File
    $key = [string]$entry.Key

    if ([string]::IsNullOrWhiteSpace($key)) { return "" }

    # For DefInjected use the canonical target file. This prevents a row shown
    # from a different source/version root from becoming a separate identity.
    if ($kind -eq "DefInjected") {
        $canonical = Get-TranslationOutputRelativeFile $entry
        if (-not [string]::IsNullOrWhiteSpace($canonical)) {
            $file = $canonical
        }
    }

    return ("$kind|$file|$key").ToLowerInvariant()
}

function Reconcile-GridEntriesIntoScriptEntries {
    $existing = @{}
    foreach ($e in @($script:Entries)) {
        $id = Get-RimWorldEntryIdentity $e
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $existing.ContainsKey($id)) {
            $existing[$id] = $e
        }
    }

    # DataGrid.Items contains the rows the user actually sees/edits.
    # Commit pending edits first so the last edited translation is not lost.
    try {
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
    } catch {}

    $added = 0
    $updated = 0

    foreach ($row in @($grid.Items)) {
        if ($null -eq $row) { continue }
        if ($row -eq [System.Windows.Data.CollectionView]::NewItemPlaceholder) { continue }

        $id = Get-RimWorldEntryIdentity $row
        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        if ($existing.ContainsKey($id)) {
            $dst = $existing[$id]

            # The grid is the authoritative editing surface.
            if (-not [string]::IsNullOrWhiteSpace([string]$row.Translation)) {
                $dst.Translation = [string]$row.Translation
            }
            if ([string]::IsNullOrWhiteSpace([string]$dst.Source) -and
                -not [string]::IsNullOrWhiteSpace([string]$row.Source)) {
                $dst.Source = [string]$row.Source
            }

            $updated++
            continue
        }

        # A row can exist in the current grid even if it originated from a
        # merged/versioned source and was lost from the canonical entry list.
        $clone = [pscustomobject]@{
            Kind = [string]$row.Kind
            File = [string]$row.File
            Key = [string]$row.Key
            Source = [string]$row.Source
            Translation = [string]$row.Translation
            DefType = [string]$row.DefType
            DefName = [string]$row.DefName
            Field = [string]$row.Field
        }

        # Recover Def metadata from the key/path when the grid row came from an
        # existing language file instead of directly from Defs.
        if ([string]::IsNullOrWhiteSpace([string]$clone.DefName) -and
            ([string]$clone.Key) -match '^(.+)\.([^.]+)$') {
            $clone.DefName = [string]$Matches[1]
            $clone.Field = [string]$Matches[2]
        }
        if ([string]::IsNullOrWhiteSpace([string]$clone.DefType) -and
            ([string]$clone.File) -match '(?i)DefInjected[\\/]+([^\\/]+)') {
            $clone.DefType = [string]$Matches[1]
            $clone.Kind = "DefInjected"
        }

        [void]$script:Entries.Add($clone)
        $existing[$id] = $clone
        $added++
    }

    # Rebuild EntryKeys from the final canonical list so later scans/builds use
    # the same identities as the reconciled entries.
    $script:EntryKeys = @{}
    foreach ($e in @($script:Entries)) {
        $id = Get-RimWorldEntryIdentity $e
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $script:EntryKeys[$id] = $true
        }
    }

    return [pscustomobject]@{
        Added = $added
        Updated = $updated
        Total = $script:Entries.Count
    }
}

function Get-BuildEntryDiagnostics([string[]]$keyPrefixes) {
    $rows = New-Object System.Collections.ArrayList

    foreach ($e in @($script:Entries)) {
        foreach ($prefix in $keyPrefixes) {
            if ([string]$e.Key -like "$prefix*") {
                [void]$rows.Add([pscustomobject]@{
                    Key = [string]$e.Key
                    Kind = [string]$e.Kind
                    File = [string]$e.File
                    CanonicalFile = Get-TranslationOutputRelativeFile $e
                    SourcePresent = -not [string]::IsNullOrWhiteSpace([string]$e.Source)
                    TranslationPresent = -not [string]::IsNullOrWhiteSpace([string]$e.Translation)
                    DefType = [string]$e.DefType
                    DefName = [string]$e.DefName
                    Field = [string]$e.Field
                })
                break
            }
        }
    }

    return @($rows)
}

function Build-TranslationMod([string]$parentFolder) {
    [void](Save-ToolkitTranslationCheckpoint "before-mod-build")

    $reconcileReport = Reconcile-GridEntriesIntoScriptEntries
    $buildDiag = @(Get-BuildEntryDiagnostics @("Tav_1x1Table","Tav_1x2Table"))

    $lang = Get-TargetLanguageInfo
    if ([string]::IsNullOrWhiteSpace($script:OriginalPackageId)) {
        throw "Oryginalny mod nie ma packageId w About.xml."
    }

    $safeName = ($script:OriginalModName -replace '[\\/:*?"<>|]', '_')
    $displayName = Get-TranslationModDisplayName $script:OriginalModName $lang
    $safeDisplayName = ($displayName -replace '[\\/:*?"<>|]', '_')
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
        $outMod = Join-Path $parentFolder $safeDisplayName
        if (Test-Path $outMod) {
            Remove-Item -LiteralPath $outMod -Recurse -Force
        }
    }

    New-Item -ItemType Directory -Path (Join-Path $outMod "About") -Force | Out-Null
    $languageWriteReport = Write-LanguageFiles $outMod

    $author = $txtAuthor.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($author)) { $author = "Community translation" }

    $pkg = Get-TranslationPackageId $script:OriginalPackageId $lang.Code

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
  <name>$([System.Security.SecurityElement]::Escape($displayName))</name>
  <author>$([System.Security.SecurityElement]::Escape($author))</author>
  <packageId>$pkg</packageId>
  <modVersion>1.0.0</modVersion>
$supportedXml  <description>$($lang.DisplayEnglish) translation for $([System.Security.SecurityElement]::Escape($script:OriginalModName)). Target language: $($lang.DisplayNative). Requires the original mod.

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
        [System.IO.File]::WriteAllText((Join-Path $outMod "About\About.xml"), $aboutText, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
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
Original PackageId: $($script:OriginalPackageId)
Generated PackageId: $(Get-TranslationPackageId $script:OriginalPackageId (Get-SelectedTargetLanguageCode))
Creator ID: $(Get-ToolkitCreatorId)
Selected content version: $($script:SelectedContentVersion)
Language roots: $((Get-LanguageRoots $script:OriginalModPath) -join "; ")`nKeyed entries: $keyed
DefInjected entries: $defs
Inherited Def fields generated: $($script:InheritedDefFieldCount)
Translated entries: $translated
Total unique entries: $($script:Entries.Count)
Language XML files written: $($languageWriteReport.Files)
Language XML entries written: $($languageWriteReport.Entries)
Language XML missing after verification: $($languageWriteReport.Missing)
Reconcile added entries: $($reconcileReport.Added)
Reconcile updated entries: $($reconcileReport.Updated)
Reconcile total entries: $($reconcileReport.Total)
Inherited Tav_1x1Table / Tav_1x2Table diagnostics:
$((@($script:InheritedDefDiagnostics | Where-Object { $_.Key -like "Tav_1x1Table*" -or $_.Key -like "Tav_1x2Table*" } | ForEach-Object { "  $($_.Key) | Parent=$($_.ParentName) | From=$($_.ResolvedFrom)" }) -join "`r`n"))
Diagnostic Tav_1x1Table / Tav_1x2Table entries:
$((@($buildDiag | ForEach-Object {
    "  $($_.Key) | Kind=$($_.Kind) | File=$($_.File) | Canonical=$($_.CanonicalFile) | Source=$($_.SourcePresent) | Translation=$($_.TranslationPresent) | DefType=$($_.DefType) | Field=$($_.Field)"
}) -join "`r`n"))
Steam Workshop description: $steamDescriptionPath
Source language: $((Get-SelectedSourceLanguageCode)) / $((Get-SelectedSourceRimWorldFolder))
Target language: $((Get-SelectedTargetLanguageCode)) / $((Get-SelectedTargetRimWorldFolder))
Source existing coverage: $((Get-CoverageText (Get-SelectedSourceLanguageCode)))
Target existing coverage: $((Get-CoverageText (Get-SelectedTargetLanguageCode)))
Existing target entries auto-loaded: $((AutoLoad-ExistingTargetTranslation))
Preview generated: $previewCreated
"@
    [System.IO.File]::WriteAllText((Join-Path $outMod "TranslationBuildReport.txt"), $report, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))

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

    $sourceTokens = @(Get-Placeholders $source)
    $result = [string]$translation

    # Repair legacy internal tokens leaked by versions up to v0.10.0.
    $legacy = @([regex]::Matches($result, '__MTTPH(\d+)__'))
    foreach ($m in @($legacy | Sort-Object Index -Descending)) {
        $index = [int]$m.Groups[1].Value
        if ($index -ge 0 -and $index -lt $sourceTokens.Count) {
            $result = $result.Remove($m.Index, $m.Length).Insert(
                $m.Index,
                [string]$sourceTokens[$index]
            )
        }
    }

    # Repair new diagnostic tokens if a provider ever returns them unchanged.
    $modern = @([regex]::Matches(
        $result,
        'ZXQ\s*MTTPH\s*0*(\d+)\s*QXZ',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    ))
    foreach ($m in @($modern | Sort-Object Index -Descending)) {
        $index = [int]$m.Groups[1].Value
        if ($index -ge 0 -and $index -lt $sourceTokens.Count) {
            $result = $result.Remove($m.Index, $m.Length).Insert(
                $m.Index,
                [string]$sourceTokens[$index]
            )
        }
    }

    $missing = @(Get-MissingPlaceholders $source $result)
    foreach ($token in $missing) {
        # Literal \n is structural. Append it without converting it into a real line break.
        if (-not $result.Contains([string]$token)) {
            $result = ($result.TrimEnd() + " " + [string]$token).Trim()
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
        if ([string]::IsNullOrWhiteSpace([string]$e.Translation)) { continue }

        # Recover old leaked internal tokens before validation.
        $repaired = Repair-TranslationPlaceholders ([string]$e.Source) ([string]$e.Translation)
        if ($repaired -cne [string]$e.Translation) {
            $e.Translation = $repaired
        }

        if (-not (Test-TranslationPlaceholderIntegrity ([string]$e.Source) ([string]$e.Translation))) {
            [void]$bad.Add($e)
        }
    }

    return @($bad)
}


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
    [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
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
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)
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
    [System.IO.File]::WriteAllText((Join-Path $localeRoot "ModTranslationToolkit-Kenshi.txt"), $instructions, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
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
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
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

    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 8
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

    if ($null -ne $txtCreatorName) { $txtCreatorName.Text = $name }
    if ($null -ne $txtSteamProfile) { $txtSteamProfile.Text = [string]$script:CreatorProfile.SteamProfile }

    if (-not [string]::IsNullOrWhiteSpace($name) -and $null -ne $txtAuthor) {
        $txtAuthor.Text = $name
    }
}

# ---------- Dark / Mrokar purple UI ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mod Translation Toolkit v0.10.24"
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
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border Name="ItemBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="#C7B5D8"
                    BorderThickness="0,0,0,1"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Stretch"
                                VerticalAlignment="Center"
                                TextElement.Foreground="{TemplateBinding Foreground}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#D5BDF0"/>
                <Setter Property="Foreground" Value="#120E17"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#7A3FC2"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
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
          <TextBlock Name="txtAppSubtitle" Text="RimWorld profile • dark Mrokar theme" Foreground="#AFA2C0" FontSize="12"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Button Name="btnApiSettings" Content="API / Tłumaczenie" Margin="0,0,8,0"/>
          <Border Background="#2B2038" CornerRadius="5" Padding="10,5" VerticalAlignment="Center">
            <TextBlock Text="v0.10.24" Foreground="#CDA8F2" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
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
              <TextBlock Name="txtRimWorldGameTitle" Text="RimWorld Game — podstawa gry i dodatki" FontSize="18" FontWeight="SemiBold" Foreground="#CDA8F2"/>
              <TextBlock Name="txtRimWorldGameSubtitle" Text="Wybierz Core albo dowolny z wykrytych dodatków. Każdy moduł może być skanowany osobno."
                         Foreground="#B9AEC9" Margin="0,4,0,0" TextWrapping="Wrap"/>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                <TextBlock Name="lblRwGameSourceLang" Text="Źródło:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="cmbRwGameSourceLang" Width="220" Margin="0,0,14,0"/>
                <TextBlock Name="lblRwGameTargetLang" Text="Cel:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="cmbRwGameTargetLang" Width="220"/>
              </StackPanel>
            </StackPanel>
          </Border>

          <Grid Grid.Row="2" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Name="txtModulesDlc" Text="Moduły / DLC:" FontWeight="SemiBold" Margin="0,0,0,4"/>
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
              <DataGridTextColumn Header="Źródło" Binding="{Binding Source}" Width="*"/>
              <DataGridTextColumn Header="Tłumaczenie" Binding="{Binding Translation}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <Grid Grid.Row="4" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Orientation="Horizontal">
              <TextBlock Name="lblRimWorldGameCount" Text="Wpisy: 0" VerticalAlignment="Center" Margin="0,0,12,0"/>
              <TextBlock Name="lblRimWorldGameFilter" Text="Filtr:" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <ComboBox Name="cmbRimWorldGameFilter" Width="190" Margin="0,0,12,0">
                <ComboBoxItem Content="Wszystkie" Tag="all" IsSelected="True"/>
                <ComboBoxItem Content="Brak tłumaczenia" Tag="missing"/>
                <ComboBoxItem Content="Przetłumaczone" Tag="translated"/>
                <ComboBoxItem Content="Identyczne source/target" Tag="identical"/>
                <ComboBoxItem Content="Podejrzane" Tag="suspicious"/>
              </ComboBox>
              <TextBlock Name="txtRimWorldGameStatus" Text="Wybierz folder gry albo użyj automatycznego wykrywania."
                         Foreground="#B9AEC9" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" Margin="12,0,0,0">
              <Button Name="btnTranslateRimWorldGameMissing" Content="Tłumacz brakujące" Margin="0,0,8,0"/>
              <Button Name="btnRimWorldGameGlossary" Content="Glosariusz..." Margin="0,0,8,0"/>
              <Button Name="btnRimWorldGameLearningMode" Content="Nauka: Ciche" Margin="0,0,8,0"/>
              <Button Name="btnRimWorldGameLearningSuggestions" Content="Propozycje: 0" Margin="0,0,8,0"/>
              <Button Name="btnBuildRimWorldGameTranslation" Content="Zbuduj mod tłumaczeniowy" Margin="0,0,8,0"/>
              <Button Name="btnEditRimWorldGameWorkshopDescription" Content="Opis Workshop..." Margin="0,0,8,0"/>
              <Button Name="btnExportRimWorldGameCsv" Content="Eksport CSV" Margin="0,0,8,0"/>
              <Button Name="btnImportRimWorldGameCsv" Content="Import CSV"/>
            </StackPanel>
          </Grid>
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
              <ComboBoxItem Content="繁體中文 🇹🇼" Tag="TW"/>
              <ComboBoxItem Content="Português (Brasil) 🇧🇷" Tag="BR"/>
              <ComboBoxItem Content="Русский 🇷🇺" Tag="RU"/>
              <ComboBoxItem Content="Svenska 🇸🇪" Tag="SE"/>
              <ComboBoxItem Content="Nederlands 🇳🇱" Tag="NL"/>
            </ComboBox>
          </Grid>

          <WrapPanel Grid.Row="2" Margin="0,0,0,10">
            <Button Name="btnExport" Content="Eksport CSV"/>
            <Button Name="btnImport" Content="Import CSV"/>
            <Label Name="lblSourceLang" Content="Z:" VerticalContentAlignment="Center"/>
            <ComboBox Name="cmbSourceLang" Width="105" Height="30" Margin="0,0,8,0"/>
            <Label Name="lblTargetLang" Content="Na:" VerticalContentAlignment="Center"/>
            <ComboBox Name="cmbTargetLang" Width="105" Height="30" Margin="0,0,8,0"/>
            <Button Name="btnAutoTranslate" Content="Tłumacz brakujące"/>
            <Button Name="btnValidate" Content="Sprawdź / napraw placeholdery"/>
            <Button Name="btnKeybindDiagnostics" Content="Diagnostyka skrótów"/>
            <Button Name="btnAssemblyDiagnostics" Content="Diagnostyka DLL/UI"/>
            <Button Name="btnBuild" Content="Zbuduj oddzielny mod"/>
            <Button Name="btnCopyWorkshop" Content="Kopiuj opis Workshop" IsEnabled="True"/>
              <Button Name="btnEditModWorkshopDescription" Content="Opis Workshop..." Margin="8,0,0,0"/>
              <Button Name="btnRimWorldModGlossary" Content="Glosariusz..." Margin="8,0,0,0"/>
              <Button Name="btnRimWorldModLearningMode" Content="Nauka: Ciche" Margin="8,0,0,0"/>
              <Button Name="btnRimWorldModLearningSuggestions" Content="Propozycje: 0" Margin="8,0,0,0"/>
            <Label Name="lblCount" Content="Wpisy: 0" VerticalContentAlignment="Center"/>
          </WrapPanel>


          <Border Grid.Row="3" Background="#19151F" BorderBrush="#40344F" BorderThickness="1"
                  CornerRadius="4" Padding="8" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Name="lblCoverageTitle" Text="Stan lokalizacji:" VerticalAlignment="Center"
                         Foreground="#B9AEC9" Margin="0,0,0,6"/>
              <WrapPanel>
                <TextBlock Name="txtCoveragePL" Text="Polski: -" VerticalAlignment="Center"
                           Foreground="#D4B5F5" Margin="0,0,12,0"/>
                <Button Name="btnLoadExistingPL" Content="Odśwież tłumaczenie PL" IsEnabled="False"/>
                <Button Name="btnLoadExternalPL" Content="Wczytaj z folderu..." Margin="6,0,0,0"/>
              </WrapPanel>
              <WrapPanel Margin="0,6,0,0">
                <TextBlock Name="txtCoverageEN" Text="English: -" VerticalAlignment="Center"
                           Foreground="#D4B5F5" Margin="0,0,12,0"/>
                <Button Name="btnLoadExistingEN" Content="Wczytaj ponownie EN" IsEnabled="False"/>
              </WrapPanel>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <TextBlock Name="lblCreatorId" Text="Creator ID:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <TextBox Name="txtCreatorId" Width="160" ToolTip="Stały identyfikator autora używany w packageId tłumaczeń."/>
                <Button Name="btnSaveCreatorId" Content="Zapisz ID" Margin="8,0,0,0"/>
              </StackPanel>
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
              <Button Name="btnEditMultiline" Content="Edytuj wieloliniowo..." Margin="8,0,0,0"
                      ToolTip="Edytuj tekst z \n jako normalne akapity i podziały linii."/>
              <Label Name="lblSearchCount" Content="" VerticalContentAlignment="Center" Margin="8,0,0,0"/>
            </WrapPanel>
          </Border>

          <DataGrid Grid.Row="5" Name="grid" AutoGenerateColumns="False" CanUserAddRows="False"
                    CanUserDeleteRows="False" IsReadOnly="False" SelectionMode="Extended"
                    EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Typ" Binding="{Binding Kind}" Width="95" IsReadOnly="True"/>
              <DataGridTextColumn Header="Plik" Binding="{Binding File}" Width="180" IsReadOnly="True"/>
              <DataGridTemplateColumn Header="Klucz" Width="230" IsReadOnly="True">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding Key}" ToolTip="{Binding Key}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
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
      
      <TabItem Name="tabProjectZomboidGame" Header="Project Zomboid Game">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="btnDetectPzGame" Content="Wykryj Project Zomboid"/>
            <Button Name="btnChoosePzGame" Content="Wybierz folder gry"/>
            <TextBox Name="txtPzGamePath" Width="650" Margin="8,0" AllowDrop="True"
                     ToolTip="Wklej ścieżkę lub przeciągnij tutaj folder Project Zomboid."/>
            <Button Name="btnOpenPzGameFolder" Content="Otwórz folder"/>
          </StackPanel>

          <Border Grid.Row="1" Background="#211A2B" BorderBrush="#4A385D" BorderThickness="1"
                  CornerRadius="6" Padding="10" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Name="txtPzGameTitle" Text="Project Zomboid Game - eksperymentalny profil"
                         FontSize="18" FontWeight="SemiBold" Foreground="#CDA8F2"/>
              <TextBlock Name="txtPzGameSubtitle"
                         Text="Skanuje pliki TXT i JSON w media/lua/shared/Translate/&lt;LANG&gt;."
                         Foreground="#B9AEC9" Margin="0,4,0,0" TextWrapping="Wrap"/>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                <TextBlock Name="lblPzGameSource" Text="Źródło:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="cmbPzGameSourceLang" Width="220" Margin="0,0,14,0"/>
                <TextBlock Name="lblPzGameTarget" Text="Cel:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="cmbPzGameTargetLang" Width="220"/>
              </StackPanel>
            </StackPanel>
          </Border>

          <StackPanel Grid.Row="2" Margin="0,0,0,10">
            <WrapPanel>
              <Button Name="btnScanPzGame" Content="Skanuj grę"/>
              <Button Name="btnTranslatePzGameMissing" Content="Tłumacz brakujące"/>
              <Button Name="btnExportPzGameCsv" Content="Eksport CSV"/>
              <Button Name="btnImportPzGameCsv" Content="Import CSV"/>
              <TextBlock Name="lblPzGameFilter" Text="Filtr:" VerticalAlignment="Center" Margin="10,0,6,0"/>
              <ComboBox Name="cmbPzGameFilter" Width="170">
                <ComboBoxItem Content="Wszystkie" Tag="all" IsSelected="True"/>
                <ComboBoxItem Content="Brak targetu" Tag="missing"/>
                <ComboBoxItem Content="Identyczne source/target" Tag="identical"/>
                <ComboBoxItem Content="Podejrzane / untranslated" Tag="suspicious"/>
              </ComboBox>
              <Label Name="lblPzGameCount" Content="Wpisy: 0" VerticalContentAlignment="Center" Margin="8,0,0,0"/>
            </WrapPanel>
            <Grid Margin="0,8,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="85"/>
              </Grid.ColumnDefinitions>
              <ProgressBar Name="prgPzGameScan" Grid.Column="0" Height="18" Minimum="0" Maximum="100" Value="0" ToolTip="Postęp skanowania lub automatycznego tłumaczenia"/>
              <TextBlock Name="lblPzGameProgress" Grid.Column="1" Text="0%" HorizontalAlignment="Right"
                         VerticalAlignment="Center" Margin="10,0,0,0"/>
            </Grid>
          </StackPanel>

          <DataGrid Grid.Row="3" Name="pzGameGrid" AutoGenerateColumns="False" CanUserAddRows="False"
                    CanUserDeleteRows="False" IsReadOnly="False" SelectionMode="Extended"
                    EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Plik" Binding="{Binding File}" Width="190" IsReadOnly="True"/>
              <DataGridTextColumn Header="Klucz" Binding="{Binding Key}" Width="300" IsReadOnly="True"/>
              <DataGridTemplateColumn Header="Źródło" Width="*">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBox Text="{Binding Source}" IsReadOnly="True" IsReadOnlyCaretVisible="True"
                             BorderThickness="0" Background="Transparent" Foreground="#ECE8F6"
                             Padding="2,0" TextWrapping="NoWrap"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Tłumaczenie"
                                  Binding="{Binding Translation, UpdateSourceTrigger=PropertyChanged}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <TextBlock Grid.Row="4" Name="txtPzGameStatus" Margin="0,10,0,0" TextWrapping="Wrap"
                     Foreground="#B9AEC9"
                     Text="Wykryj Project Zomboid lub wskaż folder instalacji gry."/>
        </Grid>
      </TabItem>
<TabItem Name="tabProjectZomboidMod" Header="Project Zomboid Mod">
        <Grid Margin="12" Background="{StaticResource Bg}">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
            <Button Name="btnDetectPzMods" Content="Wykryj mody"/>
            <Button Name="btnChoosePzMod" Content="Wybierz folder moda"/>
            <TextBox Name="txtPzModPath" Width="620" Margin="8,0" AllowDrop="True"
                     ToolTip="Ścieżka aktualnie wybranego moda Project Zomboid."/>
            <Button Name="btnOpenPzModFolder" Content="Otworz folder"/>
          </StackPanel>

          <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Name="lblPzDetectedMod" Text="Wykryty mod:" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <ComboBox Name="cmbPzDetectedMods" Width="620"/>
            <TextBlock Name="lblPzDetectedCount" Text="Mody: 0" VerticalAlignment="Center" Margin="12,0,0,0"/>
          </StackPanel>

          <Border Grid.Row="2" Background="#211A2B" BorderBrush="#4A385D" BorderThickness="1"
                  CornerRadius="6" Padding="10" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Name="txtPzTitle" Text="Project Zomboid Mod - eksperymentalny profil" FontSize="18"
                         FontWeight="SemiBold" Foreground="#CDA8F2"/>
              <TextBlock Name="txtPzSubtitle"
                         Text="Obsługa B41/B42: TXT oraz JSON, w tym wersjonowane katalogi modów B42."
                         Foreground="#B9AEC9" Margin="0,4,0,0" TextWrapping="Wrap"/>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                <TextBlock Name="lblPzSource" Text="Zrodlo:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="cmbPzSourceLang" Width="220" Margin="0,0,14,0"/>
                <TextBlock Name="lblPzTarget" Text="Cel:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="cmbPzTargetLang" Width="220"/>
              </StackPanel>
            </StackPanel>
          </Border>

          <WrapPanel Grid.Row="3" Margin="0,0,0,10">
            <Button Name="btnScanPzMod" Content="Skanuj mod"/>
            <Button Name="btnTranslatePzMissing" Content="Tlumacz brakujace"/>
            <Button Name="btnExportPzCsv" Content="Eksport CSV"/>
            <Button Name="btnImportPzCsv" Content="Import CSV"/>
            <Button Name="btnBuildPzTranslation" Content="Zbuduj mod tlumaczeniowy"/>
            <Button Name="btnOpenPzWorkshopStage" Content="Otworz paczke Workshop" IsEnabled="False"/>
            <Button Name="btnCopyPzWorkshop" Content="Kopiuj opis Workshop" IsEnabled="False"/>
            <Label Name="lblPzCount" Content="Wpisy: 0" VerticalContentAlignment="Center" Margin="8,0,0,0"/>
          </WrapPanel>

          <DataGrid Grid.Row="4" Name="pzGrid" AutoGenerateColumns="False" CanUserAddRows="False"
                    CanUserDeleteRows="False" IsReadOnly="False" SelectionMode="Extended"
                    EnableRowVirtualization="True" AlternationCount="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Root" Binding="{Binding Root}" Width="110" IsReadOnly="True"/>
              <DataGridTextColumn Header="Plik" Binding="{Binding File}" Width="190" IsReadOnly="True"/>
              <DataGridTextColumn Header="Klucz" Binding="{Binding Key}" Width="280" IsReadOnly="True"/>
              <DataGridTemplateColumn Header="Zrodlo" Width="*">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBox Text="{Binding Source}" IsReadOnly="True" IsReadOnlyCaretVisible="True"
                             BorderThickness="0" Background="Transparent" Foreground="#ECE8F6"
                             Padding="2,0" TextWrapping="NoWrap"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Tlumaczenie"
                                  Binding="{Binding Translation, UpdateSourceTrigger=PropertyChanged}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <TextBlock Grid.Row="5" Name="txtPzStatus" Margin="0,10,0,0" TextWrapping="Wrap"
                     Foreground="#B9AEC9"
                     Text="Wybierz mod Project Zomboid. Profil może teraz zbudować osobny mod tłumaczeniowy gotowy do przygotowania pod Workshop."/>
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

              <TextBlock Name="txtCreatorNameLabel" Grid.Column="0" Text="Nazwa kreatora:" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBox Grid.Column="1" Name="txtCreatorName" Margin="0,0,12,0"
                       ToolTip="Nazwa używana jako autor tłumaczeń."/>
              <TextBlock Name="txtSteamProfileLabel" Grid.Column="2" Text="SteamID / profil:" VerticalAlignment="Center" Margin="0,0,6,0"/>
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

    <Border Name="busyOverlay" Grid.RowSpan="2" Panel.ZIndex="999" Background="#D914101C"
            Visibility="Collapsed" IsHitTestVisible="True">
      <Grid>
        <Border Background="#211A2B" BorderBrush="#9D64E8" BorderThickness="1" CornerRadius="10"
                Padding="28,22" Width="440" HorizontalAlignment="Center" VerticalAlignment="Center">
          <StackPanel>
            <TextBlock Name="txtBusyTitle" Text="Skanowanie moda..." FontSize="20" FontWeight="Bold"
                       Foreground="#D4B5F5" HorizontalAlignment="Center"/>
            <TextBlock Name="txtBusyStage" Text="Przygotowywanie..." Margin="0,12,0,14"
                       Foreground="#ECE8F6" TextAlignment="Center" TextWrapping="Wrap"/>
            <ProgressBar Name="busyProgress" Height="8" IsIndeterminate="True"/>
            <TextBlock Name="txtBusyHint" Text="Program pracuje. Przy dużych modach może to potrwać chwilę."
                       Margin="0,12,0,0" Foreground="#AFA2C0" TextAlignment="Center" TextWrapping="Wrap" FontSize="11"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$names = @(
    "btnChooseMod","btnAnalyze","btnExport","btnImport","btnAutoTranslate","btnValidate","btnBuild",
    "txtModPath","txtModName","txtPackageId","txtAuthor","grid","lblCount","txtStatus","busyOverlay","txtBusyTitle","txtBusyStage","busyProgress","txtBusyHint",
    "btnDetect","txtSearch","lblMods","modsGrid","btnUseSelected","btnOpenFolder","btnOpenCurrentFolder","cmbSourceLang","cmbTargetLang","lblSourceLang","lblTargetLang","tabTranslation","tabInstalledMods","tabGameProfiles","chkPreviewFlag","cmbPreviewFlag","btnCopyWorkshop","btnEditModWorkshopDescription","btnRimWorldModGlossary","btnRimWorldModLearningMode","btnRimWorldModLearningSuggestions","lblCoverageTitle","txtCoveragePL","txtCoverageEN","btnLoadExistingPL","btnLoadExternalPL","btnLoadExistingEN","btnEditMultiline","tabKenshi","btnDetectKenshi","btnChooseKenshi","txtKenshiPath","btnOpenKenshiFolder","btnScanKenshi","btnTranslateKenshi","btnExportKenshiCsv","btnImportKenshiCsv","btnFcsHelpKenshi","btnBuildKenshi","lblKenshiCount","kenshiGrid","txtKenshiStatus",
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
  "btnTranslateRimWorldGameMissing","btnRimWorldGameGlossary","btnRimWorldGameLearningMode","btnRimWorldGameLearningSuggestions",
  "btnBuildRimWorldGameTranslation",
  "btnEditRimWorldGameWorkshopDescription",
  "btnExportRimWorldGameCsv",
  "btnImportRimWorldGameCsv",
  "rimWorldGameGrid",
  "lblRimWorldGameCount",
    "lblRimWorldGameFilter","cmbRimWorldGameFilter",
  "txtRimWorldGameStatus",
  "btnApiSettings",
  "txtAppSubtitle",
  "txtRimWorldGameTitle",
  "txtRimWorldGameSubtitle",
  "txtModulesDlc",
  "txtCreatorNameLabel",
  "txtSteamProfileLabel",
  "lblRwGameSourceLang",
  "cmbRwGameSourceLang",
  "lblRwGameTargetLang",
  "cmbRwGameTargetLang",
  "lblCreatorId",
  "txtCreatorId",
  "btnSaveCreatorId",
  "tabProjectZomboidGame",
  "btnDetectPzGame",
  "btnChoosePzGame",
  "txtPzGamePath",
  "btnOpenPzGameFolder",
  "txtPzGameTitle",
  "txtPzGameSubtitle",
  "lblPzGameSource",
  "cmbPzGameSourceLang",
  "lblPzGameTarget",
  "cmbPzGameTargetLang",
  "btnScanPzGame",
  "btnTranslatePzGameMissing",
  "btnExportPzGameCsv",
  "btnImportPzGameCsv",
  "lblPzGameFilter",
  "cmbPzGameFilter",
  "lblPzGameCount",
  "prgPzGameScan",
  "lblPzGameProgress",
  "pzGameGrid",
  "txtPzGameStatus",
  "tabProjectZomboidMod",
  "btnDetectPzMods",
  "btnChoosePzMod",
  "lblPzDetectedMod",
  "cmbPzDetectedMods",
  "lblPzDetectedCount",
  "txtPzModPath",
  "btnOpenPzModFolder",
  "txtPzTitle",
  "txtPzSubtitle",
  "lblPzSource",
  "cmbPzSourceLang",
  "lblPzTarget",
  "cmbPzTargetLang",
  "btnScanPzMod",
  "btnTranslatePzMissing",
  "btnExportPzCsv",
  "btnImportPzCsv",
  "btnBuildPzTranslation",
  "btnOpenPzWorkshopStage",
  "btnCopyPzWorkshop",
  "lblPzCount",
  "pzGrid",
  "txtPzStatus"
)
foreach ($n in $names) { Set-Variable -Name $n -Value $window.FindName($n) }

Load-WorkshopProfile
Apply-CreatorProfileToTranslator

Update-RimWorldLearningUi

# Learn from manual corrections made after an automatic translation.
$grid.Add_CellEditEnding({
    param($sender,$e)
    try {
        if ($null -eq $e.Row -or $null -eq $e.Row.Item) { return }
        if ($null -eq $e.Column -or [int]$e.Column.DisplayIndex -ne 4) { return }

        $newValue = ""
        if ($e.EditingElement -is [System.Windows.Controls.TextBox]) {
            $newValue = [string]$e.EditingElement.Text
        } else {
            $newValue = [string]$e.Row.Item.Translation
        }

        Handle-RimWorldManualTranslationEdit $e.Row.Item "Mod" $newValue
    } catch {}
})

$rimWorldGameGrid.Add_CellEditEnding({
    param($sender,$e)
    try {
        if ($null -eq $e.Row -or $null -eq $e.Row.Item) { return }
        if ($null -eq $e.Column -or [int]$e.Column.DisplayIndex -ne 4) { return }

        $newValue = ""
        if ($e.EditingElement -is [System.Windows.Controls.TextBox]) {
            $newValue = [string]$e.EditingElement.Text
        } else {
            $newValue = [string]$e.Row.Item.Translation
        }

        Handle-RimWorldManualTranslationEdit $e.Row.Item "Game" $newValue
    } catch {}
})





function Get-CoverageText([string]$code) {
    $lang = Get-LanguageByCode $code
    $name = if ($null -ne $lang) { [string]$lang.NativeName } else { $code }

    if (-not $script:LanguageCoverage.ContainsKey($code)) {
        return "$name`: -"
    }

    $c = $script:LanguageCoverage[$code]
    $sourceCode = Get-SelectedSourceLanguageCode
    $isSource = ($code -ieq $sourceCode)

    if ($isSource -and [int]$c.Found -eq 0) {
        if ($script:UiLanguage -eq "en") {
            return "Source localization $name`: none (using texts from Defs)"
        }
        return "Lokalizacja źródłowa $name`: brak (używane są teksty z Defs)"
    }

    if ($isSource) {
        if ($script:UiLanguage -eq "en") {
            return "Source localization $name`: $($c.Matched)/$($c.Total) entries"
        }
        return "Lokalizacja źródłowa $name`: $($c.Matched)/$($c.Total) wpisów"
    }

    if ($script:UiLanguage -eq "en") {
        return "Target $name`: $($c.Translated)/$($c.Translatable) ($($c.Percent)%) • identical to source: $($c.Identical) • missing: $($c.Missing) • technical: $($c.Technical) • total: $($c.Total)"
    }
    return "Tłumaczenie $name`: $($c.Translated)/$($c.Translatable) ($($c.Percent)%) • identyczne ze źródłem: $($c.Identical) • brakuje: $($c.Missing) • techniczne: $($c.Technical) • razem: $($c.Total)"
}

if ($null -ne $txtCreatorId) { $txtCreatorId.Text = Get-ToolkitCreatorId }
if ($null -ne $btnSaveCreatorId) {
    $btnSaveCreatorId.Add_Click({
        try {
            $saved = Save-ToolkitCreatorId $txtCreatorId.Text
            $txtCreatorId.Text = $saved
            $msg = if ($script:UiLanguage -eq "en") { "Creator ID saved: $saved" } else { "Zapisano Creator ID: $saved" }
            [System.Windows.MessageBox]::Show($msg,"Mod Translation Toolkit") | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message,"Mod Translation Toolkit") | Out-Null
        }
    })
}

Populate-LanguageCombo $cmbSourceLang "en"
Populate-LanguageCombo $cmbTargetLang "pl"
Select-PreviewFlagForTargetLanguage
Populate-LanguageCombo $cmbRwGameSourceLang "en"
Populate-LanguageCombo $cmbRwGameTargetLang "pl"
Populate-PzLanguageCombo $cmbPzSourceLang "en"
Populate-PzLanguageCombo $cmbPzTargetLang "pl"
Populate-PzLanguageCombo $cmbPzGameSourceLang "en"
Populate-PzLanguageCombo $cmbPzGameTargetLang "pl"

$cmbSourceLang.Add_SelectionChanged({
    if (-not [string]::IsNullOrWhiteSpace([string]$txtModPath.Text) -and (Test-ExistingFolderSafe $txtModPath.Text)) {
        try {
            $scan = Analyze-Mod $txtModPath.Text
            Refresh-LanguageCoverageUi
        } catch {}
    }
})

$cmbTargetLang.Add_SelectionChanged({
    if (-not [string]::IsNullOrWhiteSpace([string]$txtModPath.Text) -and (Test-ExistingFolderSafe $txtModPath.Text)) {
        try {
            Update-LanguageCoverage $txtModPath.Text
            foreach ($e in $script:Entries) { $e.Translation = "" }
            [void](AutoLoad-ExistingTargetTranslation)
            Refresh-LanguageCoverageUi
            Refresh-Grid
        } catch {}
    }

    Select-PreviewFlagForTargetLanguage
})


function Refresh-LanguageCoverageUi {
    $src = Get-SelectedSourceLanguageCode
    $dst = Get-SelectedTargetLanguageCode

    $txtCoverageEN.Text = Get-CoverageText $src
    $txtCoveragePL.Text = Get-CoverageText $dst

    $btnLoadExistingEN.Content = if ($script:UiLanguage -eq "en") { "Load source localization" } else { "Wczytaj lokalizację źródłową" }
    $btnLoadExistingPL.Content = if ($script:UiLanguage -eq "en") { "Refresh target translation" } else { "Odśwież tłumaczenie docelowe" }
    if ($null -ne $btnLoadExternalPL) { $btnLoadExternalPL.Content = if ($script:UiLanguage -eq "en") { "Load from folder..." } else { "Wczytaj z folderu..." } }

    $btnLoadExistingEN.IsEnabled = ($script:ExistingTranslations.ContainsKey($src) -and $script:ExistingTranslations[$src].Count -gt 0)
    $btnLoadExistingPL.IsEnabled = ($script:ExistingTranslations.ContainsKey($dst) -and $script:ExistingTranslations[$dst].Count -gt 0)
}


# ---------- Central UI localization ----------
$script:UiText = @{
    pl = @{
        AppSubtitle = "RimWorld profile • dark Mrokar theme"
        GameProfiles = "Profile gier"
        Workshop = "Workshop"
        RimWorldGame = "RimWorld Game"
        RimWorldMod = "RimWorld Mod"
        KenshiGame = "Kenshi Game"
        ProjectZomboidMod = "Project Zomboid Mod"
        ProjectZomboidGame = "Project Zomboid Game"
        Translation = "Tłumaczenie"
        InstalledMods = "Zainstalowane mody"
        DetectRimWorld = "Wykryj RimWorld"
        ChooseGameFolder = "Wybierz folder gry"
        OpenFolder = "Otwórz folder"
        RimWorldGameTitle = "RimWorld Game — podstawa gry i dodatki"
        RimWorldGameSubtitle = "Wybierz Core albo dowolny z wykrytych dodatków. Każdy moduł może być skanowany osobno."
        RwGameSourceLabel = "Źródło:"
        RwGameTargetLabel = "Cel:"
        RwGameModuleHeader = "Moduł"
        RwGameTypeHeader = "Typ"
        RwGameKeyHeader = "Klucz"
        RwGameSourceHeader = "Źródło"
        RwGameTargetHeader = "Tłumaczenie"
        RwGameDetectedModules = "Wykryto moduły: {0}."
        RwGameScanInProgress = "Skanowanie RimWorld Game..."
        RwGameSelectModule = "Zaznacz co najmniej jeden moduł / DLC."

        ModulesDlc = "Moduły / DLC:"
        SelectAll = "Zaznacz wszystko"
        CoreOnly = "Tylko Core"
        DlcOnly = "Tylko DLC"
        ScanSelected = "Skanuj wybrane"
        Entries = "Wpisy: 0"
        ChooseGameOrDetect = "Wybierz folder gry albo użyj automatycznego wykrywania."
        ChooseModFolder = "Wybierz folder moda"
        ScanAgain = "Skanuj ponownie"
        UpdateExistingTranslation = "Aktualizuj istniejące tłumaczenie"
        OpenModFolder = "Otwórz folder moda"
        Name = "Nazwa:"
        TranslatorAuthor = "Autor tłumaczenia:"
        PreviewFlag = "Preview + flaga"
        ExportCsv = "Eksport CSV"
        ImportCsv = "Import CSV"
        From = "Z:"
        To = "Na:"
        TranslateMissing = "Tłumacz brakujące"
        ValidatePlaceholders = "Sprawdź / napraw placeholdery"
        KeybindDiagnostics = "Diagnostyka skrótów"
        DllDiagnostics = "Diagnostyka DLL/UI"
        BuildSeparateMod = "Zbuduj oddzielny mod"
        CopyWorkshop = "Kopiuj opis Workshop"
        ExistingLanguages = "Stan lokalizacji"
        Search = "Szukaj:"
        Clear = "Wyczyść"
        NewText = "Nowy tekst:"
        ReplaceAll = "Zamień wszędzie"
        DetectSteamMods = "Wykryj Steam i mody"
        ModsCount = "Mody: 0"
        UseSelected = "Tłumacz / edytuj wybrany mod"
        CreatorName = "Nazwa kreatora:"
        SteamProfile = "SteamID / profil:"
        SaveProfile = "Zapisz profil"
        AddWorkshopItem = "Dodaj"
        RefreshWorkshop = "Odśwież"
        RemoveWorkshopItem = "Usuń"
        OpenWorkshopItem = "Otwórz Workshop"
        DetectKenshi = "Wykryj Kenshi"
        ChooseKenshiFolder = "Wybierz folder Kenshi"
        ScanKenshiBase = "Skanuj podstawę gry"
        FcsHelp = "Jak wyeksportować dane z FCS?"
        BuildKenshi = "Zapisz pliki tłumaczenia"
        PzScan = "Skanuj mod"
        PzChooseMod = "Wybierz folder moda"
        PzExperimentalTitle = "Project Zomboid Mod - profil eksperymentalny"
        PzExperimentalSubtitle = "Obsługa B41/B42: starsze TXT i obecne JSON, w tym wersjonowane katalogi modów B42."
        ApiSettings = "API / Tłumaczenie"
        LanguageBoth = "Oba"
        LanguageSource = "Oryginał"
        LanguageTranslation = "Tłumaczenie"
    }
    en = @{
        AppSubtitle = "RimWorld profile • dark Mrokar theme"
        GameProfiles = "Game profiles"
        Workshop = "Workshop"
        RimWorldGame = "RimWorld Game"
        RimWorldMod = "RimWorld Mod"
        KenshiGame = "Kenshi Game"
        ProjectZomboidMod = "Project Zomboid Mod"
        ProjectZomboidGame = "Project Zomboid Game"
        Translation = "Translation"
        InstalledMods = "Installed mods"
        DetectRimWorld = "Detect RimWorld"
        ChooseGameFolder = "Choose game folder"
        OpenFolder = "Open folder"
        RimWorldGameTitle = "RimWorld Game — base game and DLC"
        RimWorldGameSubtitle = "Choose Core or any detected DLC. Each module can be scanned separately."
        RwGameSourceLabel = "Source:"
        RwGameTargetLabel = "Target:"
        RwGameModuleHeader = "Module"
        RwGameTypeHeader = "Type"
        RwGameKeyHeader = "Key"
        RwGameSourceHeader = "Source"
        RwGameTargetHeader = "Translation"
        RwGameDetectedModules = "Detected modules: {0}."
        RwGameScanInProgress = "Scanning RimWorld Game..."
        RwGameSelectModule = "Select at least one module / DLC."

        ModulesDlc = "Modules / DLC:"
        SelectAll = "Select all"
        CoreOnly = "Core only"
        DlcOnly = "DLC only"
        ScanSelected = "Scan selected"
        Entries = "Entries: 0"
        ChooseGameOrDetect = "Choose the game folder or use automatic detection."
        ChooseModFolder = "Choose mod folder"
        ScanAgain = "Scan again"
        UpdateExistingTranslation = "Update existing translation"
        OpenModFolder = "Open mod folder"
        Name = "Name:"
        TranslatorAuthor = "Translation author:"
        PreviewFlag = "Preview + flag"
        ExportCsv = "Export CSV"
        ImportCsv = "Import CSV"
        From = "From:"
        To = "To:"
        TranslateMissing = "Translate missing"
        ValidatePlaceholders = "Check / repair placeholders"
        KeybindDiagnostics = "Keybind diagnostics"
        DllDiagnostics = "DLL/UI diagnostics"
        BuildSeparateMod = "Build separate mod"
        CopyWorkshop = "Copy Workshop description"
        ExistingLanguages = "Existing languages"
        Search = "Search:"
        Clear = "Clear"
        NewText = "New text:"
        ReplaceAll = "Replace all"
        DetectSteamMods = "Detect Steam and mods"
        ModsCount = "Mods: 0"
        UseSelected = "Translate / edit selected mod"
        CreatorName = "Creator name:"
        SteamProfile = "SteamID / profile:"
        SaveProfile = "Save profile"
        AddWorkshopItem = "Add"
        RefreshWorkshop = "Refresh"
        RemoveWorkshopItem = "Remove"
        OpenWorkshopItem = "Open Workshop"
        DetectKenshi = "Detect Kenshi"
        ChooseKenshiFolder = "Choose Kenshi folder"
        ScanKenshiBase = "Scan base game"
        FcsHelp = "How to export data from FCS?"
        BuildKenshi = "Save translation files"
        PzScan = "Scan mod"
        PzChooseMod = "Choose mod folder"
        PzExperimentalTitle = "Project Zomboid Mod - experimental profile"
        PzExperimentalSubtitle = "B41/B42 support: legacy TXT and current JSON translation files, including versioned B42 mod folders."
        ApiSettings = "Translation API"
        LanguageBoth = "Both"
        LanguageSource = "Source"
        LanguageTranslation = "Translation"
    }
}

function T([string]$key) {
    $lang = if ($script:UiLanguage -eq "en") { "en" } else { "pl" }
    if ($script:UiText[$lang].ContainsKey($key)) {
        return [string]$script:UiText[$lang][$key]
    }
    return $key
}

function Set-ControlContentIfExists($control, [string]$key) {
    if ($null -eq $control) { return }

    $value = T $key

    # TabItem.Content is the actual tab body. Replacing it with localized text
    # destroys the nested UI. Tabs must localize Header only.
    if ($control -is [System.Windows.Controls.TabItem]) {
        $control.Header = $value
        return
    }

    if ($control.PSObject.Properties.Name -contains "Content") {
        $control.Content = $value
    }
}

function Set-ControlTextIfExists($control, [string]$key) {
    if ($null -ne $control) { $control.Text = T $key }
}

function Apply-CentralUiLanguage {
    # Tabs
    Set-ControlContentIfExists $tabGameProfiles "GameProfiles"
    Set-ControlContentIfExists $tabWorkshop "Workshop"
    Set-ControlContentIfExists $tabRimWorldGame "RimWorldGame"
    Set-ControlContentIfExists $tabRimWorldMod "RimWorldMod"
    Set-ControlContentIfExists $tabKenshi "KenshiGame"
    Set-ControlContentIfExists $tabProjectZomboidGame "ProjectZomboidGame"
    Set-ControlContentIfExists $tabProjectZomboidMod "ProjectZomboidMod"
    Set-ControlContentIfExists $tabTranslation "Translation"
    Set-ControlContentIfExists $tabInstalledMods "InstalledMods"

    if ($null -ne $txtAppSubtitle) { $txtAppSubtitle.Text = T "AppSubtitle" }
    if ($null -ne $txtRimWorldGameTitle) { $txtRimWorldGameTitle.Text = T "RimWorldGameTitle" }
    if ($null -ne $txtRimWorldGameSubtitle) { $txtRimWorldGameSubtitle.Text = T "RimWorldGameSubtitle" }
    if ($null -ne $txtModulesDlc) { $txtModulesDlc.Text = T "ModulesDlc" }
    if ($null -ne $txtCreatorNameLabel) { $txtCreatorNameLabel.Text = T "CreatorName" }
    if ($null -ne $txtSteamProfileLabel) { $txtSteamProfileLabel.Text = T "SteamProfile" }

    if ($null -ne $lblRwGameSourceLang) { $lblRwGameSourceLang.Text = T "RwGameSourceLabel" }
    if ($null -ne $lblRwGameTargetLang) { $lblRwGameTargetLang.Text = T "RwGameTargetLabel" }

    # RimWorld Game
    if ($null -ne $rimWorldGameGrid -and $rimWorldGameGrid.Columns.Count -ge 5) {
        $rimWorldGameGrid.Columns[0].Header = T "RwGameModuleHeader"
        $rimWorldGameGrid.Columns[1].Header = T "RwGameTypeHeader"
        $rimWorldGameGrid.Columns[2].Header = T "RwGameKeyHeader"

        $srcLang = Get-RimWorldGameSelectedSourceLanguage
        $dstLang = Get-RimWorldGameSelectedTargetLanguage
        $rimWorldGameGrid.Columns[3].Header = if ($null -ne $srcLang) { [string]$srcLang.NativeName } else { T "RwGameSourceHeader" }
        $rimWorldGameGrid.Columns[4].Header = if ($null -ne $dstLang) { [string]$dstLang.NativeName } else { T "RwGameTargetHeader" }
    }

    Set-ControlContentIfExists $btnDetectRimWorldGame "DetectRimWorld"
    Set-ControlContentIfExists $btnChooseRimWorldGame "ChooseGameFolder"
    Set-ControlContentIfExists $btnOpenRimWorldGameFolder "OpenFolder"
    Set-ControlContentIfExists $btnRwGameSelectAll "SelectAll"
    Set-ControlContentIfExists $btnRwGameCoreOnly "CoreOnly"
    Set-ControlContentIfExists $btnRwGameDlcOnly "DlcOnly"
    Set-ControlContentIfExists $btnScanRimWorldGame "ScanSelected"
    Set-ControlContentIfExists $btnExportRimWorldGameCsv "ExportCsv"
    Set-ControlContentIfExists $btnImportRimWorldGameCsv "ImportCsv"

    # RimWorld Mod
    Set-ControlContentIfExists $btnChooseMod "ChooseModFolder"
    Set-ControlContentIfExists $btnAnalyze "ScanAgain"
    Set-ControlContentIfExists $btnUpdateExisting "UpdateExistingTranslation"
    Set-ControlContentIfExists $btnOpenCurrentFolder "OpenModFolder"
    Set-ControlContentIfExists $chkPreviewFlag "PreviewFlag"
    Set-ControlContentIfExists $btnExport "ExportCsv"
    Set-ControlContentIfExists $btnImport "ImportCsv"
    Set-ControlContentIfExists $btnAutoTranslate "TranslateMissing"
    Set-ControlContentIfExists $btnValidate "ValidatePlaceholders"
    Set-ControlContentIfExists $btnKeybindDiagnostics "KeybindDiagnostics"
    Set-ControlContentIfExists $btnAssemblyDiagnostics "DllDiagnostics"
    Set-ControlContentIfExists $btnBuild "BuildSeparateMod"
    Set-ControlContentIfExists $btnCopyWorkshop "CopyWorkshop"
    Set-ControlContentIfExists $btnClearSearch "Clear"
    Set-ControlContentIfExists $btnReplaceAll "ReplaceAll"
    Set-ControlContentIfExists $btnDetect "DetectSteamMods"
    Set-ControlContentIfExists $btnUseSelected "UseSelected"
    Set-ControlContentIfExists $btnOpenFolder "OpenFolder"

    # Workshop
    Set-ControlContentIfExists $btnSaveCreatorProfile "SaveProfile"
    Set-ControlContentIfExists $btnAddWorkshopItem "AddWorkshopItem"
    Set-ControlContentIfExists $btnRefreshWorkshop "RefreshWorkshop"
    Set-ControlContentIfExists $btnRemoveWorkshopItem "RemoveWorkshopItem"
    Set-ControlContentIfExists $btnOpenWorkshopItem "OpenWorkshopItem"

    # Kenshi
    Set-ControlContentIfExists $btnDetectKenshi "DetectKenshi"
    Set-ControlContentIfExists $btnChooseKenshi "ChooseKenshiFolder"
    Set-ControlContentIfExists $btnOpenKenshiFolder "OpenFolder"
    Set-ControlContentIfExists $btnScanKenshi "ScanKenshiBase"
    Set-ControlContentIfExists $btnTranslateKenshi "TranslateMissing"
    Set-ControlContentIfExists $btnExportKenshiCsv "ExportCsv"
    Set-ControlContentIfExists $btnImportKenshiCsv "ImportCsv"
    Set-ControlContentIfExists $btnFcsHelpKenshi "FcsHelp"
    Set-ControlContentIfExists $btnBuildKenshi "BuildKenshi"

    # Project Zomboid Game
    if ($null -ne $btnDetectPzGame) { $btnDetectPzGame.Content = if ($script:UiLanguage -eq "en") { "Detect Project Zomboid" } else { "Wykryj Project Zomboid" } }
    if ($null -ne $btnChoosePzGame) { $btnChoosePzGame.Content = T "ChooseGameFolder" }
    if ($null -ne $btnOpenPzGameFolder) { $btnOpenPzGameFolder.Content = T "OpenFolder" }
    if ($null -ne $btnScanPzGame) { $btnScanPzGame.Content = if ($script:UiLanguage -eq "en") { "Scan game" } else { "Skanuj grę" } }
    if ($null -ne $btnTranslatePzGameMissing) { $btnTranslatePzGameMissing.Content = T "TranslateMissing" }
    if ($null -ne $btnExportPzGameCsv) { $btnExportPzGameCsv.Content = T "ExportCsv" }
    if ($null -ne $btnImportPzGameCsv) { $btnImportPzGameCsv.Content = T "ImportCsv" }
    if ($null -ne $lblPzGameFilter) { $lblPzGameFilter.Text = if ($script:UiLanguage -eq "en") { "Filter:" } else { "Filtr:" } }
    if ($null -ne $cmbPzGameFilter -and $cmbPzGameFilter.Items.Count -ge 4) {
        $cmbPzGameFilter.Items[0].Content = if ($script:UiLanguage -eq "en") { "All" } else { "Wszystkie" }
        $cmbPzGameFilter.Items[1].Content = if ($script:UiLanguage -eq "en") { "Missing target" } else { "Brak targetu" }
        $cmbPzGameFilter.Items[2].Content = if ($script:UiLanguage -eq "en") { "Identical source/target" } else { "Identyczne source/target" }
        $cmbPzGameFilter.Items[3].Content = if ($script:UiLanguage -eq "en") { "Suspicious / untranslated" } else { "Podejrzane / untranslated" }
    }
    if ($null -ne $txtPzGameTitle) { $txtPzGameTitle.Text = if ($script:UiLanguage -eq "en") { "Project Zomboid Game - experimental profile" } else { "Project Zomboid Game - profil eksperymentalny" } }
    if ($null -ne $txtPzGameSubtitle) { $txtPzGameSubtitle.Text = if ($script:UiLanguage -eq "en") { "Scans TXT and JSON localization files from media/lua/shared/Translate/&lt;LANG&gt;." } else { "Skanuje pliki TXT i JSON w media/lua/shared/Translate/&lt;LANG&gt;." } }
    if ($null -ne $lblPzGameSource) { $lblPzGameSource.Text = if ($script:UiLanguage -eq "en") { "Source:" } else { "Źródło:" } }
    if ($null -ne $lblPzGameTarget) { $lblPzGameTarget.Text = if ($script:UiLanguage -eq "en") { "Target:" } else { "Cel:" } }

    # Project Zomboid Mod
    if ($null -ne $btnDetectPzMods) { $btnDetectPzMods.Content = if ($script:UiLanguage -eq "en") { "Detect mods" } else { "Wykryj mody" } }
    if ($null -ne $lblPzDetectedMod) { $lblPzDetectedMod.Text = if ($script:UiLanguage -eq "en") { "Detected mod:" } else { "Wykryty mod:" } }
    Set-ControlContentIfExists $btnChoosePzMod "PzChooseMod"
    Set-ControlContentIfExists $btnOpenPzModFolder "OpenFolder"
    Set-ControlContentIfExists $btnScanPzMod "PzScan"
    Set-ControlContentIfExists $btnTranslatePzMissing "TranslateMissing"
    Set-ControlContentIfExists $btnExportPzCsv "ExportCsv"
    Set-ControlContentIfExists $btnImportPzCsv "ImportCsv"
    if ($null -ne $btnBuildPzTranslation) { $btnBuildPzTranslation.Content = if ($script:UiLanguage -eq "en") { "Build translation mod" } else { "Zbuduj mod tłumaczeniowy" } }
    if ($null -ne $btnOpenPzWorkshopStage) { $btnOpenPzWorkshopStage.Content = if ($script:UiLanguage -eq "en") { "Open Workshop package" } else { "Otwórz paczkę Workshop" } }
    if ($null -ne $btnCopyPzWorkshop) { $btnCopyPzWorkshop.Content = if ($script:UiLanguage -eq "en") { "Copy Workshop description" } else { "Kopiuj opis Workshop" } }
    if ($null -ne $txtPzTitle) { $txtPzTitle.Text = T "PzExperimentalTitle" }
    if ($null -ne $txtPzSubtitle) { $txtPzSubtitle.Text = T "PzExperimentalSubtitle" }
    if ($null -ne $lblPzSource) { $lblPzSource.Text = if ($script:UiLanguage -eq "en") { "Source:" } else { "Źródło:" } }
    if ($null -ne $lblPzTarget) { $lblPzTarget.Text = if ($script:UiLanguage -eq "en") { "Target:" } else { "Cel:" } }

    # API
    Set-ControlContentIfExists $btnApiSettings "ApiSettings"

    # Search scope combo items
    if ($null -ne $cmbSearchScope -and $cmbSearchScope.Items.Count -ge 3) {
        $cmbSearchScope.Items[0].Content = T "LanguageBoth"
        $cmbSearchScope.Items[1].Content = T "LanguageSource"
        $cmbSearchScope.Items[2].Content = T "LanguageTranslation"
    }

    # Labels found by name
    if ($null -ne $lblSourceLang) { $lblSourceLang.Content = T "From" }
    if ($null -ne $lblTargetLang) { $lblTargetLang.Content = T "To" }
    if ($null -ne $lblSearchTitle) { $lblSearchTitle.Content = T "Search" }
    if ($null -ne $lblReplaceTitle) { $lblReplaceTitle.Content = T "NewText" }

    # Static named status/count labels
    if ($null -ne $lblMods -and ([string]$lblMods.Content -match '^(Mody|Mods): 0$')) {
        $lblMods.Content = T "ModsCount"
    }
    if ($null -ne $lblRimWorldGameCount -and ([string]$lblRimWorldGameCount.Text -match '^(Wpisy|Entries): 0$')) {
        $lblRimWorldGameCount.Text = T "Entries"
    }
    if ($null -ne $txtRimWorldGameStatus -and ([string]$txtRimWorldGameStatus.Text -match 'Wybierz folder gry|Choose the game folder')) {
        $txtRimWorldGameStatus.Text = T "ChooseGameOrDetect"
    }

    if ($null -ne $lblCreatorId) { $lblCreatorId.Text = "Creator ID:" }
    if ($null -ne $btnSaveCreatorId) { $btnSaveCreatorId.Content = if ($script:UiLanguage -eq "en") { "Save ID" } else { "Zapisz ID" } }
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
    $lblCoverageTitle.Text = "Localization status:"
    $btnLoadExistingPL.Content = "Refresh target translation"
    if ($null -ne $btnLoadExternalPL) { $btnLoadExternalPL.Content = "Load from folder..." }
    if ($null -ne $btnEditMultiline) { $btnEditMultiline.Content = "Edit multiline..." }
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
    $btnApiSettings.Content = "Translation API"
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

    Apply-CentralUiLanguage
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
    $picked = Show-ModernFolderPicker `
        $(if ($script:UiLanguage -eq "en") { "Choose the main RimWorld mod folder" } else { "Wybierz główny folder moda RimWorld" }) `
        $txtModPath.Text
    if ($picked) {
        $txtModPath.Text = $picked
            Reset-TranslationUpdateMode
            $script:EditingTranslationModPath = ""
            $script:EditingTranslationPackageId = ""
            $script:EditingTranslationName = ""
        try {
            $scan = Analyze-Mod $picked
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






$cmbPzGameFilter.Add_SelectionChanged({
    try { Apply-PzGameFilter } catch {}
})

$btnDetectPzGame.Add_Click({
    try {
        $detected = Get-PzInstallPath
        if ($detected) {
            $txtPzGamePath.Text = $detected
            $txtPzGameStatus.Text = if ($script:UiLanguage -eq "en") {
                "Project Zomboid detected: $detected"
            } else {
                "Wykryto Project Zomboid: $detected"
            }
        } else {
            [System.Windows.MessageBox]::Show(
                $(if ($script:UiLanguage -eq "en") { "Project Zomboid was not found in detected Steam libraries." } else { "Nie znaleziono Project Zomboid w wykrytych bibliotekach Steam." }),
                "Project Zomboid"
            ) | Out-Null
        }
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Project Zomboid") | Out-Null
    }
})

$btnChoosePzGame.Add_Click({
    $picked = Show-ModernFolderPicker `
        $(if ($script:UiLanguage -eq "en") { "Choose the main Project Zomboid folder" } else { "Wybierz główny folder Project Zomboid" }) `
        $txtPzGamePath.Text
    if ($picked) { $txtPzGamePath.Text = $picked }
})

$btnOpenPzGameFolder.Add_Click({
    if (Test-Path -LiteralPath $txtPzGamePath.Text) {
        Start-Process explorer.exe -ArgumentList "`"$($txtPzGamePath.Text)`""
    }
})

$btnScanPzGame.Add_Click({
    try {
        Scan-PzGame $txtPzGamePath.Text | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Project Zomboid Game") | Out-Null
    }
})

$btnTranslatePzGameMissing.Add_Click({
    if (-not (Test-TranslationProviderConfigured)) {
        Show-MissingTranslationProviderMessage
        return
    }

    if ($script:PzGameEntries.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $(if ($script:UiLanguage -eq "en") { "Scan Project Zomboid first." } else { "Najpierw zeskanuj Project Zomboid." }),
            "Project Zomboid Game"
        ) | Out-Null
        return
    }

    $src = Get-PzSelectedLanguage $cmbPzGameSourceLang
    $dst = Get-PzSelectedLanguage $cmbPzGameTargetLang
    if ($null -eq $src -or $null -eq $dst) { return }
    if (-not (Require-TranslationProvider)) { return }

    $missing = @($script:PzGameEntries | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Translation) })
    if ($missing.Count -eq 0) {
        Set-PzGameWorkProgress 100 $(if ($script:UiLanguage -eq "en") { "No missing translations found." } else { "Brak brakujących tłumaczeń." })
        return
    }

    $done = 0
    $failed = 0
    $total = $missing.Count

    if ($null -ne $btnTranslatePzGameMissing) { $btnTranslatePzGameMissing.IsEnabled = $false }

    try {
        Set-PzGameWorkProgress 0 $(if ($script:UiLanguage -eq "en") {
            "Starting automatic translation: 0 / $total"
        } else {
            "Rozpoczynanie automatycznego tłumaczenia: 0 / $total"
        })

        foreach ($e in $missing) {
            try {
                $e.Translation = Translate-PzText ([string]$e.Source) ([string]$src.Code) ([string]$dst.Code)
                $done++
            } catch {
                $failed++
            }

            $processed = $done + $failed
            $pct = [int](100 * ($processed / [math]::Max(1,$total)))

            if (($processed % 5) -eq 0 -or $processed -eq 1 -or $processed -eq $total) {
                Set-PzGameWorkProgress $pct $(if ($script:UiLanguage -eq "en") {
                    "Translating: $processed / $total | OK: $done | errors: $failed"
                } else {
                    "Tłumaczenie: $processed / $total | OK: $done | błędy: $failed"
                })
            }

            if (($processed % 25) -eq 0) {
                try { [void](Save-PzGameCheckpoint "auto-translate-$processed") } catch {}
            }

            if (($processed % 20) -eq 0) {
                Refresh-PzGameGrid
                try { Apply-PzGameFilter } catch {}
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        try { [void](Save-PzGameCheckpoint "auto-translate-complete") } catch {}

        Refresh-PzGameGrid
        try { Apply-PzGameFilter } catch {}

        Set-PzGameWorkProgress 100 $(if ($script:UiLanguage -eq "en") {
            "Automatic translation complete: $done / $total | errors: $failed"
        } else {
            "Automatyczne tłumaczenie zakończone: $done / $total | błędy: $failed"
        })
    }
    finally {
        if ($null -ne $btnTranslatePzGameMissing) { $btnTranslatePzGameMissing.IsEnabled = $true }
    }
})

$btnExportPzGameCsv.Add_Click({
    if ($script:PzGameEntries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    $src = Get-PzSelectedLanguage $cmbPzGameSourceLang
    $dst = Get-PzSelectedLanguage $cmbPzGameTargetLang
    $srcCode = if ($null -ne $src) { [string]$src.Code } else { "source" }
    $dstCode = if ($null -ne $dst) { [string]$dst.Code } else { "target" }
    $dlg.FileName = "Project-Zomboid-Game-$srcCode-$dstCode.csv"

    if ($dlg.ShowDialog() -eq $true) {
        try {
            Export-PzGameCsv $dlg.FileName
            $txtPzGameStatus.Text = if ($script:UiLanguage -eq "en") { "CSV exported: $($dlg.FileName)" } else { "CSV zapisany: $($dlg.FileName)" }
        } catch {
            $latest = Join-Path (Get-ToolkitAutosaveDirectory) "latest-pz-game.csv"
            $msg = "$($_.Exception.Message)`n`nCheckpoint: $latest"
            [System.Windows.MessageBox]::Show($msg, "Project Zomboid Game CSV") | Out-Null
        }
    }
})

$btnImportPzGameCsv.Add_Click({
    if ($script:PzGameEntries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    if ($dlg.ShowDialog() -eq $true) {
        try {
            $updated = Import-PzGameCsv $dlg.FileName
            $txtPzGameStatus.Text = if ($script:UiLanguage -eq "en") {
                "Imported translations for $updated entries."
            } else {
                "Zaimportowano tłumaczenia dla $updated wpisów."
            }
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Project Zomboid Game CSV") | Out-Null
        }
    }
})

$cmbPzGameSourceLang.Add_SelectionChanged({
    if (-not [string]::IsNullOrWhiteSpace([string]$txtPzGamePath.Text) -and (Test-Path -LiteralPath $txtPzGamePath.Text)) {
        try { Scan-PzGame $txtPzGamePath.Text | Out-Null } catch {}
    }
})

$cmbPzGameTargetLang.Add_SelectionChanged({
    if (-not [string]::IsNullOrWhiteSpace([string]$txtPzGamePath.Text) -and (Test-Path -LiteralPath $txtPzGamePath.Text)) {
        try { Scan-PzGame $txtPzGamePath.Text | Out-Null } catch {}
    }
})

$txtPzGamePath.Add_Drop({
    param($sender,$e)
    try {
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $paths = @($e.Data.GetData([System.Windows.DataFormats]::FileDrop))
            if ($paths.Count -gt 0 -and (Test-Path -LiteralPath $paths[0] -PathType Container)) {
                $txtPzGamePath.Text = [string]$paths[0]
            }
        }
    } catch {}
})

$btnDetectPzMods.Add_Click({
    try {
        $script:PzDetectedMods = @(Find-PzInstalledMods)
        Refresh-PzDetectedModsCombo

        if ($null -ne $lblPzDetectedCount) {
            $lblPzDetectedCount.Text = if ($script:UiLanguage -eq "en") {
                "Mods: $($script:PzDetectedMods.Count)"
            } else {
                "Mody: $($script:PzDetectedMods.Count)"
            }
        }

        if ($script:PzDetectedMods.Count -eq 0) {
            $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
                "No translatable Project Zomboid mods were detected."
            } else {
                "Nie wykryto modów Project Zomboid zawierających pliki tłumaczeń."
            }
            return
        }

        $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
            "Detected $($script:PzDetectedMods.Count) mods. [LOC OK] means supported localization files were found; [NO LOC] means none were detected."
        } else {
            "Wykryto $($script:PzDetectedMods.Count) modów. [LOC OK] = znaleziono pliki lokalizacji, [NO LOC] = brak obsługiwanych plików lokalizacji."
        }
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Project Zomboid Mod") | Out-Null
    }
})

$cmbPzDetectedMods.Add_SelectionChanged({
    try {
        if ($null -eq $cmbPzDetectedMods.SelectedItem) { return }
        $path = [string]$cmbPzDetectedMods.SelectedItem.Tag
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $txtPzModPath.Text = $path
            $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
                "Selected mod: $($cmbPzDetectedMods.SelectedItem.Content)"
            } else {
                "Wybrano mod: $($cmbPzDetectedMods.SelectedItem.Content)"
            }
        }
    } catch {}
})


$btnChoosePzMod.Add_Click({
    $picked = Show-ModernFolderPicker `
        $(if ($script:UiLanguage -eq "en") { "Choose a Project Zomboid mod or Workshop item folder" } else { "Wybierz folder moda lub elementu Workshop Project Zomboid" }) `
        $txtPzModPath.Text
    if ($picked) { $txtPzModPath.Text = $picked }
})

$btnOpenPzModFolder.Add_Click({
    if (Test-Path -LiteralPath $txtPzModPath.Text) {
        Start-Process explorer.exe -ArgumentList "`"$($txtPzModPath.Text)`""
    }
})

$btnScanPzMod.Add_Click({
    try {
        Scan-PzMod $txtPzModPath.Text | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Project Zomboid Mod") | Out-Null
    }
})

$btnTranslatePzMissing.Add_Click({
    if (-not (Test-TranslationProviderConfigured)) {
        Show-MissingTranslationProviderMessage
        return
    }

    if ($script:PzEntries.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $(if ($script:UiLanguage -eq "en") { "Scan a Project Zomboid mod first." } else { "Najpierw zeskanuj mod Project Zomboid." }),
            "Project Zomboid Mod"
        ) | Out-Null
        return
    }

    $src = Get-PzSelectedLanguage $cmbPzSourceLang
    $dst = Get-PzSelectedLanguage $cmbPzTargetLang
    if ($null -eq $src -or $null -eq $dst) { return }
    if (-not (Require-TranslationProvider)) { return }

    $missing = @($script:PzEntries | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Translation) })
    $done = 0
    foreach ($e in $missing) {
        try {
            $e.Translation = Translate-PzText ([string]$e.Source) ([string]$src.Code) ([string]$dst.Code)
            $done++
            if (($done % 25) -eq 0) {
                try {
                    $autosaveDir = Get-ToolkitAutosaveDirectory
                    $path = Join-Path $autosaveDir "latest-pz-mod.csv"
                    Export-PzCsv $path
                } catch {}
            }
            if (($done % 20) -eq 0) {
                Refresh-PzGrid
                [System.Windows.Forms.Application]::DoEvents()
            }
        } catch {}
    }
    Refresh-PzGrid
    $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
        "Automatic translation completed: $done / $($missing.Count)."
    } else {
        "Automatyczne tlumaczenie zakonczone: $done / $($missing.Count)."
    }
})


$btnBuildPzTranslation.Add_Click({
    if ($script:PzEntries.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $(if ($script:UiLanguage -eq "en") { "Scan a Project Zomboid mod first." } else { "Najpierw zeskanuj mod Project Zomboid." }),
            "Project Zomboid Mod"
        ) | Out-Null
        return
    }

    $picked = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$script:PzEditingTranslationPath) -and
        (Test-Path -LiteralPath $script:PzEditingTranslationPath)) {
        $picked = Split-Path $script:PzEditingTranslationPath -Parent
    } else {
        $defaultPzMods = Get-PzLocalInstallRoot
        $picked = Show-ModernFolderPicker `
            $(if ($script:UiLanguage -eq "en") { "Choose where to create the Project Zomboid translation mod" } else { "Wybierz folder, w którym utworzyć mod tłumaczeniowy Project Zomboid" }) `
            $defaultPzMods

        if (-not $picked) { return }
    }

    try {
        $out = Build-PzTranslationMod $picked
        $btnCopyPzWorkshop.IsEnabled = $true
        if ($null -ne $btnOpenPzWorkshopStage) { $btnOpenPzWorkshopStage.IsEnabled = $true }
        $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
            "Project Zomboid translation mod created: $out"
        } else {
            "Utworzono mod tłumaczeniowy Project Zomboid: $out"
        }
        [System.Windows.MessageBox]::Show(
            $(if ($script:UiLanguage -eq "en") { "Translation mod created.`n`n$out" } else { "Mod tłumaczeniowy gotowy.`n`n$out" }),
            "Project Zomboid Mod"
        ) | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,"Project Zomboid Mod") | Out-Null
    }
})


$btnOpenPzWorkshopStage.Add_Click({
    if ([string]::IsNullOrWhiteSpace([string]$script:PzLastWorkshopStagePath) -or
        -not (Test-Path -LiteralPath $script:PzLastWorkshopStagePath)) {
        return
    }

    Start-Process explorer.exe -ArgumentList "`"$($script:PzLastWorkshopStagePath)`""
})

$btnCopyPzWorkshop.Add_Click({
    if ([string]::IsNullOrWhiteSpace([string]$script:PzLastWorkshopDescriptionPath) -or
        -not (Test-Path -LiteralPath $script:PzLastWorkshopDescriptionPath)) {
        return
    }

    try {
        $content = Get-Content -LiteralPath $script:PzLastWorkshopDescriptionPath -Raw -Encoding UTF8
        [System.Windows.Clipboard]::SetText($content)
        $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
            "Workshop description copied to clipboard."
        } else {
            "Opis Workshop skopiowany do schowka."
        }
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,"Workshop") | Out-Null
    }
})

$btnExportPzCsv.Add_Click({
    if ($script:PzEntries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    $dlg.DefaultExt = ".csv"
    $dlg.FileName = "Project-Zomboid-Translation.csv"
    if ($dlg.ShowDialog() -eq $true) {
        try {
            Export-PzCsv $dlg.FileName
            $txtPzStatus.Text = if ($script:UiLanguage -eq "en") { "CSV exported: $($dlg.FileName)" } else { "CSV zapisany: $($dlg.FileName)" }
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Project Zomboid CSV") | Out-Null
        }
    }
})

$btnImportPzCsv.Add_Click({
    if ($script:PzEntries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    if ($dlg.ShowDialog() -eq $true) {
        try {
            $updated = Import-PzCsv $dlg.FileName
            $txtPzStatus.Text = if ($script:UiLanguage -eq "en") {
                "Imported translations for $updated entries."
            } else {
                "Zaimportowano tlumaczenia dla $updated wpisow."
            }
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Project Zomboid CSV") | Out-Null
        }
    }
})

$cmbPzSourceLang.Add_SelectionChanged({
    if (-not [string]::IsNullOrWhiteSpace([string]$txtPzModPath.Text) -and (Test-Path -LiteralPath $txtPzModPath.Text)) {
        try { Scan-PzMod $txtPzModPath.Text | Out-Null } catch {}
    }
})

$cmbPzTargetLang.Add_SelectionChanged({
    if (-not [string]::IsNullOrWhiteSpace([string]$txtPzModPath.Text) -and (Test-Path -LiteralPath $txtPzModPath.Text)) {
        try { Scan-PzMod $txtPzModPath.Text | Out-Null } catch {}
    }
})

$txtPzModPath.Add_Drop({
    param($sender,$e)
    try {
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $paths = @($e.Data.GetData([System.Windows.DataFormats]::FileDrop))
            if ($paths.Count -gt 0 -and (Test-Path -LiteralPath $paths[0] -PathType Container)) {
                $txtPzModPath.Text = [string]$paths[0]
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
    $picked = Show-ModernFolderPicker `
        $(if ($script:UiLanguage -eq "en") { "Choose the main Kenshi folder" } else { "Wybierz główny folder Kenshi" }) `
        $txtKenshiPath.Text
    if ($picked) { $txtKenshiPath.Text = $picked }
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

    if (-not (Require-TranslationProvider)) { return }

    $missing = @($script:KenshiEntries | Where-Object { [string]::IsNullOrWhiteSpace($_.Translation) })
    $done = 0
    foreach ($e in $missing) {
        try {
            # Kenshi workflow is intentionally still English -> Polish in v0.7.1.
            # It will move to the shared dynamic language selectors in a later Kenshi migration.
            $e.Translation = Translate-Configured ([string]$e.Source) "en" "pl"
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
    $code = Get-SelectedTargetLanguageCode
    $result = Apply-ExistingTranslation $code
    $txtStatus.Text = if ($script:UiLanguage -eq "en") {
        "Loaded $($result.Loaded) target entries: $($result.Translated) translated, $($result.Identical) identical to source."
    } else {
        "Wczytano $($result.Loaded) wpisów docelowych: $($result.Translated) przetłumaczonych, $($result.Identical) identycznych ze źródłem."
    }
})

$btnLoadExternalPL.Add_Click({
    $code = Get-SelectedTargetLanguageCode
    $picked = Show-ModernFolderPicker `
        $(if ($script:UiLanguage -eq "en") { "Choose a translation mod or target language folder" } else { "Wybierz mod tłumaczenia albo folder języka docelowego" }) `
        $txtModPath.Text
    if (-not $picked) { return }

    $entries = Read-ExternalTargetTranslation $picked $code
    if ($null -eq $entries -or $entries.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $(if ($script:UiLanguage -eq "en") { "No LanguageData XML files were found for the selected target language." } else { "Nie znaleziono plików LanguageData XML dla wybranego języka docelowego." }),
            "Mod Translation Toolkit") | Out-Null
        return
    }

    $script:ExistingTranslations[$code] = $entries
    $script:LanguageCoverage[$code] = Get-RimWorldCoverageStats $entries
    $result = Apply-TranslationEntries $entries
    Refresh-LanguageCoverageUi
    $txtStatus.Text = if ($script:UiLanguage -eq "en") {
        "Loaded external translation: $($result.Loaded) entries, including $($result.Translated) translated and $($result.Identical) identical to source."
    } else {
        "Wczytano zewnętrzne tłumaczenie: $($result.Loaded) wpisów, w tym $($result.Translated) przetłumaczonych i $($result.Identical) identycznych ze źródłem."
    }
})

$btnEditMultiline.Add_Click({
    if ($null -eq $grid.SelectedItem) {
        $txtStatus.Text = if ($script:UiLanguage -eq "en") { "Select an entry to edit." } else { "Zaznacz wpis do edycji." }
        return
    }
    Show-RimWorldMultilineEditor $grid.SelectedItem
})

$btnLoadExistingEN.Add_Click({
    $result = Apply-ExistingTranslation "en"
    $txtStatus.Text = if ($script:UiLanguage -eq "en") {
        "Loaded $($result.Loaded) existing English localization entries."
    } else {
        "Załadowano $($result.Loaded) istniejących angielskich wpisów lokalizacji."
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
    $sourceCode = Get-SelectedSourceLanguageCode
    $targetCode = Get-SelectedTargetLanguageCode
    $dlg.FileName = "translation_$sourceCode-$targetCode.csv"

    if ($dlg.ShowDialog()) {
        try {
            Export-ToolkitCsv $dlg.FileName
            $txtStatus.Text = if ($script:UiLanguage -eq "en") {
                "CSV saved: $($dlg.FileName)"
            } else {
                "CSV zapisany: $($dlg.FileName)"
            }
        } catch {
            $autosave = Join-Path (Get-ToolkitAutosaveDirectory) "latest.csv"
            $msg = if ($script:UiLanguage -eq "en") {
                "CSV export failed.`n`n$($_.Exception.Message)`n`nYour translation checkpoint is preserved here:`n$autosave"
            } else {
                "Eksport CSV nie powiódł się.`n`n$($_.Exception.Message)`n`nCheckpoint tłumaczenia został zachowany tutaj:`n$autosave"
            }
            [System.Windows.MessageBox]::Show($msg, "Mod Translation Toolkit") | Out-Null
            $txtStatus.Text = $msg
        }
    }
})

$btnImport.Add_Click({
    if ($script:Entries.Count -eq 0) { return }
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    if ($dlg.ShowDialog()) {
        try { Import-ToolkitCsv $dlg.FileName; $txtStatus.Text = "Zaimportowano CSV." }
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

$btnApiSettings.Add_Click({ Show-TranslationApiSettingsWindow })

$btnAutoTranslate.Add_Click({
    if (-not (Test-TranslationProviderConfigured)) {
        Show-MissingTranslationProviderMessage
        return
    }

    if ($script:Entries.Count -eq 0) { return }

    if (-not (Require-TranslationProvider)) { return }

    $srcItem = $cmbSourceLang.SelectedItem
    $dstItem = $cmbTargetLang.SelectedItem
    if ($null -eq $srcItem -or $null -eq $dstItem) { return }

    $src = [string]$srcItem.Tag
    $dst = [string]$dstItem.Tag

    $pair = Require-TranslationLanguagePair $src $dst
    if ($null -eq $pair) { return }

    if ($src -eq $dst) {
        $msg = if ($script:UiLanguage -eq "en") { "Source and target language must be different." } else { "Język źródłowy i docelowy muszą być różne." }
        [System.Windows.MessageBox]::Show($msg, "Mod Translation Toolkit")
        return
    }

    $question = if ($script:UiLanguage -eq "en") {
        "Automatic translation uses the provider configured in API Settings. Provider costs/limits may apply. Review machine-translated text manually.`n`nTranslate all empty entries?"
    } else {
        "Automatyczne tłumaczenie używa dostawcy wybranego w Ustawieniach API. Mogą obowiązywać jego koszty i limity. Wynik warto przejrzeć ręcznie.`n`nTłumaczyć wszystkie puste wpisy?"
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
        try {
            $e.Translation = Translate-RimWorldEntryWithGlossary $e "Mod" $src $dst
            Set-RimWorldLearningBaseline $e "Mod" ([string]$e.Translation)
        } catch { $failed++ }
        $done++
            if (($done % 25) -eq 0) { [void](Save-ToolkitTranslationCheckpoint "auto-translate-$done") }

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




$btnRimWorldModLearningMode.Add_Click({
    [void](Cycle-RimWorldLearningMode)
})

$btnRimWorldModLearningSuggestions.Add_Click({
    try { Show-RimWorldLearningSuggestionReview "Mod" }
    catch { [System.Windows.MessageBox]::Show($_.Exception.Message,"RimWorld learning") | Out-Null }
})

$btnRimWorldModGlossary.Add_Click({
    try { Show-RimWorldGlossaryEditor "Mod" }
    catch { [System.Windows.MessageBox]::Show($_.Exception.Message,"RimWorld glossary") | Out-Null }
})

$btnEditModWorkshopDescription.Add_Click({
    try {
        Show-RimWorldModWorkshopDescriptionEditor
    } catch {
        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "Workshop description",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
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
            $autosave = Join-Path (Get-ToolkitAutosaveDirectory) "latest.csv"
            $msg = "$($_.Exception.Message)`n`nCheckpoint: $autosave"
            [System.Windows.MessageBox]::Show($msg,"Błąd")
        }
        return
    }

    $pickedOutput = Show-ModernFolderPicker `
        $(if ($script:UiLanguage -eq "en") {
            "Choose the folder where the separate translation mod should be created"
        } else {
            "Wybierz folder, w którym ma powstać oddzielny mod tłumaczeniowy"
        }) `
        ""

    if ($pickedOutput) {
        try {
            $out = Build-TranslationMod $pickedOutput
            $script:LastWorkshopDescriptionPath = Join-Path $out "SteamWorkshopDescription.txt"
            $btnCopyWorkshop.IsEnabled = $true
            $txtStatus.Text = if ($script:UiLanguage -eq "en") {
                "Translation mod created: $out"
            } else {
                "Gotowy mod: $out"
            }
            [System.Windows.MessageBox]::Show("Gotowe.`n`n$out","Mod Translation Toolkit")
        } catch {
            $autosave = Join-Path (Get-ToolkitAutosaveDirectory) "latest.csv"
            $msg = "$($_.Exception.Message)`n`nCheckpoint: $autosave"
            [System.Windows.MessageBox]::Show($msg,"Błąd")
        }
    }
})



function Get-RimWorldGameSelectedSourceLanguage {
    return Get-SelectedLanguageFromCombo $cmbRwGameSourceLang
}
function Get-RimWorldGameSelectedTargetLanguage {
    return Get-SelectedLanguageFromCombo $cmbRwGameTargetLang
}
function Get-RimWorldGameSelectedSourceCode {
    $l = Get-RimWorldGameSelectedSourceLanguage
    if ($null -eq $l) { return "en" }
    return [string]$l.Code
}
function Get-RimWorldGameSelectedTargetCode {
    $l = Get-RimWorldGameSelectedTargetLanguage
    if ($null -eq $l) { return "pl" }
    return [string]$l.Code
}

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
    $msg = (T "RwGameDetectedModules").Replace("{0}", [string]$lstRimWorldGameModules.Items.Count)
    Set-ControlTextSafe $txtRimWorldGameStatus $msg
}



function Get-RimWorldLanguageAliases([string]$languageCodeOrName) {
    if ([string]::IsNullOrWhiteSpace($languageCodeOrName)) { return @() }

    $wanted = $languageCodeOrName.Trim()
    $lang = Get-LanguageByCode $wanted
    if ($null -eq $lang) {
        $lang = $script:Languages | Where-Object {
            $_.Name -ieq $wanted -or
            $_.NativeName -ieq $wanted -or
            $_.RimWorldFolder -ieq $wanted
        } | Select-Object -First 1
    }

    if ($null -eq $lang) { return @($wanted.ToLowerInvariant()) }

    $aliases = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($v in @($lang.Code, $lang.Name, $lang.NativeName, $lang.RimWorldFolder)) {
        if ([string]::IsNullOrWhiteSpace([string]$v)) { continue }
        $n = ([string]$v).Trim().ToLowerInvariant()
        if (-not $seen.ContainsKey($n)) {
            $seen[$n] = $true
            [void]$aliases.Add($n)
        }
    }

    # Common RimWorld / ISO variants.
    switch ([string]$lang.Code) {
        "pt-br" { foreach ($v in @("brazilian","brazilian portuguese","portuguese brazil","pt_br","pt-br")) { if (-not $seen.ContainsKey($v)) { $seen[$v]=$true; [void]$aliases.Add($v) } } }
        "zh-cn" { foreach ($v in @("chinesesimplified","simplified chinese","zh_cn","zh-cn")) { if (-not $seen.ContainsKey($v)) { $seen[$v]=$true; [void]$aliases.Add($v) } } }
        "zh-tw" { foreach ($v in @("chinesetraditional","traditional chinese","zh_tw","zh-tw")) { if (-not $seen.ContainsKey($v)) { $seen[$v]=$true; [void]$aliases.Add($v) } } }
        "cs" { foreach ($v in @("czech","čeština","cz")) { if (-not $seen.ContainsKey($v)) { $seen[$v]=$true; [void]$aliases.Add($v) } } }
    }

    return @($aliases)
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
        $asciiArchive = Join-Path $target "_language.tar"

        try {
            Copy-Item -LiteralPath $archivePath -Destination $asciiArchive -Force
            & $tar.Source -xf $asciiArchive -C $target 2>&1 | Out-Null
            $exitCode = $LASTEXITCODE
            Remove-Item -LiteralPath $asciiArchive -Force -ErrorAction SilentlyContinue

            if ($exitCode -ne 0) {
                throw "tar.exe zakończył pracę z kodem $exitCode."
            }
        } catch {
            Remove-Item -LiteralPath $asciiArchive -Force -ErrorAction SilentlyContinue
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

function Read-RimWorldKeyedXml([string]$filePath, [string]$moduleName, [string]$role) {
    $rows = New-Object System.Collections.ArrayList
    try {
        [xml]$xml = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        if (-not $xml.LanguageData) { return @() }

        foreach ($node in $xml.LanguageData.ChildNodes) {
            if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            $value = [string]$node.InnerText

            [void]$rows.Add([pscustomobject]@{
                Module = $moduleName
                Type = "Keyed"
                File = $filePath
                Key = [string]$node.Name
                Source = $(if ($role -eq "Source") { $value } else { "" })
                Translation = $(if ($role -eq "Target") { $value } else { "" })
            })
        }
    } catch {}
    return @($rows)
}

function Read-RimWorldDefInjectedXml([string]$filePath, [string]$moduleName, [string]$role, [string]$langRoot) {
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
            $value = [string]$node.InnerText

            [void]$rows.Add([pscustomobject]@{
                Module = $moduleName
                Type = $(if ([string]::IsNullOrWhiteSpace($defType)) { "DefInjected" } else { "DefInjected/$defType" })
                File = $filePath
                Key = [string]$node.Name
                Source = $(if ($role -eq "Source") { $value } else { "" })
                Translation = $(if ($role -eq "Target") { $value } else { "" })
            })
        }
    } catch {}
    return @($rows)
}

function Get-RimWorldLanguageEntries([string]$langRoot, [string]$moduleName, [string]$role) {
    $rows = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($langRoot) -or -not (Test-Path $langRoot)) { return @() }

    $keyed = Join-Path $langRoot "Keyed"
    if (Test-Path $keyed) {
        foreach ($f in Get-ChildItem -LiteralPath $keyed -Filter *.xml -File -Recurse -ErrorAction SilentlyContinue) {
            foreach ($r in @(Read-RimWorldKeyedXml $f.FullName $moduleName $role)) {
                [void]$rows.Add($r)
            }
        }
    }

    $defInjected = Join-Path $langRoot "DefInjected"
    if (Test-Path $defInjected) {
        foreach ($f in Get-ChildItem -LiteralPath $defInjected -Filter *.xml -File -Recurse -ErrorAction SilentlyContinue) {
            foreach ($r in @(Read-RimWorldDefInjectedXml $f.FullName $moduleName $role $langRoot)) {
                [void]$rows.Add($r)
            }
        }
    }

    return @($rows)
}


function Get-RimWorldGameInheritanceSummary {
    if ($null -eq $script:RimWorldGameInheritedCounts -or
        $script:RimWorldGameInheritedCounts.Count -eq 0) {
        return ""
    }

    $parts = New-Object System.Collections.ArrayList
    foreach ($name in @($script:RimWorldGameInheritedCounts.Keys | Sort-Object)) {
        [void]$parts.Add("${name}: $($script:RimWorldGameInheritedCounts[$name])")
    }

    return (@($parts) -join ", ")
}

function Get-RimWorldGameDefSourceEntries([string]$modulePath, [string]$moduleName) {
    $rows = New-Object System.Collections.ArrayList
    $defsRoot = Join-Path $modulePath "Defs"
    if (-not (Test-Path -LiteralPath $defsRoot)) { return @() }

    $fields = @(
        "label","description","jobString","reportString","gerund","verb",
        "labelShort","labelNoun","labelPlural","labelMale","labelMalePlural","labelFemale","labelFemalePlural",
        "inspectString","baseDesc","letterLabel","letterText","deathMessage","leaderTitle","pawnsPlural",
        "fixedName","formatString","labelTendedWell","labelTendedWellInner","labelSolidTendedWell",
        "destroyedLabel","destroyedOutLabel","adjective","helpText","summary","text","name","customLabel","useLabel",
        "ingestCommandString","ingestReportString","recoveryMessage","discoverLetterLabel","discoverLetterText"
    )

    # Two-pass scan, matching the RimWorld Mod workflow:
    # 1. collect concrete + abstract/template Defs
    # 2. resolve localizable fields recursively through ParentName
    $records = New-Object System.Collections.ArrayList
    $parentIndex = @{}

    foreach ($f in Get-ChildItem -LiteralPath $defsRoot -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue) {
        try {
            [xml]$doc = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
            if ($null -eq $doc.DocumentElement -or $doc.DocumentElement.Name -ne "Defs") { continue }

            foreach ($def in @($doc.DocumentElement.ChildNodes)) {
                if ($def.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                $defType = [string]$def.LocalName

                $defName = ""
                $defNameNode = Get-DirectDefFieldNode $def "defName"
                if ($null -ne $defNameNode -and
                    -not [string]::IsNullOrWhiteSpace([string]$defNameNode.InnerText)) {
                    $defName = ([string]$defNameNode.InnerText).Trim()
                }

                $templateName = ""
                try {
                    if ($null -ne $def.Attributes["Name"]) {
                        $templateName = [string]$def.Attributes["Name"].Value
                    }
                } catch {}

                $parentName = ""
                try {
                    if ($null -ne $def.Attributes["ParentName"]) {
                        $parentName = [string]$def.Attributes["ParentName"].Value
                    }
                } catch {}

                $record = [pscustomobject]@{
                    DefType = $defType
                    DefName = $defName
                    TemplateName = $templateName
                    ParentName = $parentName
                    Node = $def
                    File = [string]$f.FullName
                }
                [void]$records.Add($record)

                if (-not [string]::IsNullOrWhiteSpace($templateName)) {
                    $key = "$defType|$templateName".ToLowerInvariant()
                    if (-not $parentIndex.ContainsKey($key)) {
                        $parentIndex[$key] = $record
                    }
                }
            }
        } catch {}
    }

    $seen = @{}
    $inheritedCount = 0

    foreach ($record in @($records)) {
        if ([string]::IsNullOrWhiteSpace([string]$record.DefName)) { continue }

        $defType = [string]$record.DefType
        $defName = [string]$record.DefName

        foreach ($field in $fields) {
            $visited = New-Object 'System.Collections.Generic.HashSet[string]'
            $resolved = Resolve-InheritedDefField $record $field $parentIndex $visited

            if ($null -eq $resolved -or $null -eq $resolved.Node) { continue }

            $value = [string]$resolved.Node.InnerText
            if ([string]::IsNullOrWhiteSpace($value)) { continue }

            $key = "$defName.$field"
            $id = "$moduleName|DefInjected/$defType|$key".ToLowerInvariant()
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true

            [void]$rows.Add([pscustomobject]@{
                Module = $moduleName
                Type = "DefInjected/$defType"
                File = [string]$record.File
                Key = $key
                Source = $value.TrimEnd()
                Translation = ""
                Inherited = [bool]$resolved.Inherited
                InheritedFrom = [string]$resolved.From
            })

            if ($resolved.Inherited) { $inheritedCount++ }
        }
    }

    try {
        if ($null -eq $script:RimWorldGameInheritedCounts) {
            $script:RimWorldGameInheritedCounts = @{}
        }
        $script:RimWorldGameInheritedCounts[$moduleName] = $inheritedCount
    } catch {}

    return @($rows)
}


function Merge-RimWorldGameSourceEntries($primary, $secondary) {
    $result = New-Object System.Collections.ArrayList
    $seen = @{}

    foreach ($entry in @($primary) + @($secondary)) {
        if ($null -eq $entry) { continue }
        $id = Get-RimWorldEntryIdentity $entry
        $norm = $id.ToLowerInvariant()
        if ($seen.ContainsKey($norm)) { continue }
        $seen[$norm] = $true
        [void]$result.Add($entry)
    }

    return @($result)
}

function Get-RimWorldEntryIdentity($entry) {
    return "$($entry.Module)|$($entry.Type)|$($entry.Key)"
}



function Commit-RimWorldGameGridEdits {
    try {
        [void]$rimWorldGameGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        [void]$rimWorldGameGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
    } catch {}
}

function Get-RimWorldGameVersion([string]$gamePath) {
    $candidates = @(
        (Join-Path $gamePath "Version.txt"),
        (Join-Path $gamePath "version.txt")
    )

    foreach ($p in $candidates) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $raw = Get-Content -LiteralPath $p -Raw -Encoding UTF8
            if ($raw -match '([0-9]+\.[0-9]+)') {
                return [string]$Matches[1]
            }
        } catch {}
    }

    # Current supported fallback for this Toolkit line.
    return "1.6"
}

function Get-RimWorldOfficialPackageId([string]$moduleName) {
    switch -Regex ($moduleName) {
        '^Core$'     { return "ludeon.rimworld" }
        '^Royalty$'  { return "ludeon.rimworld.royalty" }
        '^Ideology$' { return "ludeon.rimworld.ideology" }
        '^Biotech$'  { return "ludeon.rimworld.biotech" }
        '^Anomaly$'  { return "ludeon.rimworld.anomaly" }
        '^Odyssey$'  { return "ludeon.rimworld.odyssey" }
        default      { return "" }
    }
}

function Get-RimWorldGameTargetFolder {
    $lang = Get-RimWorldGameSelectedTargetLanguage
    if ($null -eq $lang) { return "Polish" }

    if (-not [string]::IsNullOrWhiteSpace([string]$lang.RimWorldFolder)) {
        return [string]$lang.RimWorldFolder
    }

    return [string]$lang.NativeName
}

function Get-RimWorldGameBuildEntries {
    Commit-RimWorldGameGridEdits

    # Always use the full scanned set, not the currently filtered view.
    $all = @($script:RimWorldGameEntries)
    if ($all.Count -eq 0) {
        throw $(if ($script:UiLanguage -eq "en") {
            "There are no RimWorld Game entries. Scan Core/DLC first."
        } else {
            "Brak wpisów RimWorld Game. Najpierw zeskanuj Core/DLC."
        })
    }

    $translated = @($all | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Translation)
    })

    if ($translated.Count -eq 0) {
        throw $(if ($script:UiLanguage -eq "en") {
            "There are no translated entries to build."
        } else {
            "Brak przetłumaczonych wpisów do zbudowania moda."
        })
    }

    return @($translated)
}

function Get-RimWorldGameBuildKey($entry) {
    return "$([string]$entry.Type)|$([string]$entry.Key)".ToLowerInvariant()
}

function Test-RimWorldGameBuildConflicts($entries) {
    $map = @{}
    $conflicts = New-Object System.Collections.ArrayList

    foreach ($e in @($entries)) {
        $id = Get-RimWorldGameBuildKey $e
        if (-not $map.ContainsKey($id)) {
            $map[$id] = $e
            continue
        }

        $first = $map[$id]
        $a = ([string]$first.Translation).Trim()
        $b = ([string]$e.Translation).Trim()

        if ($a -cne $b) {
            [void]$conflicts.Add([pscustomobject]@{
                Type = [string]$e.Type
                Key = [string]$e.Key
                ModuleA = [string]$first.Module
                ModuleB = [string]$e.Module
                TranslationA = $a
                TranslationB = $b
            })
        }
    }

    return @($conflicts)
}

function New-RimWorldGameTranslationPreview([string]$outMod, [string]$targetCode) {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

    $aboutDir = Join-Path $outMod "About"
    New-Item -ItemType Directory -Path $aboutDir -Force | Out-Null
    $dest = Join-Path $aboutDir "Preview.png"

    $bmp = New-Object System.Drawing.Bitmap 640,360
    $g = [System.Drawing.Graphics]::FromImage($bmp)

    try {
        $g.Clear([System.Drawing.Color]::FromArgb(18,16,24))

        $panel = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(34,28,44))
        $g.FillRectangle($panel, 30, 30, 580, 300)
        $panel.Dispose()

        $accent = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(122,63,194))
        $g.FillRectangle($accent, 30, 30, 580, 12)
        $accent.Dispose()

        $font1 = New-Object System.Drawing.Font("Segoe UI",30,[System.Drawing.FontStyle]::Bold)
        $font2 = New-Object System.Drawing.Font("Segoe UI",19,[System.Drawing.FontStyle]::Regular)
        $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $soft = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190,180,210))

        $g.DrawString("RimWorld", $font1, $white, 62, 85)
        $g.DrawString("Game Translation", $font2, $soft, 65, 145)

        $flagCode = "PL"
        $lang = Get-RimWorldGameSelectedTargetLanguage
        if ($null -ne $lang -and -not [string]::IsNullOrWhiteSpace([string]$lang.Flag)) {
            $flagCode = [string]$lang.Flag
        }

        Draw-FlagOverlay $g $flagCode 390 205 170 95

        $font1.Dispose()
        $font2.Dispose()
        $white.Dispose()
        $soft.Dispose()
    } finally {
        $g.Dispose()
    }

    try {
        $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bmp.Dispose()
    }

    return $dest
}


function Get-RimWorldGameWorkshopDescriptionPath {
    return (Join-Path (Get-ToolkitSettingsDirectory) "rimworld-game-workshop-description.txt")
}

function Get-DefaultRimWorldGameWorkshopDescription {
    $targetLang = Get-RimWorldGameSelectedTargetLanguage
    $displayLanguage = if ($null -ne $targetLang) { [string]$targetLang.Name } else { "Polish" }
    if ([string]::IsNullOrWhiteSpace($displayLanguage) -and $null -ne $targetLang) {
        $displayLanguage = [string]$targetLang.NativeName
    }
    if ([string]::IsNullOrWhiteSpace($displayLanguage)) { $displayLanguage = "Translation" }

    $modules = @($lstRimWorldGameModules.SelectedItems | ForEach-Object { [string]$_.Content })
    if ($modules.Count -eq 0) {
        $modules = @($script:RimWorldGameEntries | ForEach-Object { [string]$_.Module } | Sort-Object -Unique)
    }

    $moduleLines = if ($modules.Count -gt 0) {
        (@($modules | ForEach-Object { "[*]$_" }) -join "`r`n")
    } else {
        "[*]Core / selected DLC"
    }

    $creator = Get-ToolkitCreatorId
    $toolUrl = "https://github.com/DrizztGaming/Mod-Translation-Toolkit"
    $kofiUrl = "https://ko-fi.com/drizztgaming"

    return @"
[h1]RimWorld - $displayLanguage Translation[/h1]

$displayLanguage translation package for RimWorld Core and selected DLC.

[h1]Included modules[/h1]
[list]
$moduleLines
[/list]

[h1]Translation Info[/h1]
[list]
[*]Language: $displayLanguage
[*]Creator ID: $creator
[/list]

[h1]Mod Translation Toolkit[/h1]
Created with [url=$toolUrl][b]Mod Translation Toolkit[/b][/url].

[url=$toolUrl]GitHub - Mod Translation Toolkit[/url]

[h1]Support[/h1]
[url=$kofiUrl][b]Support me on Ko-fi[/b][/url]
"@
}

function Get-RimWorldGameWorkshopDescription {
    $path = Get-RimWorldGameWorkshopDescriptionPath
    if (Test-Path -LiteralPath $path) {
        try {
            $saved = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($saved)) {
                return [string]$saved
            }
        } catch {}
    }

    return (Get-DefaultRimWorldGameWorkshopDescription)
}

function Save-RimWorldGameWorkshopDescription([string]$value) {
    $path = Get-RimWorldGameWorkshopDescriptionPath
    [System.IO.File]::WriteAllText(
        $path,
        [string]$value,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )
    return $path
}

function Reset-RimWorldGameWorkshopDescription {
    $path = Get-RimWorldGameWorkshopDescriptionPath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Show-RimWorldGameWorkshopDescriptionEditor {
    [xml]$editorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RimWorld Game - Workshop Description"
        Width="900" Height="680"
        MinWidth="700" MinHeight="500"
        WindowStartupLocation="CenterOwner"
        Background="#121018"
        Foreground="#ECE8F6">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0"
               Text="Opis Steam Workshop używany przy budowaniu moda. Obsługuje BBCode Steam."
               Margin="0,0,0,10"
               Foreground="#B9AEC9"/>

    <TextBox Name="txtDescription"
             Grid.Row="1"
             AcceptsReturn="True"
             AcceptsTab="True"
             TextWrapping="Wrap"
             VerticalScrollBarVisibility="Auto"
             HorizontalScrollBarVisibility="Auto"
             FontFamily="Consolas"
             FontSize="13"
             Background="#1B1723"
             Foreground="#ECE8F6"
             BorderBrush="#4A3B5B"
             Padding="10"/>

    <Grid Grid.Row="2" Margin="0,12,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>

      <StackPanel Grid.Column="0" Orientation="Horizontal">
        <Button Name="btnDefault"
                Content="Wczytaj domyślny"
                Padding="14,7"
                Margin="0,0,8,0"
                Background="#2A2334"
                Foreground="White"/>
        <Button Name="btnDeleteSaved"
                Content="Usuń zapisany custom"
                Padding="14,7"
                Background="#2A2334"
                Foreground="White"/>
      </StackPanel>

      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button Name="btnCancel"
                Content="Anuluj"
                Padding="18,7"
                Margin="0,0,8,0"
                Background="#2A2334"
                Foreground="White"/>
        <Button Name="btnSave"
                Content="Zapisz opis"
                Padding="18,7"
                Background="#7A3FC2"
                Foreground="White"
                FontWeight="SemiBold"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $editorXaml
    $editor = [Windows.Markup.XamlReader]::Load($reader)
    try { $editor.Owner = $window } catch {}

    $txt = $editor.FindName("txtDescription")
    $btnDefault = $editor.FindName("btnDefault")
    $btnDeleteSaved = $editor.FindName("btnDeleteSaved")
    $btnCancel = $editor.FindName("btnCancel")
    $btnSave = $editor.FindName("btnSave")

    $txt.Text = Get-RimWorldGameWorkshopDescription

    $btnDefault.Add_Click({
        $txt.Text = Get-DefaultRimWorldGameWorkshopDescription
    })

    $btnDeleteSaved.Add_Click({
        Reset-RimWorldGameWorkshopDescription
        $txt.Text = Get-DefaultRimWorldGameWorkshopDescription
        Set-ControlTextSafe $txtRimWorldGameStatus $(if ($script:UiLanguage -eq "en") {
            "Saved custom Workshop description removed."
        } else {
            "Usunięto zapisany własny opis Workshop."
        })
    })

    $btnCancel.Add_Click({
        $editor.DialogResult = $false
        $editor.Close()
    })

    $btnSave.Add_Click({
        try {
            [void](Save-RimWorldGameWorkshopDescription ([string]$txt.Text))
            Set-ControlTextSafe $txtRimWorldGameStatus $(if ($script:UiLanguage -eq "en") {
                "Custom Workshop description saved."
            } else {
                "Zapisano własny opis Workshop."
            })
            $editor.DialogResult = $true
            $editor.Close()
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message,"Workshop description") | Out-Null
        }
    })

    [void]$editor.ShowDialog()
}

function Build-RimWorldGameTranslationMod([string]$parentFolder) {
    $entries = @(Get-RimWorldGameBuildEntries)
    $conflicts = @(Test-RimWorldGameBuildConflicts $entries)

    if ($conflicts.Count -gt 0) {
        $lines = @($conflicts | Select-Object -First 15 | ForEach-Object {
            "$($_.Type) / $($_.Key) :: $($_.ModuleA) <> $($_.ModuleB)"
        })
        throw $(if ($script:UiLanguage -eq "en") {
            "Conflicting Core/DLC translation keys were found: $($conflicts.Count).`r`n`r`n$($lines -join "`r`n")"
        } else {
            "Wykryto konflikty kluczy tłumaczenia Core/DLC: $($conflicts.Count).`r`n`r`n$($lines -join "`r`n")"
        })
    }

    $targetLang = Get-RimWorldGameSelectedTargetLanguage
    if ($null -eq $targetLang) { throw "Target language is not selected." }

    $targetCode = [string]$targetLang.Code
    $targetFolder = Get-RimWorldGameTargetFolder
    $creator = Get-ToolkitCreatorId

    $displayLanguage = [string]$targetLang.Name
    if ([string]::IsNullOrWhiteSpace($displayLanguage)) { $displayLanguage = [string]$targetLang.NativeName }

    $displayName = "RimWorld - $displayLanguage Translation"
    $safeName = ($displayName -replace '[\\/:*?"<>|]', '_')
    $outMod = Join-Path $parentFolder $safeName

    if (Test-Path -LiteralPath $outMod) {
        Remove-Item -LiteralPath $outMod -Recurse -Force
    }

    $aboutDir = Join-Path $outMod "About"
    $langRoot = Join-Path $outMod "Languages\$targetFolder"
    New-Item -ItemType Directory -Path $aboutDir -Force | Out-Null
    New-Item -ItemType Directory -Path $langRoot -Force | Out-Null

    # Deduplicate equal keys across modules. Different translations were already
    # rejected above, so keeping the first identical row is safe.
    $unique = @{}
    foreach ($e in $entries) {
        $id = Get-RimWorldGameBuildKey $e
        if (-not $unique.ContainsKey($id)) { $unique[$id] = $e }
    }

    $keyed = @($unique.Values | Where-Object { $_.Type -eq "Keyed" } | Sort-Object Key)
    if ($keyed.Count -gt 0) {
        $dest = Join-Path $langRoot "Keyed\RimWorldGame.xml"
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
        [void]$sb.AppendLine('<LanguageData>')
        foreach ($e in $keyed) {
            [void]$sb.AppendLine("  <$($e.Key)>$(XmlEscape ([string]$e.Translation).TrimEnd())</$($e.Key)>")
        }
        [void]$sb.AppendLine('</LanguageData>')
        [System.IO.File]::WriteAllText($dest,$sb.ToString(),(New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
    }

    $defRows = @($unique.Values | Where-Object { $_.Type -like "DefInjected/*" })
    foreach ($typeGroup in @($defRows | Group-Object Type)) {
        $defType = ([string]$typeGroup.Name -replace '^DefInjected/','')
        if ([string]::IsNullOrWhiteSpace($defType)) { continue }

        $dest = Join-Path $langRoot "DefInjected\$defType\$defType.xml"
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
        [void]$sb.AppendLine('<LanguageData>')
        foreach ($e in @($typeGroup.Group | Sort-Object Key)) {
            [void]$sb.AppendLine("  <$($e.Key)>$(XmlEscape ([string]$e.Translation).TrimEnd())</$($e.Key)>")
        }
        [void]$sb.AppendLine('</LanguageData>')
        [System.IO.File]::WriteAllText($dest,$sb.ToString(),(New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))
    }

    $selectedModules = @($lstRimWorldGameModules.SelectedItems | ForEach-Object { [string]$_.Content })
    if ($selectedModules.Count -eq 0) {
        $selectedModules = @($entries | ForEach-Object { [string]$_.Module } | Sort-Object -Unique)
    }

    $dependencyXml = ""
    $loadAfterXml = ""
    foreach ($module in $selectedModules) {
        $pid = Get-RimWorldOfficialPackageId $module
        if ([string]::IsNullOrWhiteSpace($pid)) { continue }

        # Core is always present, so it only needs loadAfter.
        if ($module -ine "Core") {
            $dependencyXml += "    <li>`r`n      <packageId>$pid</packageId>`r`n      <displayName>$module</displayName>`r`n    </li>`r`n"
        }
        $loadAfterXml += "    <li>$pid</li>`r`n"
    }

    $version = Get-RimWorldGameVersion ([string]$txtRimWorldGamePath.Text)
    $packageId = ("mtt.rimworld.game.$creator.$targetCode" -replace '[^a-zA-Z0-9_.-]','').ToLowerInvariant()

    $about = @"
<?xml version="1.0" encoding="utf-8"?>
<ModMetaData>
  <name>$([System.Security.SecurityElement]::Escape($displayName))</name>
  <author>$([System.Security.SecurityElement]::Escape([string]$txtAuthor.Text))</author>
  <packageId>$packageId</packageId>
  <modVersion>0.10.24</modVersion>
  <supportedVersions>
    <li>$version</li>
  </supportedVersions>
  <description>$([System.Security.SecurityElement]::Escape($displayLanguage)) translation package for RimWorld Core and selected DLC.

Generated with Mod Translation Toolkit.
https://github.com/DrizztGaming/Mod-Translation-Toolkit</description>
  <modDependencies>
$dependencyXml  </modDependencies>
  <loadAfter>
$loadAfterXml  </loadAfter>
</ModMetaData>
"@
    [System.IO.File]::WriteAllText((Join-Path $aboutDir "About.xml"),$about,(New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))

    [void](New-RimWorldGameTranslationPreview $outMod $targetCode)

    $moduleText = $selectedModules -join ", "
    $report = @"
Mod Translation Toolkit v$AppVersion
Build type: RimWorld Game translation mod
Target language: $targetCode / $targetFolder
Selected modules: $moduleText
PackageId: $packageId
Supported RimWorld version: $version
Scanned entries: $($script:RimWorldGameEntries.Count)
Translated entries written: $($unique.Count)
Keyed entries written: $($keyed.Count)
DefInjected entries written: $($defRows.Count)
Conflicts: 0
Output: $outMod
"@
    [System.IO.File]::WriteAllText((Join-Path $outMod "TranslationBuildReport.txt"),$report,(New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)))

    $workshop = Get-RimWorldGameWorkshopDescription
    [System.IO.File]::WriteAllText(
        (Join-Path $outMod "SteamWorkshopDescription.txt"),
        [string]$workshop,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )

    return $outMod
}

function Export-RimWorldGameCsv([string]$path) {
    $rows = @($rimWorldGameGrid.ItemsSource)
    if ($rows.Count -eq 0) {
        $msg = if ($script:UiLanguage -eq "en") {
            "There are no RimWorld Game entries to export. Scan Core or DLC first."
        } else {
            "Brak wpisów RimWorld Game do eksportu. Najpierw zeskanuj Core lub DLC."
        }
        [System.Windows.MessageBox]::Show($msg, "RimWorld Game CSV") | Out-Null
        return $false
    }

    $sourceLang = Get-RimWorldGameSelectedSourceLanguage
    $targetLang = Get-RimWorldGameSelectedTargetLanguage
    $sourceCode = if ($null -ne $sourceLang) { [string]$sourceLang.Code } else { "" }
    $targetCode = if ($null -ne $targetLang) { [string]$targetLang.Code } else { "" }

    $exportRows = @(
        $rows |
            Select-Object Module,Type,File,Key,Source,Translation,
                @{N="SourceLanguage";E={$sourceCode}},
                @{N="TargetLanguage";E={$targetCode}}
    )

    Write-ToolkitCsvAtomic $exportRows $path
    return $true
}

function Import-RimWorldGameCsv([string]$path) {
    $rows = @(Microsoft.PowerShell.Utility\Import-Csv -LiteralPath $path -Encoding UTF8 -Delimiter ';')
    if ($rows.Count -eq 0) {
        throw $(if ($script:UiLanguage -eq "en") { "The CSV file contains no entries." } else { "Plik CSV nie zawiera wpisów." })
    }

    $required = @("Module","Type","Key","Translation")
    foreach ($name in $required) {
        if (-not ($rows[0].PSObject.Properties.Name -contains $name)) {
            throw $(if ($script:UiLanguage -eq "en") {
                "This is not a RimWorld Game CSV file. Missing column: $name"
            } else {
                "To nie jest plik CSV RimWorld Game. Brak kolumny: $name"
            })
        }
    }

    $current = @($rimWorldGameGrid.ItemsSource)
    if ($current.Count -eq 0) {
        throw $(if ($script:UiLanguage -eq "en") {
            "Scan the same RimWorld Core/DLC selection before importing the CSV."
        } else {
            "Przed importem CSV zeskanuj ten sam zestaw Core/DLC w RimWorld Game."
        })
    }

    $sourceLang = Get-RimWorldGameSelectedSourceLanguage
    $targetLang = Get-RimWorldGameSelectedTargetLanguage
    $currentSource = if ($null -ne $sourceLang) { [string]$sourceLang.Code } else { "" }
    $currentTarget = if ($null -ne $targetLang) { [string]$targetLang.Code } else { "" }

    $meta = $rows[0]
    if (($meta.PSObject.Properties.Name -contains "SourceLanguage") -and
        ($meta.PSObject.Properties.Name -contains "TargetLanguage")) {

        $csvSource = [string]$meta.SourceLanguage
        $csvTarget = [string]$meta.TargetLanguage

        if ((-not [string]::IsNullOrWhiteSpace($csvSource) -and $csvSource -ine $currentSource) -or
            (-not [string]::IsNullOrWhiteSpace($csvTarget) -and $csvTarget -ine $currentTarget)) {

            $msg = if ($script:UiLanguage -eq "en") {
                "CSV language pair: $csvSource → $csvTarget`nCurrent selection: $currentSource → $currentTarget`n`nThe file will still be imported. Verify that this is intentional."
            } else {
                "Para językowa CSV: $csvSource → $csvTarget`nAktualny wybór: $currentSource → $currentTarget`n`nPlik zostanie mimo to zaimportowany. Sprawdź, czy to zamierzone."
            }
            [System.Windows.MessageBox]::Show($msg, "RimWorld Game CSV") | Out-Null
        }
    }

    $lookup = @{}
    foreach ($r in $rows) {
        $id = "$([string]$r.Module)|$([string]$r.Type)|$([string]$r.Key)".ToLowerInvariant()
        $lookup[$id] = [string]$r.Translation
    }

    $updated = 0
    foreach ($entry in $current) {
        $id = (Get-RimWorldEntryIdentity $entry).ToLowerInvariant()
        if ($lookup.ContainsKey($id)) {
            $entry.Translation = [string]$lookup[$id]
            $updated++
        }
    }

    $script:RimWorldGameEntries = @($current)
    Apply-RimWorldGameFilter

    return $updated
}

function Apply-RimWorldGameFilter {
    if ($null -eq $rimWorldGameGrid) { return }
    $mode="all"
    try { if ($null -ne $cmbRimWorldGameFilter.SelectedItem) { $mode=[string]$cmbRimWorldGameFilter.SelectedItem.Tag } } catch {}
    $all=@($script:RimWorldGameEntries)
    $items=switch ($mode) {
        "missing" { @($all | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Translation) }) }
        "translated" { @($all | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Translation) -and ([string]$_.Source).Trim() -cne ([string]$_.Translation).Trim() }) }
        "identical" { @($all | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Translation) -and ([string]$_.Source).Trim() -ceq ([string]$_.Translation).Trim() }) }
        "suspicious" { @($all | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Translation) -or ([string]$_.Source).Trim() -ceq ([string]$_.Translation).Trim() }) }
        default { $all }
    }
    $rimWorldGameGrid.ItemsSource=$null
    $rimWorldGameGrid.ItemsSource=@($items)
    $rimWorldGameGrid.Items.Refresh()
    Set-ControlTextSafe $lblRimWorldGameCount $(if ($script:UiLanguage -eq "en") { "Entries: $($items.Count) / $($all.Count)" } else { "Wpisy: $($items.Count) / $($all.Count)" })
}

function Scan-RimWorldGameSelection {
    $selected = @($lstRimWorldGameModules.SelectedItems)
    if ($selected.Count -eq 0) {
        $msg = if ($script:UiLanguage -eq "en") { "Select at least one module / DLC." } else { "Zaznacz co najmniej jeden moduł / DLC." }
        [System.Windows.MessageBox]::Show($msg,"RimWorld Game") | Out-Null
        return
    }

    $sourceLang = Get-RimWorldGameSelectedSourceLanguage
    $targetLang = Get-RimWorldGameSelectedTargetLanguage
    if ($null -eq $sourceLang -or $null -eq $targetLang) { return }

    if ($sourceLang.Code -ieq $targetLang.Code) {
        $msg = if ($script:UiLanguage -eq "en") {
            "Source and target language must be different."
        } else {
            "Język źródłowy i docelowy muszą być różne."
        }
        [System.Windows.MessageBox]::Show($msg,"RimWorld Game") | Out-Null
        return
    }

    $rimWorldGameGrid.ItemsSource = $null
    Set-ControlTextSafe $lblRimWorldGameCount (T "Entries")
    $txtRimWorldGameStatus.ToolTip = $null

    $result = New-Object System.Collections.ArrayList
    $statusLines = New-Object System.Collections.ArrayList

    $totalSource = 0
    $totalTarget = 0
    $matched = 0
    $totalKeyed = 0
    $totalDefInjected = 0

    foreach ($item in $selected) {
        $moduleName = [string]$item.Content
        $modulePath = [string]$item.Tag

        $sourceRoot = Get-RimWorldLanguageFolder $modulePath ([string]$sourceLang.Code)
        $targetRoot = Get-RimWorldLanguageFolder $modulePath ([string]$targetLang.Code)

        $sourceLanguageEntries = @(Get-RimWorldLanguageEntries $sourceRoot $moduleName "Source")

        if ($sourceLang.Code -ieq "en") {
            # English is special in RimWorld. Core/DLC DefInjected source is often
            # represented only by Defs, not by a complete English DefInjected mirror.
            $sourceKeyed = @($sourceLanguageEntries | Where-Object { $_.Type -eq "Keyed" })
            $defSource = @(Get-RimWorldGameDefSourceEntries $modulePath $moduleName)
            $explicitDefInjected = @($sourceLanguageEntries | Where-Object { $_.Type -like "DefInjected*" })
            $sourceEntries = @(Merge-RimWorldGameSourceEntries (@($sourceKeyed) + @($defSource)) $explicitDefInjected)
        } else {
            # Non-English source must remain the selected official localization.
            # Do not silently mix English Defs into it.
            $sourceEntries = @($sourceLanguageEntries)
        }

        $targetEntries = @(Get-RimWorldLanguageEntries $targetRoot $moduleName "Target")

        $totalSource += $sourceEntries.Count
        $totalTarget += $targetEntries.Count

        $moduleKeyed = @($sourceEntries | Where-Object { $_.Type -eq "Keyed" }).Count
        $moduleDefInjected = @($sourceEntries | Where-Object { $_.Type -like "DefInjected*" }).Count
        $totalKeyed += $moduleKeyed
        $totalDefInjected += $moduleDefInjected

        $targetMap = @{}
        foreach ($entry in $targetEntries) {
            $targetMap[(Get-RimWorldEntryIdentity $entry).ToLowerInvariant()] = [string]$entry.Translation
        }

        $moduleMatched = 0
        foreach ($entry in $sourceEntries) {
            $id = (Get-RimWorldEntryIdentity $entry).ToLowerInvariant()
            if ($targetMap.ContainsKey($id)) {
                $entry.Translation = [string]$targetMap[$id]
                $moduleMatched++
                $matched++
            }
            [void]$result.Add($entry)
        }

        $targetState = if ($targetRoot) {
            "$($targetLang.NativeName): $moduleMatched/$($sourceEntries.Count)"
        } else {
            if ($script:UiLanguage -eq "en") { "$($targetLang.Name): not found" } else { "$($targetLang.NativeName): nie znaleziono" }
        }

        $sourcePathText = if ($sourceRoot) { $sourceRoot } else { "(brak / missing)" }
        $targetPathText = if ($targetRoot) { $targetRoot } else { "(brak / missing)" }

        [void]$statusLines.Add(
            "$moduleName | Keyed: $moduleKeyed | DefInjected: $moduleDefInjected | $targetState`r`nSource: $sourcePathText`r`nTarget: $targetPathText"
        )
    }

    $script:RimWorldGameEntries = @($result)
    Apply-RimWorldGameFilter

    if ($rimWorldGameGrid.Columns.Count -ge 5) {
        $rimWorldGameGrid.Columns[3].Header = [string]$sourceLang.NativeName
        $rimWorldGameGrid.Columns[4].Header = [string]$targetLang.NativeName
    }

    $countText = if ($script:UiLanguage -eq "en") {
        "Entries: $($result.Count) | Keyed: $totalKeyed | DefInjected: $totalDefInjected | matched $($targetLang.Name): $matched"
    } else {
        "Wpisy: $($result.Count) | Keyed: $totalKeyed | DefInjected: $totalDefInjected | dopasowane $($targetLang.NativeName): $matched"
    }
    Set-ControlTextSafe $lblRimWorldGameCount $countText

    $status = if ($script:UiLanguage -eq "en") {
        "Scan complete. Source $($sourceLang.Name): $totalSource, target entries found: $totalTarget, matched: $matched."
    } else {
        "Skan zakończony. Źródło $($sourceLang.NativeName): $totalSource, wpisy docelowe: $totalTarget, dopasowane: $matched."
    }
    Set-ControlTextSafe $txtRimWorldGameStatus $status

    $details = ($statusLines -join "`r`n`r`n")
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
    $picked = Show-ModernFolderPicker `
        $(if ($script:UiLanguage -eq "en") { "Choose the main RimWorld game folder" } else { "Wybierz główny folder RimWorld" }) `
        $txtRimWorldGamePath.Text
    if ($picked) {
        $txtRimWorldGamePath.Text = $picked
        Load-RimWorldGameModules $picked
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


$cmbRwGameSourceLang.Add_SelectionChanged({
    if ($rimWorldGameGrid.Columns.Count -ge 5 -and $null -ne $cmbRwGameSourceLang.SelectedItem) {
        $l = Get-RimWorldGameSelectedSourceLanguage
        if ($null -ne $l) { $rimWorldGameGrid.Columns[3].Header = [string]$l.NativeName }
    }
})
$cmbRwGameTargetLang.Add_SelectionChanged({
    if ($rimWorldGameGrid.Columns.Count -ge 5 -and $null -ne $cmbRwGameTargetLang.SelectedItem) {
        $l = Get-RimWorldGameSelectedTargetLanguage
        if ($null -ne $l) { $rimWorldGameGrid.Columns[4].Header = [string]$l.NativeName }
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
$cmbRimWorldGameFilter.Add_SelectionChanged({
    try { Apply-RimWorldGameFilter } catch {}
})

$btnScanRimWorldGame.Add_Click({
    try {
        $btnScanRimWorldGame.IsEnabled = $false
        Set-ControlTextSafe $txtRimWorldGameStatus (T "RwGameScanInProgress")
        [System.Windows.Forms.Application]::DoEvents()

        Scan-RimWorldGameSelection
    } catch {
        $msg = if ($script:UiLanguage -eq "en") {
            "RimWorld Game scan failed.`n`n$($_.Exception.Message)"
        } else {
            "Skan RimWorld Game nie powiódł się.`n`n$($_.Exception.Message)"
        }

        $rimWorldGameGrid.ItemsSource = $null
        Set-ControlTextSafe $lblRimWorldGameCount (T "Entries")
        $txtRimWorldGameStatus.ToolTip = $null
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



$btnEditRimWorldGameWorkshopDescription.Add_Click({
    try {
        Show-RimWorldGameWorkshopDescriptionEditor
    } catch {
        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "Workshop description",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
})


$btnRimWorldGameLearningMode.Add_Click({
    [void](Cycle-RimWorldLearningMode)
})

$btnRimWorldGameLearningSuggestions.Add_Click({
    try { Show-RimWorldLearningSuggestionReview "Game" }
    catch { [System.Windows.MessageBox]::Show($_.Exception.Message,"RimWorld learning") | Out-Null }
})

$btnRimWorldGameGlossary.Add_Click({
    try { Show-RimWorldGlossaryEditor "Game" }
    catch { [System.Windows.MessageBox]::Show($_.Exception.Message,"RimWorld glossary") | Out-Null }
})

$btnTranslateRimWorldGameMissing.Add_Click({
    if (-not (Test-TranslationProviderConfigured)) {
        Show-MissingTranslationProviderMessage
        return
    }

    if (@($script:RimWorldGameEntries).Count -eq 0) {
        [System.Windows.MessageBox]::Show("Najpierw zeskanuj Core lub DLC.","RimWorld Game") | Out-Null
        return
    }

    $sourceLang = Get-RimWorldGameSelectedSourceLanguage
    $targetLang = Get-RimWorldGameSelectedTargetLanguage
    if ($null -eq $sourceLang -or $null -eq $targetLang) { return }

    $src = [string]$sourceLang.Code
    $dst = [string]$targetLang.Code

    $pair = Require-TranslationLanguagePair $src $dst
    if ($null -eq $pair) { return }

    $todo = @($script:RimWorldGameEntries | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.Translation)
    })
    if ($todo.Count -eq 0) {
        Set-ControlTextSafe $txtRimWorldGameStatus "Brak pustych wpisów do tłumaczenia."
        return
    }

    $answer = [System.Windows.MessageBox]::Show(
        "Automatyczne tłumaczenie obejmie $($todo.Count) pustych wpisów Core/DLC. Glosariusz kontekstowy zostanie zastosowany automatycznie.`n`nKontynuować?",
        "RimWorld Game",
        [System.Windows.MessageBoxButton]::YesNo
    )
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $done = 0
    $failed = 0
    foreach ($e in $todo) {
        try {
            $e.Translation = Translate-RimWorldEntryWithGlossary $e "Game" $src $dst
            Set-RimWorldLearningBaseline $e "Game" ([string]$e.Translation)
        } catch {
            $failed++
        }

        $done++
        if (($done % 5) -eq 0 -or $done -eq $todo.Count) {
            Set-ControlTextSafe $txtRimWorldGameStatus "Tłumaczenie Core/DLC: $done / $($todo.Count) | błędy: $failed"
            [System.Windows.Forms.Application]::DoEvents()
        }
        Start-Sleep -Milliseconds 120
    }

    Apply-RimWorldGameFilter
    Set-ControlTextSafe $txtRimWorldGameStatus "Tłumaczenie Core/DLC zakończone. Błędy: $failed."
})

$btnBuildRimWorldGameTranslation.Add_Click({
    try {
        Commit-RimWorldGameGridEdits

        $defaultParent = ""
        try {
            $gamePath = [string]$txtRimWorldGamePath.Text
            if (-not [string]::IsNullOrWhiteSpace($gamePath)) {
                $candidate = Join-Path $gamePath "Mods"
                if (Test-Path -LiteralPath $candidate) { $defaultParent = $candidate }
            }
        } catch {}

        $picked = Show-ModernFolderPicker `
            $(if ($script:UiLanguage -eq "en") { "Choose the folder where the translation mod should be created" } else { "Wybierz folder, w którym utworzyć mod tłumaczeniowy" }) `
            $defaultParent

        if ([string]::IsNullOrWhiteSpace($picked)) { return }

        $out = Build-RimWorldGameTranslationMod $picked
        $msg = if ($script:UiLanguage -eq "en") {
            "RimWorld Game translation mod created:`n`n$out"
        } else {
            "Utworzono mod tłumaczeniowy RimWorld Game:`n`n$out"
        }
        Set-ControlTextSafe $txtRimWorldGameStatus $msg
        [System.Windows.MessageBox]::Show($msg,"RimWorld Game") | Out-Null

        try { Start-Process explorer.exe -ArgumentList @($out) } catch {}
    } catch {
        $msg = if ($script:UiLanguage -eq "en") {
            "Could not build the RimWorld Game translation mod.`n`n$($_.Exception.Message)"
        } else {
            "Nie udało się zbudować moda tłumaczeniowego RimWorld Game.`n`n$($_.Exception.Message)"
        }
        Set-ControlTextSafe $txtRimWorldGameStatus $msg
        [System.Windows.MessageBox]::Show($msg,"RimWorld Game",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    }
})

$btnExportRimWorldGameCsv.Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"
    $dlg.DefaultExt = ".csv"
    $dlg.AddExtension = $true

    $sourceLang = Get-RimWorldGameSelectedSourceLanguage
    $targetLang = Get-RimWorldGameSelectedTargetLanguage
    $src = if ($null -ne $sourceLang) { [string]$sourceLang.Code } else { "source" }
    $dst = if ($null -ne $targetLang) { [string]$targetLang.Code } else { "target" }
    $dlg.FileName = "RimWorld-Game-$src-$dst.csv"

    if ($dlg.ShowDialog() -eq $true) {
        try {
            if (Export-RimWorldGameCsv $dlg.FileName) {
                $msg = if ($script:UiLanguage -eq "en") {
                    "RimWorld Game CSV exported: $($dlg.FileName)"
                } else {
                    "Wyeksportowano CSV RimWorld Game: $($dlg.FileName)"
                }
                Set-ControlTextSafe $txtRimWorldGameStatus $msg
            }
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, "RimWorld Game CSV") | Out-Null
        }
    }
})

$btnImportRimWorldGameCsv.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "CSV (*.csv)|*.csv"

    if ($dlg.ShowDialog() -eq $true) {
        try {
            $updated = Import-RimWorldGameCsv $dlg.FileName
            $msg = if ($script:UiLanguage -eq "en") {
                "Imported translations for $updated RimWorld Game entries."
            } else {
                "Zaimportowano tłumaczenia dla $updated wpisów RimWorld Game."
            }
            Set-ControlTextSafe $txtRimWorldGameStatus $msg
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, "RimWorld Game CSV") | Out-Null
        }
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
                "Editing: $($translationInfo.Name). Loaded $($edit.Loaded)/$($edit.Total) existing entries. Original: $($edit.Original.Name). Resolved via: $($edit.ResolveMethod). Classification: $(Get-TranslationClassificationReason $translationInfo ([string]$m.Path))."
            } else {
                "Edycja: $($translationInfo.Name). Wczytano $($edit.Loaded)/$($edit.Total) istniejących wpisów. Oryginał: $($edit.Original.Name). Wykrycie źródła: $($edit.ResolveMethod). Klasyfikacja: $(Get-TranslationClassificationReason $translationInfo ([string]$m.Path))."
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

try {
    $multiIssues = @(Test-MultilingualConfiguration)
    if ($multiIssues.Count -gt 0 -and $null -ne $txtStatus) {
        $txtStatus.ToolTip = "Multilingual configuration warnings:`r`n" + ($multiIssues -join "`r`n")
    }
} catch {}

$window.ShowDialog() | Out-Null
