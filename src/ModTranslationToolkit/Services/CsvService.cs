using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using ModTranslationToolkit.Models;

namespace ModTranslationToolkit.Services;

public static class CsvService
{
    public static void Export(string path, IEnumerable<TranslationEntry> entries,
        string sourceLanguage, string targetLanguage)
    {
        var sb = new StringBuilder();
        sb.AppendLine("Module;Root;Type;File;Key;Source;Translation;SourceLanguage;TargetLanguage");
        foreach (var e in entries)
        {
            sb.AppendLine(string.Join(";",
                Q(e.Module), Q(e.Root), Q(e.Type), Q(e.File), Q(e.Key),
                Q(e.Source), Q(e.Translation), Q(sourceLanguage), Q(targetLanguage)));
        }
        File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
    }

    public static Dictionary<string,string> Import(string path)
    {
        var lines = File.ReadAllLines(path, Encoding.UTF8);
        var result = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        if (lines.Length <= 1) return result;

        var header = Parse(lines[0]);
        int m = header.FindIndex(x => x == "Module");
        int r = header.FindIndex(x => x == "Root");
        int t = header.FindIndex(x => x == "Type");
        int f = header.FindIndex(x => x == "File");
        int k = header.FindIndex(x => x == "Key");
        int tr = header.FindIndex(x => x == "Translation");

        foreach (var line in lines.Skip(1))
        {
            var cells = Parse(line);
            if (new[] {m,r,t,f,k,tr}.Any(i => i < 0 || i >= cells.Count)) continue;
            var id = $"{cells[m]}|{cells[r]}|{cells[t]}|{cells[f]}|{cells[k]}".ToLowerInvariant();
            result[id] = cells[tr];
        }
        return result;
    }

    private static string Q(string? s) =>
        "\"" + (s ?? "").Replace("\"", "\"\"") + "\"";

    private static List<string> Parse(string line)
    {
        var result = new List<string>();
        var sb = new StringBuilder();
        bool quoted = false;
        for (int i=0; i<line.Length; i++)
        {
            var c = line[i];
            if (c == '"')
            {
                if (quoted && i+1 < line.Length && line[i+1] == '"')
                {
                    sb.Append('"'); i++;
                }
                else quoted = !quoted;
            }
            else if (c == ';' && !quoted)
            {
                result.Add(sb.ToString()); sb.Clear();
            }
            else sb.Append(c);
        }
        result.Add(sb.ToString());
        return result;
    }
}
