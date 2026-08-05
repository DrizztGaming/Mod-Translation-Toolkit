$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "src\RimWorld\ModTranslationToolkit.ps1"
$logPath = Join-Path $PSScriptRoot "STARTUP_ERROR.log"

try {
    Unblock-File -LiteralPath $scriptPath -ErrorAction SilentlyContinue

    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "RemoteSigned",
        "-STA",
        "-File", $scriptPath
    )

    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Toolkit PowerShell process exited with code $($process.ExitCode)."
    }
}
catch {
    $details = @(
        "Mod Translation Toolkit startup failed.",
        "Timestamp: $(Get-Date -Format o)",
        "Message: $($_.Exception.Message)",
        "Type: $($_.Exception.GetType().FullName)",
        "ScriptStackTrace: $($_.ScriptStackTrace)",
        "Position: $($_.InvocationInfo.PositionMessage)",
        "Category: $($_.CategoryInfo)",
        "FullyQualifiedErrorId: $($_.FullyQualifiedErrorId)"
    ) -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        $logPath,
        $details,
        (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false))
    )

    Write-Host ""
    Write-Host "=== MOD TRANSLATION TOOLKIT STARTUP ERROR ===" -ForegroundColor Red
    Write-Host $details
    Write-Host ""
    Write-Host "Log: $logPath"
    Read-Host "Press Enter to close"
    exit 1
}
