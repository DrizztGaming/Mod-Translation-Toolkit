using Microsoft.Win32;
using System.Text.RegularExpressions;

namespace ModTranslationToolkit.Services;

public static class SteamDetector
{
    public static IEnumerable<string> GetSteamLibraries()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var steam = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")?.GetValue("SteamPath") as string;
        if (!string.IsNullOrWhiteSpace(steam)) set.Add(steam.Replace('/', '\\'));

        foreach (var root in set.ToArray())
        {
            var vdf = Path.Combine(root, "steamapps", "libraryfolders.vdf");
            if (!File.Exists(vdf)) continue;
            foreach (var line in File.ReadLines(vdf))
            {
                var m = Regex.Match(line, "\"path\"\\s+\"([^\"]+)\"");
                if (m.Success) set.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
            }
        }
        return set;
    }

    public static string? FindGame(string folderName)
    {
        foreach (var lib in GetSteamLibraries())
        {
            var p = Path.Combine(lib, "steamapps", "common", folderName);
            if (Directory.Exists(p)) return p;
        }
        return null;
    }

    public static IEnumerable<string> FindPzWorkshopItems()
    {
        foreach (var lib in GetSteamLibraries())
        {
            var root = Path.Combine(lib, "steamapps", "workshop", "content", "108600");
            if (!Directory.Exists(root)) continue;
            foreach (var item in Directory.EnumerateDirectories(root))
                yield return item;
        }
    }
}
