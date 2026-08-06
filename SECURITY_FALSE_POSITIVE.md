# Antivirus and false-positive information

## Current report

A small number of tests have produced the heuristic Microsoft Defender detection:

`Trojan:Script/Wacatac.B!ml`

The same release has not been detected consistently on other Windows installations. This suggests a possible environment-, reputation-, or Defender-version-dependent false positive, but it is not proof that every downloaded copy is safe.

## Safe verification workflow

1. Download the release only from the official GitHub repository.
2. Compare the release ZIP SHA-256 with `SHA256SUMS.txt`.
3. Do not run a copy whose checksum differs.
4. Keep Microsoft Defender enabled.
5. Review the PowerShell and VBS source if you are uncertain.
6. Submit the exact unchanged ZIP to Microsoft if it is detected.

## What the Toolkit does

The Toolkit:

- scans local game and mod folders,
- reads and writes localization files,
- uses configured translation services when requested,
- stores configured API credentials locally using Windows DPAPI,
- creates translation-mod and Workshop staging folders,
- opens local folders and web links when explicitly requested.

## What the Toolkit does not intentionally do

- It does not disable or reconfigure Microsoft Defender.
- It does not add antivirus exclusions.
- It does not create startup persistence or scheduled tasks.
- It does not inject into other processes.
- It does not download and execute arbitrary programs.
- It does not use `Invoke-Expression` or `IEX`.

## Submit a suspected false positive

Microsoft submission portal:

`https://www.microsoft.com/en-us/wdsi/filesubmission`

Suggested submission details:

- **Submission type:** File incorrectly detected as malware
- **Detection:** Trojan:Script/Wacatac.B!ml
- **Product:** Microsoft Defender Antivirus
- **File:** unchanged release ZIP
- **Source:** https://github.com/DrizztGaming/Mod-Translation-Toolkit
- **Version:** v0.10.0 Experimental
- **Comment:** Open-source PowerShell/WPF game-mod translation utility. Detection is not reproduced consistently on other Windows installations. Please review as a suspected false positive.

After submission, keep the submission ID for follow-up.
