using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace ModTranslationToolkit.Models;

public sealed class TranslationEntry : INotifyPropertyChanged
{
    private string _translation = "";

    public string Module { get; init; } = "";
    public string Root { get; init; } = "";
    public string Type { get; init; } = "";
    public string File { get; init; } = "";
    public string Key { get; init; } = "";
    public string Source { get; init; } = "";

    public string Translation
    {
        get => _translation;
        set
        {
            if (_translation == value) return;
            _translation = value ?? "";
            OnPropertyChanged();
        }
    }

    public bool Missing => string.IsNullOrWhiteSpace(Translation);
    public bool Identical => !Missing &&
        string.Equals(Source.Trim(), Translation.Trim(), StringComparison.Ordinal);
    public bool Translated => !Missing && !Identical;
    public bool Suspicious => Missing || Identical;

    public string Identity =>
        $"{Module}|{Root}|{Type}|{File}|{Key}".ToLowerInvariant();

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
