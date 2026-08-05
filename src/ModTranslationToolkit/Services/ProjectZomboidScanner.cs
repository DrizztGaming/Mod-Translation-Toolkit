using System.Text.Json;
using ModTranslationToolkit.Models;

namespace ModTranslationToolkit.Services;

public static class ProjectZomboidScanner
{
    public static List<TranslationEntry> Scan(
        string modOrGameRoot, string sourceCode, string targetCode)
    {
        var source = ReadLanguage(modOrGameRoot, sourceCode, source: true);
        var target = ReadLanguage(modOrGameRoot, targetCode, source: false)
            .ToDictionary(e => e.Identity, e => e.Translation, StringComparer.OrdinalIgnoreCase);

        foreach (var e in source)
            if (target.TryGetValue(e.Identity, out var value))
                e.Translation = value;

        return source;
    }

    public static List<string> FindTranslationRoots(string root)
    {
        var results = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (!Directory.Exists(root)) return [];

        foreach (var dir in Directory.EnumerateDirectories(root, "*", SearchOption.AllDirectories))
        {
            var normalized = dir.Replace('/', '\\');
            if (normalized.EndsWith(@"media\lua\shared\Translate", StringComparison.OrdinalIgnoreCase))
                results.Add(dir);
        }
        return results.ToList();
    }

    private static List<TranslationEntry> ReadLanguage(string root, string lang, bool source)
    {
        var result = new List<TranslationEntry>();
        foreach (var translateRoot in FindTranslationRoots(root))
        {
            var langDir = Path.Combine(translateRoot, lang);
            if (!Directory.Exists(langDir)) continue;

            var rootLabel = GetRootLabel(root, translateRoot);

            foreach (var file in Directory.EnumerateFiles(langDir, "*.*", SearchOption.TopDirectoryOnly))
            {
                var ext = Path.GetExtension(file).ToLowerInvariant();
                if (ext == ".json") ReadJson(file, rootLabel, result, source);
                else if (ext == ".txt") ReadTxt(file, rootLabel, result, source);
            }
        }
        return result;
    }

    private static void ReadJson(string path, string rootLabel,
        List<TranslationEntry> output, bool source)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        Flatten(doc.RootElement, "", (key, value) =>
        {
            var e = new TranslationEntry {
                Root = rootLabel, Type = "JSON", File = Path.GetFileName(path),
                Key = key, Source = source ? value : ""
            };
            if (!source) e.Translation = value;
            output.Add(e);
        });
    }

    private static void Flatten(JsonElement el, string prefix, Action<string,string> add)
    {
        if (el.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in el.EnumerateObject())
                Flatten(p.Value, string.IsNullOrEmpty(prefix) ? p.Name : $"{prefix}.{p.Name}", add);
        }
        else if (el.ValueKind == JsonValueKind.Array)
        {
            int i = 0;
            foreach (var item in el.EnumerateArray())
                Flatten(item, $"{prefix}[{i++}]", add);
        }
        else if (el.ValueKind == JsonValueKind.String)
            add(prefix, el.GetString() ?? "");
    }

    private static void ReadTxt(string path, string rootLabel,
        List<TranslationEntry> output, bool source)
    {
        foreach (var raw in File.ReadLines(path))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith("--")) continue;
            int eq = line.IndexOf('=');
            if (eq <= 0) continue;

            var key = line[..eq].Trim().Trim(',');
            var value = line[(eq+1)..].Trim().TrimEnd(',').Trim();
            if (value.StartsWith("\"") && value.EndsWith("\"") && value.Length >= 2)
                value = value[1..^1].Replace("\\n", "\n").Replace("\\\"", "\"");

            var e = new TranslationEntry {
                Root = rootLabel, Type = "TXT", File = Path.GetFileName(path),
                Key = key, Source = source ? value : ""
            };
            if (!source) e.Translation = value;
            output.Add(e);
        }
    }

    private static string GetRootLabel(string root, string translateRoot)
    {
        var rel = Path.GetRelativePath(root, translateRoot);
        var first = rel.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .FirstOrDefault() ?? "root";
        return first.Equals("media", StringComparison.OrdinalIgnoreCase) ? "root" : first;
    }
}
