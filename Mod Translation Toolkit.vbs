Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

base = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(base, "src\RimWorld\ModTranslationToolkit.ps1")
logPath = fso.BuildPath(base, "STARTUP_ERROR.log")

If Not fso.FileExists(scriptPath) Then
    MsgBox "Nie znaleziono pliku:" & vbCrLf & scriptPath, 16, "Mod Translation Toolkit"
    WScript.Quit 2
End If

quote = Chr(34)
escapedScript = Replace(scriptPath, "'", "''")
escapedLog = Replace(logPath, "'", "''")

unblockCmd = "powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command " & quote & _
    "Unblock-File -LiteralPath '" & escapedScript & "' -ErrorAction SilentlyContinue" & quote
shell.Run unblockCmd, 0, True

wrapper = "$ErrorActionPreference='Stop'; " & _
          "$log='" & escapedLog & "'; " & _
          "try { & '" & escapedScript & "' } " & _
          "catch { " & _
          "$msg = @(" & _
          "'Mod Translation Toolkit startup failed.'," & _
          "('Message: ' + $_.Exception.Message)," & _
          "('Type: ' + $_.Exception.GetType().FullName)," & _
          "('ScriptStackTrace: ' + $_.ScriptStackTrace)," & _
          "('Position: ' + $_.InvocationInfo.PositionMessage)," & _
          "('Category: ' + $_.CategoryInfo.ToString())," & _
          "('FullyQualifiedErrorId: ' + $_.FullyQualifiedErrorId)" & _
          ") -join [Environment]::NewLine; " & _
          "[IO.File]::WriteAllText($log,$msg,(New-Object Text.UTF8Encoding($false))); exit 1 }"

cmd = "powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -STA -WindowStyle Hidden -Command " & quote & Replace(wrapper, quote, quote & quote) & quote
rc = shell.Run(cmd, 0, True)

If rc <> 0 Then
    If Not fso.FileExists(logPath) Then
        Set logFile = fso.CreateTextFile(logPath, True, True)
        logFile.WriteLine "Mod Translation Toolkit startup failed."
        logFile.WriteLine "Exit code: " & rc
        logFile.WriteLine "Script: " & scriptPath
        logFile.WriteLine "No PowerShell exception details were captured."
        logFile.Close
    End If

    MsgBox "Mod Translation Toolkit nie uruchomil sie." & vbCrLf & vbCrLf & _
           "Szczegoly zapisano w STARTUP_ERROR.log.", 16, "Mod Translation Toolkit"
End If
