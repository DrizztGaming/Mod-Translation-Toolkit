$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $root "STARTUP_ERROR.log"
$main = Join-Path $root "src\RimWorld\ModTranslationToolkit.ps1"

try {
    if (Test-Path -LiteralPath $log) {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
    & $main
}
catch {
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("Mod Translation Toolkit startup error")
    [void]$lines.Add("Time: $((Get-Date).ToString('o'))")
    [void]$lines.Add("")
    [void]$lines.Add("Exception:")
    [void]$lines.Add($_.Exception.ToString())
    [void]$lines.Add("")
    [void]$lines.Add("Position:")
    [void]$lines.Add([string]$_.InvocationInfo.PositionMessage)
    [void]$lines.Add("")
    [void]$lines.Add("Script stack:")
    [void]$lines.Add([string]$_.ScriptStackTrace)

    [System.IO.File]::WriteAllLines($log, [string[]]$lines, [System.Text.Encoding]::UTF8)

    Write-Host ""
    Write-Host "Startup failed. Log written to:"
    Write-Host $log
    Write-Host ""
    Read-Host "Press Enter to close"
}
