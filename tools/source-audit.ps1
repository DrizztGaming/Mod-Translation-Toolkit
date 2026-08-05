$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$errors = @()

$app = Get-Content (Join-Path $root "src\ModTranslationToolkit\App.xaml.cs") -Raw
if ($app -notmatch "System\.Windows\.Application") {
    $errors += "App.xaml.cs must explicitly inherit System.Windows.Application"
}

$libre = Get-Content (Join-Path $root "src\ModTranslationToolkit\Services\LibreTranslateService.cs") -Raw
if ($libre -notmatch "using System\.Net\.Http;") {
    $errors += "LibreTranslateService.cs is missing using System.Net.Http"
}


$ioFiles = @(
    "src\ModTranslationToolkit\Services\CsvService.cs",
    "src\ModTranslationToolkit\Services\ProjectZomboidScanner.cs",
    "src\ModTranslationToolkit\Services\RimWorldScanner.cs",
    "src\ModTranslationToolkit\Services\SteamDetector.cs",
    "src\ModTranslationToolkit\MainWindow.xaml.cs"
)

foreach ($rel in $ioFiles) {
    $content = Get-Content (Join-Path $root $rel) -Raw
    if ($content -notmatch "using System\.IO;") {
        $errors += "$rel is missing using System.IO"
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Source audit passed."
