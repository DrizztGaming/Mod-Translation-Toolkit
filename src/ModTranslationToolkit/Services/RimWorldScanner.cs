using System.Xml.Linq;
using ModTranslationToolkit.Models;

namespace ModTranslationToolkit.Services;

public static class RimWorldScanner
{
    public static List<TranslationEntry> ScanLanguageFolders(
        string modRoot, string sourceFolderName, string targetFolderName)
    {
        var sourceRoot = Path.Combine(modRoot, "Languages", sourceFolderName);
        var targetRoot = Path.Combine(modRoot, "Languages", targetFolderName);

        var source = ReadLanguage(sourceRoot, true);
        var targets = ReadLanguage(targetRoot, false)
            .ToDictionary(x => x.Identity, x => x.Translation, StringComparer.OrdinalIgnoreCase);

        foreach (var e in source)
            if (targets.TryGetValue(e.Identity, out var tr))
                e.Translation = tr;

        return source;
    }

    public static List<TranslationEntry> ScanEnglishDefs(string modRoot)
    {
        var defs = Path.Combine(modRoot, "Defs");
        var result = new List<TranslationEntry>();
        if (!Directory.Exists(defs)) return result;

        foreach (var file in Directory.EnumerateFiles(defs, "*.xml", SearchOption.AllDirectories))
        {
            try
            {
                var doc = XDocument.Load(file, LoadOptions.PreserveWhitespace);
                foreach (var def in doc.Descendants().Where(x => x.Parent?.Name.LocalName == "Defs"))
                {
                    var defName = def.Element("defName")?.Value?.Trim();
                    if (string.IsNullOrWhiteSpace(defName)) continue;

                    foreach (var name in new[] {"label","description","jobString","reportString","gerund"})
                    {
                        var node = def.Element(name);
                        if (node is null || string.IsNullOrWhiteSpace(node.Value)) continue;
                        result.Add(new TranslationEntry {
                            Type = $"DefInjected/{def.Name.LocalName}",
                            File = Path.GetFileName(file),
                            Key = $"{defName}.{name}",
                            Source = node.Value.Trim()
                        });
                    }
                }
            }
            catch { }
        }
        return result;
    }

    private static List<TranslationEntry> ReadLanguage(string root, bool source)
    {
        var result = new List<TranslationEntry>();
        if (!Directory.Exists(root)) return result;

        foreach (var file in Directory.EnumerateFiles(root, "*.xml", SearchOption.AllDirectories))
        {
            try
            {
                var doc = XDocument.Load(file);
                var rel = Path.GetRelativePath(root, file);
                var type = rel.StartsWith("Keyed", StringComparison.OrdinalIgnoreCase)
                    ? "Keyed"
                    : rel.StartsWith("DefInjected", StringComparison.OrdinalIgnoreCase)
                        ? "DefInjected" : "XML";

                foreach (var leaf in doc.Descendants().Where(x => !x.HasElements))
                {
                    if (string.IsNullOrWhiteSpace(leaf.Value)) continue;
                    var e = new TranslationEntry {
                        Type = type, File = rel, Key = BuildKey(leaf),
                        Source = source ? leaf.Value : ""
                    };
                    if (!source) e.Translation = leaf.Value;
                    result.Add(e);
                }
            }
            catch { }
        }
        return result;
    }

    private static string BuildKey(XElement node)
    {
        var parts = node.AncestorsAndSelf()
            .Reverse()
            .SkipWhile(x => x.Name.LocalName is "LanguageData" or "Defs")
            .Select(x => x.Name.LocalName);
        return string.Join(".", parts);
    }
}
