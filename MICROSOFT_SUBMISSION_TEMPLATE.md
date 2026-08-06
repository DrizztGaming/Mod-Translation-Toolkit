# Microsoft false-positive submission template

Use this text in the Microsoft sample-submission form.

## Title

Possible false positive: Mod Translation Toolkit v0.10.0 detected as Trojan:Script/Wacatac.B!ml

## Description

Mod Translation Toolkit is an open-source Windows PowerShell/WPF utility for translating game and mod localization files.

Microsoft Defender heuristically detects the downloaded release ZIP as `Trojan:Script/Wacatac.B!ml` on one Windows installation. The detection has not been reproduced consistently on other systems, including a Windows 10 test machine.

The submitted file is the unchanged release archive downloaded from:

https://github.com/DrizztGaming/Mod-Translation-Toolkit

The source code is included in the archive and repository. The program does not intentionally disable Defender, add antivirus exclusions, create scheduled tasks or persistence, inject code into other processes, or download and execute external programs.

Please analyze the submitted file as a suspected false positive.

## Fields to add manually

- SHA-256:
- Defender security-intelligence version:
- Windows version:
- Submission date:
- Microsoft submission ID:
