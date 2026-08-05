# Mod Translation Toolkit v1

Native Windows rewrite of Mod Translation Toolkit.

## Why v1?

The 0.x application was implemented in PowerShell + WPF. It proved the workflow and features, but it also introduced Windows execution-policy friction and antivirus false positives around script launchers.

v1 is a native **C# / .NET 8 / WPF** application.

There is no PowerShell requirement at runtime.

## Current preview foundation

Implemented in Preview 1:

- Native WPF application shell
- Dark Mrokar UI
- RimWorld Game / RimWorld Mod profiles
- Kenshi Game profile shell
- Project Zomboid Game / Mod profiles
- Shared translation entry model
- Translation-state filters:
  - All
  - Missing
  - Translated
  - Identical source/target
  - Suspicious
- Project Zomboid TXT scanner
- Project Zomboid JSON scanner
- B42/common translation-root discovery
- RimWorld Languages XML scanning
- Initial English RimWorld `Defs` extraction for common fields
- Semicolon CSV import/export
- Steam library discovery
- Project Zomboid Workshop directory discovery
- Native LibreTranslate HTTP service
- GitHub Actions workflow producing a self-contained Windows x64 single-file EXE

## Build locally

Requirements:

- Windows 10/11
- .NET 8 SDK or Visual Studio 2022 with .NET Desktop Development

```powershell
dotnet restore ModTranslationToolkit.sln
dotnet build ModTranslationToolkit.sln -c Release
dotnet publish src/ModTranslationToolkit/ModTranslationToolkit.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true `
  -o publish/win-x64
```

## GitHub build

Push the project to GitHub and open:

**Actions → Build Windows EXE → Run workflow**

The resulting artifact is `ModTranslationToolkit-v1-win-x64`.

## Migration roadmap

Next:

1. Google / DeepL / LibreTranslate settings UI and DPAPI secret storage
2. Async translation batches, progress, cancel and autosave
3. Full RimWorld DefInjected extraction parity
4. RimWorld translation-mod builder
5. Project Zomboid B42 translation-mod builder
6. Project Zomboid Workshop staging
7. Reopen/update existing translation mods
8. Kenshi native workflow migration
9. Steam Workshop dashboard
10. Code signing / installer
