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

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Source audit passed."
